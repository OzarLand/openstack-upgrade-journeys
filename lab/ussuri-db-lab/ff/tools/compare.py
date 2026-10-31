#!/usr/bin/env python3
"""Comparisons of the fast-forward experiments (comparator version 2: Amendment 1 of declared-differences.md, section 8).
  compare.py schema --snap DIR --a DB --b DB_REF --hop H      comparison A, classified (DECLARED / UNDECLARED)
  compare.py data --t0 DIR --now DIR --hop H [--pred FILE] [--only-db DB]   comparison B vs T0
  compare.py same --a DIR --b DIR [--exclude-db DB | --only-db DB]  two snapshots must be identical (H4r vs H4, H1b vs H1 outside cinder)
Hop ids: 1 2 3 4 5 (5 = H4r) and 1b. DECLARED rows carry the id of declared-differences.md. Exit 1 if any UNDECLARED.
THIS FILE IS PART OF THE FROZEN ARTEFACT: it is committed before a strict run and never edited between a run and its record."""
import argparse, glob, gzip, json, os, sys, re, collections

HOPNUM = {'1': 1, '1b': 1.5, '2': 2, '3': 3, '4': 4, '5': 5}
HERE = os.path.dirname(os.path.abspath(__file__))

def rd(p):
    return [l.rstrip('\n').split('\t') for l in open(p)] if os.path.exists(p) else []

# ---------------------------------------------------------------- schema (A)
def schema_raw(a):
    A, B = '%s/schema/%s' % (a.snap, a.a), '%s/schema/%s' % (a.snap, a.b)
    out = []
    def S(name): return rd('%s/%s.tsv' % (A, name)), rd('%s/%s.tsv' % (B, name))
    ta, tb = S('tables'); da, db = {r[0]: r[1:] for r in ta}, {r[0]: r[1:] for r in tb}
    for t in sorted(set(da) | set(db)):
        if t not in db: out.append(('structural', 'table only in migrated: %s' % t))
        elif t not in da: out.append(('structural', 'table only in reference: %s' % t))
        elif da[t] != db[t]: out.append(('structural', 'table %s engine/collation: migrated=%s reference=%s' % (t, da[t], db[t])))
    ca, cb = S('columns'); da, db = {(r[0], r[1]): r[2:] for r in ca}, {(r[0], r[1]): r[2:] for r in cb}
    for k in sorted(set(da) | set(db)):
        if k not in db: out.append(('structural', 'column only in migrated: %s.%s %s' % (k[0], k[1], da[k])))
        elif k not in da: out.append(('structural', 'column only in reference: %s.%s %s' % (k[0], k[1], db[k])))
        elif da[k] != db[k]: out.append(('structural', 'column %s.%s migrated=%s reference=%s' % (k[0], k[1], da[k], db[k])))
    def idx(rows):
        d = collections.defaultdict(list)
        for r in rows: d[(r[0], r[1])].append(r[2:])
        return d
    ia, ib = idx(S('indexes')[0]), idx(S('indexes')[1])
    sa = {(t, tuple((x[2], x[3]) for x in v), v[0][0]): n for (t, n), v in ia.items()}
    sb = {(t, tuple((x[2], x[3]) for x in v), v[0][0]): n for (t, n), v in ib.items()}
    for k in sorted(set(sa) | set(sb)):
        if k not in sb: out.append(('structural', 'index only in migrated: %s %s (name %s)' % (k[0], k[1], sa[k])))
        elif k not in sa: out.append(('structural', 'index only in reference: %s %s (name %s)' % (k[0], k[1], sb[k])))
        elif sa[k] != sb[k] and not (sa[k] == 'PRIMARY'): out.append(('name-only', 'index name %s %s migrated=%s reference=%s' % (k[0], k[1], sa[k], sb[k])))
    ka, kb = S('keys')
    def keyset(rows):
        d = collections.defaultdict(list)
        for r in rows: d[(r[0], r[1])].append(r[2:])
        return {(t, tuple(x[1] for x in v), v[0][2], tuple(x[3] for x in v), v[0][4], v[0][5]): n for (t, n), v in d.items()}
    sa, sb = keyset(ka), keyset(kb)
    for k in sorted(set(sa) | set(sb), key=str):
        if k not in sb: out.append(('structural', 'key/constraint only in migrated: %s %s (name %s)' % (k[0], k[1:], sa[k])))
        elif k not in sa: out.append(('structural', 'key/constraint only in reference: %s %s (name %s)' % (k[0], k[1:], sb[k])))
        elif sa[k] != sb[k] and sa[k] != 'PRIMARY': out.append(('name-only', 'constraint name %s %s migrated=%s reference=%s' % (k[0], k[1], sa[k], sb[k])))
    xa, xb = S('checks'); sa = {(r[0], r[2]): r[1] for r in xa}; sb = {(r[0], r[2]): r[1] for r in xb}
    for k in sorted(set(sa) | set(sb)):
        if k not in sb: out.append(('structural', 'CHECK only in migrated: %s %s (name %s)' % (k[0], k[1], sa[k])))
        elif k not in sa: out.append(('structural', 'CHECK only in reference: %s %s (name %s)' % (k[0], k[1], sb[k])))
        elif sa[k] != sb[k]: out.append(('name-only', 'CHECK name %s migrated=%s reference=%s' % (k[0], sa[k], sb[k])))
    for n in ('triggers', 'other'):
        x, y = S(n)
        sx, sy = set(map(tuple, x)), set(map(tuple, y))
        for r in sorted(sx - sy): out.append(('structural', '%s only in migrated: %s' % (n, r)))
        for r in sorted(sy - sx): out.append(('structural', '%s only in reference: %s' % (n, r)))
    return out


