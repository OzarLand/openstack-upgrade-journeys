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

# ---- 1. tokens for old users
note "1. tokens"
for u in alice bob; do pv=USER_${u^^}; pr=ufj-proj-a; [ $u = bob ] && pr=ufj-proj-b
  out=$(su $u "${!pv}" $pr token issue -f value -c id -c project_id 2>&1 | head -2 | tr '\n' ' ' | sed -E 's/^[0-9a-zA-Z_-]{40,} /<token> /;s/^gAAAA[^ ]+ /<token> /'); rc=$?
  rec "token-password-$u" "$([ -n "$out" ] && echo OK || echo FAIL)" "$out"; done
AC=$(A application credential create ufj-svc02-appcred -f value -c id -c secret 2>&1); ACID=$(echo "$AC" | sed -n 1p); ACSEC=$(echo "$AC" | sed -n 2p)
tok=$(docker exec -i -e ID="$ACID" -e SEC="$ACSEC" ufj-svc-client bash -c 'unset OS_USERNAME OS_PASSWORD OS_PROJECT_NAME OS_USER_DOMAIN_NAME OS_PROJECT_DOMAIN_NAME; export OS_AUTH_URL=http://ufj-keystone:5000/v3 OS_AUTH_TYPE=v3applicationcredential OS_APPLICATION_CREDENTIAL_ID=$ID OS_APPLICATION_CREDENTIAL_SECRET=$SEC OS_IDENTITY_API_VERSION=3; openstack token issue -f value -c project_id 2>&1 | head -1' | redact)
rec "token-application-credential-alice" "$([ -n "$tok" ] && [ ${#tok} -eq 32 ] && echo OK || echo FAIL)" "new application credential of alice -> token scoped to project $tok"
A application credential delete ufj-svc02-appcred >/dev/null 2>&1

# ---- 2. EC2 and TOTP credentials of the old user decrypt
note "2. credentials"
ec=$(A ec2 credentials list -f value -c Access -c Secret 2>&1 | awk 'NF>=2{n++} END{print n+0}')
rec "ec2-credentials-alice-list-with-secret" "$([ "$ec" -ge 1 ] && echo OK || echo FAIL)" "$ec ec2 credential(s) listed with access and decrypted secret (values not recorded)"
tc=$(sosc --os-interface public credential list --type totp -f value -c ID 2>&1 | wc -l); tb=$(sosc credential show $(sosc credential list --type totp -f value -c ID | head -1) -f value -c blob 2>&1 | head -c 4 | wc -c)
rec "totp-credential-decrypts" "$([ "$tc" -ge 1 ] && [ "$tb" -ge 4 ] && echo OK || echo FAIL)" "$tc totp credential(s); blob returned (not recorded)"

# ---- 3. quota enforcement with the old quota rows (bob: instances limit 5, usage 1)
note "3. quota"
B limits show --absolute -f value > "$OUT/bob-limits-before.txt" 2>&1
INST=$(B limits show --absolute -f value 2>&1 | grep -E "^(maxTotalInstances|totalInstancesUsed)" | tr '\n' ' ')
rec "quota-bob-before" INFO "$(B quota show -f value -c instances 2>&1) instances limit; $INST"
for i in 1 2 3 4; do B server create --flavor ufj-tiny --image ufj-image-public --nic none ufj-svc02-q$i -f value -c id > /dev/null 2>&1; done
sleep 20
n=$(B server list -f value -c Name 2>/dev/null | wc -l); rec "quota-bob-servers-after-4-creates" INFO "$n servers in project b (limit 5)"
out=$(B server create --flavor ufj-tiny --image ufj-image-public --nic none ufj-svc02-q5 2>&1 | head -3 | tr '\n' ' ')
rec "quota-bob-6th-server-refused" "$(echo "$out" | grep -qiE 'quota|exceed|403' && echo OK || echo FAIL)" "$out"
B limits show --absolute -f value > "$OUT/bob-limits-after.txt" 2>&1
rec "quota-bob-usage-after" INFO "$(B limits show --absolute -f value 2>&1 | grep -E '^(maxTotalInstances|totalInstancesUsed)' | tr '\n' ' ')"
# cinder: alice gigabytes limit 500, usage about 20
out=$(A volume create --size 495 ufj-svc02-bigvol 2>&1 | head -3 | tr '\n' ' ')
rec "quota-alice-volume-495G-refused" "$(echo "$out" | grep -qiE 'quota|exceed|VolumeLimitExceeded|413|403' && echo OK || echo FAIL)" "$out"
A volume create --size 1 ufj-svc02-vol1 -f value -c id > "$OUT/.v1" 2>&1; V1=$(head -1 "$OUT/.v1"); rm -f "$OUT/.v1"
rec "quota-alice-volume-1G-accepted" "$([ -n "$V1" ] && echo OK || echo FAIL)" "volume $V1"

