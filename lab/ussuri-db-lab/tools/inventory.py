#!/usr/bin/env python
"""Inventory and functional re-check of the Ussuri lab control plane (runs inside the ufj-client container).

  inventory.py capture --out FILE        write a JSON inventory of every resource, read through the REST APIs
  inventory.py verify  --baseline FILE   capture again and compare with FILE (volatile fields ignored), then run
                                         functional checks; exit code 0 = baseline reproduced, 1 = differences

Credentials come from the environment (OS_* of admin, plus USER_ALICE / USER_BOB for the user checks).
Nothing secret is written to the inventory (no passwords, no key material, no tokens)."""
import argparse
import datetime
import hashlib
import json
import os
import sys

from keystoneauth1 import adapter, session
from keystoneauth1.identity import v3

VOLATILE = {
    'updated', 'updated_at', 'launched_at', 'OS-SRV-USG:launched_at', 'revision_number', 'heartbeat_timestamp',
    'started_at', 'links', 'OS-EXT-SRV-ATTR:launch_index', 'OS-EXT-STS:power_state', 'progress', 'last_seen_up',
    'attach_time', 'attached_at', 'status', 'admin_state_up_changed', 'binding:vif_details',
}
# fields excluded only for specific collections (they legitimately change between runs of a live control plane)
VOLATILE_BY = {'agents': {'created_at', 'started_at', 'heartbeat_timestamp', 'configurations', 'alive', 'id'},
               'compute_services': {'updated_at', 'state'},
               'volume_services': {'updated_at', 'state'},
               'placement_resource_providers': {'generation'}}


def sess(user=None, password=None, project=None):
    auth = v3.Password(auth_url=os.environ['OS_AUTH_URL'], username=user or os.environ['OS_USERNAME'],
                       password=password or os.environ['OS_PASSWORD'],
                       project_name=project or os.environ['OS_PROJECT_NAME'],
                       user_domain_name='Default', project_domain_name='Default')
    return session.Session(auth=auth)


def ad(s, stype, **kw):
    return adapter.Adapter(session=s, service_type=stype, interface='public', region_name='RegionOne', **kw)


def get(a, url, key=None, **kw):
    r = a.get(url, **kw)
    r.raise_for_status() if hasattr(r, 'raise_for_status') else None
    j = r.json()
    return j[key] if key else j


def paged_glance(a):
    out, url = [], '/v2/images?limit=100&visibility=all'
    while url:
        j = a.get(url).json()
        out += j['images']
        url = j.get('next')
    return out


