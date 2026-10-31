#!/usr/bin/env bash
# DR-003: mark every Ussuri nova-compute service forced-down THROUGH THE USSURI API (compute API microversion >= 2.11), never by SQL.
# The computes must already be stopped (70-capture.sh with STAGE=pre-forced-down stops them and records the proof).
. "$(dirname "$0")/lib.sh"; load_secrets
docker ps --format '{{.Names}}' | grep -E '^ufj-compute[0-9]+$' && die "a fake compute container is still running"
docker exec -i -e ADMIN ufj-client bash -c 'set -a; . /run/ufj/admin-openrc; set +a; export OS_PASSWORD="$ADMIN"; export OS_COMPUTE_API_VERSION=2.53
for h in $(openstack compute service list --service nova-compute -f value -c Host); do openstack compute service set --down "$h" nova-compute && echo "forced down: $h"; done
openstack compute service list --long -c ID -c Binary -c Host -c Status -c State -c "Forced Down" -c "Disabled Reason"' | tee "$RUN_DIR/forced-down.txt"
mkdir -p "$EVIDENCE_DIR"; cp "$RUN_DIR/forced-down.txt" "$EVIDENCE_DIR/forced-down-api-output.txt"