# ---------------------------------------------------------------- schema classification (Amendment 1)
try:
    A1 = set(tuple(x) for x in json.load(open(os.path.join(HERE, 'a1-checks.json'))))   # section 8.7, extracted from EXP-DB-R0 H1
except Exception:
    A1 = set()

def classify_schema(db, cls, msg, hop):
    h = HOPNUM[str(hop)]
    # S-1 covers the table `migrate_version` itself, not `shadow_migrate_version` (which the old shell filter hid under S-1)
    if re.search(r"only in migrated: migrate_version(\b|\.)", msg):
        if db in ('keystone', 'glance'): return 'DECLARED', 'S-1c/S-1d'
        if db in ('nova', 'nova_api', 'nova_cell0', 'cinder') and h == 1: return 'DECLARED', 'S-1a'
        return 'UNDECLARED', '-'
    if db in ('nova', 'nova_cell0') and re.search(r"only in migrated: shadow_migrate_version\b", msg): return 'DECLARED', 'S-3.4'
    m = re.match(r"CHECK only in migrated: (\w+) `(\w+)` in \(0,1\)", msg)
    if m: return ('DECLARED', 'A1/S-3.1') if (db, m.group(1), m.group(2)) in A1 else ('UNDECLARED', '-')
    if db in ('nova', 'nova_cell0') and 'shadow_alembic_version' in msg and 'only in reference' in msg: return 'DECLARED', 'A2/S-3.2'
    if db in ('nova', 'nova_cell0') and msg.startswith('column shadow_quota_usages.resource migrated=') and "'YES'" in msg.split('reference=')[0] and "'NO'" in msg.split('reference=')[1]: return 'DECLARED', 'A3/S-3.3'
    if db == 'cinder' and cls == 'name-only' and 'quota_usages' in msg and 'migrated=quota_usages_project_id_key reference=project_id' in msg: return 'DECLARED', 'A4/S-N.1'
    if db == 'neutron' and msg.startswith('column portnumaaffinitypolicies.numa_affinity_policy') and h == 2 and "'socket'" not in msg.split('reference=')[0] and "'socket'" in msg.split('reference=')[1]: return 'DECLARED', 'A7/S-2.1'
    return 'UNDECLARED', '-'

def schema_cmd(a):
    res = schema_raw(a)
    out = []
    for cls, msg in res:
        st, i = classify_schema(a.a, cls, msg, a.hop)
        out.append((st, i, cls, msg))
    return out

