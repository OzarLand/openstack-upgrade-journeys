"""Fake L2 agent for the lab: reports an 'OFA driver agent' for one host through neutron-server's real
report_state RPC so that the test mechanism driver 'fake_agent' can bind ports on that host, and marks the ports
bound to the host as up (update_device_up RPC) so that neutron sends the network-vif-plugged event to nova.
The list of ports to mark up is read straight from the neutron database (ml2_port_bindings): a real agent would learn
it from the datapath. It does not plug anything: there is no datapath in this lab."""
import argparse
import sys
import time
import uuid

p = argparse.ArgumentParser()
p.add_argument('--host', required=True)
p.add_argument('--interval', type=int, default=20)
a = p.parse_args()
sys.argv = ['fake-l2-agent', '--config-file', '/etc/neutron/neutron.conf']

from oslo_config import cfg  # noqa: E402
from neutron.common import config as common_config  # noqa: E402,F401
from neutron_lib import rpc as n_rpc  # noqa: E402
from neutron.agent import rpc as agent_rpc  # noqa: E402
from neutron_lib import constants, context  # noqa: E402
from neutron_lib.agent import topics  # noqa: E402
from neutron_lib.plugins.ml2 import api as ml2_api  # noqa: E402,F401
from oslo_log import log as logging  # noqa: E402

cfg.CONF(args=['--config-file', '/etc/neutron/neutron.conf'], project='neutron')
logging.setup(cfg.CONF, 'fake-l2-agent')
n_rpc.init(cfg.CONF)
ctx = context.get_admin_context_without_session()
report = agent_rpc.PluginReportStateAPI(topics.REPORTS)
plugin = agent_rpc.PluginApi(topics.PLUGIN)
state = {
    'binary': 'neutron-fake-l2-agent',
    'host': a.host,
    'topic': constants.L2_AGENT_TOPIC,
    'configurations': {'tunnel_types': ['vxlan'], 'interface_mappings': {'physnet1': 'none'}},
    'agent_type': constants.AGENT_TYPE_OFA,
    'start_flag': True,
}
agent_id = 'fake-l2-' + a.host
print('fake agent for', a.host, flush=True)


def down_ports():
    import pymysql
    from urllib.parse import urlparse
    import configparser
    cp = configparser.ConfigParser(interpolation=None)
    cp.read('/etc/neutron/neutron.conf')
    u = urlparse(cp.get('database', 'connection'))
    c = pymysql.connect(host=u.hostname, user=u.username, password=u.password, db=u.path.lstrip('/'))
    try:
        with c.cursor() as cur:
            cur.execute("SELECT p.id FROM ports p JOIN ml2_port_bindings b ON b.port_id = p.id "
                        "WHERE b.host = %s AND b.vif_type = 'ovs' AND p.status = 'DOWN' "
                        "AND p.device_owner LIKE 'compute:%%'", (a.host,))
            return [r[0] for r in cur.fetchall()]
    finally:
        c.close()

while True:
    try:
        report.report_state(ctx, state, use_call=False)
        state.pop('start_flag', None)
    except Exception as e:  # keep trying: neutron-server may restart
        print('report_state failed:', e, flush=True)
    try:
        for dev in down_ports():
            plugin.update_device_up(ctx, dev, agent_id, a.host)
            print('marked up', dev, flush=True)
    except Exception as e:
        print('update_device_up failed:', e, flush=True)
    time.sleep(a.interval)
