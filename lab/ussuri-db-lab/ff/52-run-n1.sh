#!/usr/bin/env bash
# EXP-DB-N1: 2026.1 code directly against the Ussuri database (nova api+cells, keystone, cinder). Engine: 11.4 on the 10.3
# datadir; if 11.4 refuses it, falls back to 10.3 (recorded). Each command is run on its own; errors are kept verbatim.
. "$(dirname "$0")/lib.sh"; ff_vars n1; set +e
LOG="$RUN_EV/run.log"; exec > >(tee -a "$LOG") 2>&1
"$FF_DIR/10-new-copy.sh" n1 baseline || exit 1
ENG=11.4; "$FF_DIR/20-engine.sh" n1 mariadb:11.4; rc=$?
if [ $rc -ne 0 ]; then echo "ENGINE: 11.4 refused or failed on the 10.3 datadir (rc=$rc); falling back to 10.3"; echo "engine=10.3 (11.4 refused: see engine-11.4/)" > "$RUN_EV/engine-used.txt"; ENG=10.3
  docker rm -f "$DB_FF" >/dev/null 2>&1; docker volume rm "$VOL_FF" >/dev/null; docker volume create "$VOL_FF" >/dev/null
  docker run --rm -v "$VOL_FF":/v -v "$BASE_BACKUP/volumes":/in:ro mariadb:10.3 sh -c 'tar -C /v -xzf /in/ufj-mariadb-data.tar.gz'; ff_db_start mariadb:10.3
else echo "engine=11.4 on the upgraded 10.3 datadir" > "$RUN_EV/engine-used.txt"; fi
"$FF_DIR/15-overrides.sh" n1
CF() { echo "--config-file /etc/$1/$2 --config-file /etc/ff/$3"; }
run() { local n=$1 svc=$2; shift 2; ff_oneshot 2026.1 "$svc" -- "$@" > "$RUN_EV/$n.raw" 2>&1; local r=$?; ff_redact < "$RUN_EV/$n.raw" > "$RUN_EV/$n.txt"; rm -f "$RUN_EV/$n.raw"; printf '%s\texit=%s\n' "$n" "$r" | tee -a "$RUN_EV/exitcodes.tsv"; echo "--- last lines of $n"; tail -12 "$RUN_EV/$n.txt"; }
: > "$RUN_EV/exitcodes.tsv"
run nova-api_db_sync   nova nova-manage $(CF nova nova.conf nova.conf) api_db sync
run nova-db_sync-cell0 nova nova-manage $(CF nova nova.conf nova-cell0.conf) db sync --local_cell
run nova-db_sync-cell1 nova nova-manage $(CF nova nova.conf nova.conf) db sync --local_cell
run keystone-db_sync   keystone keystone-manage $(CF keystone keystone.conf keystone.conf) db_sync
run cinder-db_sync     cinder cinder-manage $(CF cinder cinder.conf cinder.conf) db sync
# after the attempts: did anything change? (row counts + bookkeeping, read-only)
{ for d in nova nova_api nova_cell0 keystone cinder; do for t in migrate_version alembic_version; do echo "$d.$t: $(ff_sql "SELECT GROUP_CONCAT(CONCAT_WS('/',$( [ $t = alembic_version ] && echo version_num || echo repository_id,version)) SEPARATOR ';') FROM \`$d\`.\`$t\`" 2>&1 | head -1)"; done; done; } > "$RUN_EV/bookkeeping-after.txt"
cat "$RUN_EV/bookkeeping-after.txt"
