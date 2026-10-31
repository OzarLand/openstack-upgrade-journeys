#!/usr/bin/env python3
"""Comparisons of the fast-forward experiments.
  compare.py schema --snap DIR --a DB --b DB_REF            comparison A: migrated vs reference (same server)
  compare.py data --t0 DIR --now DIR --hop N [--dbs ...]    comparison B: counts and per-row fingerprints vs T0
  compare.py idem --a DIR --b DIR                           H4 vs H4r: nothing may differ (no exclusions)
Every difference is classified DECLARED (with the id from declared-differences.md) or UNDECLARED. Exit 1 if any UNDECLARED."""
import argparse, glob, gzip, json, os, sys, re, collections

def rd(p):
    return [l.rstrip('\n').split('\t') for l in open(p)] if os.path.exists(p) else []

# ---------------------------------------------------------------- schema (A)
def schema(a):
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

# ---------------------------------------------------------------- data (B)
# TABLES_TO_DROP of neutron 2024.1/expand/054e34dbe6b4_drop_unused_tables.py (R-10), read from source
TABLES_TO_DROP = set(['cisco_csr_identifier_map', 'nuage_net_partition_router_mapping', 'nuage_net_partitions', 'nuage_provider_net_bindings', 'nuage_subnet_l2dom_mapping', 'cisco_ml2_apic_contracts', 'cisco_ml2_apic_names', 'cisco_ml2_apic_host_links', 'cisco_ml2_n1kv_policy_profiles', 'cisco_ml2_n1kv_port_bindings', 'cisco_ml2_n1kv_network_bindings', 'cisco_ml2_n1kv_vxlan_allocations', 'cisco_ml2_n1kv_vlan_allocations', 'cisco_ml2_n1kv_profile_bindings', 'cisco_ml2_nexusport_bindings', 'cisco_ml2_nexus_nve', 'ml2_nexus_vxlan_mcast_groups', 'ml2_ucsm_port_profiles', 'cisco_port_mappings', 'cisco_router_mappings', 'cisco_hosting_devices', 'cisco_ml2_n1kv_network_profiles', 'ml2_nexus_vxlan_allocations', 'cisco_network_profiles', 'cisco_policy_profiles', 'tz_network_bindings', 'neutron_nsx_network_mappings', 'neutron_nsx_security_group_mappings', 'neutron_nsx_port_mappings', 'neutron_nsx_router_mappings', 'multi_provider_networks', 'networkconnections', 'networkgatewaydevicereferences', 'networkgatewaydevices', 'networkgateways', 'maclearningstates', 'portqueuemappings', 'networkqueuemappings', 'qosqueues', 'lsn_port', 'lsn', 'nsxv_router_bindings', 'nsxv_edge_vnic_bindings', 'nsxv_edge_dhcp_static_bindings', 'nsxv_internal_networks', 'nsxv_internal_edges', 'nsxv_security_group_section_mappings', 'nsxv_rule_mappings', 'nsxv_port_vnic_mappings', 'nsxv_router_ext_attributes', 'nsxv_tz_network_bindings', 'nsxv_port_index_mappings', 'nsxv_firewall_rule_bindings', 'nsxv_spoofguard_policy_network_mappings', 'nsxv_vdr_dhcp_bindings', 'vcns_router_bindings', 'brocadeports', 'brocadenetworks', 'ml2_brocadeports', 'ml2_brocadenetworks'])
BOOKKEEPING = re.compile(r'^(alembic_version.*|migrate_version)$')
RBAC = ['networkrbacs', 'qospolicyrbacs', 'securitygrouprbacs', 'addressscoperbacs', 'subnetpoolrbacs']
N3_UPDATED = {  # N-3: updated_at may change in these tables
    'nova': ['instances', 'pci_devices'], 'cinder': ['volumes', 'snapshots', 'volume_admin_metadata', 'quota_classes', 'quotas', 'quota_usages', 'reservations'],
    'neutron': ['ports', 'ml2_port_bindings', 'network_segment_ranges', 'tags', 'standardattributes']}

def load_counts(d): return {(r[0], r[1]): int(r[2]) for r in rd(d + '/counts.tsv') if not r[0].endswith('_ref')}
def load_fp(d, db, t):
    p = '%s/fp/%s.%s.json.gz' % (d, db, t)
    return json.load(gzip.open(p, 'rt')) if os.path.exists(p) else None

