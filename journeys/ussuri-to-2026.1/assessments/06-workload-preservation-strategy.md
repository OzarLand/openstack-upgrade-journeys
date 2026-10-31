# Workload preservation strategy: identity, metadata and relationships

| | |
|---|---|
| Author | Agent 6, OpenStack Operations and Reliability Expert (OzarLand multi-agent team, Stage 1) |
| Model | Sonnet (high reasoning) |
| Date | 2026-10-31 |
| Status | `PROPOSED-UNVERIFIED`. Source-read only; nothing executed on a lab. |
| Inputs read | `00-mission-brief.md`; skills `openstack-maintenance-planning`, `openstack-vm-troubleshooting` (`instance-lifecycle.md`, `instance-networking.md`, `volumes.md`, `compute-host-events.md`), `openstack-kolla-ansible-operations` (`architecture-implications.md`, storage section), `openstack-change-review`; upstream: `keystone@origin/stable/2026.1:keystone/server/flask/common.py:660-663`, `glance@origin/stable/2026.1:glance/api/v2/images.py:1317-1323`, `neutron-lib==3.0.0` `neutron_lib/api/definitions/port.py` (`id` is `allow_post: False`), `nova@origin/stable/2026.1:nova/api/openstack/compute/schemas/servers.py`, `nova@origin/stable/2026.1:doc/source/admin/hw-machine-type.rst`. |
| Companions | `06-operational-risk-assessment.md`, `06-recovery-and-rollback-plan.md` |

Status vocabulary per the brief. "Preserved" in this file always means "the identifier or attribute is the same afterwards, **and** it has been verified by a stated check". Nothing is claimed as verified by a run; the check column says how it would be.

---

## 1. Principle

Data integrity beats speed. Preservation has three layers, and a strategy can keep one and lose another:

1. **Identity**: the UUID or name that other systems store (Terraform state, monitoring, billing, DNS, CMDB, user scripts).
2. **State**: what the resource contains and how it is configured (disk contents, properties, rules).
3. **Relationships**: which project owns it, which network it is on, which volume is attached to which server, which image a server was built from.

In strategies A, B and D the Nova, Neutron, Cinder, Glance and Keystone *databases* are the carriers of identity and relationships, so IDs survive by construction **if** the migration of those databases is correct (other agents own that). In strategy C there is no shared database: each resource is re-created through an API, and the APIs decide which identifiers you may choose.

---

## 2. Which identifiers an API-level migration (strategy C) can and cannot set

From source reading of the `2026.1` branch (and `neutron-lib` 3.0.0 for Neutron attribute definitions). `Not validated` means I did not run it.

