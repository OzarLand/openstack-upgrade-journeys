#!/usr/bin/env bash
# Shared helpers of the fast-forward (ff) experiments. Source after scripts/lib.sh semantics; never run directly.
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"
FF_DIR="$LAB_DIR/ff"; FF_RUN_ROOT="$RUN_DIR/ff"
TOOL_IMG="$PYIMG_TAG"            # python 3.8 image with PyMySQL: used for the snapshot/compare tools only
BASE_BACKUP="${BASE_BACKUP:-$BACKUP_DIR/latest}"
ff_vars() { # ff_vars <run-id>
  RUN="$1"; NET_FF="ufj-ff-$RUN-net"; DB_FF="ufj-ff-$RUN-db"; VOL_FF="ufj-ff-$RUN-data"; CFG_FF="$FF_RUN_ROOT/$RUN"
  EXP_EV="${EXP_EV:-$EVIDENCE_DIR/../EXP-DB-01}"; RUN_EV="$EXP_EV/$RUN"; mkdir -p "$CFG_FF" "$RUN_EV"
  set -a; . "$BASE_BACKUP/config/passwords.env"; set +a
}
ff_mysql() { docker exec -i -e MYSQL_PWD="$DB_ROOT" "$DB_FF" sh -c 'exec "$(command -v mariadb || command -v mysql)" -uroot "$@"' _ "$@" 2>/dev/null; }
ff_sql() { ff_mysql -N -B -e "$1"; }
ff_redact() { # stdin -> stdout, every generated secret replaced
  python3 -c '
import sys,re
vals=[l.split("=",1)[1].strip() for l in open(sys.argv[1]) if "=" in l]
t=sys.stdin.read()
for v in sorted(set(vals),key=len,reverse=True):
    if len(v)>=8: t=t.replace(v,"<redacted>")
sys.stdout.write(t)' "$BASE_BACKUP/config/passwords.env"; }
DB_FLAGS=(--character-set-server=utf8 --collation-server=utf8_general_ci --log-bin=mysql-bin --binlog-format=ROW --expire-logs-days=14 --default-storage-engine=innodb --innodb-autoinc-lock-mode=2 --max-connections=1000 --skip-name-resolve --innodb-buffer-pool-size=512M)
ff_db_start() { # ff_db_start <image>
  docker rm -f "$DB_FF" >/dev/null 2>&1 || true
  docker run -d --name "$DB_FF" --hostname ufj-mariadb --network "$NET_FF" --network-alias ufj-mariadb --label org.ozarland.ufj=1 \
    -v "$VOL_FF":/var/lib/mysql -e MYSQL_ROOT_PASSWORD="$DB_ROOT" "$1" "${DB_FLAGS[@]}" >/dev/null
  local i; for i in $(seq 1 120); do docker exec -e MYSQL_PWD="$DB_ROOT" "$DB_FF" sh -c 'mariadb -uroot -e "select 1" || mysql -uroot -e "select 1"' >/dev/null 2>&1 && return 0; sleep 2; done
  docker logs --tail 30 "$DB_FF" >&2; return 1
}
# ff_oneshot <release|ussuri> <svc> <extra docker args...> -- <command...>
# Config = the rendered baseline (production-style) file + override.conf mounted as a second --config-file by the caller.
ff_oneshot() {
  local rel=$1 svc=$2; shift 2; local extra=(); while [ "$1" != "--" ]; do extra+=("$1"); shift; done; shift
  local img="ufj-ff-$rel:1"; [ "$rel" = ussuri ] && img="$PYIMG_TAG"
  docker run --rm --network "$NET_FF" --label org.ozarland.ufj=1 -v "$CFG_FF/etc/$svc:/etc/$svc:ro" -v "$CFG_FF/override:/etc/ff:ro" \
    -v "$FF_DIR:/ffsrc:ro" "${extra[@]}" "$img" "$@"
}
