#!/usr/bin/env bash
# Baseline capture. Order matters for a provable baseline:
#  1. API inventory (control plane running)         -> inventory.json
#  2. stop every service container (MariaDB stays)  -> the database is quiescent: no heartbeats, no writes
#  3. logical dumps, schema-only dump, exact row counts, CHECKSUM TABLE of every table
#  4. stop MariaDB cleanly, tar the Docker volumes (cold copy), start everything again
# Output: backups/baseline-<UTC time>/ (git-ignored; holds credentials) + sanitized evidence copy in $EVIDENCE_DIR.
. "$(dirname "$0")/lib.sh"; load_secrets
# STAGE=pre-forced-down: computes/agents running -> services table + running inventory -> stopped (+proof) -> full capture.
# STAGE=final (default): computes already stopped AND marked forced-down through the API (71-forced-down.sh) -> full capture.
STAGE="${STAGE:-final}"; EV="$EVIDENCE_DIR"; [ "$STAGE" = pre-forced-down ] && EV="$EVIDENCE_DIR/pre-forced-down"
TS=$(date -u +%Y%m%dT%H%M%SZ); B="$BACKUP_DIR/baseline-$TS-$STAGE"; mkdir -p "$B/volumes" "$B/config"; chmod 700 "$BACKUP_DIR" "$B"; umask 077
T0=$(date +%s); tm() { printf '%s\t%s s\n' "$1" "$(( $(date +%s)-T0 ))" | tee -a "$B/timings.txt"; }

inv() { docker exec -i -e ADMIN -e USER_ALICE -e USER_BOB ufj-client bash -c 'set -a; . /run/ufj/admin-openrc; set +a; export OS_PASSWORD="$ADMIN"; python /lab/tools/inventory.py capture --out /tmp/inventory.json'; docker cp ufj-client:/tmp/inventory.json "$1"; }
svc_table() { # nova services table, read-only
  mysql_root -N -B -e "SELECT id, host, \`binary\`, version, disabled, IFNULL(disabled_reason,'NULL'), forced_down, updated_at, deleted FROM nova.services ORDER BY id" ; }
