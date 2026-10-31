#!/usr/bin/env bash
# Restore test into FRESH MariaDB containers (never touches the running lab):
#   A. logical: all-databases.sql.gz loaded into an empty mariadb:10.3
#   B. physical: the cold tarball of ufj-mariadb-data unpacked into a new volume and started
# Proves equality with the baseline: exact row counts, CHECKSUM TABLE of every table, sha256 of the OpenStack-only dump.
# usage: 80-restore-test.sh [backup-dir]   (default: backups/latest)
. "$(dirname "$0")/lib.sh"
B=$(readlink -f "${1:-$BACKUP_DIR/latest}"); [ -f "$B/MANIFEST.sha256" ] || die "no baseline at $B"
set -a; . "$B/config/passwords.env"; set +a
OUT="$B/restore-test-$(date -u +%Y%m%dT%H%M%SZ).txt"; : > "$OUT"
say() { echo "$*" | tee -a "$OUT"; }
cleanup() { docker rm -f ufj-restore-sql ufj-restore-vol >/dev/null 2>&1 || true; docker volume rm ufj-restore-sql-data ufj-restore-vol-data >/dev/null 2>&1 || true; }
trap cleanup EXIT; cleanup
say "# restore test of $B at $(date -u +%FT%TZ)"
say "manifest check: $( (cd "$B" && sha256sum --quiet -c MANIFEST.sha256 && echo OK) 2>&1 | tail -1 )"

compare() { # compare <container> <label>
  local c=$1 l=$2 ok=1
  sql_rowcounts "$c" "$DB_ROOT" > "$B/.rc.$l"; sql_checksums "$c" "$DB_ROOT" > "$B/.ck.$l"
  if diff -q "$B/rowcounts.tsv" "$B/.rc.$l" >/dev/null; then say "[$l] row counts identical for $(wc -l < "$B/rowcounts.tsv") tables"; else say "[$l] ROW COUNT DIFFERENCES:"; diff "$B/rowcounts.tsv" "$B/.rc.$l" | head -20 | tee -a "$OUT"; ok=0; fi
  # CHECKSUM TABLE: the OpenStack databases must be identical; mysql.* system tables are reported but not required
  if diff -q <(grep -vE '^mysql\.' "$B/table-checksums.tsv") <(grep -vE '^mysql\.' "$B/.ck.$l") >/dev/null; then
    say "[$l] CHECKSUM TABLE identical for $(grep -vcE '^mysql\.' "$B/table-checksums.tsv") OpenStack tables"
  else say "[$l] CHECKSUM TABLE DIFFERENCES:"; diff <(grep -vE '^mysql\.' "$B/table-checksums.tsv") <(grep -vE '^mysql\.' "$B/.ck.$l") | head -20 | tee -a "$OUT"; ok=0; fi
  diff -q <(grep -E '^mysql\.' "$B/table-checksums.tsv") <(grep -E '^mysql\.' "$B/.ck.$l") >/dev/null && say "[$l] mysql.* system table checksums identical" || say "[$l] note: mysql.* system tables differ (grants/stats; not part of the OpenStack baseline)"
  local sum; sum=$(docker exec -e MYSQL_PWD="$DB_ROOT" "$c" mysqldump -uroot --routines --triggers --events --single-transaction --hex-blob --skip-dump-date --databases "${OS_DBS[@]}" | sha256sum | awk '{print $1}')
  if [ "$sum" = "$(cat "$B/openstack-databases.sql.sha256")" ]; then say "[$l] sha256 of OpenStack dump identical: $sum"; else say "[$l] DUMP SHA256 DIFFERS: $sum vs $(cat "$B/openstack-databases.sql.sha256")"; ok=0; fi
  rm -f "$B/.rc.$l" "$B/.ck.$l"
  [ $ok = 1 ] && say "[$l] RESULT: PASS" || say "[$l] RESULT: FAIL"; return $((1-ok))
}
waitdb() { for i in $(seq 1 90); do docker exec -e MYSQL_PWD="$DB_ROOT" "$1" mysql -uroot -e 'select 1' >/dev/null 2>&1 && return 0; sleep 2; done; return 1; }
RC=0
T0=$(date +%s)
say "== A. logical restore (all-databases.sql.gz into an empty $MARIADB_IMAGE)"
docker run -d --name ufj-restore-sql --label org.ozarland.ufj=1 -v ufj-restore-sql-data:/var/lib/mysql -e MYSQL_ROOT_PASSWORD="$DB_ROOT" \
  "$MARIADB_IMAGE" --character-set-server=utf8 --collation-server=utf8_general_ci --log-bin=mysql-bin --binlog-format=ROW --skip-name-resolve >/dev/null
waitdb ufj-restore-sql || die "restore container did not start"
zcat "$B/all-databases.sql.gz" | docker exec -i -e MYSQL_PWD="$DB_ROOT" ufj-restore-sql mysql -uroot 2>&1 | head -5 | tee -a "$OUT" || true
docker exec -e MYSQL_PWD="$DB_ROOT" ufj-restore-sql mysql -uroot -e 'FLUSH PRIVILEGES' 
say "logical restore took $(( $(date +%s)-T0 )) s"
compare ufj-restore-sql logical || RC=1
say "== B. physical restore (cold tarball of ufj-mariadb-data into a new volume)"
T1=$(date +%s)
docker volume create ufj-restore-vol-data >/dev/null
docker run --rm -v ufj-restore-vol-data:/v -v "$B/volumes":/in:ro "$MARIADB_IMAGE" sh -c 'tar -C /v -xzf /in/ufj-mariadb-data.tar.gz'
docker run -d --name ufj-restore-vol --label org.ozarland.ufj=1 -v ufj-restore-vol-data:/var/lib/mysql -e MYSQL_ROOT_PASSWORD="$DB_ROOT" \
  "$MARIADB_IMAGE" --character-set-server=utf8 --collation-server=utf8_general_ci --log-bin=mysql-bin --binlog-format=ROW --skip-name-resolve >/dev/null
waitdb ufj-restore-vol || die "tarball restore container did not start"
say "physical restore took $(( $(date +%s)-T1 )) s"
compare ufj-restore-vol physical || RC=1
say "OVERALL: $([ $RC = 0 ] && echo PASS || echo FAIL)"
mkdir -p "$EVIDENCE_DIR"; cp "$OUT" "$EVIDENCE_DIR/restore-test.txt"
exit $RC
