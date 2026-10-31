#!/usr/bin/env bash
# Shared settings for the Ussuri control-plane lab. Source this file; do not run it.
# Everything the lab creates is named ufj-* so cleanup is targeted (see destroy.sh).
set -euo pipefail
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_DIR="$LAB_DIR/.secrets"      # git-ignored: passwords.env
RUN_DIR="$LAB_DIR/.run"              # git-ignored: rendered config files (contain passwords)
BACKUP_DIR="$LAB_DIR/backups"        # git-ignored: dumps and tarballs (contain credentials hashes, fernet keys)
EVIDENCE_DIR="${EVIDENCE_DIR:-$LAB_DIR/../../journeys/ussuri-to-2026.1/evidence/lab-baseline}"
PYIMG_TAG="ufj-ussuri-py38:1"
NET="ufj-net"
MARIADB_IMAGE="${MARIADB_IMAGE:-mariadb:10.3}"
RABBIT_IMAGE="${RABBIT_IMAGE:-rabbitmq:3.8-management}"
MEMCACHED_IMAGE="${MEMCACHED_IMAGE:-memcached:1.5}"
# docker volumes (state): database, rabbitmq, glance images, keystone fernet keys, nova/cinder/neutron state dirs
VOLUMES=(ufj-mariadb-data ufj-rabbitmq-data ufj-glance-images ufj-keystone-keys)
SERVICES_DB=(keystone glance placement nova_api nova nova_cell0 neutron cinder)

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing command: $1"; }

gen_secrets() {
  mkdir -p "$SECRETS_DIR"; chmod 700 "$SECRETS_DIR"
  [ -f "$SECRETS_DIR/passwords.env" ] && return 0
  umask 077
  {
    for k in DB_ROOT RABBIT ADMIN SVC_KEYSTONE SVC_GLANCE SVC_PLACEMENT SVC_NOVA SVC_NEUTRON SVC_CINDER \
             DBPW_KEYSTONE DBPW_GLANCE DBPW_PLACEMENT DBPW_NOVA DBPW_NEUTRON DBPW_CINDER \
             METADATA_SECRET USER_ALICE USER_BOB USER_CAROL; do
      printf '%s=%s\n' "$k" "$(openssl rand -hex 12)"
    done
  } > "$SECRETS_DIR/passwords.env"
  log "generated $SECRETS_DIR/passwords.env (git-ignored)"
}
load_secrets() { gen_secrets; set -a; . "$SECRETS_DIR/passwords.env"; set +a; }

mysql_root() { docker exec -i -e MYSQL_PWD="$DB_ROOT" ufj-mariadb mysql -uroot "$@"; }
ufj_client() { docker exec -i ufj-client "$@"; }
# openstack CLI inside ufj-client with the admin credentials of the lab (password read from the secrets file there)
osc() { docker exec -i ufj-client bash -c 'set -a; . /run/ufj/admin-openrc; set +a; exec openstack "$@"' _ "$@"; }

IMG="$PYIMG_TAG"
# oneshot <service-etc-dir> <extra docker args...> -- <command...>: run a command in a throwaway container with the config mounted
oneshot() {
  local svc=$1; shift; local extra=()
  while [ "$1" != "--" ]; do extra+=("$1"); shift; done; shift
  docker run --rm --network "$NET" --label org.ozarland.ufj=1 -v "$RUN_DIR/etc/$svc:/etc/$svc:ro" "${extra[@]}" "$IMG" "$@"
}
cexists()  { docker inspect "$1" >/dev/null 2>&1; }
crunning() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]; }
# svc_start <container> <etcdir> <docker args...> -- <command...>: long-running service container, kept if already running
svc_start() {
  local n=$1 svc=$2; shift 2; local extra=()
  while [ "$1" != "--" ]; do extra+=("$1"); shift; done; shift
  if crunning "$n"; then return 0; elif cexists "$n"; then docker start "$n" >/dev/null; return 0; fi
  docker run -d --name "$n" --hostname "$n" --network "$NET" --label org.ozarland.ufj=1 --restart unless-stopped \
    -v "$RUN_DIR/etc/$svc:/etc/$svc:ro" "${extra[@]}" "$IMG" "$@" >/dev/null
}
wait_http() { # wait_http <url> [seconds]
  local i; for i in $(seq 1 "${2:-120}"); do docker exec ufj-client python -c "import urllib.request,sys; urllib.request.urlopen('$1', timeout=3)" >/dev/null 2>&1 && return 0
    # 401 on a versioned endpoint also proves the service is up
    docker exec ufj-client python -c "import urllib.request,urllib.error; 
try: urllib.request.urlopen('$1', timeout=3)
except urllib.error.HTTPError as e: raise SystemExit(0 if e.code in (300,401,403) else 1)
except Exception: raise SystemExit(1)" >/dev/null 2>&1 && return 0; sleep 1; done; return 1
}

# Containers that write to MariaDB (everything labelled ufj except the infra containers and the client)
service_containers() { docker ps -a --filter label=org.ozarland.ufj=1 --format '{{.Names}}' | grep -vE '^ufj-(mariadb|rabbitmq|memcached|client|restore-.*)$' | sort; }
# SQL helpers working on any running MariaDB container: $1 = container, password in $2
sql_tables() { docker exec -e MYSQL_PWD="$2" "$1" mysql -uroot -N -e "SELECT table_schema, table_name FROM information_schema.tables WHERE table_type='BASE TABLE' AND table_schema NOT IN ('information_schema','performance_schema') ORDER BY 1,2"; }
sql_rowcounts() { # container pw -> TSV db table rows (exact COUNT(*))
  sql_tables "$1" "$2" | awk -F'\t' '{printf "SELECT \"%s\",\"%s\",COUNT(*) FROM `%s`.`%s`;\n",$1,$2,$1,$2}' | docker exec -i -e MYSQL_PWD="$2" "$1" mysql -uroot -N; }
sql_checksums() { # container pw -> TSV db.table checksum
  sql_tables "$1" "$2" | awk -F'\t' '{printf "CHECKSUM TABLE `%s`.`%s`;\n",$1,$2}' | docker exec -i -e MYSQL_PWD="$2" "$1" mysql -uroot -N; }
OS_DBS=(keystone glance placement nova_api nova nova_cell0 neutron cinder)
