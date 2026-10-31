#!/usr/bin/env bash
# @@GLOBAL.sql_mode of each engine image with the lab's server flags (correction 5 of the checklist review). Throwaway containers.
. "$(dirname "$0")/lib.sh"; OUT="$EVIDENCE_DIR/../EXP-DB-01/engine-sql-mode.txt"; : > "$OUT"
for img in mariadb:10.3 mariadb:10.5 mariadb:10.6 mariadb:10.11 mariadb:11.4; do
  n=ufj-ff-sqlmode; docker rm -f $n >/dev/null 2>&1
  docker run -d --name $n -e MYSQL_ROOT_PASSWORD=x "$img" "${DB_FLAGS[@]}" >/dev/null
  for i in $(seq 1 60); do docker exec -e MYSQL_PWD=x $n sh -c 'exec "$(command -v mariadb || command -v mysql)" -uroot -N -e "select 1"' >/dev/null 2>&1 && break; sleep 2; done
  echo "$img $(docker exec -e MYSQL_PWD=x $n sh -c 'exec "$(command -v mariadb || command -v mysql)" -uroot -N -e "select version(), @@GLOBAL.sql_mode, @@character_set_server, @@collation_server"' 2>/dev/null | tr '\t' ' ')" | tee -a "$OUT"
  docker rm -f $n >/dev/null
done