# ---- 4. new port and new server on an old network, old image, old flavor
note "4. network"
out=$(A port create --network a-net1 ufj-svc02-port -f value -c id -c status 2>&1 | tr '\n' ' '); rec "port-create-on-old-network-a-net1" "$(echo "$out" | grep -qE '^[0-9a-f-]{36}' && echo OK || echo FAIL)" "$out"
A server create --flavor ufj-tiny --image ufj-image-a --network a-net1 ufj-svc02-srv1 -f value -c id > "$OUT/.s1" 2>&1; S1=$(head -1 "$OUT/.s1"); rm -f "$OUT/.s1"
st=$(waitfor 120 ACTIVE bash -c "docker exec -i -e U=alice -e P='$USER_ALICE' ufj-svc-client bash -c 'set -a; . /run/svc/admin-openrc; OS_USERNAME=alice; OS_PASSWORD=\$P; OS_PROJECT_NAME=ufj-proj-a; set +a; openstack server show $S1 -f value -c status'")
rec "server-create-old-network-old-image-old-flavor" "$([ "$st" = ACTIVE ] && echo OK || echo FAIL)" "$S1 status $st; $(A server show $S1 -f value -c addresses -c OS-EXT-SRV-ATTR:host 2>&1 | tr '\n' ' ')"
rec "port-of-new-server-binding" INFO "$(sosc port list --server $S1 -f value -c ID -c Status -c binding_vif_type -c binding_host_id 2>&1 | tr '\n' ' ')"

# ---- 5. volume attach and detach (old available volume, old active server), snapshots
note "5. volume attach/detach and snapshots"
A server add volume a-vm2 a-vol2 > "$OUT/attach.txt" 2>&1; rec "volume-attach-a-vol2-to-a-vm2 (command rc=$?)" INFO "$(head -c 200 "$OUT/attach.txt" | tr '\n' ' ')"
st=$(waitfor 90 in-use bash -c "docker exec -i ufj-svc-client bash -c 'set -a; . /run/svc/admin-openrc; set +a; openstack volume show a-vol2 -f value -c status'")
rec "volume-attached" "$([ "$st" = in-use ] && echo OK || echo FAIL)" "a-vol2 status $st; attachments: $(sosc volume show a-vol2 -f value -c attachments 2>&1 | cut -c1-160)"
A server remove volume a-vm2 a-vol2 > "$OUT/detach.txt" 2>&1
st=$(waitfor 90 available bash -c "docker exec -i ufj-svc-client bash -c 'set -a; . /run/svc/admin-openrc; set +a; openstack volume show a-vol2 -f value -c status'")
rec "volume-detached" "$([ "$st" = available ] && echo OK || echo FAIL)" "a-vol2 status $st"
A volume snapshot create --volume a-vol2 ufj-svc02-snap -f value -c id > "$OUT/.sn" 2>&1; SN=$(head -1 "$OUT/.sn"); rm -f "$OUT/.sn"
st=$(waitfor 60 available bash -c "docker exec -i ufj-svc-client bash -c 'set -a; . /run/svc/admin-openrc; set +a; openstack volume snapshot show $SN -f value -c status'")
rec "volume-snapshot-of-old-volume" "$([ "$st" = available ] && echo OK || echo FAIL)" "snapshot $SN status $st"
A server image create a-vm3 --name ufj-svc02-img > "$OUT/img.txt" 2>&1; rec "server-image-create (nova snapshot) of a-vm3, command rc=$?" INFO "$(head -c 160 "$OUT/img.txt" | tr '\n' ' ')"
sleep 20; rec "server-image-status" INFO "$(sosc image show ufj-svc02-img -f value -c status 2>&1 | head -1) (fake driver uploads no data)"