PROV = False
def data(a):
    global PROV
    PROV = bool(a.provisional)
    hop = int(a.hop)
    c0, cn = load_counts(a.t0), load_counts(a.now)
    rep = []   # (class, id, text)
    D = lambda i, t: rep.append(('DECLARED', i, t)); U = lambda t: rep.append(('UNDECLARED', '-', t))
    for k in sorted(set(c0) | set(cn)):
        db, t = k
        if k in c0 and k not in cn:
            if BOOKKEEPING.match(t) and hop >= 2 and db in ('nova', 'nova_cell0', 'nova_api', 'cinder') and t == 'migrate_version': D('R-1/S-1b', '%s.%s dropped' % k)
            elif db == 'neutron' and hop >= 2 and (t == 'portbindingports' or t in TABLES_TO_DROP) and c0[k] == 0: D('R-9' if t == 'portbindingports' else 'R-10', 'neutron.%s dropped (T0 rows %d)' % (t, c0[k]))
            elif PROV and db == 'neutron' and hop == 1 and (t == 'portbindingports' or t in TABLES_TO_DROP) and c0[k] == 0: rep.append(('PROPOSED', 'R0-A5', 'neutron.%s dropped at H1 (step 10 runs neutron at 2023.1)' % t))
            else: U('table dropped: %s.%s (T0 rows %d)' % (db, t, c0[k]))
        elif k in cn and k not in c0:
            n = cn[k]
            if BOOKKEEPING.match(t): D('R-2/N-6', '%s.%s new bookkeeping table (%d rows)' % (db, t, n))
            elif (db, t) == ('neutron', 'securitygroupdefaultrules'): D('R-6', 'rows=%d (expect 4)' % n) if n == 4 else U('securitygroupdefaultrules rows %d != 4' % n)
            elif (db, t) == ('neutron', 'porttrusted'): D('R-8', 'neutron.porttrusted rows=%d' % n)
            elif n == 0: D('R-4/R-12/R-13/R-14/R-15', 'new empty table %s.%s' % k)
            else: U('new table with rows: %s.%s rows=%d' % (db, t, n))
        else:
            d = cn[k] - c0[k]
            if d == 0: continue
            if BOOKKEEPING.match(t): D('N-6', '%s.%s rows %d -> %d' % (db, t, c0[k], cn[k]))
            elif (db, t) == ('neutron', 'standardattributes') and d == 4 and hop >= 2: D('R-7', '+4')
            elif (db, t) == ('cinder', 'quota_classes') and 0 <= d <= 2 and hop >= 2: D('R-5', '+%d (written to the run record as predicted at T0)' % d)
            elif (db, t) == ('neutron', 'network_segment_ranges') and d < 0: U('R-11 deletion of %d segment ranges (d must be 0 in main runs)' % -d)
            elif PROV and (db, t) in (('placement', 'projects'), ('placement', 'users')) and d == 1: rep.append(('PROPOSED', 'R0-A6', '%s.%s +1 (incomplete-consumer sentinel row)' % (db, t)))
            else: U('row count %s.%s: %d -> %d (%+d)' % (db, t, c0[k], cn[k], d))
    # fingerprints
    changed_cols = collections.defaultdict(lambda: collections.Counter())
    examples = {}
    for k in sorted(set(c0) & set(cn)):
        db, t = k
        if BOOKKEEPING.match(t): continue
        f0, fn = load_fp(a.t0, db, t), load_fp(a.now, db, t)
        if not f0 or not fn: continue
        cols0, colsn = f0['cols'], fn['cols']
        ren = {'target_tenant': 'target_project'} if (db == 'neutron' and t in RBAC) else {}
        for c in cols0:
            cn_ = ren.get(c, c)
            if cn_ not in colsn:
                if (db, t) == ('nova_api', 'build_requests'): D('V-N6', 'dropped columns of build_requests (0 rows at T0)'); break
                if (db, t) == ('neutron', 'subnets') and c == 'in_use': D('V-Q5', 'subnets.in_use dropped'); continue
                if (db, t) == ('neutron', 'portforwardings') and c in ('socket', 'external_port'): D('V-Q4', 'portforwardings.%s split' % c); continue
                U('column dropped: %s.%s.%s' % (db, t, c)); continue
        r0, rn = f0['rows'], fn['rows']
        miss = [x for x in r0 if x not in rn]; add = [x for x in rn if x not in r0]
        pkren = bool(set(f0['pk']) != set(fn['pk']))
        if miss and not pkren:
            ok = (db, t) == ('cinder', 'quota_classes')
            if not ok: U('rows missing vs T0 in %s.%s: %d (e.g. %s)' % (db, t, len(miss), miss[0]))
        for key in r0:
            if key not in rn: continue
            for c in cols0:
                c2 = ren.get(c, c)
                if c2 not in colsn: continue
                if r0[key][c] != rn[key][c2]:
                    changed_cols[(db, t, c)][key] += 1
        # added rows in existing tables (count already reported); note keys
        if add and (db, t) not in (('cinder', 'quota_classes'), ('neutron', 'standardattributes')) and len(add) != (cn[k] - c0[k]):
            U('row set changed in %s.%s: %d added / %d removed' % (db, t, len(add), len(miss)))
    for (db, t, c), keys in sorted(changed_cols.items()):
        n = len(keys); ex = next(iter(keys))
        if c == 'updated_at' and t in N3_UPDATED.get(db, []): D('N-3', '%s.%s.updated_at changed on %d rows' % (db, t, n)); continue
        if (db, t, c) == ('nova', 'pci_devices', 'uuid') and hop >= 1: D('V-N1', '%d rows' % n); continue
        if db == 'cinder' and t in ('quota_classes', 'quotas', 'quota_usages', 'reservations') and c in ('deleted', 'deleted_at') and hop >= 2: D('V-C6/N-4', '%s.%s.%s %d rows' % (db, t, c, n)); continue
        if (db, t, c) in (('cinder', 'volume_admin_metadata', 'deleted'), ('cinder', 'volume_admin_metadata', 'deleted_at')) and hop >= 2: D('V-C9/N-4', '%d rows' % n); continue
        if (db, t, c) == ('neutron', 'ml2_port_bindings', 'profile') and hop >= 3: D('V-Q7', '%d rows (trusted key moved)' % n); continue
        if (db, t, c) == ('neutron', 'network_segment_ranges', 'physical_network') and hop >= 4: D('V-Q9', '%d rows NULL -> empty' % n); continue
        if (db, t, c) == ('neutron', 'ports', 'device_owner') and hop >= 2: D('V-Q1', '%d rows' % n); continue
        U('value changed: %s.%s.%s on %d rows (e.g. key %s)' % (db, t, c, n, ex))
    return rep