TABLES_TO_DROP = set(['cisco_csr_identifier_map', 'nuage_net_partition_router_mapping', 'nuage_net_partitions', 'nuage_provider_net_bindings', 'nuage_subnet_l2dom_mapping', 'cisco_ml2_apic_contracts', 'cisco_ml2_apic_names', 'cisco_ml2_apic_host_links', 'cisco_ml2_n1kv_policy_profiles', 'cisco_ml2_n1kv_port_bindings', 'cisco_ml2_n1kv_network_bindings', 'cisco_ml2_n1kv_vxlan_allocations', 'cisco_ml2_n1kv_vlan_allocations', 'cisco_ml2_n1kv_profile_bindings', 'cisco_ml2_nexusport_bindings', 'cisco_ml2_nexus_nve', 'ml2_nexus_vxlan_mcast_groups', 'ml2_ucsm_port_profiles', 'cisco_port_mappings', 'cisco_router_mappings', 'cisco_hosting_devices', 'cisco_ml2_n1kv_network_profiles', 'ml2_nexus_vxlan_allocations', 'cisco_network_profiles', 'cisco_policy_profiles', 'tz_network_bindings', 'neutron_nsx_network_mappings', 'neutron_nsx_security_group_mappings', 'neutron_nsx_port_mappings', 'neutron_nsx_router_mappings', 'multi_provider_networks', 'networkconnections', 'networkgatewaydevicereferences', 'networkgatewaydevices', 'networkgateways', 'maclearningstates', 'portqueuemappings', 'networkqueuemappings', 'qosqueues', 'lsn_port', 'lsn', 'nsxv_router_bindings', 'nsxv_edge_vnic_bindings', 'nsxv_edge_dhcp_static_bindings', 'nsxv_internal_networks', 'nsxv_internal_edges', 'nsxv_security_group_section_mappings', 'nsxv_rule_mappings', 'nsxv_port_vnic_mappings', 'nsxv_router_ext_attributes', 'nsxv_tz_network_bindings', 'nsxv_port_index_mappings', 'nsxv_firewall_rule_bindings', 'nsxv_spoofguard_policy_network_mappings', 'nsxv_vdr_dhcp_bindings', 'vcns_router_bindings', 'brocadeports', 'brocadenetworks', 'ml2_brocadeports', 'ml2_brocadenetworks'])
BOOKKEEPING = re.compile(r'^(alembic_version.*|migrate_version)$')
RBAC = ['networkrbacs', 'qospolicyrbacs', 'securitygrouprbacs', 'addressscoperbacs', 'subnetpoolrbacs']
N3_UPDATED = {  # N-3: updated_at may change in these tables
    'nova': ['instances', 'pci_devices'], 'cinder': ['volumes', 'snapshots', 'volume_admin_metadata', 'quota_classes', 'quotas', 'quota_usages', 'reservations'],
    'neutron': ['ports', 'ml2_port_bindings', 'network_segment_ranges', 'tags', 'standardattributes']}
CINDER_QUOTA_TABLES = ('quota_classes', 'quotas', 'quota_usages', 'reservations')

def load_counts(d, only=None, exclude=None):
    r = {(x[0], x[1]): int(x[2]) for x in rd(d + '/counts.tsv') if not x[0].endswith('_ref')}
    if only: r = {k: v for k, v in r.items() if k[0] == only}
    if exclude: r = {k: v for k, v in r.items() if k[0] != exclude}
    return r

def load_fp(d, db, t):
    p = '%s/fp/%s.%s.json.gz' % (d, db, t)
    return json.load(gzip.open(p, 'rt')) if os.path.exists(p) else None