if [ "$STAGE" = pre-forced-down ]; then
  log "1/5 services table and API inventory, platform RUNNING (fake computes and fake agents up)"
  { echo "# nova.services before stopping anything: id host binary version disabled disabled_reason forced_down updated_at deleted"; svc_table; } > "$B/nova-services-running.tsv"
  inv "$B/inventory-running.json"; tm inventory-running
  log "2/5 FENCE: stop the fake nova-compute and fake agent containers (service rows stay in the databases)"
  mapfile -t FENCE < <(docker ps --format '{{.Names}}' | grep -E '^ufj-(compute|fake-agent)[0-9]+$' | sort); printf '%s\n' "${FENCE[@]}" > "$B/fenced-containers.txt"
  [ ${#FENCE[@]} -gt 0 ] && docker stop -t 30 "${FENCE[@]}" >/dev/null; tm fenced
else
  log "1/5 final stage: computes must already be stopped and forced down"
  docker ps --format '{{.Names}}' | grep -E '^ufj-(compute|fake-agent)[0-9]+$' && die "fake compute/agent containers are running: fence first"
fi
{ echo "# proof the Ussuri fake computes and agents are stopped, $(date -u +%FT%TZ)"; for c in $(docker ps -a --format '{{.Names}}' | grep -E '^ufj-(compute|fake-agent)[0-9]+$' | sort); do docker inspect -f '{{.Name}} status={{.State.Status}} running={{.State.Running}} finished={{.State.FinishedAt}} exit={{.State.ExitCode}}' "$c"; done; echo "running ufj-compute/agent containers now: $(docker ps --format '{{.Names}}' | grep -cE '^ufj-(compute|fake-agent)[0-9]+$')"; } > "$B/fence-proof.txt"
cat "$B/fence-proof.txt"
{ echo "# nova.services after fencing ($STAGE): id host binary version disabled disabled_reason forced_down updated_at deleted"; svc_table; } > "$B/nova-services-table.tsv"
log "   API inventory, platform FENCED (primary baseline of this stage: inventory.json)"
inv "$B/inventory.json"; tm inventory-fenced

log "3/5 stopping the remaining service containers (database quiescent)"
mapfile -t SVCS < <(service_containers); printf '%s\n' "${SVCS[@]}" > "$B/stopped-containers.txt"
docker stop -t 30 "${SVCS[@]}" >/dev/null; tm services-stopped
docker exec -e MYSQL_PWD="$DB_ROOT" ufj-mariadb mysql -uroot -e 'FLUSH TABLES WITH READ LOCK; UNLOCK TABLES;' >/dev/null
# a short settle: open connections of the stopped services are closed by now
log "4/5 logical dumps, row counts, table checksums"
DUMP="docker exec -e MYSQL_PWD=$DB_ROOT ufj-mariadb mysqldump -uroot --routines --triggers --events --single-transaction --hex-blob --skip-dump-date"
$DUMP --all-databases | gzip -n > "$B/all-databases.sql.gz"; tm dump-all
$DUMP --databases "${OS_DBS[@]}" > "$B/openstack-databases.sql"; tm dump-openstack
$DUMP --no-data --routines --triggers --events --databases "${OS_DBS[@]}" > "$B/schema-only.sql"; tm dump-schema
sql_rowcounts ufj-mariadb "$DB_ROOT" > "$B/rowcounts.tsv"; tm rowcounts
sql_checksums ufj-mariadb "$DB_ROOT" > "$B/table-checksums.tsv"; tm checksums
mysql_root -N -e 'select version()' > "$B/mariadb-version.txt"
"$LAB_DIR/tools/coverage_counts.sh" ufj-mariadb "$DB_ROOT" > "$B/coverage-counts-T0.tsv"; tm coverage-counts
mysql_root -N -e "SELECT CONCAT(\`binary\`,'\t',host,'\tversion=',version,'\tdisabled=',disabled,'\tforced_down=',forced_down,'\tdeleted=',deleted) FROM nova.services" > "$B/nova-services-rows.tsv"
mysql_root -N -e "SELECT CONCAT(\`binary\`,'\t',host,'\tdeleted=',deleted) FROM cinder.services" >> "$B/nova-services-rows.tsv"
mysql_root -N -e "select table_schema, count(*) from information_schema.tables where table_type='BASE TABLE' group by 1 order by 1" > "$B/table-counts-per-db.tsv"
# schema version markers: sqlalchemy-migrate (migrate_version) and alembic (alembic_version) tables of every database
for d in "${OS_DBS[@]}"; do for t in migrate_version alembic_version; do
  mysql_root -N -e "SELECT '$d','$t',t.* FROM \`$d\`.\`$t\` t" 2>/dev/null || true
done; done > "$B/schema-versions.tsv"
sha256sum "$B/openstack-databases.sql" | awk '{print $1}' > "$B/openstack-databases.sql.sha256"

log "5/5 cold volume copy (MariaDB stopped cleanly)"
docker stop -t 60 ufj-mariadb >/dev/null; tm mariadb-stopped
for v in ufj-mariadb-data ufj-keystone-keys ufj-glance-images; do
  docker run --rm -v "$v":/v:ro -v "$B/volumes":/out "$MARIADB_IMAGE" tar -C /v -czf "/out/$v.tar.gz" . ; done; tm volumes-tarred
tar -C "$RUN_DIR" -czf "$B/config/rendered-etc.tar.gz" etc; cp "$SECRETS_DIR/passwords.env" "$B/config/passwords.env"
docker start ufj-mariadb >/dev/null; for i in $(seq 1 60); do mysql_root -e 'select 1' >/dev/null 2>&1 && break; sleep 2; done
docker start "${SVCS[@]}" >/dev/null; tm services-restarted   # the fenced containers stay STOPPED: the baseline is a fenced platform
( cd "$B" && find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 sha256sum > MANIFEST.sha256 )
if [ "$STAGE" = final ]; then ln -sfn "baseline-$TS-$STAGE" "$BACKUP_DIR/latest"; else ln -sfn "baseline-$TS-$STAGE" "$BACKUP_DIR/latest-pre-forced-down"; fi

# sanitized evidence copy: counts, checksums, schema, inventory (no row data, no credentials)
mkdir -p "$EV"
cp "$B/rowcounts.tsv" "$B/table-checksums.tsv" "$B/inventory.json" "$B/timings.txt" "$B/mariadb-version.txt" "$B/table-counts-per-db.tsv" "$B/schema-versions.tsv" "$B/openstack-databases.sql.sha256" "$B/MANIFEST.sha256" "$B/coverage-counts-T0.tsv" "$B/nova-services-rows.tsv" "$EV/"; cp "$B"/fence-proof.txt "$B"/nova-services-table.tsv "$EV/"; for f in fenced-containers.txt nova-services-running.tsv; do [ -f "$B/$f" ] && cp "$B/$f" "$EV/"; done
[ -f "$B/inventory-running.json" ] && cp "$B/inventory-running.json" "$EV/inventory-running.json"; cp "$B/inventory.json" "$EV/inventory-fenced.json"
# fake compute host names and the compute_driver settings (sanitised: no passwords, no connection strings)
{ echo "compute hosts: $(grep -h -o "ufj-compute[0-9]*" "$B/fenced-containers.txt" | sort -u | tr "\n" " ")"; echo "--- nova.conf (shared) driver-related lines"; grep -nE "^(compute_driver|vif_plugging|reclaim_instance_interval|enabled_filters|resume_guests|firewall_driver)" "$RUN_DIR/etc/nova/nova.conf"; echo "--- nova-compute.conf (compute containers only)"; cat "$RUN_DIR/etc/nova/nova-compute.conf"; echo "--- cinder.conf quota/backends"; grep -nE "^(quota_backups|enabled_backends|volume_driver|volume_backend_name)" "$RUN_DIR/etc/cinder/cinder.conf"; echo "--- neutron service_plugins / ml2"; grep -nE "^(service_plugins|mechanism_drivers|type_drivers)" "$RUN_DIR/etc/neutron/neutron.conf" "$RUN_DIR/etc/neutron/ml2_conf.ini"; } > "$EV/fake-compute-config.txt"
cp "$RUN_DIR/archive.log" "$EV/nova-archive-deleted-rows.txt" 2>/dev/null || true
gzip -9nc "$B/schema-only.sql" > "$EV/schema-only.sql.gz"
log "baseline: $B"; wc -l "$B/rowcounts.tsv" | sed 's/^/tables: /'
