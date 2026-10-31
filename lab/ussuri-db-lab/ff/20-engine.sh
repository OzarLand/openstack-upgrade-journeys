#!/usr/bin/env bash
# Engine step of one run: clean shutdown (innodb_fast_shutdown=0), start the target image on the same datadir volume,
# mariadb-upgrade, mariadb-check --check-upgrade, error-log scan. usage: 20-engine.sh <run> <image>  (exit 1 = SC-ENGINE)
. "$(dirname "$0")/lib.sh"; ff_vars "${1:?run}"; IMG="${2:?image}"; tag=${IMG#mariadb:}; OUT="$RUN_EV/engine-$tag"; mkdir -p "$OUT"; set +e
t0=$(date +%s)
ff_sql "SET GLOBAL innodb_fast_shutdown=0" || true
docker stop -t 600 "$DB_FF" >/dev/null; docker logs "$DB_FF" > "$OUT/errorlog-before.txt" 2>&1
ff_db_start "$IMG" || { echo "SC-ENGINE: $IMG did not start on the datadir" | tee "$OUT/result.txt"; docker logs "$DB_FF" > "$OUT/start-failure.log" 2>&1; exit 1; }
t1=$(date +%s)
UPG=mariadb-upgrade; docker exec "$DB_FF" which mariadb-upgrade >/dev/null 2>&1 || UPG=mysql_upgrade
docker exec -e MYSQL_PWD="$DB_ROOT" "$DB_FF" $UPG -uroot > "$OUT/mariadb-upgrade.txt" 2>&1; rc_up=$?
CHK=mariadb-check; docker exec "$DB_FF" which mariadb-check >/dev/null 2>&1 || CHK=mysqlcheck
docker exec -e MYSQL_PWD="$DB_ROOT" "$DB_FF" $CHK -uroot --all-databases --check-upgrade > "$OUT/mariadb-check.txt" 2>&1; rc_ck=$?
docker logs "$DB_FF" > "$OUT/errorlog-after.txt" 2>&1
bad=$(grep -ciE "\[ERROR\]|crash recovery|corrupt|InnoDB: Database was not shut down normally" "$OUT/errorlog-after.txt")
notok=$(grep -vE "OK$|^$|Phase|Running|Checking|mysql\.|Upgrading|Looking|Setting|This installation|Upgrade process|Processing" "$OUT/mariadb-check.txt" | grep -ciE "error|corrupt|warning|Needs upgrade|NOT OK")
{ echo "image=$IMG version=$(ff_sql 'select version()')"; echo "start_seconds=$((t1-t0)) upgrade+check_seconds=$(( $(date +%s)-t1 ))"; echo "mariadb-upgrade exit=$rc_up; check exit=$rc_ck; errorlog error-like lines=$bad; check non-OK lines=$notok"; } | tee "$OUT/result.txt"
[ $rc_up -eq 0 ] && [ $rc_ck -eq 0 ] || { echo "SC-ENGINE" | tee -a "$OUT/result.txt"; exit 1; }
