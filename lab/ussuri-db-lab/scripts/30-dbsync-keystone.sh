#!/usr/bin/env bash
# Keystone: fernet/credential keys, db_sync, bootstrap (admin user/project/role, identity endpoints). Timed.
. "$(dirname "$0")/lib.sh"; load_secrets
T0=$(date +%s)
KV="-v ufj-keystone-keys:/var/lib/ufj/keys"
oneshot keystone $KV -- sh -c 'mkdir -p /var/lib/ufj/keys; [ -d /var/lib/ufj/keys/fernet-keys ] || keystone-manage --config-file /etc/keystone/keystone.conf fernet_setup --keystone-user root --keystone-group root; [ -d /var/lib/ufj/keys/credential-keys ] || keystone-manage --config-file /etc/keystone/keystone.conf credential_setup --keystone-user root --keystone-group root'
oneshot keystone $KV -- keystone-manage --config-file /etc/keystone/keystone.conf db_sync
oneshot keystone $KV -- keystone-manage --config-file /etc/keystone/keystone.conf bootstrap \
  --bootstrap-password "$ADMIN" --bootstrap-username admin --bootstrap-project-name admin --bootstrap-role-name admin \
  --bootstrap-service-name keystone --bootstrap-region-id RegionOne \
  --bootstrap-admin-url http://ufj-keystone:5000/v3/ --bootstrap-internal-url http://ufj-keystone:5000/v3/ --bootstrap-public-url http://ufj-keystone:5000/v3/
log "keystone db_sync + bootstrap: $(( $(date +%s)-T0 )) s"
