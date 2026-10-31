#!/usr/bin/env python3
"""N-3 reconciliation (Red Team Stage 5b condition): per hop, the number of rows whose `updated_at` changed between two consecutive
snapshots, per N-3 table, must equal what the migrations of that hop are known to write: the ODM 'migrated' counts of the hop
(summaries `logs/*-odm*-N.summary.txt`) or the T0 predictions for schema migrations. Any mismatch is an undeclared write: exit 1.
usage: reconcile_n3.py --prev SNAPDIR --now SNAPDIR --hopdir EVDIR --hop 1|1b|2|3|4|5 --pred predictions.json"""
import argparse, glob, gzip, json, os, re, sys

ap = argparse.ArgumentParser()
for k in ('prev', 'now', 'hopdir', 'hop', 'pred'): ap.add_argument('--' + k, required=True)
a = ap.parse_args()
pred = json.load(open(a.pred))
N3 = {'nova': ['instances', 'pci_devices'],
      'cinder': ['volumes', 'snapshots', 'volume_admin_metadata', 'quota_classes', 'quotas', 'quota_usages', 'reservations'],
      'neutron': ['ports', 'ml2_port_bindings', 'network_segment_ranges', 'tags', 'standardattributes']}

def migrated(name):
    tot = 0
    for f in glob.glob(os.path.join(a.hopdir, 'logs', '*.summary.txt')):
        for l in open(f):
            m = re.match(r'\s*(\d+) rows matched query %s, (\d+) migrated' % re.escape(name), l)
            if m: tot += int(m.group(2))
    return tot

h = a.hop
exp = {}   # (db, table) -> expected number of rows with a changed updated_at in this hop
for db, tabs in N3.items():
    for t in tabs: exp[(db, t)] = 0
exp[('cinder', 'volumes')] = migrated('volume_use_quota_online_data_migration')
exp[('cinder', 'snapshots')] = migrated('snapshot_use_quota_online_data_migration')
exp[('nova', 'instances')] = migrated('populate_instance_compute_id')
exp[('nova', 'pci_devices')] = migrated('populate_dev_uuids')
if h == '2':
    exp[('cinder', 'volume_admin_metadata')] = pred.get('temporary_rows', 0)
    cq = pred.get('v_c6_rows', 0)     # spread over the four quota tables: compared as a sum
if h == '3': exp[('neutron', 'ml2_port_bindings')] = pred.get('trusted_ports', 0)
if h == '4': exp[('neutron', 'network_segment_ranges')] = pred.get('segrange_null', 0)

def load(d, db, t):
    p = '%s/fp/%s.%s.json.gz' % (d, db, t)
    return json.load(gzip.open(p, 'rt')) if os.path.exists(p) else None

bad = 0; qsum = 0
for (db, t), e in sorted(exp.items()):
    p, n = load(a.prev, db, t), load(a.now, db, t)
    if not p or not n or 'updated_at' not in p['cols'] or 'updated_at' not in n['cols']:
        print('SKIP %s.%s (no updated_at / table absent in one snapshot)' % (db, t)); continue
    got = sum(1 for k, r in p['rows'].items() if k in n['rows'] and r['updated_at'] != n['rows'][k]['updated_at'])
    if h == '2' and db == 'cinder' and t in ('quota_classes', 'quotas', 'quota_usages', 'reservations'):
        qsum += got; print('INFO %s.%s updated_at rows changed: %d (quota tables are compared as a sum)' % (db, t, got)); continue
    ok = got == e
    bad += 0 if ok else 1
    print('%s %s.%s updated_at rows changed: %d, expected from this hop\'s ODM/prediction: %d' % ('OK  ' if ok else 'MISMATCH', db, t, got, e))
if h == '2':
    ok = qsum == pred.get('v_c6_rows', 0); bad += 0 if ok else 1
    print('%s cinder quota tables (sum) updated_at rows changed: %d, predicted soft-deleted consistencygroups rows (V-C6): %d' % ('OK  ' if ok else 'MISMATCH', qsum, pred.get('v_c6_rows', 0)))
print('N3-RECONCILIATION %s' % ('PASS' if not bad else 'FAIL: %d mismatch(es) = undeclared write' % bad))
sys.exit(1 if bad else 0)
