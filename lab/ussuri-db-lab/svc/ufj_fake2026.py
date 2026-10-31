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
