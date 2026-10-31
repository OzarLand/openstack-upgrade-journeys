#!/usr/bin/env python
"""REST-only creation of baseline-coverage items that python-openstackclient 5.2 cannot express. Runs inside ufj-client.
usage: coverage_rest.py <item>   (credentials: OS_* of the calling user; some items need admin)
Prints one JSON line {"item":..., "ok":bool, "detail":...}; never raises (failures are recorded, not hidden)."""
import json
import os
import sys
import uuid

from keystoneauth1 import adapter, session
from keystoneauth1.identity import v3


def sess():
    return session.Session(auth=v3.Password(
        auth_url=os.environ['OS_AUTH_URL'], username=os.environ['OS_USERNAME'], password=os.environ['OS_PASSWORD'],
        project_name=os.environ['OS_PROJECT_NAME'], user_domain_name='Default', project_domain_name='Default'))


S = sess()


def ad(t, mv=None):
    return adapter.Adapter(session=S, service_type=t, interface='public', region_name='RegionOne', default_microversion=mv)


def j(r):
    if r.status_code >= 400:
        raise RuntimeError('%s %s %s' % (r.request.method, r.url.split('?')[0], r.text[:300]))
    return r.json() if r.text else {}


def multisegment():
    n = ad('network')
    segs = [{'provider:network_type': 'vlan', 'provider:physical_network': 'physnet1', 'provider:segmentation_id': 150},
            {'provider:network_type': 'vlan', 'provider:physical_network': 'physnet1', 'provider:segmentation_id': 151}]
    net = j(n.post('/v2.0/networks', json={'network': {'name': 'ufj-multiseg', 'segments': segs}}))['network']
    return 'network %s segments=%d' % (net['id'], len(net.get('segments', [])))


def glance_multilocation():
    g = ad('image')
    img = j(g.post('/v2/images', json={'name': 'ufj-image-multiloc', 'disk_format': 'raw', 'container_format': 'bare',
                                       'visibility': 'public'}))
    for f in ('ufj-image-a.raw', 'ufj-image-b.raw'):
        j(g.patch('/v2/images/%s' % img['id'], headers={'Content-Type': 'application/openstack-images-v2.1-json-patch'},
                  json=[{'op': 'add', 'path': '/locations/-', 'value': {'url': 'http://ufj-static:8000/' + f, 'metadata': {}}}]))
    cur = j(g.get('/v2/images/%s' % img['id']))
    return 'image %s locations=%d status=%s' % (img['id'], len(cur.get('locations', [])), cur['status'])


def glance_task():
    g = ad('image')
    t = j(g.post('/v2/tasks', json={'type': 'import', 'input': {
        'import_from': 'http://ufj-static:8000/ufj-image-b.raw', 'import_from_format': 'raw',
        'image_properties': {'name': 'ufj-image-from-task', 'disk_format': 'raw', 'container_format': 'bare'}}}))
    return 'task %s status=%s' % (t['id'], t['status'])


def placement_nested():
    p = ad('placement', 'placement 1.30')
    rps = j(p.get('/resource_providers'))['resource_providers']
    parent = [r for r in rps if r['name'] == 'ufj-compute1'][0]['uuid']
    nid = str(uuid.uuid5(uuid.NAMESPACE_DNS, 'ufj-nested-1'))
    j(p.post('/resource_providers', json={'name': 'ufj-compute1-nested', 'uuid': nid, 'parent_provider_uuid': parent}))
    r = p.put('/traits/CUSTOM_UFJ_LAB')
    if r.status_code not in (201, 204):
        raise RuntimeError('trait: %s %s' % (r.status_code, r.text[:200]))
    gen = j(p.get('/resource_providers/%s' % nid))['generation']
    j(p.put('/resource_providers/%s/traits' % nid, json={'resource_provider_generation': gen, 'traits': ['CUSTOM_UFJ_LAB']}))
    return 'nested provider %s parent %s trait CUSTOM_UFJ_LAB' % (nid, parent)


def placement_consumer():
    p = ad('placement', 'placement 1.28')
    rps = j(p.get('/resource_providers'))['resource_providers']
    rp = [r for r in rps if r['name'] == 'ufj-compute2'][0]['uuid']
    cid = str(uuid.uuid5(uuid.NAMESPACE_DNS, 'ufj-manual-consumer'))
    proj = S.get_project_id()
    user = S.get_user_id()
    r = p.put('/allocations/%s' % cid, json={'allocations': {rp: {'resources': {'MEMORY_MB': 64}}},
                                             'project_id': proj, 'user_id': user, 'consumer_generation': None})
    if r.status_code >= 400:
        raise RuntimeError('%s %s' % (r.status_code, r.text[:300]))
    return 'manual consumer %s (no instance, microversion 1.28, no consumer type)' % cid


def cinder_group_quota():
    c = ad('volumev3', 'volume 3.50')
    pid = j(ad('identity').get('/v3/projects?name=ufj-proj-a'))['projects'][0]['id']
    j(c.put('/os-quota-sets/%s' % pid, json={'quota_set': {'groups': 7, 'consistencygroups': 6, 'backups': 11}}))
    return 'groups=7 consistencygroups=6 backups=11 on %s' % pid


def force_delete(name):
    n = ad('compute', '2.60')
    sid = [x['id'] for x in j(n.get('/servers?all_tenants=1&name=%s' % name))['servers'] if x['name'] == name][0]
    j(n.post('/servers/%s/action' % sid, json={'forceDelete': None}))
    return 'force-deleted %s %s' % (name, sid)


def revoke_token():
    ks = ad('identity')
    tok = S.get_token()
    s2 = sess()
    t2 = s2.get_token()
    r = ks.delete('/v3/auth/tokens', headers={'X-Subject-Token': t2})
    return 'revoked a token (status %s)' % r.status_code


ITEMS = {k: v for k, v in globals().items() if callable(v) and k in (
    'multisegment', 'glance_multilocation', 'glance_task', 'placement_nested', 'placement_consumer',
    'cinder_group_quota', 'revoke_token', 'force_delete')}

if __name__ == '__main__':
    item, args = sys.argv[1], sys.argv[2:]
    try:
        d = ITEMS[item](*args)
        print(json.dumps({'item': item, 'ok': True, 'detail': d}))
    except Exception as e:  # noqa
        print(json.dumps({'item': item, 'ok': False, 'detail': str(e)[:400]}))
