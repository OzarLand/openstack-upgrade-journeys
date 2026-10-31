#!/usr/bin/env bash
# Renders the service configuration files into .run/etc/<service>/ (git-ignored: they contain passwords).
# Plain upstream options only; no Kolla templates. Re-running overwrites the files (idempotent).
. "$(dirname "$0")/lib.sh"; load_secrets
E="$RUN_DIR/etc"; mkdir -p "$E"/{keystone,glance,placement,nova,neutron,cinder,client}; umask 077
MQ="rabbit://openstack:${RABBIT}@ufj-rabbitmq:5672//"
db() { echo "mysql+pymysql://$1:$2@ufj-mariadb/$3?charset=utf8"; }
authtoken() { # authtoken <service-user> <password>
cat <<T
[keystone_authtoken]
www_authenticate_uri = http://ufj-keystone:5000
auth_url = http://ufj-keystone:5000
memcached_servers = ufj-memcached:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = $1
password = $2
T
}
auth_section() { # auth_section <section> <user> <password>
cat <<T
[$1]
auth_url = http://ufj-keystone:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
region_name = RegionOne
username = $2
password = $3
T
}

cat > "$E/keystone/keystone.conf" <<T
[DEFAULT]
use_stderr = true
debug = false
[database]
connection = $(db keystone "$DBPW_KEYSTONE" keystone)
[cache]
backend = oslo_cache.memcache_pool
enabled = true
memcache_servers = ufj-memcached:11211
[token]
provider = fernet
[fernet_tokens]
key_repository = /var/lib/ufj/keys/fernet-keys
[fernet_receipts]
key_repository = /var/lib/ufj/keys/fernet-keys
[credential]
key_repository = /var/lib/ufj/keys/credential-keys
T

cat > "$E/glance/glance-api.conf" <<T
[DEFAULT]
bind_host = 0.0.0.0
bind_port = 9292
transport_url = $MQ
use_stderr = true
show_image_direct_url = false
show_multiple_locations = true
[database]
connection = $(db glance "$DBPW_GLANCE" glance)
$(authtoken glance "$SVC_GLANCE")
[paste_deploy]
flavor = keystone
[glance_store]
stores = file,http
default_store = file
filesystem_store_datadir = /var/lib/glance/images
[oslo_concurrency]
lock_path = /var/lib/glance/tmp
T

cat > "$E/placement/placement.conf" <<T
[DEFAULT]
use_stderr = true
[api]
auth_strategy = keystone
[placement_database]
connection = $(db placement "$DBPW_PLACEMENT" placement)
$(authtoken placement "$SVC_PLACEMENT")
T

cat > "$E/nova/nova.conf" <<T
[DEFAULT]
transport_url = $MQ
my_ip = 0.0.0.0
use_stderr = true
state_path = /var/lib/nova
enabled_apis = osapi_compute,metadata
osapi_compute_listen = 0.0.0.0
osapi_compute_listen_port = 8774
metadata_listen = 0.0.0.0
metadata_listen_port = 8775
compute_driver = fake.FakeDriver
firewall_driver = nova.virt.firewall.NoopFirewallDriver
vif_plugging_is_fatal = false
vif_plugging_timeout = 0
resume_guests_state_on_host_boot = false
reclaim_instance_interval = 3600
[api]
auth_strategy = keystone
[api_database]
connection = $(db nova "$DBPW_NOVA" nova_api)
[database]
connection = $(db nova "$DBPW_NOVA" nova)
$(authtoken nova "$SVC_NOVA")
[glance]
api_servers = http://ufj-glance:9292
$(auth_section placement placement "$SVC_PLACEMENT")
$(auth_section neutron neutron "$SVC_NEUTRON")
service_metadata_proxy = false
$(auth_section cinder cinder "$SVC_CINDER")
os_region_name = RegionOne
[scheduler]
discover_hosts_in_cells_interval = 30
[filter_scheduler]
enabled_filters = AvailabilityZoneFilter,NUMATopologyFilter,ComputeFilter,ComputeCapabilitiesFilter,ImagePropertiesFilter,ServerGroupAntiAffinityFilter,ServerGroupAffinityFilter
[conductor]
workers = 2
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
T

