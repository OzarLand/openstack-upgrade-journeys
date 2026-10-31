#!/usr/bin/env bash
# Runs INSIDE the ufj-client container (via scripts/60-populate.sh). Creates representative resources through the
# real Ussuri APIs with python-openstackclient. Idempotent where the client allows it ("show || create").
# Environment: ADMIN, USER_ALICE, USER_BOB, USER_CAROL passwords (from the git-ignored secrets file).
set -euo pipefail
export OS_COMPUTE_API_VERSION=2.60 OS_VOLUME_API_VERSION=3 OS_IMAGE_API_VERSION=2
set -a; . /run/ufj/admin-openrc; set +a; export OS_PASSWORD="${ADMIN:?}"
ADMIN_PW="$ADMIN"
oa() { openstack "$@"; }
oA() { env OS_USERNAME=alice OS_PASSWORD="$USER_ALICE" OS_PROJECT_NAME=ufj-proj-a openstack "$@"; }
oB() { env OS_USERNAME=bob   OS_PASSWORD="$USER_BOB"   OS_PROJECT_NAME=ufj-proj-b openstack "$@"; }
say() { printf '[populate %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ensure() { local kind=$1 name=$2; shift 2; "${CLI:-oa}" "$kind" show "$name" >/dev/null 2>&1 || "${CLI:-oa}" "$kind" create "$@" "$name" >/dev/null; }

say "identity"
ensure project ufj-proj-a --domain Default --description "Project A (journey lab)"
ensure project ufj-proj-b --domain Default --description "Project B (journey lab)"
ensure user alice --domain Default --password "$USER_ALICE" --email alice@example.invalid
ensure user bob   --domain Default --password "$USER_BOB"   --email bob@example.invalid
ensure user carol --domain Default --password "$USER_CAROL" --email carol@example.invalid
oa role add --project ufj-proj-a --user alice member
oa role add --project ufj-proj-b --user bob member
oa role add --project ufj-proj-a --user carol admin
oa role add --project ufj-proj-b --user carol reader
ensure group ufj-ops --domain Default
oa group add user ufj-ops bob 2>/dev/null || true
oa role add --project ufj-proj-a --group ufj-ops member
oa user set --description "journey-lab user, member of ufj-proj-a" alice
oA application credential show ufj-appcred >/dev/null 2>&1 || oA application credential create --description "lab appcred" ufj-appcred >/dev/null
ensure domain ufj-dom --description "Extra domain"
oa region show RegionTwo >/dev/null 2>&1 || oa region create --description "second region record" RegionTwo >/dev/null

say "quotas"
oa quota set --instances 20 --cores 40 --ram 81920 --key-pairs 50 --server-groups 5 ufj-proj-a
oa quota set --volumes 25 --gigabytes 500 --snapshots 30 ufj-proj-a
oa quota set --networks 20 --ports 200 --floating-ips 15 --secgroups 15 --routers 5 ufj-proj-a
oa quota set --instances 5 --cores 10 --ram 20480 ufj-proj-b

say "flavors"
ensure flavor ufj.tiny --id ufj-tiny --vcpus 1 --ram 512 --disk 1
ensure flavor ufj.small --id ufj-small --vcpus 1 --ram 2048 --disk 10
ensure flavor ufj.medium --id ufj-medium --vcpus 2 --ram 4096 --disk 20
oa flavor set --property hw:cpu_policy=shared --property ufj:purpose=lab ufj.medium
ensure flavor ufj.private --id ufj-private --vcpus 2 --ram 2048 --disk 5 --private
oa flavor set --project ufj-proj-a ufj.private 2>/dev/null || true

say "host aggregate / availability zone"
ensure aggregate ufj-agg1 --zone az1
oa aggregate add host ufj-agg1 ufj-compute1 2>/dev/null || true
oa aggregate set --property ssd=true ufj-agg1
ensure aggregate ufj-agg2
oa aggregate add host ufj-agg2 ufj-compute2 2>/dev/null || true

say "images"
mkdir -p /tmp/ufj; [ -f /tmp/ufj/ufj-image-a.raw ] || head -c 8388608 /dev/urandom > /tmp/ufj/ufj-image-a.raw
[ -f /tmp/ufj/ufj-image-b.raw ] || head -c 3145728 /dev/urandom > /tmp/ufj/ufj-image-b.raw
# the files are also served by ufj-static (multi-location image, glance task import)
cp -n /tmp/ufj/ufj-image-a.raw /tmp/ufj/ufj-image-b.raw /static/
oA image show ufj-image-a >/dev/null 2>&1 || oA image create --file /tmp/ufj/ufj-image-a.raw --disk-format raw --container-format bare \
   --min-disk 1 --min-ram 64 --property os_distro=lab --property hw_disk_bus=virtio --tag lab --tag ussuri ufj-image-a >/dev/null
oa image show ufj-image-public >/dev/null 2>&1 || oa image create --file /tmp/ufj/ufj-image-b.raw --disk-format raw --container-format bare --public --tag lab ufj-image-public >/dev/null
oA image add project ufj-image-a ufj-proj-b 2>/dev/null || true
oB image set --accept ufj-image-a 2>/dev/null || true

say "block storage types"
ensure "volume type" ufj-fake --description "fake backend" --property volume_backend_name=fake
oa volume type show ufj-fake >/dev/null

say "external network, subnetpool (admin)"
oa network show ufj-ext >/dev/null 2>&1 || oa network create --external --share --provider-network-type flat --provider-physical-network physnet1 ufj-ext >/dev/null
oa subnet show ufj-ext-subnet >/dev/null 2>&1 || oa subnet create --network ufj-ext --subnet-range 203.0.113.0/24 --gateway 203.0.113.1 --no-dhcp \
   --allocation-pool start=203.0.113.10,end=203.0.113.100 ufj-ext-subnet >/dev/null
oa subnet pool show ufj-pool >/dev/null 2>&1 || oa subnet pool create --pool-prefix 10.50.0.0/16 --default-prefix-length 24 --share ufj-pool >/dev/null

say "networking project A"
CLI=oA ensure network a-net1
CLI=oA ensure network a-net2
oA subnet show a-sub1 >/dev/null 2>&1 || oA subnet create --network a-net1 --subnet-range 192.168.10.0/24 --dns-nameserver 192.0.2.53 a-sub1 >/dev/null
oA subnet show a-sub2 >/dev/null 2>&1 || oA subnet create --network a-net2 --subnet-range 192.168.20.0/24 a-sub2 >/dev/null
oA subnet show a-sub2-v6 >/dev/null 2>&1 || oA subnet create --network a-net2 --ip-version 6 --subnet-range 2001:db8:a2::/64 --ipv6-ra-mode slaac --ipv6-address-mode slaac a-sub2-v6 >/dev/null
CLI=oA ensure router a-router
oA router set --external-gateway ufj-ext a-router
oA router add subnet a-router a-sub1 2>/dev/null || true
oA router add subnet a-router a-sub2 2>/dev/null || true
oA network set --tag lab --tag proj-a a-net1
oA router set --route destination=198.51.100.0/24,gateway=192.168.10.254 a-router 2>/dev/null || true
CLI=oA ensure "security group" a-web --description "web"
for p in 22 80 443; do oA security group rule create --proto tcp --dst-port $p --remote-ip 0.0.0.0/0 a-web >/dev/null 2>&1 || true; done
oA security group rule create --proto icmp --remote-ip 0.0.0.0/0 a-web >/dev/null 2>&1 || true
CLI=oA ensure "security group" a-db --description "db tier"
oA security group rule create --proto tcp --dst-port 3306 --remote-group a-web a-db >/dev/null 2>&1 || true
oA port show a-port-fixed >/dev/null 2>&1 || oA port create --network a-net1 --fixed-ip subnet=a-sub1,ip-address=192.168.10.50 --security-group a-web a-port-fixed >/dev/null

say "networking project B"
CLI=oB ensure network b-net1
oB subnet show b-sub1 >/dev/null 2>&1 || oB subnet create --network b-net1 --subnet-range 192.168.30.0/24 b-sub1 >/dev/null
CLI=oB ensure router b-router
oB router set --external-gateway ufj-ext b-router
oB router add subnet b-router b-sub1 2>/dev/null || true
CLI=oB ensure "security group" b-ssh --description "ssh only"
oB security group rule create --proto tcp --dst-port 22 --remote-ip 10.0.0.0/8 b-ssh >/dev/null 2>&1 || true
oa network rbac create --target-project ufj-proj-a --action access_as_shared --type network b-net1 >/dev/null 2>&1 || true

say "key pairs"
oA keypair show ufj-key-a >/dev/null 2>&1 || oA keypair create ufj-key-a > /tmp/ufj/ufj-key-a.pem
oB keypair show ufj-key-b >/dev/null 2>&1 || oB keypair create ufj-key-b > /tmp/ufj/ufj-key-b.pem
if ! oA keypair show ufj-key-imported >/dev/null 2>&1; then
  python - <<'PY' > /tmp/ufj/imp.pub
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization as s
from cryptography.hazmat.backends import default_backend
k = rsa.generate_private_key(public_exponent=65537, key_size=2048, backend=default_backend())
print(k.public_key().public_bytes(s.Encoding.OpenSSH, s.PublicFormat.OpenSSH).decode())
PY
  oA keypair create --public-key /tmp/ufj/imp.pub ufj-key-imported >/dev/null
fi

say "volumes (before servers)"
oA volume show a-vol1 >/dev/null 2>&1 || oA volume create --size 10 --type ufj-fake --description "data vol" --property tier=gold a-vol1 >/dev/null
oA volume show a-vol2 >/dev/null 2>&1 || oA volume create --size 5 --type ufj-fake a-vol2 >/dev/null
# create-from-image fails with the fake LVM-derived driver (volume goes to 'error'): kept in the baseline, recorded as a failure
oA volume show a-boot >/dev/null 2>&1 || oA volume create --size 2 --image ufj-image-a --type ufj-fake a-boot >/dev/null
oA volume show a-boot2 >/dev/null 2>&1 || { oA volume create --size 2 --type ufj-fake a-boot2 >/dev/null; oA volume set --bootable a-boot2; }
oB volume show b-vol1 >/dev/null 2>&1 || oB volume create --size 3 b-vol1 >/dev/null

say "servers"
oA server group show a-aaff >/dev/null 2>&1 || oA server group create --policy anti-affinity a-aaff >/dev/null
oA server show a-vm1 >/dev/null 2>&1 || oA server create --flavor ufj.tiny --image ufj-image-a --network a-net1 --security-group a-web \
   --key-name ufj-key-a --property role=web --property owner=alice --hint group="$(oA server group show a-aaff -f value -c id)" --wait a-vm1 >/dev/null
oA server show a-vm2 >/dev/null 2>&1 || oA server create --flavor ufj.small --image ufj-image-a --nic net-id="$(oA network show a-net1 -f value -c id)" \
   --nic net-id="$(oA network show a-net2 -f value -c id)" --security-group a-web --security-group a-db --key-name ufj-key-imported \
   --property role=db --hint group="$(oA server group show a-aaff -f value -c id)" --wait a-vm2 >/dev/null
oA server show a-vm3 >/dev/null 2>&1 || oA server create --flavor ufj.tiny --volume a-boot2 --network a-net1 --security-group a-web --wait a-vm3 >/dev/null || say "WARN boot-from-volume server failed (recorded)"
oB server show b-vm1 >/dev/null 2>&1 || oB server create --flavor ufj.tiny --image ufj-image-public --network b-net1 --security-group b-ssh --key-name ufj-key-b \
   --property owner=bob --wait b-vm1 >/dev/null

say "server tags (compute API 2.26+, python-openstackclient 5.2 has no option)"
oA_tags() { env OS_USERNAME=alice OS_PASSWORD="$USER_ALICE" OS_PROJECT_NAME=ufj-proj-a python /lab/tools/tag_server.py "$@"; }
oA_tags a-vm1 web lab; oA_tags a-vm2 db; env OS_USERNAME=bob OS_PASSWORD="$USER_BOB" OS_PROJECT_NAME=ufj-proj-b python /lab/tools/tag_server.py b-vm1 edge

say "volume attach, snapshot"
[ "$(oA volume show a-vol1 -f value -c status)" = in-use ] || oA server add volume a-vm1 a-vol1 || say "WARN attach a-vol1 failed (recorded)"
oA volume snapshot show a-vol1-snap >/dev/null 2>&1 || oA volume snapshot create --volume a-vol1 --force a-vol1-snap >/dev/null || say "WARN snapshot failed"
oA volume snapshot show a-vol2-snap >/dev/null 2>&1 || oA volume snapshot create --volume a-vol2 a-vol2-snap >/dev/null || say "WARN snapshot2 failed"

say "floating IPs"
# project A: one associated to a-vm1, one left unassociated (marked by its description); project B: one associated to b-vm1
oA server show a-vm1 -f value -c addresses | grep -q '203\.0\.113\.' || { F=$(oA floating ip create ufj-ext --description "lab fip for a-vm1" -f value -c floating_ip_address); oA server add floating ip a-vm1 "$F" || say "WARN fip associate failed"; }
oA floating ip list --long -f value -c Description | grep -q "unassociated lab fip" || oA floating ip create ufj-ext --description "unassociated lab fip" >/dev/null
oB server show b-vm1 -f value -c addresses | grep -q '203\.0\.113\.' || { F=$(oB floating ip create ufj-ext -f value -c floating_ip_address); oB server add floating ip b-vm1 "$F" || say "WARN fip b failed"; }

say "server metadata / lock / other state"
oA server set --property tier=gold --property backup=daily a-vm1
oA server set --name a-vm2 --description "db server" a-vm2 2>/dev/null || true
say "done"
