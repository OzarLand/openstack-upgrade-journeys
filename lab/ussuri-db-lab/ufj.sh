#!/usr/bin/env bash
# Dispatcher. usage: ./ufj.sh build|up|populate|capture|verify|restore-test|restore|destroy|status
D="$(cd "$(dirname "$0")" && pwd)/scripts"
case "${1:-}" in
  build)        shift; exec "$D/05-build-image.sh" "$@";;
  up)           exec "$D/01-up.sh";;
  versions)     exec "$D/75-versions.sh";;
  all)          "$0" build && "$0" up && "$0" populate && "$0" versions && "$0" capture && "$0" restore-test && "$0" verify;;
  populate)     exec "$D/60-populate.sh";;
  capture)      exec "$D/72-capture-both.sh";;
  verify)       exec "$D/90-verify.sh" "${2:-}";;
  restore-test) shift; exec "$D/80-restore-test.sh" "$@";;
  restore)      shift; exec "$D/85-restore-into-lab.sh" "$@";;
  destroy)      shift; exec "$D/99-destroy.sh" "$@";;
  ff)           shift; exec "$(dirname "$0")/ff/${1:?script}" "${@:2}";;
  status)       docker ps -a --filter name='^ufj-' --format 'table {{.Names}}\t{{.Status}}'; docker volume ls -q | grep '^ufj-';;
  *) echo "usage: $0 build|up|populate|versions|capture|verify|restore-test|restore|destroy|status|all"; exit 2;;
esac
