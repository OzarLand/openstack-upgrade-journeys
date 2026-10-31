#!/usr/bin/env bash
# Helpers of the 2026.1 runtime lab (EXP-SVC-01/02). Everything is named ufj-svc-*; the databases/endpoints keep the names of the
# Ussuri lab (ufj-mariadb, ufj-keystone, ... as network aliases) because the catalog and nova's cell mappings store those names.
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"
SVC_DIR="$LAB_DIR/svc"; SVC_RUN="$RUN_DIR/svc"; SNET=ufj-svc-net; SIMG=ufj-svc-2026.1:1
SBASE="${SBASE:-$BACKUP_DIR/../backups-v4/latest}"      # Ussuri baseline v4 (config templates, keys, passwords)
set -a; . "$SBASE/config/passwords.env"; set +a
EVD="${EVD:-$EVIDENCE_DIR/../EXP-SVC-01}"
sname() { echo "ufj-svc-$1"; }
srun() { # srun <container> <alias> <extra docker args...> -- <command...>  : long-running container on ufj-svc-net, name ufj-svc-<container>, network alias <alias>
  local n=$1 al=$2; shift 2; local extra=(); while [ "$1" != "--" ]; do extra+=("$1"); shift; done; shift
  docker rm -f "ufj-svc-$n" >/dev/null 2>&1
  docker run -d --name "ufj-svc-$n" --hostname "${HOSTN:-$al}" --network "$SNET" --network-alias "$al" --label org.ozarland.ufj=1 --label org.ozarland.svc=1 \
    "${extra[@]}" "$@" >/dev/null
}
sexec() { docker exec -i "$@"; }
sdb() { docker exec -i -e MYSQL_PWD="$DB_ROOT" ufj-svc-db sh -c 'exec mariadb -uroot "$@"' _ "$@"; }
# openstack CLI (2026.1 client) inside ufj-svc-client with admin credentials; extra args = the command
sosc() { docker exec -i ufj-svc-client bash -c 'set -a; . /run/svc/admin-openrc; set +a; exec openstack "$@"' _ "$@"; }
slog() { docker logs "ufj-svc-$1" 2>&1; }
swait() { # swait <url> [seconds] : HTTP answer (any status < 500) from inside the client container
  local i; for i in $(seq 1 "${2:-120}"); do docker exec ufj-svc-client python -c "
import urllib.request,urllib.error,sys
try: urllib.request.urlopen('$1', timeout=3)
except urllib.error.HTTPError as e: sys.exit(0 if e.code < 500 else 1)
except Exception: sys.exit(1)" >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }
