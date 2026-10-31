#!/usr/bin/env bash
# Builds nothing; brings the control plane up from an existing image: infra, config, keystone, db syncs, services.
# Step logs: .run/logs/<step>.log; timings: .run/up-timings.txt (copied to the evidence dir).
. "$(dirname "$0")/lib.sh"; D="$(dirname "$0")"
docker image inspect "$PYIMG_TAG" >/dev/null 2>&1 || die "image $PYIMG_TAG missing: run ./ufj.sh build first"
mkdir -p "$RUN_DIR/logs"; : > "$RUN_DIR/up-timings.txt"
for step in 10-infra 20-config 30-dbsync-keystone 35-client-keystone 40-dbsync-services 50-services; do
  t0=$(date +%s); log "$step"
  "$D/$step.sh" > "$RUN_DIR/logs/$step.log" 2>&1 || { tail -25 "$RUN_DIR/logs/$step.log"; die "$step failed (log: $RUN_DIR/logs/$step.log)"; }
  printf '%s\t%s s\n' "$step" "$(( $(date +%s)-t0 ))" | tee -a "$RUN_DIR/up-timings.txt"
done
# nova: map the two fake computes into cell1 (the scheduler would do it within 30 s; do it now, deterministically)
for i in $(seq 1 30); do [ "$(docker exec ufj-client bash -c 'set -a; . /run/ufj/admin-openrc; set +a; openstack compute service list --service nova-compute -f value -c Host | wc -l')" -ge 2 ] && break; sleep 2; done
oneshot nova -- nova-manage --config-file /etc/nova/nova.conf cell_v2 discover_hosts --verbose > "$RUN_DIR/logs/discover_hosts.log" 2>&1
mkdir -p "$EVIDENCE_DIR"; cp "$RUN_DIR/up-timings.txt" "$EVIDENCE_DIR/up-timings.txt"; cp "$RUN_DIR/dbsync-timings.txt" "$EVIDENCE_DIR/dbsync-timings.txt"
log "control plane up"
