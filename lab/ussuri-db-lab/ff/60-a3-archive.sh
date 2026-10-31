#!/usr/bin/env bash
# A3 condition (declared-differences A3/S-3.3 and S-3.4): on a DISPOSABLE COPY of the H4r database (never inside the H4r comparison)
# run the 2026.1 `nova-manage db archive_deleted_rows --until-complete --verbose` for cell1 and cell0 (and once with --all-cells), then
# `db purge --before` to record the S-3.4 message about shadow_migrate_version. Pass = archive exit 0 or 1 (1 = rows archived), no error.
# usage: 60-a3-archive.sh <run>   -> evidence/.../<run>/A3/   exit 1 on failure
. "$(dirname "$0")/lib.sh"; ff_vars "${1:?run}"; set +e
O="$RUN_EV/A3"; mkdir -p "$O"; A3VOL="ufj-ff-$RUN-a3-data"; A3NET="ufj-ff-$RUN-a3-net"; A3DB="ufj-ff-$RUN-a3-db"
ff_sql "SET GLOBAL innodb_fast_shutdown=0" >/dev/null; docker stop -t 600 "$DB_FF" >/dev/null
docker volume rm "$A3VOL" >/dev/null 2>&1; docker volume create "$A3VOL" >/dev/null
docker run --rm -v "$VOL_FF":/from:ro -v "$A3VOL":/to mariadb:11.4 sh -c 'cp -a /from/. /to/'
docker start "$DB_FF" >/dev/null
docker network create "$A3NET" >/dev/null 2>&1
docker run -d --name "$A3DB" --hostname ufj-mariadb --network "$A3NET" --network-alias ufj-mariadb --label org.ozarland.ufj=1 -v "$A3VOL":/var/lib/mysql -e MYSQL_ROOT_PASSWORD="$DB_ROOT" mariadb:11.4 "${DB_FLAGS[@]}" >/dev/null
for i in $(seq 1 90); do docker exec -e MYSQL_PWD="$DB_ROOT" "$A3DB" sh -c 'exec mariadb -uroot -e "select 1"' >/dev/null 2>&1 && break; sleep 2; done
NET_FF="$A3NET"
CF() { echo "--config-file /etc/$1/$2 --config-file /etc/ff/$3"; }
RC=0
run() { local n=$1; shift; ff_oneshot 2026.1 nova -- "$@" > "$O/$n.raw" 2>&1; local r=$?; ff_redact < "$O/$n.raw" | grep -vE "^$" > "$O/$n.txt"; rm -f "$O/$n.raw"; printf '%s\texit=%s\n' "$n" "$r" | tee -a "$O/exitcodes.tsv"; echo "$r"; }
: > "$O/exitcodes.tsv"
for spec in "cell1:nova.conf" "cell0:nova-cell0.conf"; do c=${spec%%:*}; f=${spec#*:}
  r=$(run archive-$c nova-manage $(CF nova nova.conf $f) db archive_deleted_rows --until-complete --verbose | tail -1); { [ "$r" = 0 ] || [ "$r" = 1 ]; } || RC=1
done
r=$(run archive-all-cells nova-manage $(CF nova nova.conf nova.conf) db archive_deleted_rows --all-cells --until-complete --verbose | tail -1); { [ "$r" = 0 ] || [ "$r" = 1 ]; } || RC=1
r=$(run purge-before nova-manage $(CF nova nova.conf nova.conf) db purge --before "$(date -u +%F)" --all-cells --verbose | tail -1)
grep -hiE "shadow_migrate_version|no timestamp|error|Traceback" "$O"/*.txt | head -8 | tee "$O/messages.txt"
grep -qiE "Traceback|\berror\b" "$O"/archive-*.txt && RC=1
echo "A3 archive check: $([ $RC = 0 ] && echo PASS || echo FAIL)" | tee "$O/result.txt"
docker rm -f "$A3DB" >/dev/null 2>&1; docker volume rm "$A3VOL" >/dev/null 2>&1; docker network rm "$A3NET" >/dev/null 2>&1
exit $RC
