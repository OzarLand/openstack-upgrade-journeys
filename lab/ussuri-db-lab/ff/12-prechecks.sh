#!/usr/bin/env bash
# Read-only pre-checks PC-* of experiments/fast-forward-checks.md on the run's Ussuri database (SELECT only).
# usage: 12-prechecks.sh <run>  -> evidence/EXP-DB-01/<run>/prechecks.txt ; exit 1 on any failing PC (named stop condition)
. "$(dirname "$0")/lib.sh"; ff_vars "${1:?run}"; set +e
O="$RUN_EV/prechecks.txt"; FAIL=0
chk() { # chk <id> <description> <query> <expected-regex-for-value>
  local v; v=$(ff_sql "$3" | tr '\n' ';' | sed 's/;$//'); if echo "$v" | grep -Eq "$4"; then echo "PASS $1 $2 -> [$v]"; else echo "FAIL $1 $2 -> [$v] expected /$4/"; FAIL=1; fi; }
{
echo "# prechecks $(date -u +%FT%TZ) on $(ff_sql 'select version()')"
# ---- checks that must run BEFORE anything else touches the copy / that change it (PC-V3, PC-G1a, PC-O1 with Ussuri tools)
chk PC-V3 "no alembic_version left by newer code in the legacy-managed databases" "SELECT TABLE_SCHEMA FROM information_schema.TABLES WHERE TABLE_NAME='alembic_version' AND TABLE_SCHEMA IN ('nova','nova_cell0','nova_api','keystone','cinder')" '^$'
CFU() { echo "--config-file /etc/$1/$2 --config-file /etc/ff/$3"; }
mkdir -p "$RUN_EV/pc-o1"
ff_oneshot ussuri glance -- glance-manage $(CFU glance glance-api.conf glance.conf) db check > "$RUN_EV/pc-o1/glance-db-check.txt" 2>&1; rc=$?
if [ $rc -eq 0 ]; then echo "PASS PC-G1a Ussuri glance-manage db check -> exit 0 ($(grep -h 'up to date' "$RUN_EV/pc-o1/glance-db-check.txt" | tail -1 | cut -c1-80))"; else echo "FAIL PC-G1a Ussuri glance-manage db check -> exit $rc (SC-GLANCE)"; FAIL=1; fi
odm() { # odm <label> <svc> <command...> : Ussuri ODM until exit 0 (max 10)
  local lab=$1 svc=$2; shift 2; local i rc
  for i in $(seq 1 10); do ff_oneshot ussuri "$svc" -- "$@" > "$RUN_EV/pc-o1/$lab-$i.raw" 2>&1; rc=$?
    ff_redact < "$RUN_EV/pc-o1/$lab-$i.raw" | grep -E "matched query|^\|" > "$RUN_EV/pc-o1/$lab-$i.txt"; rm -f "$RUN_EV/pc-o1/$lab-$i.raw"
    [ $rc -eq 0 ] && { echo "PASS PC-O1 $lab Ussuri online_data_migrations -> exit 0 after $i run(s)"; return 0; }; [ $rc -ne 1 ] && break; done
  echo "FAIL PC-O1 $lab -> exit $rc (finish the Ussuri ODMs first)"; FAIL=1; }
odm nova-cell1 nova nova-manage $(CFU nova nova.conf nova.conf) db online_data_migrations
odm nova-cell0 nova nova-manage $(CFU nova nova.conf nova-cell0.conf) db online_data_migrations
odm placement placement placement-manage $(CFU placement placement.conf placement.conf) db online_data_migrations
odm cinder cinder cinder-manage $(CFU cinder cinder.conf cinder.conf) db online_data_migrations
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
chk PC-C4 "no non-deleted cinder volume without service_uuid" "SELECT CONCAT(id,' ',status,' no_host=',host IS NULL) FROM cinder.volumes WHERE deleted=0 AND service_uuid IS NULL" '^$'
echo "-- PC-C1p prediction (deleted rows that H1 will leave NULL, V-C1a/V-C2a): volumes $(ff_sql "SELECT CONCAT('deleted=',deleted,':',COUNT(*)) FROM cinder.volumes GROUP BY deleted" | tr '\n' ' ') snapshots $(ff_sql "SELECT CONCAT('deleted=',deleted,':',COUNT(*)) FROM cinder.snapshots GROUP BY deleted" | tr '\n' ' ')"
echo "-- PC-Q5 diagnostic (rows of the duplicate groups, empty when PC-Q5 passes)"; ff_sql "SELECT s.network_id, s.network_type, s.physical_network, s.segmentation_id, s.segment_index, s.is_dynamic, (SELECT COUNT(*) FROM neutron.ml2_port_binding_levels l WHERE l.segment_id=s.id) AS bound_levels FROM neutron.networksegments s JOIN (SELECT network_id, network_type, physical_network FROM neutron.networksegments WHERE physical_network IS NOT NULL GROUP BY 1,2,3 HAVING COUNT(*)>1) d USING (network_id, network_type, physical_network) ORDER BY 1,5"
TD=$(python3 -c "
import importlib.util,sys
sp=importlib.util.spec_from_file_location('c','$FF_DIR/tools/compare.py'); m=importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
print(' '.join(sorted(m.TABLES_TO_DROP)))")
q3=""; for t in $TD; do n=$(ff_sql "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='neutron' AND TABLE_NAME='$t'"); [ "$n" = 1 ] && q3="$q3 $(ff_sql "SELECT CONCAT('$t=',COUNT(*)) FROM neutron.\`$t\`")"; done
if echo "$q3" | grep -qE "=[1-9]"; then echo "FAIL PC-Q3 legacy plugin tables not empty:$q3"; FAIL=1; else echo "PASS PC-Q3 legacy plugin tables (TABLES_TO_DROP of 054e34dbe6b4) present at T0: $(echo $q3 | wc -w), all 0 rows"; fi
chk PC-E1 "@@GLOBAL.sql_mode" "SELECT @@GLOBAL.sql_mode" 'STRICT'
chk R-8-pred "ports with trusted profile (predicts neutron.porttrusted rows)" "SELECT COUNT(*) FROM neutron.ml2_port_bindings WHERE profile LIKE '%trusted%'" '.'
chk V-Q1-pred "dhcp ports with device_id like ovnmeta (V-Q1)" "SELECT COUNT(*) FROM neutron.ports WHERE device_owner='network:dhcp' AND device_id LIKE 'ovnmeta%'" '^0$'
# ---- predictions for the declared changes (read by compare.py; RT-N-21)
mkdir -p "$CFG_FF/snap"
DB_ROOT="$DB_ROOT" DB_FF="$DB_FF" python3 - > "$CFG_FF/snap/predictions.json" <<'PY'
import json, os, subprocess
def n(sql):
    r = subprocess.run(['docker', 'exec', '-i', '-e', 'MYSQL_PWD=' + os.environ['DB_ROOT'], os.environ['DB_FF'], 'sh', '-c', 'exec "$(command -v mariadb || command -v mysql)" -uroot -N -B'], input=sql, capture_output=True, text=True).stdout.strip()
    return int(r or 0)
p = {}
p['r5_missing'] = 2 - n("SELECT COUNT(*) FROM cinder.quota_classes WHERE class_name='default' AND deleted=0 AND resource IN ('backups','backup_gigabytes')")
p['trusted_ports'] = n("SELECT COUNT(*) FROM neutron.ml2_port_bindings WHERE profile LIKE '%trusted%'")
p['v_c6_rows'] = sum(n("SELECT COUNT(*) FROM cinder.%s WHERE resource='consistencygroups' AND deleted=0" % t) for t in ('quota_classes', 'quotas', 'quota_usages', 'reservations'))
p['temporary_rows'] = n("SELECT COUNT(*) FROM cinder.volume_admin_metadata WHERE `key`='temporary' AND deleted=0")
p['segrange_null'] = n("SELECT COUNT(*) FROM neutron.network_segment_ranges WHERE physical_network IS NULL")
p['ovnmeta_dhcp'] = n("SELECT COUNT(*) FROM neutron.ports WHERE device_owner='network:dhcp' AND device_id LIKE 'ovnmeta%'")
p['sentinel_projects'] = n("SELECT COUNT(*) FROM placement.projects WHERE external_id='00000000-0000-0000-0000-000000000000'")
p['sentinel_users'] = n("SELECT COUNT(*) FROM placement.users WHERE external_id='00000000-0000-0000-0000-000000000000'")
p['deleted_volumes'] = n("SELECT COUNT(*) FROM cinder.volumes WHERE deleted<>0")
p['deleted_snapshots'] = n("SELECT COUNT(*) FROM cinder.snapshots WHERE deleted<>0")
print(json.dumps(p, indent=1))
PY
echo "-- predictions: $(tr -d '\n ' < "$CFG_FF/snap/predictions.json")"
echo "-- PC-E2 largest tables"; ff_sql "SELECT TABLE_SCHEMA,TABLE_NAME,TABLE_ROWS,DATA_LENGTH+INDEX_LENGTH FROM information_schema.TABLES WHERE TABLE_SCHEMA IN ('keystone','glance','placement','nova','nova_api','nova_cell0','neutron','cinder') ORDER BY 4 DESC LIMIT 10"
echo "-- charsets (non-utf8 tables)"; ff_sql "SELECT TABLE_SCHEMA,TABLE_NAME,TABLE_COLLATION FROM information_schema.TABLES WHERE TABLE_SCHEMA IN ('keystone','glance','placement','nova','nova_api','nova_cell0','neutron','cinder') AND TABLE_COLLATION NOT LIKE 'utf8\\_%' AND TABLE_TYPE='BASE TABLE'"
echo "-- SC overall: $([ $FAIL = 0 ] && echo PASS || echo 'FAIL (named stop condition SC-PC-*)')"
} > "$O" 2>&1
cat "$O"; exit $FAIL