# ---- 6. resize of an old server (fake driver)
note "6. resize"
A server resize --flavor ufj-small a-vm1 > "$OUT/resize.txt" 2>&1; rc=$?
st=$(waitfor 120 VERIFY_RESIZE bash -c "docker exec -i ufj-svc-client bash -c 'set -a; . /run/svc/admin-openrc; set +a; openstack server show a-vm1 -f value -c status'")
rec "resize-a-vm1-to-ufj-small (rc=$rc)" "$([ "$st" = VERIFY_RESIZE ] && echo OK || echo FAIL)" "status $st"
if [ "$st" = VERIFY_RESIZE ]; then A server resize confirm a-vm1 > /dev/null 2>&1; st=$(waitfor 90 ACTIVE bash -c "docker exec -i ufj-svc-client bash -c 'set -a; . /run/svc/admin-openrc; set +a; openstack server show a-vm1 -f value -c status'"); rec "resize-confirm" "$([ "$st" = ACTIVE ] && echo OK || echo FAIL)" "status $st; flavor $(sosc server show a-vm1 -f value -c flavor 2>&1 | cut -c1-60)"; fi

# ---- cleanup of the objects created here, log scan, counts
note "cleanup and log scan"
for n in 1 2 3 4 5; do B server delete ufj-svc02-q$n > /dev/null 2>&1; done
A server delete ufj-svc02-srv1 > /dev/null 2>&1; A port delete ufj-svc02-port > /dev/null 2>&1; A volume snapshot delete ufj-svc02-snap > /dev/null 2>&1; A volume delete ufj-svc02-vol1 > /dev/null 2>&1; sosc image delete ufj-svc02-img > /dev/null 2>&1
: > "$OUT/service-log-errors.txt"
for c in nova-api nova-conductor nova-scheduler neutron neutron-rpc cinder-api cinder-scheduler cinder-volume glance keystone placement compute1 compute2 compute3; do
  e5=$(docker logs --since "$T0" ufj-svc-$c 2>&1 | grep -cE 'Returning 500|HTTP/1.1" 500|status: 500 len|500 Internal Server Error|InternalServerError')
  er=$(docker logs --since "$T0" ufj-svc-$c 2>&1 | grep -cE '\] ERROR |CRITICAL')
  echo "$c: http500-lines=$e5 error-lines=$er" >> "$OUT/service-log-errors.txt"; done
cat "$OUT/service-log-errors.txt" | tee -a "$OUT/run.log"
{ echo "harness commit: $(git -C "$LAB_DIR/../.." rev-parse HEAD)"; echo "lab/ files changed:"; git -C "$LAB_DIR/../.." status --porcelain -- lab | grep -v '^??'; echo "script sha256: $(sha256sum "$0" | cut -d' ' -f1)"; echo "image: $(docker image inspect $SIMG --format '{{.Id}}')"; echo "label $LABEL"; } > "$OUT/harness.txt"
awk -F'\t' '$2=="FAIL"{f++} $2=="OK"{o++} END{print "SUMMARY ok=" o+0 " fail=" f+0}' "$RES" | tee -a "$OUT/run.log"
note "done: $LABEL"
