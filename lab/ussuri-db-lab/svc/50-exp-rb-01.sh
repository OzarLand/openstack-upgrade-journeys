#!/usr/bin/env bash
# EXP-RB-01: rollback. Restore the pre-bridge dump (baseline v4 "final", taken before the first 2023.1 db sync) into the Ussuri lab and start the Ussuri services.
#   usage: 50-exp-rb-01.sh <label>      evidence: evidence/EXP-RB-01/<label>/
# Needs the 2026.1 runtime of EXP-SVC-02 to be the "after" state (its database stays in volume ufj-svc-data, only measured, never reused).
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
set +eu
LABEL=${1:?label}; OUT="$EVIDENCE_DIR/../EXP-RB-01/$LABEL"; mkdir -p "$OUT"
B="$LAB_DIR/backups-v4/latest"
note() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$OUT/run.log"; }
{ echo "harness commit: $(git -C "$LAB_DIR/../.." rev-parse HEAD)"; echo "lab/ files changed:"; git -C "$LAB_DIR/../.." status --porcelain -- lab | grep -v '^??'; echo "script sha256: $(sha256sum "$0" | cut -d' ' -f1)"; echo "restored baseline: $(readlink -f "$B")"; echo "dump sha256 recorded: $(cat "$B/openstack-databases.sql.sha256")"; } > "$OUT/harness.txt"
case $LABEL in strict*) [ -z "$(git -C "$LAB_DIR/../.." status --porcelain -- lab | grep -v '^??')" ] || { echo "STRICT run refused: lab/ has uncommitted changes"; exit 3; };; esac

note "0. what the 2026.1 phase changed (counts in the 2026.1 database, volume ufj-svc-data, vs the baseline T0 counts)"
docker start ufj-svc-db >/dev/null 2>&1; sleep 15
{ printf 'table\tT0\tafter_2026.1_phase\n'
  for t in nova.instances nova.instance_faults nova_api.cell_mappings nova.migrations cinder.volumes cinder.volume_attachment cinder.snapshots neutron.ports neutron.networks keystone.role keystone.implied_role keystone.password keystone.revocation_event keystone.application_credential glance.images nova.services; do
    d=${t%%.*}; tb=${t#*.}; t0=$(awk -F'\t' -v d="$d" -v t="$tb" '$1==d && $2==t{print $3}' "$B/rowcounts.tsv"); now=$(sdb -N -e "select count(*) from $t" 2>&1)
    printf '%s\t%s\t%s\n' "$t" "${t0:-?}" "$now"; done; } | tee "$OUT/lost-after-dump-counts.tsv" | tee -a "$OUT/run.log"
sdb -e "select host,\`binary\`,version,forced_down from nova.services order by id" > "$OUT/services-in-2026.1-db.tsv" 2>&1
note "1. stop the 2026.1 runtime"; "$SVC_DIR/10-stack.sh" down | tee -a "$OUT/run.log"; docker stop ufj-svc-db >/dev/null 2>&1; docker rm -f ufj-svc-db ufj-svc-rabbitmq ufj-svc-memcached ufj-svc-client >/dev/null 2>&1
note "2. restore baseline v4 into the Ussuri lab and start the Ussuri services (computes and agents fenced)"
T=$(date +%s); "$LAB_DIR/scripts/85-restore-into-lab.sh" --yes "$B" > "$OUT/restore.log" 2>&1; rc=$?; echo "restore rc=$rc in $(( $(date +%s)-T )) s" | tee -a "$OUT/run.log"; tail -4 "$OUT/restore.log" | tee -a "$OUT/run.log"
note "3. API answers and inventory equals T0 (tools/inventory.py verify with the functional checks)"
sleep 20; "$LAB_DIR/scripts/90-verify.sh" "$B" > "$OUT/verify.txt" 2>&1; vrc=$?; echo "verify rc=$vrc" | tee -a "$OUT/run.log"; tail -14 "$OUT/verify.txt" | tee -a "$OUT/run.log"
cp "$B"/verify-*.txt "$OUT/" 2>/dev/null; rm -f "$B"/verify-*.txt
note "4. state of the restored Nova service rows (they are the rows of the dump: forced_down=1 for the fenced computes)"
docker exec -e MYSQL_PWD="$DB_ROOT" ufj-mariadb mysql -uroot -e "select host,\`binary\`,version,forced_down,disabled from nova.services order by id" > "$OUT/services-restored.tsv" 2>&1; cat "$OUT/services-restored.tsv" | tee -a "$OUT/run.log"
docker exec -e ADMIN="$ADMIN" ufj-client bash -c 'set -a; . /run/ufj/admin-openrc; set +a; export OS_PASSWORD="$ADMIN"; openstack compute service list -f value -c Binary -c Host -c Status -c State' 2>&1 | tee "$OUT/ussuri-api-service-list.txt" | tee -a "$OUT/run.log"
note "done: $LABEL (verify rc=$vrc)"
