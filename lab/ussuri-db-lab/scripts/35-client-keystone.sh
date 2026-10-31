#!/usr/bin/env bash
# Starts keystone (gunicorn) and the client container; creates the service project/users/catalog entries. Idempotent.
. "$(dirname "$0")/lib.sh"; load_secrets
start_keystone_client
log "waiting for keystone"; wait_http http://ufj-keystone:5000/v3 120 || die "keystone not answering"
osc project show service >/dev/null 2>&1 || osc project create --domain Default service >/dev/null
mk_user() { # name password
  osc user show "$1" >/dev/null 2>&1 || osc user create --domain Default --password "$2" "$1" >/dev/null
  osc role add --project service --user "$1" admin
}
mk_user glance "$SVC_GLANCE"; mk_user placement "$SVC_PLACEMENT"; mk_user nova "$SVC_NOVA"; mk_user neutron "$SVC_NEUTRON"; mk_user cinder "$SVC_CINDER"
mk_ep() { # name type description url
  osc service show "$2" >/dev/null 2>&1 || osc service create --name "$1" --description "$3" "$2" >/dev/null
  for iface in public internal admin; do
    osc endpoint list --service "$2" --interface $iface -f value -c ID | grep -q . || osc endpoint create --region RegionOne "$2" $iface "$4" >/dev/null
  done
}
mk_ep glance image "OpenStack Image" http://ufj-glance:9292
mk_ep placement placement "Placement API" http://ufj-placement:8778
mk_ep nova compute "OpenStack Compute" http://ufj-nova-api:8774/v2.1
mk_ep neutron network "OpenStack Networking" http://ufj-neutron:9696
mk_ep cinderv3 volumev3 "OpenStack Block Storage" 'http://ufj-cinder-api:8776/v3/%(project_id)s'
log "keystone ready; service users/endpoints created"
