#!/usr/bin/env bash
# Restores the Docker volumes (database, keystone keys, glance images) and the configuration/secrets from a baseline
# capture into the lab, then starts everything WITHOUT writing to the restored database.
# DESTRUCTIVE for the live lab state: needs --yes. usage: 85-restore-into-lab.sh --yes [backup-dir]
. "$(dirname "$0")/lib.sh"
[ "${1:-}" = --yes ] || die "needs --yes (replaces ufj-mariadb-data, ufj-keystone-keys, ufj-glance-images)"; shift
B=$(readlink -f "${1:-$BACKUP_DIR/latest}"); [ -f "$B/MANIFEST.sha256" ] || die "no baseline at $B"
(cd "$B" && sha256sum --quiet -c MANIFEST.sha256) || die "baseline manifest check failed: refusing to restore"
T0=$(date +%s)
mapfile -t OLD < <(docker ps -a --format '{{.Names}}' | grep -E '^ufj-' || true); [ ${#OLD[@]} -gt 0 ] && docker rm -f "${OLD[@]}" >/dev/null
for v in ufj-mariadb-data ufj-keystone-keys ufj-glance-images ufj-rabbitmq-data; do docker volume rm "$v" >/dev/null 2>&1 || true; docker volume create "$v" >/dev/null; done
docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
mkdir -p "$SECRETS_DIR" "$RUN_DIR"; chmod 700 "$SECRETS_DIR"
cp "$B/config/passwords.env" "$SECRETS_DIR/passwords.env"; chmod 600 "$SECRETS_DIR/passwords.env"
rm -rf "$RUN_DIR/etc"; tar -C "$RUN_DIR" -xzf "$B/config/rendered-etc.tar.gz"
for v in ufj-mariadb-data ufj-keystone-keys ufj-glance-images; do
  docker run --rm -v "$v":/v -v "$B/volumes":/in:ro "$MARIADB_IMAGE" sh -c "tar -C /v -xzf /in/$v.tar.gz"; log "restored volume $v"; done
UFJ_SKIP_DB_BOOTSTRAP=1 "$(dirname "$0")/10-infra.sh"
FENCED="${FENCED:-1}" "$(dirname "$0")/50-services.sh"   # the baseline is a fenced platform: computes and fake agents stay stopped (FENCED=0 to start them)
log "restore into lab done in $(( $(date +%s)-T0 )) s from $B"