| Identifier | Can the caller choose it at create time? | Evidence | Consequence |
|---|---|---|---|
| Nova server UUID | **No.** The create schema takes no instance UUID; a new one is generated. | `nova@origin/stable/2026.1:nova/api/openstack/compute/schemas/servers.py` (no top-level `id`/`uuid` for the server; the `uuid` fields there are for block-device and network references) | Every server in the new cloud has a new UUID. Anything keyed on the old UUID must be remapped. |
| Neutron port UUID, network UUID, subnet UUID, router UUID, security group UUID, floating IP UUID | **No** for the object ID: `id` is `allow_post: False` in the port definition; other Neutron resources follow the same pattern (I read the port definition only; `Not validated` for the rest) | `neutron-lib==3.0.0` `neutron_lib/api/definitions/port.py:32` | New UUIDs. |
| Port MAC address | **Yes** (`mac_address` is a postable attribute of a port); default policy restricts it to admin | same file, `PORT_MAC_ADDRESS` | MAC can be preserved, which preserves guest-side network configuration that is MAC-bound (udev rules, licences). Needs admin or a policy change. `Not validated` for policy. |
| Port fixed IP | **Yes** (`fixed_ips` with `ip_address`), if the subnet is the same range and the address is free | Neutron API behaviour; `Not validated` here | IPs can be preserved only if the new subnet covers the same CIDR and the old port is gone or the ranges are disjoint at the moment of creation. Two clouds both owning the same CIDR cannot both be reachable from the same L2 segment. |
| Floating IP address | **Yes**, admin or policy allowed, `floating_ip_address` request on an external network that contains that address | Neutron API behaviour; `Not validated` here | The address can be preserved only if the new cloud's external network owns the same prefix and the old cloud releases it first. A floating IP address can live in exactly one cloud at a time at L3/ARP level: moving it is itself the cut-over. |
| Glance image UUID | **Yes.** The `id` request attribute is mapped to `image_id` at create. | `glance@origin/stable/2026.1:glance/api/v2/images.py:1322-1323` | An image can be re-created with the same ID if the ID is free in the target. Visibility, properties and checksums need to be set/verified separately. Whether a policy restricts this to admin: not read. |
| Glance image checksum (`checksum` MD5, `os_hash_algo`/`os_hash_value`) | Computed by Glance from the uploaded bytes; not settable | Glance behaviour | Preserved only if the bytes are identical (verify by hash after upload, compare to the source's values). |
| Keystone project, user, group, domain, role, service, endpoint IDs | **No** via the API: `_assign_unique_id` sets `ref['id'] = uuid.uuid4().hex` on create | `keystone@origin/stable/2026.1:keystone/server/flask/common.py:660-663`; `keystone/api/projects.py:213` calls it | All project IDs change in a pure API-migrated cloud. Everything owned by a project (images, quotas, shared resources, volume ownership, Nova server project, Neutron networks) is keyed on it: the migration tool needs an old-to-new project map. **Exception route**: carry the Keystone database across (strategy D variant); then IDs are preserved. That is a database operation, not an API one, and its feasibility belongs to the database agents. |
| Cinder volume UUID | **No** on create; `volume manage` adopts an existing backend object but assigns a new volume ID | `cinder@origin/stable/2026.1:cinder/api/schemas/volume_manage.py` (schema read; ID behaviour of manage not re-checked per driver) | New UUIDs; RBD image or LV is renamed on manage (driver-specific; `Not validated`). |
| Cinder snapshot UUID | **No** on create; `snapshot manage` exists | Cinder API | New UUIDs. |
| Keypair name | **Yes** (keyed by name and user) | Nova | Names preserved; public key preserved by importing it; keypairs belong to a *user*, whose ID changes in C. |
| Server metadata, tags | **Yes** | Nova | Key/value copied via the API. |
| Flavor ID | **Yes** (flavors can be created with a chosen `id`) | Nova API | Preserve flavor IDs; otherwise server records created from templates drift. |
| Quota values | **Yes** (per project) | Nova/Neutron/Cinder quota APIs | Quotas are per project ID, so the project map is required. |
| Server created time, `launched_at`, action history (`instance actions`) | **No** | Nova | Audit history stays in the old cloud's database. Keep it for the retention period (see recovery plan). |

**Consequence summary for C** `[PROPOSED-UNVERIFIED]`: with a pure API migration, nothing keyed by Keystone IDs or by Nova/Cinder/Neutron UUIDs survives; names, MACs (admin), fixed IPs (if ranges free), floating IP addresses (if the prefix moves), image IDs and checksums can be preserved. Integrations that store resource UUIDs (Terraform state, Ansible dynamic inventory caches, billing, monitoring labels) need an explicit old-to-new map and a re-import. Users see new instance IDs and, if projects are recreated, new project IDs; application credentials and EC2 credentials are not carried over and must be re-issued.

---

## 3. Resource-by-resource table

Legend: **A** in-place release-by-release; **B** offline DB fast-forward then 2026.1; **C** parallel cloud and API migration; **D** hybrid (new 2026.1 control plane built from a walked clone of the DBs, new computes, workloads moved in waves). Status in each cell is `PROPOSED-UNVERIFIED` unless noted. "Verify" gives the check to run before and after; record both in the change decision record.

| Resource | How preserved: A | B | C | D | Verify (before and after) |
|---|---|---|---|---|---|
| **VM identity** (instance UUID, hostname, flavor, AZ, created/launched times, instance action history) | Same DB, same UUID. Hostnames and flavor kept | Same DB lineage; UUID kept if the offline walk is correct | **Not preserved.** New UUID per server; names can be kept; history lives in the old DB only | Same as B if the Nova DB (`nova`, `nova_api`, `nova_cell0`) is carried; otherwise as C. Instance record keeps `host` and `node` pointing at the old compute until it is moved | `openstack server list --all-projects -f value -c ID -c Name -c Status -c "Flavor" ` before/after; compare sorted UUID lists; for C use the map file |
| **VM metadata** (key/value metadata, tags, keypair name, user data, config drive flag, image ref, scheduler hints, server groups) | Kept in DB | Kept | Metadata and tags copied by API; user data resupplied at create; image ref points to the new image ID (equal if the image ID was preserved); scheduler hints and server group membership re-created | Kept with DB; server group membership kept | Per-server dump (`openstack server show -f json`) normalised and diffed |
| **Guest hardware definition** (libvirt XML: machine type, CPU model, devices, vNIC order, MACs, disk bus) | Regenerated by nova-compute on hard reboot/migration; machine type is recorded per instance only from Wallaby on (`hw-machine-type.rst`) | Same, with the extra risk that no compute ever ran a version that recorded it, so recording happens at first 2026.1 compute start-up; `nova-manage libvirt list_unset_machine_type` for `SHELVED_OFFLOADED` ones | New guest: hardware defined fresh by the target Nova; guest OS may notice device changes (NIC name, disk bus) | Regenerated at first start/migration on the new computes | Before: `virsh dumpxml` per domain (machine, cpu, devices). After: same, plus boot test of a canary per hardware class |
| **Networks** (network, subnet, segments, MTU, DHCP enabled, DNS, provider mappings) | Same DB, UUIDs kept | Same | Re-created; **UUIDs new**; CIDR, gateway, MTU, DHCP/DNS settings copied; provider networks must be mapped to the same physical segment or a new one | Kept with Neutron DB; physical bridge mappings must exist on the new computes with the same names | `openstack network list/show`, `subnet list/show` diff; MTU test across tunnel (`instance-networking.md`, "Tunnel MTU mismatch") |
| **Ports** (port UUID, MAC, fixed IPs, security groups, binding host, device owner, allowed address pairs) | Kept in DB; binding re-done by the OVS agent per host | Kept | Re-create each port with chosen MAC (admin) and fixed IP, then attach; **port UUID new**; binding done on first boot | Kept with DB; binding profile/host rewritten when instance moves | `openstack port list -f json` diff on MAC, fixed IPs, security groups; after move `binding_host_id` points to the new host |
| **IPs** (fixed IP allocation, DHCP leases, gateway) | Kept; leases survive agent restarts | Kept; leases need DHCP agent back before expiry (`dhcp_lease_duration` default 86400 s; longer outage `Not validated`) | Fixed IPs preserved only if the CIDR is the same and not simultaneously live in the old cloud; otherwise renumber | Kept with DB; leases kept if DHCP agents come back within the lease | Console log / `ip a` inside representative guests; ping and SSH matrix |
| **Floating IPs** (address, association, UUID) | Kept; one brief gap when `ovs-vswitchd` is recreated (2 s on the 2025.1 to 2026.1 lab, KA-ARCH-29 `LAB-VALIDATED`) | Kept; association survives the DB walk; traffic path rebuilds when L3 agents return | **Address** preserved only if the prefix moves to the new external network (cut-over); **UUID new**; associations re-created after the instance exists. An address cannot be live in both clouds | Kept with DB; for moved instances, associations survive the move in the DB but the router namespace must exist on the new network node | `openstack floating ip list -f json` diff; external probe to each FIP from outside, before/after |
| **Routers** (gateway, interfaces, HA state, SNAT) | Namespaces and keepalived persist across agent stop (legacy routers, VM-NET-25 `LAB-VALIDATED`); HA behaviour on container replacement `Not validated` | Same; rebuilt by agents at first start | Re-created; **UUIDs new**; external gateway IP may change | Kept with DB; L3 agents on the new network nodes pick them up | `ip netns list` on network nodes; `openstack router show` diff; north-south probe |
| **Security groups and rules** | Kept in DB; enforced as kernel/OVS state | Kept | Re-created; **UUIDs new**; rule content copied (including remote-group references, which must be remapped to new group IDs) | Kept with DB | Per-group dump diffed after normalising IDs (C) or exact diff (A/B/D); functional test with a probe VM |
| **Volumes** (UUID, size, type, bootable, attachments, metadata) | Same DB and same backend object (LV/RBD) | Same | **Not preserved by ID.** Copy data via backup/restore, `volume manage` of the same Ceph pool image, or image upload/download; new UUID; attach to the new server | Same DB and same backend object; for Ceph, the same pool is read by the new plane (see single-writer rule below) | Per-volume checksum of data (`sha256` over the block device read-only) before/after; `openstack volume list` diff; attachments table (server, device) |
| **Attachments / bootable volumes** | `block_device_mapping` kept; Cinder attachment records kept. After a long outage, stale attachments are the common fault (`volumes.md`) | Kept | Re-created at attach time on the new server | Kept in DB; connection info re-fetched on host change | `openstack server show` volumes list; `openstack volume show` status `in-use` and attachment host |
| **Snapshots and backups** | Kept | Kept; Cinder backup format backward-compatibility across 12 releases `Not validated` | Snapshots are backend objects; to move them: restore from backup in the new cloud (new IDs) or `snapshot manage` | Kept in DB; backups readable only if the backup driver and format remain supported | Restore one backup of each type on the target as a test; compare data checksum |
| **Images** (UUID, name, visibility, checksum, properties, sharing, locations) | Kept | Kept | Re-create with the **same ID** (supported: `id` maps to `image_id`, `glance@origin/stable/2026.1:glance/api/v2/images.py:1322`), upload bytes, set properties and visibility; `owner` must be the new project ID; image members re-created with new project IDs | Kept with DB; bytes remain in the same backend (file path or Ceph pool) | `openstack image show -f json` diff on `checksum`, `os_hash_value`, `size`, `properties`; hash recompute on the stored bytes |
| **Users, groups, domains** | Kept | Kept | **IDs new** via API (`keystone.../common.py:660-663`); passwords not exportable (hashes are DB state), so users reset passwords or an external IdP is used; application and EC2 credentials re-issued | Kept if the Keystone DB is carried; Fernet keys and credential keys must be carried too | User list diff; auth test per integration account; token validation across the cut-over |
| **Projects** | Kept | Kept | **IDs new** via API; a project map is required for every project-scoped object | Kept if Keystone DB is carried | Project list diff; map file for C |
| **Roles and assignments** | Kept | Kept | Re-created by name against new IDs | Kept | Assignment list diff |
| **Quotas** | Kept (per project) | Kept | Re-set per project via API; compare usage after | Kept | `openstack quota show` diff; `limits show --absolute` |
| **Service catalog / endpoints** | Kept; endpoints redeployed by Kolla-Ansible | Kept; URLs change if VIP/DNS changes | New catalog; client configs change | New catalog or reused VIP; decide before cut-over; redirects for old FQDN | Catalog diff; client smoke test |
| **Relationships** (server to ports, volumes, SGs, keypair, project, flavor, image, AZ, server group, aggregates) | By DB foreign keys | By DB foreign keys | Rebuilt by the migration tool from a normalised export: **requires an ID map** and a verified graph comparison | By DB foreign keys; moved instances keep their DB row | Export a graph before; diff after with IDs normalised; zero orphans, zero dangling references |
| **Host aggregates, availability zones, flavor extra specs, server groups, Placement allocations** | Kept; Placement resource providers reconcile as computes re-register | Kept; check reconcile after rebuild | Rebuilt manually | Kept in DB; new computes must re-register with the same hostnames or the records must be reconciled (Nova `compute_id` behaviour: not read, open question) | `openstack aggregate list`, `openstack resource provider list` counts and inventories |

### Single-writer rule for shared backends (applies to D and any parallel-plane variant)

Two control planes must never both believe they own the same Ceph RBD image, LVM volume, or nova local disk. With Ceph, a parallel plane that is pointed at the same pool can read images (Glance) and manage volumes only if exactly one plane at a time runs writes against each image. The mechanism for ownership transfer is per image, owner recorded in the migration tracker, and the old plane's record is set to a state that cannot be used (detach, or delete only the record never the data). `[PROPOSED-UNVERIFIED]`; the dual-writer hazard is the basis for gate G6 in the recovery plan.

---

## 4. Per-strategy preservation summary

| Question | A | B | C | D |
|---|---|---|---|---|
| Instance UUIDs kept | Yes | Yes (if walk correct) | **No** | Yes (if Nova DB carried) |
| Project/user IDs kept | Yes | Yes | **No** unless Keystone DB carried | Yes if Keystone DB carried |
| MAC/IP kept | Yes | Yes | Yes with admin and range control | Yes |
| Floating IPs kept | Yes (2 s gaps) | Yes | Address kept only through a coordinated prefix move | Yes |
| Disk contents kept | Yes (live migration across OS changes) | Yes where disks are shared/boot-from-volume; local disks need copy | Copy; consistency depends on quiesce | Yes where disks shared; local disks copied |
| Instance runtime state (memory, processes) | Kept on live migration; lost on any stop | Lost (every instance is stopped at least once) | Lost | Lost per moved instance unless live migration across stacks were possible (it is not between Ussuri and 2026.1) |
| Audit history kept | Yes | Yes | Only in the old cloud | Yes |
| User-visible change | Many small ones | One large | Many, and visible | One planned API outage, then per-wave moves |

---

## 5. Verification design (before execution, per `openstack-change-review` step 8)

Capture, before the first change and again after each phase:

1. **Inventory snapshot** (read-only, from the APIs): servers, ports, networks, subnets, routers, floating IPs, security groups and rules, volumes with attachments, snapshots, backups, images with checksums, users, projects, roles, quotas, flavors, keypairs, aggregates, resource providers. Store as normalised JSON outside the cloud.
2. **Hypervisor truth**: per compute, `virsh list --all` and `virsh dumpxml` of every domain, so Nova's view can be compared to libvirt's.
3. **Data-plane probes**: external ping/SSH to each floating IP and to a sample of tenant-network VMs; MTU test; DHCP renewal check; metadata fetch from a canary.
4. **Storage truth**: for Ceph `rbd ls` per pool with sizes, for LVM `lvs`; per-volume data checksums for a representative set.
5. **Business capability test** (`openstack-incident-analysis`/`control-plane-recovery.md` "validated end to end"): create a test project, network, router, instance, volume, floating IP, reach it, delete it.

A difference that cannot be explained is a stop condition. "Command succeeded" is not a verification.

---

## 6. Open questions / what I could not verify

1. Neutron: I read the `port` definition only (`id` not postable, `mac_address` postable). Network, subnet, router, security group and floating IP attribute definitions, and the default policy for `mac_address`/`floating_ip_address`, were not read. `Not validated`.
2. Glance: `id` maps to `image_id` at create; whether policy restricts that to admin, and whether an image ID can be reused after deletion in the same database, was not read.
3. Cinder `manage` ID and rename behaviour per driver (RBD, LVM): not read; Ceph pool sharing between two planes is a design hazard, not a tested design.
4. Nova `compute_id` and compute node UUID continuity when a host is reinstalled and registers under the same hostname: not read.
5. Whether Keystone credential and Fernet key material (`/etc/keystone/fernet-keys`, `credential-keys`) in Kolla is straightforwardly transferable between independently deployed clouds: `Not validated`.
6. Cinder backup format compatibility across many releases: `Not validated`.
7. Whether tenants use features that do not migrate at API level at all (Heat stacks, Octavia load balancers, Designate zones, Barbican secrets): inventory `unknown`. They must be listed before any strategy is chosen, because several store UUIDs of the resources above.
