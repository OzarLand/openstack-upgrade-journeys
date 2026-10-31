#!/usr/bin/env bash
# Dispatcher. usage: ./ufj.sh build|up|populate|capture|verify|restore-test|restore|destroy|status
D="$(cd "$(dirname "$0")" && pwd)/scripts"
case "${1:-}" in
  build)        shift; exec "$D/05-build-image.sh" "$@";;
  up)           "$D/10-infra.sh" && "$D/20-config.sh" && "$D/30-dbsync-keystone.sh" && "$D/35-client-keystone.sh" \
                && "$D/40-dbsync-services.sh" && "$D/50-services.sh";;
  populate)     exec "$D/60-populate.sh";;
  capture)      exec "$D/70-capture.sh";;
  verify)       exec "$D/90-verify.sh" "${2:-}";;
  restore-test) shift; exec "$D/80-restore-test.sh" "$@";;
  restore)      shift; exec "$D/85-restore-into-lab.sh" "$@";;
  destroy)      shift; exec "$D/99-destroy.sh" "$@";;
  status)       docker ps -a --filter name='^ufj-' --format 'table {{.Names}}\t{{.Status}}'; docker volume ls -q | grep '^ufj-';;
  *) echo "usage: $0 build|up|populate|capture|verify|restore-test|restore|destroy|status"; exit 2;;
esac