def data(a):
    hop = a.hop; h = HOPNUM[str(hop)]
    pred = json.load(open(a.pred)) if a.pred and os.path.exists(a.pred) else {}
    c0, cn = load_counts(a.t0, a.only_db), load_counts(a.now, a.only_db)
    rep = []
    D = lambda i, t: rep.append(('DECLARED', i, t)); U = lambda t: rep.append(('UNDECLARED', '-', t))
    for k in sorted(set(c0) | set(cn)):
        db, t = k
        if k in c0 and k not in cn:
            if db in ('nova', 'nova_cell0', 'nova_api') and t == 'migrate_version' and h >= 2: D('R-1/S-1b', '%s.%s dropped' % k)
            elif db == 'cinder' and t == 'migrate_version' and h >= 1.5: D('AM1-H1b-S/R-1', 'cinder.migrate_version dropped')
            elif db == 'neutron' and t == 'portbindingports' and h >= 1 and c0[k] == 0: D('R-9 (A5: H1 with step 10)', 'neutron.portbindingports dropped (T0 rows 0)')
            elif db == 'neutron' and t in TABLES_TO_DROP and h >= 2 and c0[k] == 0: D('R-10', 'neutron.%s dropped (T0 rows 0)' % t)
            else: U('table dropped: %s.%s (T0 rows %d)' % (db, t, c0[k]))
        elif k in cn and k not in c0:
            n = cn[k]
            if BOOKKEEPING.match(t): D('R-2/N-6', '%s.%s new bookkeeping table (%d rows)' % (db, t, n))
            elif (db, t) == ('neutron', 'securitygroupdefaultrules'): D('R-6', 'rows=%d' % n) if n == 4 and h >= 2 else U('securitygroupdefaultrules rows %d at hop %s (expect 4 from H2)' % (n, hop))
            elif (db, t) == ('neutron', 'porttrusted'):
                exp = pred.get('trusted_ports')
                D('R-8', 'neutron.porttrusted rows=%d (predicted %s)' % (n, exp)) if exp is not None and n == exp and h >= 3 else U('porttrusted rows %d, predicted %s, hop %s' % (n, exp, hop))
            elif n == 0: D('R-4/R-12/R-13/R-14/R-15', 'new empty table %s.%s' % k)
            else: U('new table with rows: %s.%s rows=%d' % (db, t, n))
        else:
            d = cn[k] - c0[k]
            if d == 0: continue
            if BOOKKEEPING.match(t): D('N-6', '%s.%s rows %d -> %d' % (db, t, c0[k], cn[k]))
            elif (db, t) == ('neutron', 'standardattributes') and d == 4 and h >= 2: D('R-7', '+4')
            elif (db, t) == ('cinder', 'quota_classes') and h >= 2 and d == pred.get('r5_missing', -99): D('R-5', '+%d = predicted at T0' % d)
            elif (db, t) in (('placement', 'projects'), ('placement', 'users')) and d == 1 and h >= 1 and pred.get('sentinel_' + t) == 0: D('A6/V-P4', '%s.%s +1 (sentinel absent at T0: predicted)' % (db, t))
            else: U('row count %s.%s: %d -> %d (%+d)' % (db, t, c0[k], cn[k], d))
    changed_cols = collections.defaultdict(lambda: collections.Counter())
    for k in sorted(set(c0) & set(cn)):
        db, t = k
        if BOOKKEEPING.match(t): continue
        f0, fn = load_fp(a.t0, db, t), load_fp(a.now, db, t)
        if not f0 or not fn: continue
        cols0, colsn = f0['cols'], fn['cols']
        ren = {'target_tenant': 'target_project'} if (db == 'neutron' and t in RBAC) else {}
        for c in cols0:
            if ren.get(c, c) not in colsn:
                if (db, t) == ('nova_api', 'build_requests'): D('V-N6', 'dropped columns of build_requests (0 rows at T0)'); break
                if (db, t, c) == ('neutron', 'subnets', 'in_use') and h >= 2: D('V-Q5', 'subnets.in_use dropped'); continue
                if (db, t) == ('neutron', 'portforwardings') and c in ('socket', 'external_port') and h >= 1: D('V-Q4 (H1 with step 10, A5/S10)', 'portforwardings.%s split' % c); continue
                U('column dropped: %s.%s.%s' % (db, t, c))
        r0, rn = f0['rows'], fn['rows']
        miss = [x for x in r0 if x not in rn]; add = [x for x in rn if x not in r0]
        if miss and set(f0['pk']) == set(fn['pk']): U('rows missing vs T0 in %s.%s: %d (e.g. %s)' % (db, t, len(miss), miss[0]))
        for key in r0:
            if key not in rn: continue
            for c in cols0:
                c2 = ren.get(c, c)
                if c2 in colsn and r0[key][c] != rn[key][c2]: changed_cols[(db, t, c)][key] += 1
        if add and len(add) != (cn[k] - c0[k]): U('row set changed in %s.%s: %d added / %d removed' % (db, t, len(add), len(miss)))
    # S-3.4: shadow_migrate_version must have 0 rows at T0 and now (pinned at every hop)
    for dbn in ('nova', 'nova_cell0'):
        k = (dbn, 'shadow_migrate_version')
        if k in c0 or k in cn:
            if c0.get(k, 0) == 0 and cn.get(k, 0) == 0: D('S-3.4', '%s.shadow_migrate_version rows = 0 at T0 and now' % dbn)
            else: U('%s.shadow_migrate_version has rows (T0 %s, now %s): S-3.4 pins 0' % (dbn, c0.get(k), cn.get(k)))
    cq_deleted = 0
    for (db, t, c), keys in sorted(changed_cols.items()):
        n = len(keys); ex = next(iter(keys))
        if c == 'updated_at' and t in N3_UPDATED.get(db, []): D('N-3', '%s.%s.updated_at changed on %d rows' % (db, t, n)); continue
        if (db, t, c) == ('nova', 'pci_devices', 'uuid') and h >= 1: D('V-N1', '%d rows' % n); continue
        if db == 'cinder' and t in CINDER_QUOTA_TABLES and c in ('deleted', 'deleted_at') and h >= 2:
            if c == 'deleted': cq_deleted += n
            continue
        if db == 'cinder' and (t, c) in (('volume_admin_metadata', 'deleted'), ('volume_admin_metadata', 'deleted_at')) and h >= 2:
            if n == pred.get('temporary_rows', -1): D('V-C9/N-4', '%d rows = predicted' % n)
            else: U('volume_admin_metadata.%s changed on %d rows, predicted %s' % (c, n, pred.get('temporary_rows')))
            continue
        if (db, t, c) == ('neutron', 'ml2_port_bindings', 'profile') and h >= 3:
            if n == pred.get('trusted_ports', -1): D('V-Q7', '%d rows = predicted' % n)
            else: U('ml2_port_bindings.profile changed on %d rows, predicted %s' % (n, pred.get('trusted_ports')))
            continue
        if (db, t, c) == ('neutron', 'network_segment_ranges', 'physical_network') and h >= 4:
            if n == pred.get('segrange_null', -1): D('V-Q9', '%d rows NULL -> empty = predicted' % n)
            else: U('network_segment_ranges.physical_network changed on %d rows, predicted %s' % (n, pred.get('segrange_null')))
            continue
        if (db, t, c) == ('neutron', 'ports', 'device_owner') and h >= 1 and n == pred.get('ovnmeta_dhcp', 0): D('V-Q1', '%d rows' % n); continue
        U('value changed: %s.%s.%s on %d rows (e.g. key %s)' % (db, t, c, n, ex))
    if cq_deleted or h >= 2:
        exp = pred.get('v_c6_rows', 0)
        if cq_deleted == exp: D('V-C6/N-4', 'consistencygroups rows soft-deleted: %d = predicted' % cq_deleted)
        else: U('cinder quota rows soft-deleted %d, predicted (V-C6) %s' % (cq_deleted, exp))
    return rep

