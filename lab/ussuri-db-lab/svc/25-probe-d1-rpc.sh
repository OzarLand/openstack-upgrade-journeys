#!/usr/bin/env bash
# SUPPLEMENTARY probe (not part of the strict EXP-SVC-01 run): state (d) with a compute-RPC-bearing call while no 2026.1 compute is registered,
# to obtain the positive log evidence "Not caching compute RPC version_cap, because min service_version is 0" (DEBUG, once per process).
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"; set +eu
OUT="$EVD/probe-d1-rpc"; mkdir -p "$OUT"; STK="$SVC_DIR/10-stack.sh"
docker stop ufj-ff-derive-h4r-db >/dev/null 2>&1; "$STK" down >/dev/null; "$STK" clone ufj-ff-derive-h4r-data >/dev/null; "$STK" infra >/dev/null 2>&1; "$STK" up
T=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sid=$(sdb -N -e "select uuid from nova.instances where host='ufj-compute1' and vm_state='active' and deleted=0 order by id limit 1")
{ echo "server $sid on the fenced ufj-compute1 (service row forced-down, version 51); no 2026.1 compute running"; sosc server stop $sid 2>&1; echo "stop exit $?"; sleep 15
  sosc server show $sid -f value -c status -c OS-EXT-STS:task_state 2>&1 | paste -sd' '; } > "$OUT/call.txt" 2>&1
for c in nova-api nova-conductor nova-scheduler; do docker logs --since "$T" ufj-svc-$c 2>&1 | grep -E "Not caching|Automatically selected|TooOld" | sed -E "s/^/$c: /" | cut -c1-300; done > "$OUT/rpc-lines.txt"
cat "$OUT/call.txt" "$OUT/rpc-lines.txt"
