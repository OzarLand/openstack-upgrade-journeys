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
    return adapter.Adapter(session=S, service_type=t, interface='public', region_name='RegionOne', default_microversion=mv, raise_exc=False)


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
    p = ad('placement', '1.30')
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
    p = ad('placement', '1.28')
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
    c = ad('volumev3', '3.50')
    pid = j(ad('identity').get('/projects?name=ufj-proj-a'))['projects'][0]['id']
    j(c.put('/os-quota-sets/%s' % pid, json={'quota_set': {'groups': 7, 'backups': 11}}))
    return 'groups=7 backups=11 (consistencygroups is not an accepted quota key in the v3 API) on %s' % pid


def force_delete(name):
    n = ad('compute', '2.60')
    import time
    for _ in range(30):  # the delete is asynchronous: wait for SOFT_DELETED
        found = [x['id'] for x in j(n.get('/servers?all_tenants=1&deleted=True&name=%s' % name))['servers'] if x['name'] == name]
        if found:
            break
        time.sleep(2)
    sid = found[0]
    j(n.post('/servers/%s/action' % sid, json={'forceDelete': None}))
    return 'force-deleted %s %s' % (name, sid)


def revoke_token():
    ks = ad('identity')
    tok = S.get_token()
    s2 = sess()
    t2 = s2.get_token()
    r = ks.delete('/auth/tokens', headers={'X-Subject-Token': t2})
    return 'revoked a token (status %s)' % r.status_code


def cinder_groups():
    c = ad('volumev3', '3.50')
    out = []
    gt = j(c.post('/group_types', json={'group_type': {'name': 'ufj-gtype', 'description': 'lab', 'is_public': True,
                                                         'group_specs': {'consistent_group_snapshot_enabled': '<is> True'}}}))
    g = j(c.post('/groups', json={'group': {'name': 'ufj-group', 'group_type': gt['group_type']['id'], 'volume_types': ['ufj-fake']}}))
    out.append('group %s' % g['group']['id'])
    try:
        cg = j(c.post('/consistencygroups', json={'consistencygroup': {'name': 'ufj-cg', 'volume_types': 'ufj-fake'}}))
        out.append('consistencygroup %s' % cg['consistencygroup']['id'])
    except Exception as e:  # noqa
        out.append('consistencygroups API: %s' % str(e)[:160])
    return '; '.join(out)


def many_revocations(n='1500'):
    ks = ad('identity')
    done = 0
    for _ in range(int(n)):
        t = sess().get_token()
        if ks.delete('/auth/tokens', headers={'X-Subject-Token': t}).status_code == 204:
            done += 1
    return 'revoked %d tokens' % done


def appcred_access_rules():
    ks = ad('identity')
    uid = S.get_user_id()
    r = j(ks.post('/users/%s/application_credentials' % uid, json={'application_credential': {
        'name': 'ufj-appcred-rules', 'access_rules': [{'path': '/v2.1/servers', 'method': 'GET', 'service': 'compute'}]}}))
    return 'application credential with access rule %s' % r['application_credential']['id']


def community_image():
    g = ad('image')
    img = j(g.post('/v2/images', json={'name': 'ufj-image-community', 'disk_format': 'raw', 'container_format': 'bare',
                                       'visibility': 'community'}))
    return 'community image %s' % img['id']


def hidden_image():
    g = ad('image')
    img = j(g.post('/v2/images', json={'name': 'ufj-image-hidden', 'disk_format': 'raw', 'container_format': 'bare',
                                       'visibility': 'private', 'os_hidden': True}))
    return 'hidden image %s' % img['id']


def create_console(name):
    n = ad('compute', '2.60')
    sid = [x['id'] for x in j(n.get('/servers?name=%s' % name))['servers'] if x['name'] == name][0]
    r = j(n.post('/servers/%s/remote-consoles' % sid, json={'remote_console': {'protocol': 'vnc', 'type': 'novnc'}}))
    return 'console for %s (url host only: %s)' % (name, r['remote_console']['url'].split('?')[0])


def service_provider():
    ks = ad('identity')
    r = j(ks.put('/OS-FEDERATION/service_providers/ufj-sp', json={'service_provider': {
        'auth_url': 'https://sp.example.invalid/v3/OS-FEDERATION/identity_providers/ufj-idp/protocols/saml2/auth',
        'sp_url': 'https://sp.example.invalid/Shibboleth.sso/SAML2/ECP', 'enabled': True}}))
    return 'service provider ufj-sp'


def trust(trustee_id, impersonate='1', expires=''):
    ks = ad('identity')
    body = {'trustor_user_id': S.get_user_id(), 'trustee_user_id': trustee_id, 'project_id': S.get_project_id(),
            'impersonation': impersonate == '1', 'roles': [{'name': 'member'}]}
    if expires:
        body['expires_at'] = expires
    t = j(ks.post('/OS-TRUST/trusts', json={'trust': body}))['trust']
    return 'trust %s impersonation=%s expires_at=%s' % (t['id'], t['impersonation'], t.get('expires_at'))


def rbac(object_type, object_name, target_project_name):
    ks, n = ad('identity'), ad('network')
    tp = j(ks.get('/projects?name=%s' % target_project_name))['projects'][0]['id']
    coll = {'address_scope': 'address-scopes', 'subnetpool': 'subnetpools', 'security_group': 'security-groups',
            'qos_policy': 'qos/policies'}[object_type]
    key = {'address_scope': 'address_scopes', 'subnetpool': 'subnetpools', 'security_group': 'security_groups',
           'qos_policy': 'policies'}[object_type]
    obj = [o for o in j(n.get('/v2.0/%s?name=%s' % (coll, object_name)))[key] if o['name'] == object_name][0]
    r = j(n.post('/v2.0/rbac-policies', json={'rbac_policy': {'object_type': object_type, 'object_id': obj['id'],
                                                                'action': 'access_as_shared', 'target_tenant': tp}}))
    return 'rbac %s on %s %s -> %s' % (r['rbac_policy']['id'], object_type, object_name, target_project_name)


ITEMS = {k: v for k, v in globals().items() if callable(v) and k in (
    'multisegment', 'glance_multilocation', 'glance_task', 'placement_nested', 'placement_consumer',
    'cinder_group_quota', 'revoke_token', 'force_delete', 'trust', 'rbac', 'cinder_groups', 'many_revocations', 'appcred_access_rules', 'community_image', 'hidden_image', 'create_console', 'service_provider')}

if __name__ == '__main__':
    item, args = sys.argv[1], sys.argv[2:]
    try:
        d = ITEMS[item](*args)
        print(json.dumps({'item': item, 'ok': True, 'detail': d}))
    except Exception as e:  # noqa
        print(json.dumps({'item': item, 'ok': False, 'detail': str(e)[:400]}))
