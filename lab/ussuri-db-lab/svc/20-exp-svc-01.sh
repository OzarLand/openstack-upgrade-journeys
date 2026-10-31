#!/usr/bin/env bash
# EXP-SVC-01: 2026.1 services on the fast-forwarded (H4r) databases; DR-003 gate states (d), then (a) -> (b) -> (c); F2 read-back; C-5.
#   usage: 20-exp-svc-01.sh <label> [d|abc|all]      evidence: evidence/EXP-SVC-01/<label>/
# Every part starts from a fresh clone of the H4r database (volume $H4R_VOL, never modified).
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
set +eu
LABEL=${1:?label}; PART=${2:-all}
OUT="$EVD/$LABEL"; mkdir -p "$OUT"
H4R_VOL=${H4R_VOL:-ufj-ff-derive-h4r-data}
STK="$SVC_DIR/10-stack.sh"
NOVA_CONF="$SVC_RUN/etc/nova/nova.conf"
note() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$OUT/run.log"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
rows() { # rows <state> <tag> : every nova.services row (read-only SQL)
  mkdir -p "$OUT/$1"; sdb -e "select id,host,\`binary\`,version,disabled,disabled_reason,forced_down,deleted,updated_at from nova.services order by id" > "$OUT/$1/services-rows-$2.tsv" 2>&1; }
