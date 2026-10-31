# Baseline coverage checklist (pass criterion of EXP-DB-00)

| Metadata | |
|---|---|
| Origin | Red Team blocking issue RT-B-04 (`assessments/07-red-team-stage3-review.md` §2.3), adopted by the architect |
| Owners | Agent 5 (builds the dataset), Agent 4 (reviews the checklist) |
| Rule | Each item must be created **through the Ussuri APIs with Ussuri code**. Direct SQL is allowed only on disposable copies used by negative experiments (marked *negative-copy*). T0 records the count of each item. An item that cannot be produced in this lab is recorded as "not covered", with the reason. It is never silently dropped. |

The differential test (EXP-DB-01 vs 02 vs 03) and the API read-back (EXP-SVC-01) are only as strong as the data they
see. Each item below exercises a code path that the migration or the 2026.1 object loading takes.

## Cinder

- [ ] Volumes in `available`, `in-use` and `deleted` states.
- [ ] At least one snapshot.
- [ ] At least one volume with `volume_admin_metadata.temporary = 'True'` (`use_quota` online-migration semantics).
- [ ] At least one volume with `migration_status LIKE 'target:%'`.
- [ ] Rows in `quota_usages`.
- [ ] Consistency-group quota rows (migration `b7b88f50aab5`).
- [ ] A non-default `quota_backups` in `cinder.conf`, recorded (migration `9c74c1c6971f`).

## Nova

- [ ] Instances in ACTIVE, SHUTOFF, ERROR-without-host and soft-deleted states.
- [ ] Deleted then archived instances, so that the shadow tables are populated.
- [ ] One instance on a host whose `compute_nodes` row is later deleted: the residue case of
      `populate_instance_compute_id`.
- [ ] A flavor with `hw:numa_nodes` **without** `hw:cpu_policy=dedicated`, plus one pinned flavor, each with an
      instance.
- [ ] Volume-backed BDMs.
- [ ] One resized instance and one migrated instance: populated `migrations` and `migration_context`.
- [ ] `request_specs` with scheduler hints and a server group.
- [ ] `instance_actions` rows.
- [ ] Quotas set in both the legacy and the API database.
- [ ] At least two fake computes.

## Keystone

