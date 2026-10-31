#!/usr/bin/env python
"""F2: read back every pre-existing resource through the 2026.1 APIs and compare it with the T0 inventory (EXP-SVC-01).
Runs inside ufj-svc-client (OS_* of admin; USER_ALICE / USER_BOB in the environment). Uses tools/inventory.py capture().

  f2_readback.py --baseline INV.json --expected expected-changes.json --out DIR [--coverage coverage-actions.tsv]

Comparison is by SUBSET: every field of every baseline object must be present with the same value (volatile fields as in
inventory.py), except fields listed in expected-changes.json. Added fields and new objects are listed, not hidden.
Exit 0 only if there is no undeclared difference, no HTTP 5xx and every extra check passes."""
import argparse
import json
import os
import re
import sys
import hashlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inventory as inv  # noqa: E402

KEYFIELDS = ('id', 'uuid', 'name')


def ident(x):
    if isinstance(x, dict):
        for k in KEYFIELDS:
            if k in x and isinstance(x[k], str):
                return x[k]
    return None


def subset(b, n, path, out, added):
    """record differences of baseline value b against current value n"""
    if isinstance(b, dict) and isinstance(n, dict):
        for k in b:
            if k not in n:
                out.append((path + [k], 'missing', b[k], None))
            else:
                subset(b[k], n[k], path + [k], out, added)
        for k in n:
            if k not in b:
                added.append(path + [k])
    elif isinstance(b, list) and isinstance(n, list):
        if all(isinstance(x, dict) and ident(x) for x in b + n) and b:
            bm, nm = {ident(x): x for x in b}, {ident(x): x for x in n}
            for k in bm:
                if k not in nm:
                    out.append((path + ['[%s]' % k], 'missing', bm[k], None))
                else:
                    subset(bm[k], nm[k], path + ['[%s]' % k], out, added)
            for k in nm:
                if k not in bm:
                    out.append((path + ['[%s]' % k], 'new-element', None, nm[k]))
        elif b and all(isinstance(x, dict) for x in b + n):
            # elements without id/uuid/name (e.g. port forwardings in Ussuri): each baseline element must be a subset of a distinct current element
            used = set()
            for i, be in enumerate(b):
                for j, ne in enumerate(n):
                    if j in used:
                        continue
                    o2, a2 = [], []
                    subset(be, ne, path + ['[#%d]' % i], o2, a2)
                    if not o2:
                        used.add(j)
                        added.extend(a2)
                        break
                else:
                    out.append((path + ['[#%d]' % i], 'missing', be, None))
        elif b != n:
            out.append((path, 'changed', b, n))
    elif b != n:
        out.append((path, 'changed', b, n))


def declared(coll, path, expected):
    """expected: {collection: {dotted-prefix: reason}}; '*' applies to all collections; element ids are ignored in the match"""
    p = '.'.join(x for x in path if not x.startswith('['))
    for c in (coll, '*'):
        for pref, why in expected.get(c, {}).items():
            if p == pref or p.startswith(pref + '.'):
                return why
    return None


def short(v):
    s = json.dumps(v, sort_keys=True, default=str)
    return s if len(s) < 160 else s[:157] + '...'


def f2(base, now, expected):
    lines, undecl, decl, new_objs, added_fields = [], 0, 0, [], {}
    for coll in sorted(base):
        if coll == '_meta':
            continue
        if coll not in now:
            lines.append('UNDECLARED %s: collection missing in the current capture' % coll)
            undecl += 1
            continue
        b, n = inv.keyed(coll, base[coll]), inv.keyed(coll, now[coll])
        for k in sorted(b):
            if k not in n:
                if declared(coll, ['[missing-object]'], expected):
                    decl += 1
                    lines.append('declared   %s %s: object not returned (%s)' % (coll, k, declared(coll, ['[missing-object]'], expected)))
                else:
                    undecl += 1
                    lines.append('UNDECLARED %s %s: object missing now' % (coll, k))
                continue
            out, added = [], []
            subset(b[k], n[k], [], out, added)
            for path, kind, bv, nv in out:
                why = declared(coll, path, expected)
                tag = 'declared  ' if why else 'UNDECLARED'
                if why:
                    decl += 1
                else:
                    undecl += 1
                lines.append('%s %s %s .%s %s: %s -> %s%s' % (tag, coll, k, '.'.join(path), kind, short(bv), short(nv), (' [%s]' % why) if why else ''))
            for path in added:
                added_fields.setdefault(coll, {}).setdefault('.'.join(x for x in path if not x.startswith('[')), 0)
                added_fields[coll]['.'.join(x for x in path if not x.startswith('['))] += 1
        for k in sorted(set(n) - set(b)):
            new_objs.append('%s %s' % (coll, k))
    return lines, undecl, decl, new_objs, added_fields


