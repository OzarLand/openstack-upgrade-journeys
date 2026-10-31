"""Lab stand-in for the report_state RPC of the fake L2 agents (EXP-SVC-02 only): refreshes agents.heartbeat_timestamp of the
'OFA driver agent' rows every 15 s through the Neutron database, because the real report_state RPC (tools/fake_l2_agent.py,
ported to 2026.1) was not answered by neutron-rpc-server in this lab (client call timeouts, cause not found).  The agent rows
themselves are the ones of the Ussuri baseline (no row is created or deleted).  Nothing is marked 'up' (no update_device_up)."""
import configparser
import sys
import time
from urllib.parse import urlparse

import pymysql

cp = configparser.ConfigParser(interpolation=None, strict=False)
cp.read('/etc/neutron/neutron.conf')
u = urlparse(cp.get('database', 'connection'))
while True:
    try:
        c = pymysql.connect(host=u.hostname, user=u.username, password=u.password, db=u.path.lstrip('/'), autocommit=True)
        with c.cursor() as cur:
            n = cur.execute("UPDATE agents SET heartbeat_timestamp = UTC_TIMESTAMP() WHERE agent_type = 'OFA driver agent'")
        c.close()
        print('heartbeat for %d agent rows' % n, flush=True)
    except Exception as e:  # noqa
        print('heartbeat failed:', e, file=sys.stderr, flush=True)
    time.sleep(15)
