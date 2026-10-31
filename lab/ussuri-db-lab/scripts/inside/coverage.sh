#!/usr/bin/env bash
# Runs INSIDE ufj-client after populate.sh: creates the items of experiments/baseline-coverage-checklist.md that need more
# than the base data set, ONLY through the Ussuri APIs. Every attempt is recorded in /evidence/coverage-actions.tsv
# (item <TAB> OK|FAILED <TAB> detail); a failure never stops the script and is never hidden.
set -uo pipefail
export OS_COMPUTE_API_VERSION=2.60 OS_VOLUME_API_VERSION=3 OS_IMAGE_API_VERSION=2
set -a; . /run/ufj/admin-openrc; set +a; export OS_PASSWORD="${ADMIN:?}"
oa() { openstack "$@"; }
oA() { env OS_USERNAME=alice OS_PASSWORD="$USER_ALICE" OS_PROJECT_NAME=ufj-proj-a openstack "$@"; }
oB() { env OS_USERNAME=bob   OS_PASSWORD="$USER_BOB"   OS_PROJECT_NAME=ufj-proj-b openstack "$@"; }
pyA() { env OS_USERNAME=alice OS_PASSWORD="$USER_ALICE" OS_PROJECT_NAME=ufj-proj-a python /lab/tools/coverage_rest.py "$@"; }
pyadm() { python /lab/tools/coverage_rest.py "$@"; }
OUT=/evidence/coverage-actions.tsv; mkdir -p /evidence; [ -f "$OUT" ] || printf 'item\tresult\tdetail\n' > "$OUT"
rec() { # rec <item> <cmd...>: run, record OK/FAILED with the last output line
  local item=$1; shift; local o; if o=$("$@" 2>&1); then printf '%s\tOK\t%s\n' "$item" "created: $(echo "$o" | grep -E '^\| (id|name|status|binding_profile|OS-EXT-SRV-ATTR:host) ' | tr -s ' |' ' ' | tr '\n' ';' | cut -c1-200) (client output not kept: it can contain secrets)" >> "$OUT"
  else printf '%s\tFAILED\t%s\n' "$item" "$(echo "$o" | tail -2 | tr '\t\n' '  ' | cut -c1-300)" >> "$OUT"; fi; }