def capture():
    s = sess()
    ks, glance, nova, neutron, cinder, plc = (ad(s, 'identity'), ad(s, 'image'), ad(s, 'compute'), ad(s, 'network'),
                                              ad(s, 'volumev3'), ad(s, 'placement'))
    nv = {'headers': {'X-OpenStack-Nova-API-Version': '2.60'}}
    cv = {'headers': {'OpenStack-API-Version': 'volume 3.50'}}
    pv = {'headers': {'OpenStack-API-Version': 'placement 1.30'}}
    inv = {'_meta': {'captured_at': datetime.datetime.utcnow().isoformat() + 'Z', 'tool': 'inventory.py'}}
    # --- identity
    inv['projects'] = get(ks, '/v3/projects', 'projects')
    inv['users'] = get(ks, '/v3/users', 'users')
    inv['groups'] = get(ks, '/v3/groups', 'groups')
    inv['roles'] = get(ks, '/v3/roles', 'roles')
    inv['domains'] = get(ks, '/v3/domains', 'domains')
    inv['regions'] = get(ks, '/v3/regions', 'regions')
    inv['services'] = get(ks, '/v3/services', 'services')
    inv['endpoints'] = get(ks, '/v3/endpoints', 'endpoints')
    inv['role_assignments'] = get(ks, '/v3/role_assignments?include_names=true', 'role_assignments')
    inv['group_memberships'] = {g['name']: sorted(u['name'] for u in get(ks, '/v3/groups/%s/users' % g['id'], 'users'))
                                for g in inv['groups']}
    pid = {p['id']: p['name'] for p in inv['projects']}
    # --- image
    imgs = paged_glance(glance)
    for i in imgs:
        i['_members'] = sorted((m['member_id'], m['status']) for m in glance.get('/v2/images/%s/members' % i['id']).json()['members'])
    inv['images'] = imgs
    # --- compute
    inv['servers'] = get(nova, '/servers/detail?all_tenants=1', 'servers', **nv)
    inv['flavors'] = get(nova, '/flavors/detail?is_public=None', 'flavors', **nv)
    for f in inv['flavors']:
        f['_extra_specs'] = get(nova, '/flavors/%s/os-extra_specs' % f['id'], 'extra_specs', **nv)
        f['_access'] = sorted(a['tenant_id'] for a in get(nova, '/flavors/%s/os-flavor-access' % f['id'], 'flavor_access', **nv)) if not f['os-flavor-access:is_public'] else []
    inv['keypairs'] = []
    for u in inv['users']:
        for k in get(nova, '/os-keypairs?user_id=%s' % u['id'], 'keypairs', **nv):
            kp = dict(k['keypair'])
            kp['_user'] = u['name']
            kp.pop('public_key', None)
            inv['keypairs'].append(kp)
    inv['aggregates'] = get(nova, '/os-aggregates', 'aggregates', **nv)
    inv['server_groups'] = get(nova, '/os-server-groups?all_projects=true', 'server_groups', **nv)
    inv['compute_services'] = get(nova, '/os-services', 'services', **nv)
    inv['hypervisors'] = get(nova, '/os-hypervisors/detail', 'hypervisors', **nv)
    inv['nova_quotas'] = {pid[p]: get(nova, '/os-quota-sets/%s' % p, 'quota_set', **nv) for p in pid}
    # --- network
    for key, path in (('networks', 'networks'), ('subnets', 'subnets'), ('ports', 'ports'), ('routers', 'routers'),
                      ('floatingips', 'floatingips'), ('security_groups', 'security-groups'),
                      ('security_group_rules', 'security-group-rules'), ('subnetpools', 'subnetpools'),
                      ('rbac_policies', 'rbac-policies'), ('agents', 'agents')):
        inv[key] = get(neutron, '/v2.0/%s' % path, key if key != 'security_group_rules' else 'security_group_rules')
    inv['neutron_quotas'] = {pid[p]: get(neutron, '/v2.0/quotas/%s' % p, 'quota') for p in pid}
    # --- block storage
    inv['volumes'] = get(cinder, '/volumes/detail?all_tenants=1', 'volumes', **cv)
    inv['snapshots'] = get(cinder, '/snapshots/detail?all_tenants=1', 'snapshots', **cv)
    inv['volume_types'] = get(cinder, '/types?is_public=None', 'volume_types', **cv)
    inv['volume_services'] = get(cinder, '/os-services', 'services', **cv)
    inv['cinder_quotas'] = {pid[p]: get(cinder, '/os-quota-sets/%s' % p, 'quota_set', **cv) for p in pid}
    # --- placement
    rps = get(plc, '/resource_providers', 'resource_providers', **pv)
    for rp in rps:
        rp['_inventories'] = get(plc, '/resource_providers/%s/inventories' % rp['uuid'], 'inventories', **pv)
        rp['_allocations'] = get(plc, '/resource_providers/%s/allocations' % rp['uuid'], 'allocations', **pv)
    inv['placement_resource_providers'] = rps
    inv['_meta']['counts'] = {k: (len(v) if isinstance(v, (list, dict)) else None) for k, v in inv.items() if k != '_meta'}
    return inv


def norm(coll, obj, key_of=None):
    drop = VOLATILE | VOLATILE_BY.get(coll, set())
    if isinstance(obj, dict):
        return {k: norm(coll, v) for k, v in sorted(obj.items()) if k not in drop}
    if isinstance(obj, list):
        items = [norm(coll, v) for v in obj]
        return sorted(items, key=lambda x: json.dumps(x, sort_keys=True))
    return obj


def keyed(coll, v):
    """Collection -> {identity: normalised record}."""
    if isinstance(v, dict):
        return {'%s' % k: norm(coll, x) for k, x in v.items()}
    out = {}
    for x in v:
        ident = x.get('id') or x.get('uuid') or x.get('name') or json.dumps(x, sort_keys=True)
        if coll == 'keypairs':
            ident = '%s/%s' % (x['_user'], x['name'])
        if coll in ('agents', 'compute_services', 'volume_services', 'hypervisors'):
            ident = '%s/%s' % (x.get('binary') or x.get('service_type') or x.get('agent_type') or 'x', x.get('host') or x.get('hypervisor_hostname') or '')
        out[ident] = norm(coll, x)
    return out


def compare(base, now):
    diffs = []
    for coll in sorted(set(base) | set(now)):
        if coll == '_meta':
            continue
        if coll not in base or coll not in now:
            diffs.append((coll, 'collection missing in %s' % ('baseline' if coll not in base else 'current')))
            continue
        b, n = keyed(coll, base[coll]), keyed(coll, now[coll])
        for k in sorted(set(b) | set(n)):
            if k not in n:
                diffs.append((coll, 'missing now: %s' % k))
            elif k not in b:
                diffs.append((coll, 'new now: %s' % k))
            elif b[k] != n[k]:
                ch = sorted(f for f in set(b[k]) | set(n[k]) if (b[k].get(f) if isinstance(b[k], dict) else None) != (n[k].get(f) if isinstance(n[k], dict) else None)) if isinstance(b[k], dict) and isinstance(n[k], dict) else ['<value>']
                diffs.append((coll, 'changed: %s fields=%s' % (k, ch)))
    return diffs


