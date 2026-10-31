"""Fake L2 agent for the lab: reports an 'OFA driver agent' for one host through neutron-server's real
report_state RPC so that the test mechanism driver 'fake_agent' can bind ports on that host, and marks the ports
bound to the host as up (update_device_up RPC) so that neutron sends the network-vif-plugged event to nova.
It does not plug anything: there is no datapath in this lab."""
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
while True:
    try:
        report.report_state(ctx, state, use_call=False)
        state.pop('start_flag', None)
    except Exception as e:  # keep trying: neutron-server may restart
        print('report_state failed:', e, flush=True)
    time.sleep(a.interval)
