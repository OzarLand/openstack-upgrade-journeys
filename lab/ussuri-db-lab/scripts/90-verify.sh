#!/usr/bin/env bash
# Functional re-check: compares the live control plane (via the APIs) with the inventory of a baseline capture and runs
# functional checks (logins, image checksums, servers, write test). usage: 90-verify.sh [backup-dir]
. "$(dirname "$0")/lib.sh"; load_secrets
B=$(readlink -f "${1:-$BACKUP_DIR/latest}"); [ -f "$B/inventory.json" ] || die "no inventory in $B"
docker cp "$B/inventory.json" ufj-client:/tmp/baseline-inventory.json
set +e
docker exec -i -e ADMIN -e USER_ALICE -e USER_BOB ufj-client bash -c 'set -a; . /run/ufj/admin-openrc; set +a; export OS_PASSWORD="$ADMIN"; python /lab/tools/inventory.py verify --baseline /tmp/baseline-inventory.json --report /tmp/verify-report.txt'
rc=$?
docker cp ufj-client:/tmp/verify-report.txt "$B/verify-$(date -u +%Y%m%dT%H%M%SZ).txt" 2>/dev/null
exit $rc
