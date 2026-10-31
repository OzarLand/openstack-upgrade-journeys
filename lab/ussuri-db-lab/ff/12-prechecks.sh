#!/usr/bin/env bash
# Read-only pre-checks PC-* of experiments/fast-forward-checks.md on the run's Ussuri database (SELECT only).
# usage: 12-prechecks.sh <run>  -> evidence/EXP-DB-01/<run>/prechecks.txt ; exit 1 on any failing PC (named stop condition)
. "$(dirname "$0")/lib.sh"; ff_vars "${1:?run}"; set +e
O="$RUN_EV/prechecks.txt"; FAIL=0
chk() { # chk <id> <description> <query> <expected-regex-for-value>
  local v; v=$(ff_sql "$3" | tr '\n' ';' | sed 's/;$//'); if echo "$v" | grep -Eq "$4"; then echo "PASS $1 $2 -> [$v]"; else echo "FAIL $1 $2 -> [$v] expected /$4/"; FAIL=1; fi; }
{
echo "# prechecks $(date -u +%FT%TZ) on $(ff_sql 'select version()')"
chk PC-V1a "nova/nova_cell0 migrate_version >= 401" "SELECT version FROM nova.migrate_version UNION ALL SELECT version FROM nova_cell0.migrate_version" '^407;407$'
chk PC-V1b "nova_api migrate_version >= 66" "SELECT version FROM nova_api.migrate_version" '^72$'
chk PC-V1c "keystone repos (record 078/079)" "SELECT CONCAT(repository_id,'=',version) FROM keystone.migrate_version ORDER BY 1" 'keystone_contract=0?(78|79)'
chk PC-V1d "cinder >= 134" "SELECT version FROM cinder.migrate_version" '^136$'
chk PC-V2a "glance alembic head" "SELECT version_num FROM glance.alembic_version" 'ussuri_contract01'
chk PC-V2b "placement alembic head" "SELECT version_num FROM placement.alembic_version" 'b5c396305c25'
chk PC-V2c "neutron alembic heads recorded" "SELECT version_num FROM neutron.alembic_version ORDER BY 1" '.'
chk PC-G1b "glance image_locations with a backend key" "SELECT COUNT(*) FROM glance.image_locations WHERE INSTR(meta_data,'\"backend\":')>0" '^0$'
chk PC-G2 "leftover triggers glance/keystone" "SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA IN ('glance','keystone')" '^0$'
chk PC-N1a "in-flight nova work" "SELECT COUNT(*) FROM nova.instances WHERE deleted=0 AND task_state IS NOT NULL" '^0$'
chk PC-N1b "migrations in non-final status (recorded)" "SELECT CONCAT(status,'=',COUNT(*)) FROM nova.migrations WHERE deleted=0 GROUP BY status" '.'
chk PC-N2 "cell mappings (names only)" "SELECT CONCAT(id,' ',name) FROM nova_api.cell_mappings ORDER BY id" 'cell0.*cell1'
chk PC-N3 "build requests" "SELECT COUNT(*) FROM nova_api.build_requests" '^0$'
chk PC-N4 "compute_id residue predicted (instances incl. deleted without compute_nodes row, host not NULL)" "SELECT COUNT(*) FROM nova.instances i WHERE i.host IS NOT NULL AND NOT EXISTS (SELECT 1 FROM nova.compute_nodes c WHERE c.host=i.host AND c.hypervisor_hostname=i.node AND c.deleted=0)" '.'
chk PC-N4b "instances with host NULL (their compute_id stays NULL)" "SELECT COUNT(*) FROM nova.instances WHERE host IS NULL" '.'
chk PC-C2 "cinder transitional states" "SELECT COUNT(*) FROM cinder.volumes WHERE deleted=0 AND status IN ('creating','attaching','detaching','migrating','backing-up','restoring-backup','downloading','uploading','extending','retyping')" '^0$'
chk PC-C3a "cinder default quota_classes present" "SELECT CONCAT(resource,'=',hard_limit) FROM cinder.quota_classes WHERE class_name='default' AND deleted=0 AND resource IN ('backups','backup_gigabytes')" '.*'
chk PC-C3b "cinder consistencygroups rows (V-C6 prediction)" "SELECT CONCAT((SELECT COUNT(*) FROM cinder.quota_classes WHERE resource='consistencygroups' AND deleted=0),'/',(SELECT COUNT(*) FROM cinder.quotas WHERE resource='consistencygroups' AND deleted=0),'/',(SELECT COUNT(*) FROM cinder.quota_usages WHERE resource='consistencygroups' AND deleted=0),'/',(SELECT COUNT(*) FROM cinder.reservations WHERE resource='consistencygroups' AND deleted=0))" '.'
chk PC-C3c "cinder temporary admin metadata (V-C9 prediction)" "SELECT COUNT(*) FROM cinder.volume_admin_metadata WHERE \`key\`='temporary' AND deleted=0" '.'
chk PC-K1 "duplicate trusts" "SELECT COUNT(*) FROM (SELECT 1 FROM keystone.trust GROUP BY trustor_user_id,trustee_user_id,project_id,impersonation,expires_at HAVING COUNT(*)>1) t" '^0$'
chk PC-K2 "password hashers (prefix: count)" "SELECT CONCAT(h,'=',c) FROM (SELECT SUBSTRING(password_hash,1,4) h, COUNT(*) c FROM keystone.password GROUP BY SUBSTRING(password_hash,1,4)) t" '.'
chk PC-Q1 "duplicate neutron quotas" "SELECT COUNT(*) FROM (SELECT 1 FROM neutron.quotas GROUP BY project_id,resource HAVING COUNT(*)>1) t" '^0$'
chk PC-Q2 "portbindingports" "SELECT COUNT(*) FROM neutron.portbindingports" '^0$'
chk PC-Q4 "duplicate segment ranges" "SELECT COUNT(*) FROM (SELECT 1 FROM neutron.network_segment_ranges GROUP BY \`default\`,network_type,IFNULL(physical_network,''),minimum,maximum HAVING COUNT(*)>1) t" '^0$'
chk PC-Q5 "duplicate network segments (physnet not NULL)" "SELECT COUNT(*) FROM (SELECT 1 FROM neutron.networksegments WHERE physical_network IS NOT NULL GROUP BY network_id,network_type,physical_network HAVING COUNT(*)>1) t" '^0$'
chk PC-Q6 "duplicate HA networks per project" "SELECT COUNT(*) FROM (SELECT 1 FROM neutron.ha_router_networks GROUP BY project_id HAVING COUNT(*)>1) t" '^0$'
chk PC-E1 "@@GLOBAL.sql_mode" "SELECT @@GLOBAL.sql_mode" 'STRICT'
chk R-8-pred "ports with trusted profile (predicts neutron.porttrusted rows)" "SELECT COUNT(*) FROM neutron.ml2_port_bindings WHERE profile LIKE '%trusted%'" '.'
chk V-Q1-pred "dhcp ports with device_id like ovnmeta (V-Q1)" "SELECT COUNT(*) FROM neutron.ports WHERE device_owner='network:dhcp' AND device_id LIKE 'ovnmeta%'" '^0$'
echo "-- PC-E2 largest tables"; ff_sql "SELECT TABLE_SCHEMA,TABLE_NAME,TABLE_ROWS,DATA_LENGTH+INDEX_LENGTH FROM information_schema.TABLES WHERE TABLE_SCHEMA IN ('keystone','glance','placement','nova','nova_api','nova_cell0','neutron','cinder') ORDER BY 4 DESC LIMIT 10"
echo "-- charsets (non-utf8 tables)"; ff_sql "SELECT TABLE_SCHEMA,TABLE_NAME,TABLE_COLLATION FROM information_schema.TABLES WHERE TABLE_SCHEMA IN ('keystone','glance','placement','nova','nova_api','nova_cell0','neutron','cinder') AND TABLE_COLLATION NOT LIKE 'utf8\\_%' AND TABLE_TYPE='BASE TABLE'"
echo "-- SC overall: $([ $FAIL = 0 ] && echo PASS || echo 'FAIL (named stop condition SC-PC-*)')"
} > "$O" 2>&1
cat "$O"; exit $FAIL
