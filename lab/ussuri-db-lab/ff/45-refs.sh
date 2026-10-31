#!/usr/bin/env bash
# Builds the reference schemas <db>_ref on the SAME server with the SAME code (fresh db sync), for comparison A.
# usage: 45-refs.sh <run> <rel>
. "$(dirname "$0")/lib.sh"; ff_vars "${1:?run}"; REL="${2:?release}"; set +e
for svc in ${ONLY:-keystone glance placement nova neutron cinder}; do
  pw_var="DBPW_$(echo $svc | tr a-z A-Z)"; pw="${!pw_var}"; dbs=("$svc"); [ "$svc" = nova ] && dbs=(nova_api nova nova_cell0)
  for d in "${dbs[@]}"; do ff_sql "DROP DATABASE IF EXISTS \`${d}_ref\`; CREATE DATABASE \`${d}_ref\` CHARACTER SET utf8 COLLATE utf8_general_ci; GRANT ALL PRIVILEGES ON \`${d}_ref\`.* TO '$svc'@'%';"; done
done
CF() { echo "--config-file /etc/$1/$2 --config-file /etc/ff/$3"; }
LOCAL=""; [ "$REL" != ussuri ] && LOCAL="--local_cell"
R() { ff_oneshot "$REL" "$@" > "$RUN_EV/${CUR:-ref}.ref.log" 2>&1 || { echo "reference build failed: $*"; tail -20 "$RUN_EV/${CUR:-ref}.ref.log"; exit 1; }; }
if [ -z "${ONLY:-}" ]; then
R keystone -- keystone-manage $(CF keystone keystone.conf keystone-ref.conf) db_sync
R glance -- glance-manage $(CF glance glance-api.conf glance-ref.conf) db sync
R placement -- placement-manage $(CF placement placement.conf placement-ref.conf) db sync
R nova -- nova-manage $(CF nova nova.conf nova-ref.conf) api_db sync
R nova -- nova-manage $(CF nova nova.conf nova-cell0-ref.conf) db sync $LOCAL
R nova -- nova-manage $(CF nova nova.conf nova-ref.conf) db sync $LOCAL
R neutron -- neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/ml2_conf.ini --config-file /etc/ff/neutron-ref.conf upgrade heads
fi
# cinder reference: REL_CINDER (23.5.0 image at H1b), else the hop release
REL_SAVE=$REL; REL=${REL_CINDER:-$REL}; R cinder -- cinder-manage $(CF cinder cinder.conf cinder-ref.conf) db sync; REL=$REL_SAVE
echo "references built with release $REL"