def same(a):
    rep = []
    c1, c2 = load_counts(a.a, a.only_db, a.exclude_db), load_counts(a.b, a.only_db, a.exclude_db)
    for k in sorted(set(c1) | set(c2)):
        if c1.get(k) != c2.get(k): rep.append(('UNDECLARED', '-', 'row count %s.%s: %s -> %s' % (k[0], k[1], c1.get(k), c2.get(k))))
    for k in sorted(set(c1) & set(c2)):
        f1, f2 = load_fp(a.a, *k), load_fp(a.b, *k)
        if f1 is None or f2 is None: continue
        if f1['rows'] != f2['rows']:
            n = sum(1 for x in f1['rows'] if f1['rows'].get(x) != f2['rows'].get(x))
            rep.append(('UNDECLARED', '-', 'rows changed in %s.%s: %d' % (k[0], k[1], n)))
    for db in sorted({k[0] for k in c1}):
        for f in ('tables', 'columns', 'indexes', 'keys', 'checks', 'triggers', 'other'):
            if rd('%s/schema/%s/%s.tsv' % (a.a, db, f)) != rd('%s/schema/%s/%s.tsv' % (a.b, db, f)):
                rep.append(('UNDECLARED', '-', 'schema %s/%s differs' % (db, f)))
    return rep

if __name__ == '__main__':
    ap = argparse.ArgumentParser(); ap.add_argument('mode')
    ap.add_argument('--snap'); ap.add_argument('--a'); ap.add_argument('--b'); ap.add_argument('--t0'); ap.add_argument('--now'); ap.add_argument('--hop')
    ap.add_argument('--pred'); ap.add_argument('--only-db'); ap.add_argument('--exclude-db')
    a = ap.parse_args()
    if a.mode == 'schema':
        res = schema_cmd(a)
        for r in res: print('%s\t%s\t%s\t%s' % r)
        u = sum(1 for r in res if r[0] == 'UNDECLARED'); print('SUMMARY declared=%d undeclared=%d' % (len(res) - u, u))
        sys.exit(1 if u else 0)
    rep = data(a) if a.mode == 'data' else same(a)
    for r in rep: print('%s\t%s\t%s' % r)
    u = sum(1 for r in rep if r[0] == 'UNDECLARED'); print('SUMMARY declared=%d undeclared=%d' % (len(rep) - u, u))
    sys.exit(1 if u else 0)