nodes() { mkdir -p "$OUT/$1"; sdb -e "select id,uuid,host,hypervisor_hostname,service_id,deleted,mapped from nova.compute_nodes order by id" > "$OUT/$1/compute-nodes-$2.tsv" 2>&1; }
waitapi() { swait http://ufj-keystone:5000/v3 60; swait http://ufj-nova-api:8774/ 120; }
ctl_restart() { # restart the three Nova control services (one restart, as in DR-003 step 5)
  docker restart ufj-svc-nova-api ufj-svc-nova-conductor ufj-svc-nova-scheduler >/dev/null 2>&1; sleep 5; waitapi; }
rpc_lines() { # rpc_lines <state> <tag> <since>
  mkdir -p "$OUT/$1"; : > "$OUT/$1/rpc-cap-$2.txt"
  for c in nova-api nova-conductor nova-scheduler; do
    docker logs --since "$3" ufj-svc-$c 2>&1 | grep -E "Automatically selected compute RPC|Not caching compute RPC|TooOldComputeService|too old|Unhandled error|SchedulerHostFilterNotFound" | sed -E "s/^/$c: /" | cut -c1-400 >> "$OUT/$1/rpc-cap-$2.txt"; done
  echo "(containers: $(docker ps -a --filter label=org.ozarland.svc=1 --format '{{.Names}}={{.Status}}' | grep nova | tr '\n' ' '))" >> "$OUT/$1/rpc-cap-$2.txt"
  cat "$OUT/$1/rpc-cap-$2.txt" | tee -a "$OUT/run.log"; }
status_all() { # status_all <state> <tag> : every *-status upgrade check with the services online
  mkdir -p "$OUT/$1"; f="$OUT/$1/status-tools-$2.txt"; : > "$f"; K="$SVC_RUN/keys"; R=(docker run --rm --network $SNET)
  st_run() { echo "===== $1" >> "$f"; shift; "$@" >> "$f" 2>&1; echo "===== exit code: $?" >> "$f"; }
  st_run "nova-status upgrade check" "${R[@]}" -v "$SVC_RUN/etc/nova:/etc/nova:ro" $SIMG nova-status upgrade check
  st_run "cinder-status upgrade check" "${R[@]}" -v "$SVC_RUN/etc/cinder:/etc/cinder:ro" $SIMG cinder-status upgrade check
  st_run "neutron-status --config-file neutron.conf upgrade check" "${R[@]}" -v "$SVC_RUN/etc/neutron:/etc/neutron:ro" $SIMG neutron-status --config-file /etc/neutron/neutron.conf upgrade check
  st_run "placement-status upgrade check" "${R[@]}" -v "$SVC_RUN/etc/placement:/etc/placement:ro" $SIMG placement-status upgrade check
  st_run "glance-status --config-file glance-api.conf upgrade check" "${R[@]}" -v "$SVC_RUN/etc/glance:/etc/glance:ro" $SIMG glance-status --config-file /etc/glance/glance-api.conf upgrade check
  st_run "keystone-status --config-file keystone.conf upgrade check (keys also mounted at /etc/keystone: the tool checks the default repository paths)" "${R[@]}" -v "$K/fernet-keys:/etc/keystone/fernet-keys:ro" -v "$K/credential-keys:/etc/keystone/credential-keys:ro" -v "$K:/var/lib/ufj/keys:ro" -v "$SVC_RUN/etc/keystone:/conf:ro" $SIMG keystone-status --config-file /conf/keystone.conf upgrade check
  grep -E "^=====|Check:|Result:" "$f" | paste -sd' ' | sed 's/=====/\n=====/g' | sed -E 's/ +/ /g;s/\| //g' | tee -a "$OUT/run.log" | cut -c1-700; }
svcset() { # svcset up|down <host> : forced-down through the 2026.1 API; on failure the HTTP error body is logged
  out=$(sosc compute service set --$1 $2 nova-compute 2>&1); rc=$?; echo "compute service set --$1 $2 nova-compute -> rc=$rc $out" | tee -a "$OUT/run.log"
  if [ $rc != 0 ]; then sosc --debug compute service set --$1 $2 nova-compute 2>&1 | grep -E "RESP BODY|HTTP/1.1\" [45]" | cut -c1-400 | tee -a "$OUT/run.log"; fi; }
flag() { # flag on|off : [workarounds] disable_compute_service_check_for_ffu in nova.conf (edited in place)
  python3 - "$1" "$NOVA_CONF" <<'PY'
import sys,re
mode,p=sys.argv[1:3]; t=open(p).read()
t=re.sub(r'\n\[workarounds\]\ndisable_compute_service_check_for_ffu = true\n','\n',t)
if mode=='on': t=t.rstrip('\n')+'\n\n[workarounds]\ndisable_compute_service_check_for_ffu = true\n'
open(p,'w').write(t)
PY
  note "workaround flag $1: $(grep -c disable_compute_service_check_for_ffu "$NOVA_CONF") line(s) in nova.conf"; }
op() { # op <state> <tag> <host> <since> : RPC-bearing operation = build_and_run_instance on <host> (server create --nic none, old image and flavor, forced host); then delete it
  mkdir -p "$OUT/$1"; f="$OUT/$1/op-$2.txt"; : > "$f"
  az=$(sosc compute service list --service nova-compute -f value -c Host -c Zone 2>/dev/null | awk -v h=$3 '$1==h{print $2}')
  name=ufj-svc01-op-$1-$2
  sosc server create --flavor ufj-tiny --image ufj-image-public --nic none --availability-zone "$az:$3" "$name" -f value -c id > "$OUT/$1/.sid" 2>> "$f"; echo "server create -> exit $? (flavor ufj-tiny, image ufj-image-public, host $az:$3)" >> "$f"
  sid=$(grep -E '^[0-9a-f-]{36}$' "$OUT/$1/.sid" | head -1); rm -f "$OUT/$1/.sid"; echo "server $sid" >> "$f"
  for i in $(seq 1 45); do sleep 2; j=$(sosc server show "$sid" -f value -c status 2>&1 | head -1); case "$j" in ACTIVE|ERROR) break;; esac; done
  echo "status after wait: $j" >> "$f"
  sosc server show "$sid" -f json -c status -c OS-EXT-STS:task_state -c OS-EXT-STS:vm_state -c OS-EXT-SRV-ATTR:host -c fault 2>&1 | tr -d '\n' | cut -c1-600 >> "$f"; echo >> "$f"
  echo "compute log (errors since $4):" >> "$f"; docker logs --since "$4" ufj-svc-compute${3#ufj-compute} 2>&1 | grep -E "\] ERROR|UnsupportedVersion|RPC version|Endpoint does not support" | grep -v "DB access" | tail -4 | cut -c1-320 >> "$f"
  docker logs --since "$4" ufj-svc-nova-conductor 2>&1 | grep -E "\] ERROR|UnsupportedVersion|MessagingTimeout|NoValidHost" | tail -3 | cut -c1-320 >> "$f"
  sosc server delete "$sid" >> "$f" 2>&1; for i in $(seq 1 20); do sleep 2; sosc server show "$sid" >/dev/null 2>&1 || break; done
  cat "$f" | tee -a "$OUT/run.log"; rpc_lines "$1" "$2-after-op" "$4"; }
reset() {
  note "reset: fresh clone of $H4R_VOL"; docker stop ufj-ff-derive-h4r-db >/dev/null 2>&1
  "$STK" down >/dev/null; "$STK" clone "$H4R_VOL" | tee -a "$OUT/run.log"; "$STK" infra >> "$OUT/run.log" 2>&1; }
register_wait() { # register_wait <n> : the 2026.1 compute n has reported (service row version 72)
  for i in $(seq 1 60); do v=$(sdb -N -e "select version from nova.services where host='ufj-compute$1' and \`binary\`='nova-compute' and deleted=0"); [ "$v" = 72 ] && return 0; sleep 3; done; return 1; }
adoption() { # adoption <state> <n> : C-5 evidence
  f="$OUT/$1/adoption-compute$2.txt"; mkdir -p "$OUT/$1"
  { echo "compute_id file: $(docker exec ufj-svc-compute$2 cat /var/lib/nova/compute_id 2>&1)"
    echo "compute_nodes rows for ufj-compute$2 (all, including deleted):"; sdb -e "select id,uuid,host,hypervisor_hostname,service_id,deleted from nova.compute_nodes where host='ufj-compute$2'"
    echo "services row:"; sdb -e "select id,version,forced_down,disabled from nova.services where host='ufj-compute$2' and \`binary\`='nova-compute'"
    echo "compute log (node identity / adoption / errors):"; docker logs ufj-svc-compute$2 2>&1 | grep -E "node identity|compute_id|Duplicate|were not found|Wrote|InvalidConfiguration|\] ERROR|\] CRITICAL" | grep -v "DB access allowed\|logging_exception_prefix" | cut -c1-320 | head -12
    echo "placement resource provider of the node:"; sosc resource provider list --name ufj-compute$2 -f value -c uuid -c name; } > "$f" 2>&1
  cat "$f" | tee -a "$OUT/run.log"; }

run_d() {
  st=d; mkdir -p "$OUT/$st"; reset
  rows $st 0-pre-start; nodes $st 0-pre-start
  T=$(now); "$STK" up | tee -a "$OUT/run.log"; waitapi
  note "(d) d1: Ussuri rows forced-down, no flag, 2026.1 control plane started"
  grep -c "disable_compute_service_check_for_ffu" "$NOVA_CONF" | sed 's/^/flag lines in nova.conf: /' | tee "$OUT/$st/flag-absent.txt"
  rows $st 1-started; nodes $st 1-started
  sosc compute service list --long -f value -c Binary -c Host -c Status -c State -c "Forced Down" > "$OUT/$st/api-service-list-1.txt" 2>&1
  rpc_lines $st 1-started "$T"; status_all $st 1-started
  note "F2 read-back (state d1)"; f2 $st
  note "(d) d2: re-register one host (ufj-compute1, 2026.1 fake compute)"
  T2=$(now); "$STK" computes 1; register_wait 1 || note "WARNING: compute1 did not report version 72"
  sleep 20; rows $st 2-compute1-registered; nodes $st 2-compute1-registered; adoption $st 1
  sosc compute service list --long -f value -c Binary -c Host -c Status -c State -c "Forced Down" > "$OUT/$st/api-service-list-2.txt" 2>&1
  sosc hypervisor list -f value -c ID -c "Hypervisor Hostname" -c State > "$OUT/$st/hypervisors-2.txt" 2>&1
  note "(d) clear forced-down on ufj-compute1 (after verification), restart nova-api/conductor/scheduler once"
  svcset up ufj-compute1
  T3=$(now); ctl_restart; rows $st 3-cleared-restarted
  rpc_lines $st 3-cleared-restarted "$T3"; status_all $st 3-cleared-restarted
  op $st 3 ufj-compute1 "$T3"
}
f2() { # f2 <state>
  mkdir -p "$OUT/$1/f2"
  for i in $(seq 1 60); do sosc --os-volume-api-version 3.50 volume service list --long -f value -c "Backend State" 2>/dev/null | grep -q None || break; sleep 3; done   # cinder-volume publishes backend state after its first stats report
  docker exec -e USER_ALICE="$USER_ALICE" -e USER_BOB="$USER_BOB" ufj-svc-client bash -c "set -a; . /run/svc/admin-openrc; set +a; python /lab/tools/f2_readback.py --baseline /lab/backups-v4/latest/inventory.json --expected /lab/svc/expected-changes.json --coverage /evidence/lab-baseline/coverage-actions.tsv --out /evidence/EXP-SVC-01/$LABEL/$1/f2" 2>&1 | tail -3 | cut -c1-300 | tee -a "$OUT/run.log"
  : > "$OUT/$1/f2/http500-in-service-logs.txt"
  for c in keystone glance placement nova-api neutron cinder-api; do echo "$c: $(docker logs ufj-svc-$c 2>&1 | grep -cE 'status: 500|HTTP 500|"[A-Z]+ [^"]*" 500 | 500 ')" >> "$OUT/$1/f2/http500-in-service-logs.txt"; done
  cat "$OUT/$1/f2/http500-in-service-logs.txt" | tee -a "$OUT/run.log"; }

run_abc() {
  st=a; mkdir -p "$OUT/a" "$OUT/b" "$OUT/c"; reset; "$STK" up | tee -a "$OUT/run.log"; waitapi
  note "(a) start 2026.1 compute ufj-compute1, then clear forced-down on all three Ussuri rows through the 2026.1 API"
  "$STK" computes 1; register_wait 1; sleep 15; adoption a 1
  for h in 1 2 3; do svcset up ufj-compute$h; done
  rows a 1-unforced; sosc compute service list --long -f value -c Binary -c Host -c Status -c State -c "Forced Down" > "$OUT/a/api-service-list-1.txt" 2>&1
  note "(a) restart control WITHOUT the workaround: expected refusal (min service version 51 of the unforced Ussuri rows)"
  T=$(now); ctl_restart; sleep 10; rpc_lines a 2-restart-no-flag "$T"
  docker ps -a --filter label=org.ozarland.svc=1 --format '{{.Names}} {{.Status}}' | grep nova > "$OUT/a/containers-no-flag.txt"
  for c in nova-api nova-conductor nova-scheduler; do docker logs --since "$T" ufj-svc-$c 2>&1 | grep -iE "TooOld|too old|older than" | head -2 | cut -c1-400; done | tee "$OUT/a/refusal-lines.txt" | tee -a "$OUT/run.log"
  note "(a) workaround set, restart"
  flag on; T=$(now); ctl_restart; sleep 10; rows a 3-flag-restarted
  rpc_lines a 3-flag-restarted "$T"; status_all a 3-flag-restarted; op a 3 ufj-compute1 "$T"
  # ---- (b)
  note "(b) forced-down on ufj-compute2/3 through the 2026.1 API (ufj-compute1, 2026.1, stays up), then restart"
  for h in 2 3; do svcset down ufj-compute$h; done
  rows b 1-forced-down; T=$(now); ctl_restart; sleep 10; rows b 2-restarted
  rpc_lines b 2-restarted "$T"; status_all b 2-restarted; op b 2 ufj-compute1 "$T"
  # ---- (c)
  note "(c) 2026.1 computes adopt ufj-compute2/3; forced-down cleared; workaround removed; restart"
  "$STK" computes 2 3; register_wait 2; register_wait 3; sleep 20; adoption c 2; adoption c 3
  for h in 2 3; do svcset up ufj-compute$h; done
  flag off; rows c 1-cleared; nodes c 1-cleared; T=$(now); ctl_restart; sleep 10; rows c 2-restarted
  rpc_lines c 2-restarted "$T"; status_all c 2-restarted; op c 2 ufj-compute2 "$T"; op c 2b ufj-compute3 "$T"
}
case $PART in d) run_d;; abc) run_abc;; all) run_d; run_abc;; esac
note "done: $LABEL $PART"
