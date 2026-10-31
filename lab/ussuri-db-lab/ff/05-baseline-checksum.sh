#!/usr/bin/env bash
# sha256 of every file of the two preserved baselines (backups/latest and backups/latest-pre-forced-down).
# usage: 05-baseline-checksum.sh <label: before|after> -> evidence/EXP-DB-01/baseline-checksums-<label>.txt
. "$(dirname "$0")/../scripts/lib.sh"
OUT="$EVIDENCE_DIR/../EXP-DB-01/baseline-checksums-${1:?label}.txt"; mkdir -p "$(dirname "$OUT")"
{ echo "# $(date -u +%FT%TZ) $1"; for l in latest latest-pre-forced-down; do d=$(readlink -f "$BACKUP_DIR/$l"); echo "## $l -> $(basename "$d")"; (cd "$d" && find . -type f ! -name 'restore-test-*' ! -name 'verify-*' -print0 | sort -z | xargs -0 sha256sum); done; } > "$OUT"
echo "$OUT: $(grep -c '^[0-9a-f]\{64\}' "$OUT") files, digest of digests $(grep '^[0-9a-f]' "$OUT" | sha256sum | cut -c1-16)"
