#!/usr/bin/env python
"""Set server tags through the compute API (microversion 2.26+): python-openstackclient 5.2 has no server tag option.
usage: tag_server.py <server-name> <tag> [<tag>...]   (credentials: OS_* environment of the calling user)"""
import os
import sys
from keystoneauth1 import adapter, session
from keystoneauth1.identity import v3

name, tags = sys.argv[1], sys.argv[2:]
s = session.Session(auth=v3.Password(auth_url=os.environ['OS_AUTH_URL'], username=os.environ['OS_USERNAME'],
                                     password=os.environ['OS_PASSWORD'], project_name=os.environ['OS_PROJECT_NAME'],
                                     user_domain_name='Default', project_domain_name='Default'))
n = adapter.Adapter(session=s, service_type='compute', interface='public', region_name='RegionOne',
                    default_microversion='2.60')
sid = [x['id'] for x in n.get('/servers?name=%s' % name).json()['servers'] if x['name'] == name][0]
r = n.put('/servers/%s/tags' % sid, json={'tags': tags})
print(name, sid, r.json())
