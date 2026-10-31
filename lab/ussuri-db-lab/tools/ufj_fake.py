"""Lab compute driver: nova.virt.fake.FakeDriver plus a two-cell NUMA topology and PCPU inventory, so that flavors with
hw:numa_nodes / hw:cpu_policy=dedicated can be scheduled and claimed on a node without a hypervisor.
Installed read-only as nova/virt/ufj_fake.py inside the compute containers (compute_driver = ufj_fake.UfjFakeDriver).
Only the Ussuri baseline uses it; the 2026.1 fake compute of EXP-SVC-01 uses the stock fake.FakeDriver."""
from oslo_serialization import jsonutils  # noqa: F401

from nova import objects
from nova.virt import fake


class UfjFakeDriver(fake.FakeDriver):
    def get_available_resource(self, nodename):
        res = super(UfjFakeDriver, self).get_available_resource(nodename)
        if res:
            cells = []
            for i in range(2):
                cells.append(objects.NUMACell(
                    id=i, cpuset=set(range(i * 4, i * 4 + 2)), pcpuset=set(range(i * 4 + 2, i * 4 + 4)),
                    memory=65536, cpu_usage=0, memory_usage=0, pinned_cpus=set(), siblings=[],
                    mempages=[objects.NUMAPagesTopology(size_kb=4, total=16777216, used=0, reserved=0)]))
            res['numa_topology'] = objects.NUMATopology(cells=cells)._to_json()
        return res

    def update_provider_tree(self, provider_tree, nodename, allocations=None):
        super(UfjFakeDriver, self).update_provider_tree(provider_tree, nodename, allocations)
        inv = dict(provider_tree.data(nodename).inventory)
        inv['PCPU'] = {'total': 8, 'min_unit': 1, 'max_unit': 8, 'step_size': 1, 'allocation_ratio': 1.0, 'reserved': 0}
        provider_tree.update_inventory(nodename, inv)
