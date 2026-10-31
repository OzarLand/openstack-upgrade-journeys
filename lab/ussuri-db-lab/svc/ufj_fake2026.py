"""Lab compute driver of the 2026.1 runtime (EXP-SVC-01): nova.virt.fake.FakeDriver that identifies its node the way the real
single-node drivers do (node uuid = the compute_id file, hypervisor_hostname = host), so that a 2026.1 compute can ADOPT an existing
compute_nodes row.  The stock fake driver derives a random per-process uuid ('uuids.node_<name>') and then creates a second node
record ('Duplicate compute node record found'), which no real driver does.  Installed read-only as nova/virt/ufj_fake2026.py."""
import nova.virt.node
from nova.virt import fake


class UfjFake2026Driver(fake.FakeDriver):
    def get_nodenames_by_uuid(self, refresh=False):
        return {nova.virt.node.get_local_node_uuid(): self.get_available_nodes()[0]}

    def get_available_resource(self, nodename):
        res = super().get_available_resource(nodename)
        res.pop('uuid', None)
        return res


# EXP-SVC-02: guests created by the Ussuri computes still "exist" on the hypervisor after the control plane was migrated (a libvirt driver finds
# the domains).  The fake driver keeps its guests in memory, so a freshly started fake compute knows none of them.  The wrapper below registers a
# guest the first time the manager touches it, so that operations on pre-existing instances reach the Nova code path instead of failing in the fake.
from nova.compute import power_state  # noqa: E402


def _adopt_wrap(name):
    orig = getattr(fake.FakeDriver, name)

    def wrapper(self, *args, **kwargs):
        inst = None
        for a in list(args) + list(kwargs.values()):
            if hasattr(a, 'uuid') and hasattr(a, 'name') and hasattr(a, 'vm_state'):
                inst = a
                break
        if inst is not None and inst.uuid not in self.instances:
            state = power_state.SHUTDOWN if inst.vm_state in ('stopped',) else power_state.RUNNING
            self.instances[inst.uuid] = fake.FakeInstance(inst.name, state, inst.uuid)
        return orig(self, *args, **kwargs)
    wrapper.__name__ = name
    return wrapper


for _n in ('power_off', 'power_on', 'reboot', 'pause', 'unpause', 'suspend', 'resume', 'snapshot', 'destroy',
           'migrate_disk_and_power_off', 'finish_migration', 'confirm_migration', 'finish_revert_migration', 'get_info',
           'attach_volume', 'detach_volume', 'rescue', 'unrescue'):
    if hasattr(fake.FakeDriver, _n):
        setattr(UfjFake2026Driver, _n, _adopt_wrap(_n))