def idem(a):
    rep = []
    c1, c2 = load_counts(a.a), load_counts(a.b)
    for k in sorted(set(c1) | set(c2)):
        if c1.get(k) != c2.get(k): rep.append(('UNDECLARED', '-', 'row count %s.%s: %s -> %s' % (k[0], k[1], c1.get(k), c2.get(k))))
    for k in sorted(set(c1) & set(c2)):
        f1, f2 = load_fp(a.a, *k), load_fp(a.b, *k)
        if f1 is None or f2 is None: continue
        if f1['rows'] != f2['rows']:
            n = sum(1 for x in f1['rows'] if f1['rows'].get(x) != f2['rows'].get(x))
            rep.append(('UNDECLARED', '-', 'rows changed between H4 and H4r in %s.%s: %d' % (k[0], k[1], n)))
    for db in sorted({k[0] for k in c1}):
        for f in ('tables', 'columns', 'indexes', 'keys', 'checks', 'triggers', 'other'):
            if rd('%s/schema/%s/%s.tsv' % (a.a, db, f)) != rd('%s/schema/%s/%s.tsv' % (a.b, db, f)):
                rep.append(('UNDECLARED', '-', 'schema %s/%s differs between H4 and H4r' % (db, f)))
    return rep

if __name__ == '__main__':
    ap = argparse.ArgumentParser(); ap.add_argument('mode')
    ap.add_argument('--snap'); ap.add_argument('--a'); ap.add_argument('--b'); ap.add_argument('--t0'); ap.add_argument('--now'); ap.add_argument('--hop'); ap.add_argument('--provisional', action='store_true')
    a = ap.parse_args()
    if a.mode == 'schema':
        res = schema(a); print('# schema %s vs %s' % (a.a, a.b)); [print('%s\t%s' % x) for x in res]
        print('SUMMARY structural=%d name-only=%d' % (sum(1 for x in res if x[0] == 'structural'), sum(1 for x in res if x[0] == 'name-only')))
        sys.exit(0)
    rep = data(a) if a.mode == 'data' else idem(a)
    for r in rep: print('%s\t%s\t%s' % r)
    u = sum(1 for r in rep if r[0] == 'UNDECLARED'); pr = sum(1 for r in rep if r[0] == 'PROPOSED'); print('SUMMARY declared=%d proposed=%d undeclared=%d' % (len(rep) - u - pr, pr, u))
    sys.exit(1 if u else 0)
