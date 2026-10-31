#!/usr/bin/env bash
# Targeted cleanup: only containers, volumes and the network whose names start with "ufj-" (and the ufj-ussuri image
# with --images). Backups (backups/) and secrets (.secrets/) are NOT touched unless --purge-backups / --purge-secrets.
# Refuses to run without --yes: this deletes the live lab database volume. Take a capture first (70-capture.sh).
. "$(dirname "$0")/lib.sh"
YES=0; IMAGES=0; PB=0; PS=0
for a in "$@"; do case $a in --yes) YES=1;; --images) IMAGES=1;; --purge-backups) PB=1;; --purge-secrets) PS=1;; *) die "unknown option $a";; esac; done
echo "Will remove containers: $(docker ps -a --format '{{.Names}}' | grep -E '^ufj-' | grep -vE '^ufj-ff-' | tr '\n' ' ')"
echo "Will remove volumes:    $(docker volume ls -q | grep -E '^ufj-' | grep -vE '^ufj-ff-' | tr '\n' ' ')"
[ $YES = 1 ] || die "re-run with --yes to delete (latest baseline: $(readlink -f "$BACKUP_DIR/latest" 2>/dev/null || echo none))"
docker ps -a --format '{{.Names}}' | grep -E '^ufj-' | grep -vE '^ufj-ff-' | xargs -r docker rm -f >/dev/null
docker volume ls -q | grep -E '^ufj-' | grep -vE '^ufj-ff-' | xargs -r docker volume rm >/dev/null
docker network inspect "$NET" >/dev/null 2>&1 && docker network rm "$NET" >/dev/null
[ $IMAGES = 1 ] && { docker rmi "$PYIMG_TAG" >/dev/null 2>&1 || true; docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^ufj/" | xargs -r docker rmi >/dev/null 2>&1 || true; }
rm -rf "$RUN_DIR"
[ $PB = 1 ] && rm -rf "$BACKUP_DIR"
[ $PS = 1 ] && rm -rf "$SECRETS_DIR"
log "removed. Remaining ufj-* objects: $(docker ps -a --format '{{.Names}}' | grep -cE '^ufj-') containers, $(docker volume ls -q | grep -cE '^ufj-') volumes"