recpy() { local o; o=$("$@" 2>&1 | tail -1); python - "$o" <<'PY' >> "$OUT"
import json,sys
try:
    d=json.loads(sys.argv[1]); print('%s\t%s\t%s' % (d['item'], 'OK' if d['ok'] else 'FAILED', d['detail'].replace('\t',' ').replace('\n',' ')))
except Exception: print('python-helper\tFAILED\t%s' % sys.argv[1][:300])
PY
}
say() { printf '[coverage %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
waitst() { # waitst <cli-func> <server> <status> [seconds]
  local f=$1 n=$2 st=$3 i; for i in $(seq 1 "${4:-90}"); do [ "$($f server show "$n" -f value -c status)" = "$st" ] && return 0; [ "$($f server show "$n" -f value -c status)" = ERROR ] && return 1; sleep 1; done; return 1; }

say "keystone"
USERS_OK=$(oa user show dave >/dev/null 2>&1 && echo y || echo n)
UID_ALICE=$(oa user show alice -f value -c id); UID_BOB=$(oa user show bob -f value -c id); UID_CAROL=$(oa user show carol -f value -c id)
recpy pyA trust "$UID_BOB" 1
recpy pyA trust "$UID_CAROL" 0
rec appcred-bob oB application credential create --description "bob appcred" ufj-appcred-bob
rec appcred-alice-restricted oA application credential create --role member --restricted ufj-appcred-restricted
rec ec2-credential oA ec2 credentials create
rec totp-credential oa credential create --type totp --project ufj-proj-a alice "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
recpy pyadm revoke_token
oa identity provider show ufj-idp >/dev/null 2>&1 || rec federation-idp oa identity provider create --remote-id https://idp.example.invalid/saml ufj-idp
cat > /tmp/ufj/mapping.json <<'J'
[{"local":[{"user":{"name":"{0}"},"group":{"name":"ufj-ops","domain":{"name":"Default"}}}],"remote":[{"type":"REMOTE_USER"}]}]
J
oa mapping show ufj-mapping >/dev/null 2>&1 || rec federation-mapping oa mapping create --rules /tmp/ufj/mapping.json ufj-mapping
oa federation protocol show --identity-provider ufj-idp saml2 >/dev/null 2>&1 || rec federation-protocol oa federation protocol create --identity-provider ufj-idp --mapping ufj-mapping saml2

say "cinder"
recpy pyadm cinder_group_quota
oA volume show a-vol-deleted >/dev/null 2>&1 || { oA volume create --size 1 --type ufj-fake a-vol-deleted >/dev/null; sleep 3; rec volume-deleted oA volume delete a-vol-deleted; }
# volume migration between two backends: generic migration needs a data path, expected to fail; the failed attempt may leave migration_status rows
oA volume show a-vol-mig >/dev/null 2>&1 || { oA volume create --size 1 --type ufj-fake a-vol-mig >/dev/null; sleep 4; }
rec volume-migrate-attempt oa volume migrate --host 'ufj-cinder-volume@fake2#fake2' a-vol-mig
sleep 8
oA volume show a-vol-mig -f value -c status -c migration_status >> /tmp/ufj/migrate-state.txt 2>&1 || true
rec cinder-temporary-volume echo "no API path creates volume_admin_metadata temporary=True without a working backup/attach data path (see report)"; sed -i '$ s/\tOK\t/\tNOT COVERED\t/' "$OUT"

say "neutron"
recpy pyadm multisegment
rec segment-range-null-physnet oa network segment range create --private --project ufj-proj-a --network-type vxlan --minimum 2000 --maximum 2100 ufj-range-vxlan
oa network segment range create --shared --network-type vlan --physical-network physnet1 --minimum 300 --maximum 310 ufj-range-vlan >/dev/null 2>&1 || true
rec port-binding-profile oa port create --network ufj-ext --binding-profile ufj_key=ufj_value --binding-profile pci_slot=0000:00:03.0 --extra-dhcp-option name=tftp-server,value=192.0.2.9 --extra-dhcp-option name=bootfile-name,value=pxelinux.0 ufj-port-profile
rec network-tags oA network set --tag extra-tag a-net2
rec ha-router echo "needs L3 agents (min_l3_agents_per_router) and l3_ha=true; no L3 agent in this lab"; sed -i '$ s/\tOK\t/\tNOT COVERED\t/' "$OUT"

say "glance"
recpy pyadm glance_multilocation
recpy pyadm glance_task

say "nova"
# flavors for NUMA / pinned, and a flavor too big for any host (ERROR without host)
oa flavor show ufj.numa >/dev/null 2>&1 || oa flavor create --id ufj-numa --vcpus 2 --ram 1024 --disk 1 --property hw:numa_nodes=2 ufj.numa >/dev/null
oa flavor show ufj.pinned >/dev/null 2>&1 || oa flavor create --id ufj-pinned --vcpus 2 --ram 1024 --disk 1 --property hw:cpu_policy=dedicated ufj.pinned >/dev/null
oa flavor show ufj.huge >/dev/null 2>&1 || oa flavor create --id ufj-huge --vcpus 1 --ram 512 --disk 1 --property trait:CUSTOM_UFJ_NOT_PROVIDED=required ufj.huge >/dev/null
oa flavor set --project ufj-proj-a ufj.numa; oa flavor set --project ufj-proj-a ufj.pinned; oa flavor set --project ufj-proj-a ufj.huge 2>/dev/null
mk() { # mk <name> <flavor> [extra args]: create a server as alice and wait, record
  local n=$1 f=$2; shift 2; oA server show "$n" >/dev/null 2>&1 && return 0
  rec "server-$n" oA server create --flavor "$f" --image ufj-image-a --network a-net1 --security-group a-web --wait "$n" "$@"; }
mk a-numa ufj.numa
mk a-pinned ufj.pinned
oA server show a-huge >/dev/null 2>&1 || { oA server create --flavor ufj.huge --image ufj-image-a --network a-net1 a-huge >/dev/null 2>&1; sleep 15; rec server-a-huge-error oA server show a-huge -f value -c status; }
# instance on a dedicated host (ufj-compute3): the 'host whose compute_nodes row is later deleted' residue case
oA server show a-on-compute3 >/dev/null 2>&1 || rec server-on-compute3 env OS_USERNAME=carol OS_PASSWORD="$USER_CAROL" OS_PROJECT_NAME=ufj-proj-a openstack server create --flavor ufj.tiny --image ufj-image-a --network a-net1 --availability-zone nova:ufj-compute3 --wait a-on-compute3
# SHUTOFF
mk a-stopped ufj.tiny
[ "$(oA server show a-stopped -f value -c status 2>/dev/null)" = ACTIVE ] && { oA server stop a-stopped; waitst oA a-stopped SHUTOFF 60; }
# resize (confirmed) and migrate (left in VERIFY_RESIZE: migration_context present)
mk a-resize ufj.tiny
if [ "$(oA server show a-resize -f value -c status 2>/dev/null)" = ACTIVE ]; then rec resize-request oA server resize --flavor ufj.small a-resize; waitst oA a-resize VERIFY_RESIZE 90 && rec resize-confirm oA server resize --confirm a-resize; fi
mk a-migrate ufj.tiny
if [ "$(oA server show a-migrate -f value -c status 2>/dev/null)" = ACTIVE ]; then rec migrate-request env OS_USERNAME=carol OS_PASSWORD="$USER_CAROL" OS_PROJECT_NAME=ufj-proj-a openstack server migrate --wait a-migrate; fi
# deleted: soft-deleted (reclaim_instance_interval=3600) and force-deleted + archived
mk a-del-soft ufj.tiny; mk a-del-archived ufj.tiny
oA server show a-del-soft >/dev/null 2>&1 && [ "$(oA server show a-del-soft -f value -c status)" = ACTIVE ] && rec delete-soft oA server delete a-del-soft
oA server show a-del-archived >/dev/null 2>&1 && [ "$(oA server show a-del-archived -f value -c status)" = ACTIVE ] && { oA server delete a-del-archived; sleep 5; recpy pyadm force_delete a-del-archived; }
# a server group with affinity + scheduler hints (request_specs) on project B
oB server group show b-aff >/dev/null 2>&1 || rec server-group-affinity oB server group create --policy affinity b-aff
rec nova-quota-api oa quota set --instances 22 --key-pairs 60 ufj-proj-a
recpy pyadm placement_nested
recpy pyadm placement_consumer
say "extra items from the Agent 4 review"
recpy pyA trust "$UID_CAROL" 0 2031-01-01T00:00:00.000000Z
rec project-tags oa project set --tag lab --tag Mixed-Case --tag "tâg-ünï" ufj-proj-a
recpy pyA appcred_access_rules
recpy pyadm service_provider
recpy pyadm many_revocations 1500
rec encrypted-volume-type oa volume type create --encryption-provider luks --encryption-cipher aes-xts-plain64 --encryption-key-size 256 --encryption-control-location front-end ufj-enc
oA volume show a-enc-vol >/dev/null 2>&1 || rec encrypted-volume oA volume create --size 1 --type ufj-enc a-enc-vol
sleep 3; rec encrypted-volume-attach oA server add volume a-vm2 a-enc-vol
recpy pyadm cinder_groups
oa volume type show ufj-fake >/dev/null && rec cinder-default-quota-classes echo "see coverage-counts-T0.tsv (quota_classes)"
recpy pyadm community_image
recpy pyadm hidden_image
recpy pyA create_console a-vm1
# neutron: port forwarding, trusted binding profile, extra RBAC types, mixed-case/non-ASCII tags
FIPID=$(oA floating ip list --long -f value -c ID -c Description | grep "unassociated" | head -1 | cut -d' ' -f1)
rec port-forwarding oA floating ip port forwarding create --internal-ip-address 192.168.10.50 --port a-port-fixed --internal-protocol-port 22 --external-protocol-port 2222 --protocol tcp "$FIPID"
rec port-trusted-profile oa port create --network ufj-ext --binding-profile trusted=true ufj-port-trusted
rec qos-policy oa network qos policy create --project ufj-proj-a ufj-qos
recpy pyadm rbac qos_policy ufj-qos ufj-proj-b
recpy pyadm rbac security_group a-web ufj-proj-b
rec subnetpool-rbac-project oa subnet pool create --pool-prefix 10.60.0.0/16 --default-prefix-length 24 ufj-pool-priv
recpy pyadm rbac subnetpool ufj-pool-priv ufj-proj-b
rec address-scope oA address scope create --ip-version 4 ufj-scope
recpy pyadm rbac address_scope ufj-scope ufj-proj-b
rec tags-nonascii oA network set --tag "Mixed-Case" --tag "tâg-ünï" --tag "ÉTÉ" a-net1
# nova: volume-backed deleted+archived instance, a deleted instance on a compute that is then removed
oA volume show a-bfv-vol >/dev/null 2>&1 || { oA volume create --size 1 --type ufj-fake a-bfv-vol >/dev/null; oA volume set --bootable a-bfv-vol; }
oA server show a-del-bfv >/dev/null 2>&1 || rec server-bfv-to-delete oA server create --flavor ufj.tiny --volume a-bfv-vol --network a-net1 --wait a-del-bfv
oA server show a-del-bfv >/dev/null 2>&1 && { oA server delete a-del-bfv; sleep 5; recpy pyadm force_delete a-del-bfv; }
printf 'not-covered\tdeleted instance (deleted<>0 in nova.instances) whose compute_nodes row is gone\tNOT COVERED\tarchiving moves deleted instances to shadow_instances; a compute service can only be deleted through the API when no live instance is on it, and a fourth fake compute received live instances from the scheduler (tried, removed). The live-instance residue case IS covered: a-on-compute3 is on ufj-compute3\n' >> "$OUT"
printf 'not-covered\tpci_devices row with NULL uuid\tNOT COVERED\tthe fake driver reports no PCI devices\n' >> "$OUT"
printf 'not-covered\tvolume_admin_metadata temporary=True (non-deleted and deleted)\tNOT COVERED\tonly created internally by backup/migration data paths (attach/copy), unavailable with the fake driver and without cinder-backup\n' >> "$OUT"
printf 'not-covered\tnova legacy-cell-DB quotas\tNOT COVERED (by design)\tthe Ussuri API writes quotas to the API DB; legacy rows would need SQL\n' >> "$OUT"
printf 'not-covered\tDHCP ports\tNOT COVERED\tno DHCP agent in the lab, so neutron never creates network:dhcp ports\n' >> "$OUT"
printf 'not-covered\tlibvirt blobs, PCI/SR-IOV, OVN, real Ceph/LVM connection info\tNOT COVERED\tfake driver, no datapath (Tier B only)\n' >> "$OUT"
say "done (archive_deleted_rows and engine/db facts are recorded by 70-capture.sh)"
