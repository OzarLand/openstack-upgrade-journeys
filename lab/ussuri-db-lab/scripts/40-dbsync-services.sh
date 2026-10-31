#!/usr/bin/env bash
# Runs the real Ussuri schema commands for glance, placement, nova (api db, cell0, cell1), neutron and cinder.
# Each step is timed into .run/dbsync-timings.txt. Needs MariaDB and RabbitMQ (infra) and the rendered config.
. "$(dirname "$0")/lib.sh"; load_secrets
mkdir -p "$RUN_DIR"; T="$RUN_DIR/dbsync-timings.txt"; : > "$T"
timed() { local n=$1; shift; local t0; t0=$(date +%s.%N); log "$n"; "$@" > "$RUN_DIR/log-$n.txt" 2>&1 || { tail -20 "$RUN_DIR/log-$n.txt"; die "$n failed"; }
  printf '%s\t%.1f s\n' "$n" "$(echo "$(date +%s.%N) - $t0" | bc)" | tee -a "$T"; }

timed glance-db_sync       oneshot glance -v ufj-glance-images:/var/lib/glance -- glance-manage --config-file /etc/glance/glance-api.conf db_sync
timed placement-db_sync    oneshot placement -- placement-manage --config-file /etc/placement/placement.conf db sync
timed nova-api_db_sync     oneshot nova -- nova-manage --config-file /etc/nova/nova.conf api_db sync
# map_cell0 / create_cell are idempotent only if the cell does not exist yet: check first
if ! oneshot nova -- nova-manage --config-file /etc/nova/nova.conf cell_v2 list_cells 2>/dev/null | grep -q ' cell0 '; then
  timed nova-cell_v2_map_cell0 oneshot nova -- nova-manage --config-file /etc/nova/nova.conf cell_v2 map_cell0 --database_connection "mysql+pymysql://nova:${DBPW_NOVA}@ufj-mariadb/nova_cell0?charset=utf8"
fi
if ! oneshot nova -- nova-manage --config-file /etc/nova/nova.conf cell_v2 list_cells 2>/dev/null | grep -q ' cell1 '; then
  timed nova-cell_v2_create_cell oneshot nova -- nova-manage --config-file /etc/nova/nova.conf cell_v2 create_cell --name=cell1 --verbose
fi
timed nova-db_sync         oneshot nova -- nova-manage --config-file /etc/nova/nova.conf db sync
timed neutron-db_upgrade   oneshot neutron -- neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/ml2_conf.ini upgrade heads
timed cinder-db_sync       oneshot cinder -- cinder-manage --config-file /etc/cinder/cinder.conf db sync
log "all db syncs done"; cat "$T"