# compute-only overrides (kept apart so that the shared nova.conf stays the stock FakeDriver setting)
printf '[DEFAULT]\ncompute_driver = ufj_fake.UfjFakeDriver\n' > "$E/nova/nova-compute.conf"
cat > "$E/neutron/neutron.conf" <<T
[DEFAULT]
core_plugin = ml2
service_plugins = router,segments,network_segment_range
allow_overlapping_ips = true
auth_strategy = keystone
transport_url = $MQ
notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true
bind_host = 0.0.0.0
api_workers = 2
rpc_workers = 2
use_stderr = true
state_path = /var/lib/neutron
[database]
connection = $(db neutron "$DBPW_NEUTRON" neutron)
$(authtoken neutron "$SVC_NEUTRON")
$(auth_section nova nova "$SVC_NOVA")
[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
T
cat > "$E/neutron/ml2_conf.ini" <<'T'
# 'fake_agent' is a test mechanism driver shipped inside the neutron wheel
# (neutron.tests.unit.plugins.ml2.drivers.mech_fake_agent). It binds ports for hosts that have an alive fake agent.
[ml2]
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan
mechanism_drivers = fake_agent
extension_drivers = port_security
[ml2_type_flat]
flat_networks = physnet1
[ml2_type_vlan]
network_vlan_ranges = physnet1:100:200
[ml2_type_vxlan]
vni_ranges = 1:1000
[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.firewall.NoopFirewallDriver
T

cat > "$E/cinder/cinder.conf" <<T
[DEFAULT]
transport_url = $MQ
auth_strategy = keystone
my_ip = 0.0.0.0
osapi_volume_listen = 0.0.0.0
osapi_volume_listen_port = 8776
enabled_backends = fake,fake2
quota_backups = 7
default_volume_type = __DEFAULT__
use_stderr = true
state_path = /var/lib/cinder
[database]
connection = $(db cinder "$DBPW_CINDER" cinder)
$(authtoken cinder "$SVC_CINDER")
$(auth_section nova nova "$SVC_NOVA")
[oslo_concurrency]
lock_path = /var/lib/cinder/tmp
[fake]
volume_driver = cinder.tests.fake_driver.FakeLoggingVolumeDriver
volume_backend_name = fake
[fake2]
volume_driver = cinder.tests.fake_driver.FakeLoggingVolumeDriver
volume_backend_name = fake2
T

# paste pipelines ship as data files in the wheels (/opt/ussuri/etc/<svc>/); copy them next to the rendered configs
for pair in nova:api-paste.ini neutron:api-paste.ini glance:glance-api-paste.ini cinder:api-paste.ini; do
  docker run --rm "$IMG" cat "/opt/ussuri/etc/${pair%%:*}/${pair#*:}" > "$E/${pair%%:*}/${pair#*:}"
done

# Admin credentials for the client container. Mounted read-only at /run/ufj.
cat > "$E/client/admin-openrc" <<T
OS_AUTH_URL=http://ufj-keystone:5000/v3
OS_PROJECT_NAME=admin
OS_USER_DOMAIN_NAME=Default
OS_PROJECT_DOMAIN_NAME=Default
OS_USERNAME=admin
OS_PASSWORD=$ADMIN
OS_REGION_NAME=RegionOne
OS_IDENTITY_API_VERSION=3
OS_INTERFACE=public
T
chmod 600 "$E"/*/* 2>/dev/null || true
chmod -R a+rX "$RUN_DIR"   # readable by container users; the .run tree is git-ignored, host dir is mode 700 via $SECRETS_DIR only
log "rendered configs into $E"