- [ ] Trusts. A duplicate pair is allowed only on a *negative-copy*.
- [ ] Application credentials.
- [ ] EC2 and TOTP credentials, with the credential key repository preserved.
- [ ] Revocation events.
- [ ] A federated mapping.
- [ ] The password hasher per user, recorded (a `sha512_crypt` user if Ussuri's default produced one).
- [ ] The `migrate_version` row (078 or 079).

## Neutron

- [ ] A multi-segment network.
- [ ] A segment range with NULL `physical_network`, and a duplicate range on a *negative-copy*.
- [ ] Non-empty `quotas`.
- [ ] Ports with binding profiles and `extra_dhcp_opts`.
- [ ] An HA router, if the fake agents allow it; otherwise "not covered".
- [ ] RBAC entries.
- [ ] Tags.

## Glance

- [ ] A multi-location image.
- [ ] `image_locations.meta_data` without `"backend":`, counted.
- [ ] Tasks.

## Placement

- [ ] A nested provider.
- [ ] A custom trait.
- [ ] Allocations for every fake instance.
- [ ] A consumer with no `consumer_types` row.

## Engine

- [ ] `@@GLOBAL.sql_mode` of the Ussuri engine, recorded.
- [ ] The session `sql_mode` used by the migration tools, recorded for EXP-DB-N2.

## Review by Agent 4 (2026-10-31)

Reviewer: Agent 4 — Database and Messaging Specialist (Opus). Basis: `experiments/declared-differences.md` and
`experiments/fast-forward-checks.md` (same date), source at the refs cited there. The checklist is accepted with the
additions and corrections below. Each addition names the code path it exercises. Every item keeps the rule of the header:
produced through Ussuri APIs, or recorded as "not covered" with the reason.

**Corrections**

1. Cinder "Rows in `quota_usages`": also require **`consistencygroups` rows in `quota_usages` and `reservations`**, not only
   in `quota_classes`/`quotas`. `b7b88f50aab5` soft-deletes all four tables (declared V-C6). Consistency-group quotas
   exist only if the CG/group quota resources are in use. Record "not covered" if the Ussuri API cannot produce them.
2. Cinder temporary volume: the `use_quota` ODM only honours a **non-deleted** admin-metadata row with key `temporary`
   and value exactly `'True'` (`calculate_use_quota`). Require one such volume **and** one deleted volume (the ODM uses
   `read_deleted='yes'`). Separately, the 2024.1+ ODM soft-deletes every `temporary` row (V-C9), so record the T0 count.
3. Nova "Quotas set in both the legacy and the API database": the Ussuri ODMs `migrate_quota_limits_to_api_db` /
   `migrate_quota_classes_to_api_db` must already have reported 0 at T0 (PC-O1). Legacy-DB quota rows therefore cannot be
   produced through Ussuri APIs (the API writes the API DB). Mark this half "not covered (by design)" rather than inserting by SQL.
4. Keystone `migrate_version`: record **all** rows, including the old `keystone` repository row (version 109) next to
   `keystone_expand`/`keystone_data_migrate`/`keystone_contract`. Keystone never drops this table (declared S-1c).
5. Engine: also record `@@GLOBAL.sql_mode` of each later engine image (10.5, 10.6, 10.11, 11.4), not only Ussuri's
   (PC-E1).

**Additions**

| Service | Item | Code path |
|---|---|---|
| Cinder | One-shot `cinder.conf` = production rendered file + connection override only; production `quota_backups`/`quota_backup_gigabytes` recorded (CP-C1) | `9c74c1c6971f` (R-5, V-C5) |
| Cinder | Whether `default` quota classes for `backups`/`backup_gigabytes` already exist at T0 (predicts R-5 Δ) | `9c74c1c6971f` guard |
| Cinder | A volume type with encryption and one attached volume (`volume_attachment.connection_info` blob) | object load at F2 |
| Nova | ≥1 `pci_devices` row with NULL `uuid`, or "not covered" (the fake driver reports no PCI devices) | `populate_dev_uuids` (V-N1) |
| Nova | ≥1 **deleted** instance whose node record is gone, as well as a live one: `populate_instance_compute_id` does not filter `deleted` | V-N2 / N-R1 |
| Nova | Rows in `console_auth_tokens` (create a console, fake driver permitting) | `2903cd72dc14` |
| Nova | `block_device_mapping` rows also in `shadow_block_device_mapping` (archive a volume-backed deleted instance) | `ccb0fa1a2252` on shadow tables |
| Nova | `cell_mappings` rows with the exact URLs Kolla-Ansible stores (literal), and the lab name resolution that makes them reachable | CP-N3 / PC-N2 |
| Nova | Service rows: `nova-compute` rows for every fake compute, **stopped** (RT-B-02), plus one row for a compute that no longer exists | V-N8, DR-003 states (a)–(c) |
| Keystone | ≥1 trust with `expires_at` NULL and one with a value (NULLs never collide in the new unique constraint, which is part of what is tested) | `b4f8b3f584e0` |
| Keystone | ≥1 federation `mapping` row | `47147121` sets `schema_version='1.0'` (V-K2) |
| Keystone | ≥1 `service_provider` row, or "not covered" | `11c3b243b4cb` (V-K3) |
| Keystone | ≥1 `access_rule` (via an application credential with access rules) and a project with tags | `99de3849d860`, `c88cdce8f248` |
| Keystone | Thousands of `revocation_event` rows (cheap: revoke tokens in a loop) | `742c857f1dfb` index build timing |
| Neutron | ≥1 port-forwarding rule (floating IP + internal port) | `I43e0b669096` split of `socket`/`external_port` (V-Q4) |
| Neutron | ≥1 port whose binding profile contains `"trusted": "true"` (admin port create with `binding:profile`), and one without a profile | `5bcb7b31ec7d` (R-8, V-Q7) |
| Neutron | RBAC rows in `networkrbacs`, `qospolicyrbacs`, `securitygrouprbacs`, `subnetpoolrbacs`, `addressscoperbacs` | rename `target_tenant` → `target_project` (V-Q3) |
| Neutron | Tags with mixed case and non-ASCII characters | `d553edeb540f` collation conversion (V-Q8) |
| Neutron | `ha_router_networks` row (an HA router), or "not covered" | `682c319773d7` (PC-Q6) |
| Neutron | DHCP ports (any network with DHCP) | `fd6107509ccd` must change **none** of them under ML2/OVS (V-Q1) |
| Neutron | Record T0 counts of `portbindingports` and every existing `TABLES_TO_DROP` table (expected 0) | R-9, R-10 |
| Glance | ≥1 image with properties, members (shared), a community image, a hidden image, and ≥1 task with a result | object load at F2; `wallaby_expand01` (V-G1) |
| Placement | Every consumer with a project/user (no incomplete consumers at T0, PC-O1) | `create_incomplete_consumers` must find 0 |
| All | Ussuri ODM summary tables saved at T0, each "0 remaining" | baseline of V-N7, V-P3 |

**Not coverable in this lab (record, do not fake)**: libvirt-specific blobs (real `hw_machine_type`, CPU model,
`vcpu_model`), PCI/SR-IOV devices, OVN state, real Ceph/LVM-backed connection info. They remain `Not validated`
whatever the lab shows (Red Team §2.2 point 3). Tier B (production copy) is the only source for them.