def extras(cov_file):
    """objects that inventory.py does not capture: trusts, application credentials, credentials, federation, service providers"""
    res = []
    s = inv.sess()
    ks = inv.ad(s, 'identity')
    five = []

    def chk(name, ok, detail):
        res.append((name, ok, detail))

    ids = {'trust': [], 'appcred': [], 'idp': [], 'mapping': [], 'protocol': [], 'sp': []}
    for line in open(cov_file):
        f = line.rstrip('\n').split('\t')
        if len(f) < 3 or f[1] != 'OK':
            continue
        m = re.search(r'\b([0-9a-f]{32})\b', f[2])
        if f[0] == 'trust' and m:
            ids['trust'].append(m.group(1))
        elif f[0].startswith('appcred') and m:
            ids['appcred'].append(m.group(1))
        elif f[0] == 'appcred_access_rules' and m:
            ids['appcred'].append(m.group(1))
    r = ks.get('/OS-TRUST/trusts')
    tr = {t['id'] for t in r.json().get('trusts', [])} if r.status_code == 200 else set()
    chk('trusts listed by admin (HTTP %s)' % r.status_code, r.status_code == 200 and set(ids['trust']) <= tr, '%d of T0 trusts %s present of %d listed' % (len(set(ids['trust']) & tr), len(ids['trust']), len(tr)))
    for t in ids['trust']:
        r = ks.get('/OS-TRUST/trusts/%s' % t)
        chk('trust %s show' % t[:8], r.status_code == 200, 'HTTP %s' % r.status_code)
    # application credentials: owners authenticate with their stored passwords (alice, bob)
    found = set()
    for u, pw, pr in (('alice', 'USER_ALICE', 'ufj-proj-a'), ('bob', 'USER_BOB', 'ufj-proj-b')):
        try:
            su = inv.sess(u, os.environ[pw], pr)
            kus = inv.ad(su, 'identity')
            uid = su.get_user_id()
            r = kus.get('/users/%s/application_credentials' % uid)
            chk('application credentials of %s (HTTP %s)' % (u, r.status_code), r.status_code == 200, '%d listed' % len(r.json().get('application_credentials', [])))
            found |= {a['id'] for a in r.json().get('application_credentials', [])}
        except Exception as e:  # noqa
            chk('application credentials of %s' % u, False, str(e)[:150])
    chk('T0 application credentials present', set(ids['appcred']) <= found, '%d of %d' % (len(set(ids['appcred']) & found), len(ids['appcred'])))
    # credentials: the blob is stored encrypted with the credential keys; GET decrypts it
    r = ks.get('/credentials')
    cr = r.json().get('credentials', []) if r.status_code == 200 else []
    kinds = {}
    bad = []
    for c in cr:
        kinds[c['type']] = kinds.get(c['type'], 0) + 1
        try:
            blob = c['blob']
            if c['type'] == 'ec2':
                bj = json.loads(blob)
                assert bj.get('access') and bj.get('secret')
            else:
                assert blob
        except Exception:  # noqa
            bad.append(c['id'])
    chk('credentials list (HTTP %s), blobs decrypt (ec2 JSON with access+secret; others non-empty)' % r.status_code, r.status_code == 200 and cr and not bad,
        'by type %s; undecryptable %s; blob sha256 of ec2/totp not recorded' % (kinds, bad))
    # federation objects
    for path, key, want in (('/OS-FEDERATION/identity_providers', 'identity_providers', 'ufj-idp'), ('/OS-FEDERATION/mappings', 'mappings', 'ufj-mapping'),
                            ('/OS-FEDERATION/service_providers', 'service_providers', 'ufj-sp')):
        r = ks.get(path)
        have = [x['id'] for x in r.json().get(key, [])] if r.status_code == 200 else []
        chk('federation %s (HTTP %s)' % (key, r.status_code), r.status_code == 200 and want in have, 'have %s' % have)
    r = ks.get('/OS-FEDERATION/identity_providers/ufj-idp/protocols')
    chk('federation protocol saml2 (HTTP %s)' % r.status_code, r.status_code == 200 and 'saml2' in [p['id'] for p in r.json().get('protocols', [])], 'ok')
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--baseline', required=True)
    ap.add_argument('--expected', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--coverage', required=True)
    a = ap.parse_args()
    base = json.load(open(a.baseline))
    expected = json.load(open(a.expected))
    now = json.loads(json.dumps(inv.capture(), default=str))
    os.makedirs(a.out, exist_ok=True)
    json.dump(now, open(os.path.join(a.out, 'inventory-2026.1.json'), 'w'), indent=1, sort_keys=True)
    lines, undecl, decl, new_objs, added = f2(base, now, expected)
    func = inv.functional(base)
    ext = extras(a.coverage)
    rep = ['F2 read-back through the 2026.1 APIs against the T0 inventory (%s)' % base.get('_meta', {}).get('captured_at'),
           'baseline counts: %s' % json.dumps(base['_meta']['counts'], sort_keys=True),
           'current  counts: %s' % json.dumps(now['_meta']['counts'], sort_keys=True),
           'declared differences: %d   UNDECLARED differences: %d' % (decl, undecl), '--- differences']
    rep += lines or ['(none)']
    rep += ['--- new objects (present now, not in T0): %d' % len(new_objs)] + ['  ' + x for x in new_objs]
    rep += ['--- fields added by the 2026.1 APIs (field: number of objects)']
    for c in sorted(added):
        rep.append('  %s: %s' % (c, ', '.join('%s(%d)' % (f, n) for f, n in sorted(added[c].items()))))
    rep += ['--- functional checks (inventory.py)'] + ['  [%s] %s: %s' % ('PASS' if ok else 'FAIL', n, d) for n, ok, d in func]
    rep += ['--- extra read-backs'] + ['  [%s] %s: %s' % ('PASS' if ok else 'FAIL', n, d) for n, ok, d in ext]
    ok = undecl == 0 and all(x[1] for x in func) and all(x[1] for x in ext)
    rep.append('RESULT: %s' % ('PASS' if ok else 'FAIL'))
    open(os.path.join(a.out, 'f2-report.txt'), 'w').write('\n'.join(rep) + '\n')
    print('\n'.join(rep[:4] + [x for x in rep if x.startswith('RESULT')]))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
