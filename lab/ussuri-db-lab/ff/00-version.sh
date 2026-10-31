#!/usr/bin/env bash
# Harness version of a run: git commit, dirty flag, sha256 of every harness file (comparator included), image ids.
# usage: 00-version.sh <run> [--strict]   --strict: exit 1 when the harness tree is not committed (a strict run must not start).
. "$(dirname "$0")/lib.sh"; ff_vars "${1:?run}"; set +e
O="$RUN_EV/harness.txt"; REPO=$(git -C "$LAB_DIR" rev-parse --show-toplevel 2>/dev/null)
SHA=$(git -C "$LAB_DIR" rev-parse HEAD 2>/dev/null); DIRTY=$(git -C "$LAB_DIR" status --porcelain -- ff scripts tools wsgi image ufj.sh 2>/dev/null | grep -v '^??.*\(ff/image/.*/\(ca\|build.log\)\)' | wc -l)
{
echo "# harness version $(date -u +%FT%TZ)"
echo "repository: $REPO"
echo "commit: ${SHA:-unknown (not a git checkout)}"
echo "uncommitted harness changes (ff scripts tools wsgi image ufj.sh): $DIRTY"
echo "--- sha256 of the harness files"
( cd "$LAB_DIR" && find ff scripts tools wsgi -type f \( -name '*.sh' -o -name '*.py' -o -name '*.json' -o -name Dockerfile \) ! -path '*/ca/*' | sort | xargs sha256sum )
echo "--- images"
for i in ufj-ff-2023.1:1 ufj-ff-2023.2:1 ufj-ff-2024.1:1 ufj-ff-2025.1:1 ufj-ff-2026.1:1 "$PYIMG_TAG" mariadb:10.3 mariadb:10.5 mariadb:10.6 mariadb:10.11 mariadb:11.4; do echo "$i $(docker image inspect "$i" -f '{{.Id}}' 2>/dev/null || echo missing)"; done
echo "--- baseline: $BASE_BACKUP -> $(readlink -f "$BASE_BACKUP")"
} > "$O"
cat "$O" | head -6
if [ "${2:-}" = --strict ] && { [ "$DIRTY" != 0 ] || [ -z "$SHA" ]; }; then echo "REFUSED: the harness has uncommitted changes (or is not versioned). Commit it, then start the strict run."; exit 1; fi
exit 0
