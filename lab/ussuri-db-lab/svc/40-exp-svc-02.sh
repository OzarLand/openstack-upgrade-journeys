#!/usr/bin/env bash
# EXP-SVC-02: operations on pre-existing resources through the 2026.1 services (H4r database, DR-003 state d -> all three hosts re-adopted).
#   usage: 40-exp-svc-02.sh <label>      evidence: evidence/EXP-SVC-02/<label>/
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
set +eu
LABEL=${1:?label}
OUT="$EVIDENCE_DIR/../EXP-SVC-02/$LABEL"; mkdir -p "$OUT"
H4R_VOL=${H4R_VOL:-ufj-ff-derive-h4r-data}
STK="$SVC_DIR/10-stack.sh"
note() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$OUT/run.log"; }
redact() { PWENV="$SBASE/config/passwords.env" python3 -c "
import sys,os
vals=[l.strip().split('=',1)[1].strip('\"') for l in open(os.environ['PWENV']) if '=' in l and not l.startswith('#')]
t=sys.stdin.read()
for v in sorted([v for v in vals if len(v)>=8],key=len,reverse=True): t=t.replace(v,'<redacted>')
sys.stdout.write(t)"; }
# su <user> <password> <project> <openstack args...> : the 2026.1 client as an old (non-admin) user
su() { local u=$1 p=$2 pr=$3; shift 3; docker exec -i -e U="$u" -e P="$p" -e PR="$pr" ufj-svc-client bash -c 'set -a; . /run/svc/admin-openrc; OS_USERNAME=$U; OS_PASSWORD=$P; OS_PROJECT_NAME=$PR; set +a; exec openstack "$@"' _ "$@" 2>&1 | redact; return ${PIPESTATUS[0]}; }
A() { su alice "$USER_ALICE" ufj-proj-a "$@"; }
B() { su bob "$USER_BOB" ufj-proj-b "$@"; }
RES="$OUT/results.tsv"; : > "$RES"
rec() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" | tee -a "$RES" | tee -a "$OUT/run.log" | cut -c1-260; }
# waitfor <seconds> <want> <command...> : poll the command's output until it equals <want>
waitfor() { local n=$1 want=$2; shift 2; local got; for i in $(seq 1 $((n/2))); do got=$("$@" 2>&1 | head -1); [ "$got" = "$want" ] && { echo "$got"; return 0; }; sleep 2; done; echo "$got"; return 1; }
svcset() { sosc compute service set --$1 $2 nova-compute 2>&1 | tee -a "$OUT/run.log"; }

note "reset and start the 2026.1 stack (state d), then re-adopt the three hosts and restart the Nova control services once (DR-003 steps 4-5)"
docker stop ufj-ff-derive-h4r-db >/dev/null 2>&1; "$STK" down >/dev/null; "$STK" clone "$H4R_VOL" >/dev/null; "$STK" infra >/dev/null 2>&1; "$STK" up | tee -a "$OUT/run.log"
"$STK" computes 1 2 3; "$STK" heartbeat
for n in 1 2 3; do for i in $(seq 1 60); do [ "$(sdb -N -e "select version from nova.services where host='ufj-compute$n' and \`binary\`='nova-compute' and deleted=0")" = 72 ] && break; sleep 3; done; done
sleep 15; for n in 1 2 3; do svcset up ufj-compute$n; done
docker restart ufj-svc-nova-api ufj-svc-nova-conductor ufj-svc-nova-scheduler >/dev/null; sleep 8; swait http://ufj-nova-api:8774/ 120
sosc compute service list --service nova-compute -f value -c Host -c Status -c State -c "Forced Down" > "$OUT/compute-services.txt" 2>&1; cat "$OUT/compute-services.txt" | tee -a "$OUT/run.log"
sosc network agent list -f value -c Host -c Alive > "$OUT/agents.txt" 2>&1
T0=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ids (names cannot be used as filters by the Cinder API in 2026.1 without resource_filters.json)
vid() { sosc volume list --all-projects -f value -c ID -c Name 2>/dev/null | awk -v n="$1" '$2==n{print $1; exit}'; }
sid() { sosc server list --all-projects -f value -c ID -c Name 2>/dev/null | awk -v n="$1" '$2==n{print $1; exit}'; }
astat() { sosc "$@" 2>&1 | head -1; }          # admin status probe
sstatus() { astat server show "$1" -f value -c status; }
vstatus() { astat volume show "$1" -f value -c status; }
RV=$(vid a-vol2); VM1=$(sid a-vm1); VM2=$(sid a-vm2); VM3=$(sid a-vm3); MIG=$(sid a-migrate)
note "roles after bootstrap: $(sosc role list -f value -c Name | tr '\n' ' '); nova user in project service: $(sosc role assignment list --user nova --project service --names -f value 2>&1 | tr '\n' ' ')"
echo "$(sosc role list -f value -c Name | tr '\n' ' ')" > "$OUT/roles-before.txt"

case $LABEL in strict*) [ -z "$(git -C "$LAB_DIR/../.." status --porcelain -- lab | grep -v '^??')" ] || { echo "STRICT run refused: lab/ has uncommitted changes" | tee -a "$OUT/run.log"; exit 3; };; esac
# ---- 1. tokens for old users
note "1. tokens (6.5 cap: all compute rows are version 72)"
for u in alice bob; do pv=USER_${u^^}; pr=ufj-proj-a; [ $u = bob ] && pr=ufj-proj-b
  out=$(su $u "${!pv}" $pr token issue -f value -c project_id 2>&1 | head -1)
  rec "token-password-$u" "$([ ${#out} -eq 32 ] && echo OK || echo FAIL)" "token scoped to project $out"; done
AC=$(A application credential create ufj-svc02-appcred -f value -c id -c secret 2>&1); ACID=$(echo "$AC" | sed -n 1p); ACSEC=$(echo "$AC" | sed -n 2p)
tok=$(docker exec -i -e ID="$ACID" -e SEC="$ACSEC" ufj-svc-client bash -c 'unset OS_USERNAME OS_PASSWORD OS_PROJECT_NAME OS_USER_DOMAIN_NAME OS_PROJECT_DOMAIN_NAME; export OS_AUTH_URL=http://ufj-keystone:5000/v3 OS_AUTH_TYPE=v3applicationcredential OS_APPLICATION_CREDENTIAL_ID=$ID OS_APPLICATION_CREDENTIAL_SECRET=$SEC OS_IDENTITY_API_VERSION=3; openstack token issue -f value -c project_id 2>&1 | head -1' | redact)
rec "token-application-credential-alice (NEW credential of a pre-existing user; the secrets of the pre-existing credentials were not retained by the baseline, so they cannot be used)" "$([ ${#tok} -eq 32 ] && echo OK || echo FAIL)" "token scoped to project $tok"
A application credential delete ufj-svc02-appcred >/dev/null 2>&1
n=$(A application credential list -f value -c ID 2>&1 | wc -l); rec "application-credentials-of-alice-listed (pre-existing)" "$([ "$n" -ge 3 ] && echo OK || echo FAIL)" "$n listed"

# ---- 2. EC2 and TOTP credentials of the old user decrypt
note "2. credentials"
ec=$(A ec2 credentials list -f value -c Access -c Secret 2>&1 | awk 'NF>=2{n++} END{print n+0}')
rec "ec2-credentials-alice-list-with-secret" "$([ "$ec" -ge 1 ] && echo OK || echo FAIL)" "$ec ec2 credential(s) listed with access and decrypted secret (values not recorded)"
tid=$(sosc credential list --type totp -f value -c ID 2>&1 | head -1); tb=$(sosc credential show "$tid" -f value -c blob 2>&1 | head -c 8 | wc -c)
rec "totp-credential-decrypts" "$([ -n "$tid" ] && [ "$tb" -ge 4 ] && echo OK || echo FAIL)" "totp credential $tid; blob returned (not recorded)"

# ---- 3. operations on PRE-EXISTING servers and volumes. The stack start includes the Kolla-equivalent Keystone bootstrap (10-stack.sh bootstrap:
#         role 'service' for the nova/cinder/neutron users, config-changes.txt 12-13); strict-r1 (interrupted) showed that without it Cinder 2026.1 refuses
#         Nova's attachment delete (409 ConflictNovaUsingAttachment), so volume detach and resize-with-volume failed.
note "3. pre-existing resources, as migrated (flavors: a-vm1 $(sosc server show $VM1 -f value -c flavor 2>&1 | cut -c1-40); a-vm2 $(sosc server show $VM2 -f value -c flavor 2>&1 | cut -c1-40))"
sosc role assignment list --names -f value -c Role -c User -c Project 2>&1 | grep -E '^(service|admin) (nova|cinder|neutron)@' | sort > "$OUT/service-user-roles.txt"
VM="docker exec -i ufj-svc-client bash -c 'set -a; . /run/svc/admin-openrc; set +a; openstack"
A server stop a-vm3 > /dev/null 2>&1; st=$(waitfor 60 SHUTOFF bash -c "$VM server show $VM3 -f value -c status'")
A server start a-vm3 > /dev/null 2>&1; st2=$(waitfor 60 ACTIVE bash -c "$VM server show $VM3 -f value -c status'")
rec "stop-start-of-Ussuri-created-ACTIVE-server-a-vm3 (boot volume attached)" "$([ "$st" = SHUTOFF ] && [ "$st2" = ACTIVE ] && echo OK || echo FAIL)" "after stop $st, after start $st2"
A server resize confirm a-migrate > "$OUT/confirm-migrate.txt" 2>&1; rc=$?
st=$(waitfor 90 ACTIVE bash -c "$VM server show $MIG -f value -c status'")
rec "resize-confirm-of-Ussuri-created-VERIFY_RESIZE-server-a-migrate (rc=$rc)" "$([ "$st" = ACTIVE ] && echo OK || echo FAIL)" "status $st $(head -c 120 "$OUT/confirm-migrate.txt" | tr '\n' ' ')"
# 3a. the Ussuri-era attachment of a-vol1 on a-vm1 (attachment row created by Ussuri Nova/Cinder): detach, then re-attach
V1=$(vid a-vol1); sdb -e "select id,attach_status,attach_mode,connector is not null as has_connector,connection_info is not null as has_conn_info,created_at from cinder.volume_attachment where volume_id='$V1' and deleted=0" > "$OUT/vol1-attachment-row-before.txt" 2>&1
A server remove volume a-vm1 "$V1" > "$OUT/detach-vol1.txt" 2>&1; rc=$?
st=$(waitfor 90 available bash -c "$VM volume show $V1 -f value -c status'")
rec "volume-detach-of-Ussuri-era-attachment-a-vol1-from-a-vm1 (rc=$rc)" "$([ "$st" = available ] && echo OK || echo FAIL)" "volume status $st $(head -c 150 "$OUT/detach-vol1.txt" | tr '\n' ' ')"
A server add volume a-vm1 "$V1" > "$OUT/reattach-vol1.txt" 2>&1; rc=$?
st=$(waitfor 90 in-use bash -c "$VM volume show $V1 -f value -c status'")
rec "volume-re-attach-a-vol1-to-a-vm1 (rc=$rc)" "$([ "$st" = in-use ] && echo OK || echo FAIL)" "volume status $st $(head -c 120 "$OUT/reattach-vol1.txt" | tr '\n' ' ')"
# 3b. a new attachment (2026.1 attachment row) on an old volume and an old server: attach, detach
A server add volume a-vm2 "$RV" > "$OUT/attach.txt" 2>&1; rc=$?
st=$(waitfor 90 in-use bash -c "$VM volume show $RV -f value -c status'")
rec "volume-attach-a-vol2-to-a-vm2 (rc=$rc)" "$([ "$st" = in-use ] && echo OK || echo FAIL)" "volume status $st $(head -c 120 "$OUT/attach.txt" | tr '\n' ' ')"
A server remove volume a-vm2 "$RV" > "$OUT/detach.txt" 2>&1; rc=$?
st=$(waitfor 90 available bash -c "$VM volume show $RV -f value -c status'")
rec "volume-detach-a-vol2-from-a-vm2 (rc=$rc)" "$([ "$st" = available ] && echo OK || echo FAIL)" "volume status $st $(head -c 120 "$OUT/detach.txt" | tr '\n' ' ')"
# 3c. resize of old servers with attached volumes (fake driver): a-vm1 (ufj.tiny -> ufj.small, a-vol1 attached), a-vm2 (ufj.small -> ufj.medium, encrypted a-enc-vol attached)
rsz() { # rsz <name> <id> <flavor> <label>
  A server resize --flavor "$3" "$1" > "$OUT/resize-$1.txt" 2>&1; local rc=$?
  local st=$(waitfor 150 VERIFY_RESIZE bash -c "$VM server show $2 -f value -c status'")
  rec "resize-of-Ussuri-created-server-$1-$4 (rc=$rc)" "$([ "$st" = VERIFY_RESIZE ] && echo OK || echo FAIL)" "status $st $(head -c 120 "$OUT/resize-$1.txt" | tr '\n' ' ')"
  if [ "$st" = VERIFY_RESIZE ]; then A server resize confirm "$1" > /dev/null 2>&1; st=$(waitfor 90 ACTIVE bash -c "$VM server show $2 -f value -c status'")
    rec "resize-confirm-$1" "$([ "$st" = ACTIVE ] && echo OK || echo FAIL)" "status $st; flavor $(sosc server show $2 -f value -c flavor 2>&1 | cut -c1-60)"
  else sosc server show $2 -f value -c fault 2>&1 | tr -d '\n' | grep -oE "[A-Za-z]*Exception: [^\\]{0,200}|[A-Za-z]*Error: [^\\]{0,200}" | tail -1 > "$OUT/fault-$1.txt"; rec "fault-of-$1" INFO "$(cat "$OUT/fault-$1.txt")"; fi; }
rsz a-vm1 $VM1 ufj.small "with-attached-volume-a-vol1"
rsz a-vm2 $VM2 ufj.medium "with-attached-encrypted-volume"
docker logs --since "$T0" ufj-svc-cinder-api 2>&1 | grep -E "not a valid service token|ConflictNovaUsingAttachment" | cut -c1-250 > "$OUT/cinder-service-token-lines.txt"
rec "cinder-api-service-token-warnings-since-T0" INFO "$(wc -l < "$OUT/cinder-service-token-lines.txt") line(s) (expected 0 with the service role)"

# ---- 4. snapshots
note "4. snapshots"
A volume snapshot create --volume "$RV" ufj-svc02-snap -f value -c id > "$OUT/.sn" 2>&1; SN=$(head -1 "$OUT/.sn"); rm -f "$OUT/.sn"
st=$(waitfor 60 available bash -c "docker exec -i ufj-svc-client bash -c 'set -a; . /run/svc/admin-openrc; set +a; openstack volume snapshot show $SN -f value -c status'")
rec "volume-snapshot-of-old-volume" "$([ "$st" = available ] && echo OK || echo FAIL)" "snapshot $SN status $st"
A server image create a-vm3 --name ufj-svc02-img > "$OUT/img.txt" 2>&1; rec "server-image-create (nova snapshot) of a-vm3, command rc=$?" INFO "command accepted"
sleep 20; rec "server-image-status" INFO "$(sosc image show ufj-svc02-img -f value -c status 2>&1 | head -1) (fake driver uploads no data)"

# ---- 5. quota enforcement with the old quota rows (bob: instances limit 5, usage 1; alice: gigabytes limit 500)
note "5. quota"
lim() { B limits show --absolute -f value 2>&1 | grep -E "^(instances|instances_used) " | tr '\n' ' '; }
rec "quota-bob-before" INFO "$(lim)"
for i in 1 2 3 4; do B server create --flavor ufj.tiny --image ufj-image-public --nic none ufj-svc02-q$i -f value -c id > /dev/null 2>&1; done
sleep 25; rec "quota-bob-after-4-creates" INFO "$(lim)"
out=$(B server create --flavor ufj.tiny --image ufj-image-public --nic none ufj-svc02-q5 2>&1 | head -3 | tr '\n' ' ')
rec "quota-bob-6th-server-refused" "$(echo "$out" | grep -qiE 'quota|exceed|403' && echo OK || echo FAIL)" "$out"
out=$(A volume create --size 495 ufj-svc02-bigvol 2>&1 | head -3 | tr '\n' ' ')
rec "quota-alice-volume-495G-refused" "$(echo "$out" | grep -qiE 'quota|exceed|VolumeLimitExceeded|VolumeSizeExceeds|413|403' && echo OK || echo FAIL)" "$out"
A volume create --size 1 ufj-svc02-vol1 -f value -c id > "$OUT/.v1" 2>&1; V1N=$(head -1 "$OUT/.v1"); rm -f "$OUT/.v1"
rec "quota-alice-volume-1G-accepted" "$([ ${#V1N} -eq 36 ] && echo OK || echo FAIL)" "volume $V1N"

# ---- 6. new port and new server on an old network, old image, old flavor
note "6. network"
out=$(A port create --network a-net1 ufj-svc02-port -f value -c id -c status 2>&1 | tr '\n' ' '); rec "port-create-on-old-network-a-net1" "$(echo "$out" | grep -qE '^[0-9a-f-]{36}' && echo OK || echo FAIL)" "$out"
A server create --flavor ufj.tiny --image ufj-image-a --network a-net1 ufj-svc02-srv1 -f value -c id > "$OUT/.s1" 2>&1; S1=$(head -1 "$OUT/.s1"); rm -f "$OUT/.s1"
st=$(waitfor 120 ACTIVE bash -c "docker exec -i ufj-svc-client bash -c 'set -a; . /run/svc/admin-openrc; set +a; openstack server show $S1 -f value -c status'")
rec "server-create-old-network-old-image-old-flavor" "$([ "$st" = ACTIVE ] && echo OK || echo FAIL)" "$S1 status $st; $(sosc server show $S1 -f value -c addresses -c OS-EXT-SRV-ATTR:host 2>&1 | tr '\n' ' ')"
rec "port-binding-of-new-server" INFO "$(sdb -N -e "select b.vif_type,b.host from neutron.ml2_port_bindings b join neutron.ports p on p.id=b.port_id where p.device_id='$S1'" 2>&1 | tr '\n' ' ')"

# ---- cleanup of the objects created here, log scan, counts
note "cleanup and log scan"
for n in 1 2 3 4 5; do B server delete ufj-svc02-q$n > /dev/null 2>&1; done; sleep 5
A server delete ufj-svc02-srv1 > /dev/null 2>&1; A port delete ufj-svc02-port > /dev/null 2>&1; A volume snapshot delete ufj-svc02-snap > /dev/null 2>&1; A volume delete ufj-svc02-vol1 > /dev/null 2>&1; sosc image delete ufj-svc02-img > /dev/null 2>&1
for c in nova-api nova-conductor nova-scheduler; do docker logs --since "$T0" ufj-svc-$c 2>&1 | grep "Automatically selected compute RPC" | sed -E "s/^/$c: /;s/\[None[^]]*\]//" | cut -c1-220; done > "$OUT/rpc-cap.txt"; cat "$OUT/rpc-cap.txt" | tee -a "$OUT/run.log"
: > "$OUT/service-log-errors.txt"
for c in nova-api nova-conductor nova-scheduler neutron neutron-rpc cinder-api cinder-scheduler cinder-volume glance keystone placement compute1 compute2 compute3; do
  e5=$(docker logs --since "$T0" ufj-svc-$c 2>&1 | grep -cE 'Returning 500|HTTP/1.1" 500|status: 500 len|500 Internal Server Error|InternalServerError')
  er=$(docker logs --since "$T0" ufj-svc-$c 2>&1 | grep -cE '\] ERROR |CRITICAL')
  oc=$(docker logs --since "$T0" ufj-svc-$c 2>&1 | grep -cE 'IncompatibleObjectVersion|ObjectActionError')
  echo "$c: http500-lines=$e5 error-lines=$er object-version-errors=$oc" >> "$OUT/service-log-errors.txt"; done
cat "$OUT/service-log-errors.txt" | tee -a "$OUT/run.log"
{ echo "harness commit: $(git -C "$LAB_DIR/../.." rev-parse HEAD)"; echo "lab/ files changed:"; git -C "$LAB_DIR/../.." status --porcelain -- lab | grep -v '^??'; echo "script sha256: $(sha256sum "$0" | cut -d' ' -f1)"; echo "image: $(docker image inspect $SIMG --format '{{.Id}}')"; echo "label $LABEL"; } > "$OUT/harness.txt"
awk -F'\t' '$2=="FAIL"{f++} $2=="OK"{o++} END{print "SUMMARY ok=" o+0 " fail=" f+0}' "$RES" | tee -a "$OUT/run.log"
note "done: $LABEL"
