#!/usr/bin/env bash
# Starts the Ussuri API services and workers as containers on ufj-net. Idempotent (running containers are kept).
. "$(dirname "$0")/lib.sh"; load_secrets
W=(-v "$LAB_DIR/wsgi:/wsgi:ro")
svc_start ufj-glance glance -v ufj-glance-images:/var/lib/glance -- glance-api --config-file /etc/glance/glance-api.conf
svc_start ufj-placement placement "${W[@]}" -- gunicorn --chdir /wsgi --bind 0.0.0.0:8778 --workers 2 --timeout 120 placement_app:application
svc_start ufj-nova-api nova -- nova-api --config-file /etc/nova/nova.conf
svc_start ufj-nova-conductor nova -- nova-conductor --config-file /etc/nova/nova.conf
svc_start ufj-nova-scheduler nova -- nova-scheduler --config-file /etc/nova/nova.conf
svc_start ufj-neutron neutron -- neutron-server --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/ml2_conf.ini
svc_start ufj-cinder-api cinder -- cinder-api --config-file /etc/cinder/cinder.conf
svc_start ufj-cinder-scheduler cinder -- cinder-scheduler --config-file /etc/cinder/cinder.conf
svc_start ufj-cinder-volume cinder -- cinder-volume --config-file /etc/cinder/cinder.conf
log "waiting for the APIs"
wait_http http://ufj-glance:9292/ 120       || die "glance not answering"
wait_http http://ufj-placement:8778/ 120    || die "placement not answering"
wait_http http://ufj-nova-api:8774/ 180     || die "nova-api not answering"
wait_http http://ufj-neutron:9696/ 180      || die "neutron-server not answering"
wait_http http://ufj-cinder-api:8776/ 120   || die "cinder-api not answering"
# two fake compute nodes (nova.virt.fake.FakeDriver): no hypervisor, no libvirt
for n in 1 2; do svc_start ufj-compute$n nova -- nova-compute --config-file /etc/nova/nova.conf; done
# fake L2 agents (real report_state RPC to neutron-server) so that the 'fake_agent' mechanism driver can bind ports
for n in 1 2; do svc_start ufj-fake-agent$n neutron -v "$LAB_DIR/tools:/tools:ro" -- python /tools/fake_l2_agent.py --host ufj-compute$n; done
log "services started"