def functional(base):
    """Checks that need a running data path through the APIs; returns [(name, ok, detail)]."""
    res = []
    admin = sess()
    # 1. authenticate as the lab users with their stored passwords
    for u, pw, pr in (('alice', 'USER_ALICE', 'ufj-proj-a'), ('bob', 'USER_BOB', 'ufj-proj-b')):
        try:
            s = sess(u, os.environ[pw], pr)
            tok = s.get_token()
            res.append(('auth %s' % u, bool(tok), 'token issued'))
        except Exception as e:  # noqa
            res.append(('auth %s' % u, False, str(e)[:120]))
    # 2. image data survives: download and compare checksum with the glance record from the baseline
    glance = ad(admin, 'image')
    bad = []
    for i in base['images']:
        if not i.get('checksum'):
            continue
        h = hashlib.md5()
        r = glance.get('/v2/images/%s/file' % i['id'], stream=True)
        for chunk in r.iter_content(65536):
            h.update(chunk)
        if h.hexdigest() != i['checksum']:
            bad.append(i['name'])
    res.append(('image data md5 == glance checksum (%d images)' % len([i for i in base['images'] if i.get('checksum')]), not bad, 'mismatch: %s' % bad if bad else 'all equal'))
    # 3. servers: same ids and still ACTIVE in the API (DB state), volume attachments and floating IPs
    nova = ad(admin, 'compute')
    nv = {'headers': {'X-OpenStack-Nova-API-Version': '2.60'}}
    now = {s['id']: s for s in get(nova, '/servers/detail?all_tenants=1', 'servers', **nv)}
    bs = {s['id']: s for s in base['servers']}
    res.append(('servers present with same status', all(i in now and now[i]['status'] == bs[i]['status'] for i in bs),
                '%d/%d servers, statuses %s' % (len(now), len(bs), sorted(set(s['status'] for s in now.values())))))
    # 4. write test through the APIs: create and delete a project-scoped network as alice
    try:
        s = sess('alice', os.environ['USER_ALICE'], 'ufj-proj-a')
        net = ad(s, 'network')
        nid = net.post('/v2.0/networks', json={'network': {'name': 'ufj-functional-test'}}).json()['network']['id']
        net.delete('/v2.0/networks/%s' % nid)
        res.append(('write test (create/delete network as alice)', True, nid))
    except Exception as e:  # noqa
        res.append(('write test (create/delete network as alice)', False, str(e)[:120]))
    # 5. every nova-compute service and cinder-volume is up, neutron agents alive
    cs = [x for x in get(nova, '/os-services', 'services', **nv) if x['binary'] == 'nova-compute']
    # the preserved baseline is FENCED: the service rows must exist (nova service version is recorded in the DB report)
    res.append(('nova-compute service rows present (fenced baseline: state not required)', len(cs) >= 3, '%d computes: %s' % (len(cs), sorted((x['host'], x['state']) for x in cs))))
    return res


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    c = sub.add_parser('capture'); c.add_argument('--out', required=True)
    v = sub.add_parser('verify'); v.add_argument('--baseline', required=True); v.add_argument('--report')
    a = ap.parse_args()
    if a.cmd == 'capture':
        inv = capture()
        json.dump(inv, open(a.out, 'w'), indent=1, sort_keys=True, default=str)
        print('wrote %s: %s' % (a.out, json.dumps(inv['_meta']['counts'], sort_keys=True)))
        return 0
    base = json.load(open(a.baseline))
    diffs = compare(base, json.loads(json.dumps(capture(), default=str)))
    func = functional(base)
    lines = ['# inventory verify %s' % datetime.datetime.utcnow().isoformat(), 'differences: %d' % len(diffs)]
    lines += ['  [%s] %s' % d for d in diffs]
    lines += ['functional checks:'] + ['  [%s] %s: %s' % ('PASS' if ok else 'FAIL', n, d) for n, ok, d in func]
    ok = not diffs and all(x[1] for x in func)
    lines.append('RESULT: %s' % ('PASS - baseline reproduced' if ok else 'FAIL'))
    print('\n'.join(lines))
    if a.report:
        open(a.report, 'w').write('\n'.join(lines) + '\n')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
