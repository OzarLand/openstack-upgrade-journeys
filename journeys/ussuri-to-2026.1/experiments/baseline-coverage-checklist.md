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
