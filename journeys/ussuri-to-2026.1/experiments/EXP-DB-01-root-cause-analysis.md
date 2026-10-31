# EXP-DB-01 — Root-cause analysis (Stage 5 validation by Agent 4)

| Metadata | |
|---|---|
| Author | Agent 4 — Database and Messaging Specialist |
| Model | Opus (claude-opus-5-5) |
| Date | 2026-10-31 |
| Inputs | `EXP-DB-01-s2c-r1.md`, `EXP-DB-R0-schema-calibration.md`, `EXP-DB-N1-direct-2026.1.md`, `evidence/EXP-DB-01/`, `evidence/EXP-DB-R0/`; source at the cited refs **and release tags**; one reproduction in this lab |
| Lab work done | Cinder database of `backups-v2/latest` (read only: the cinder section of `openstack-databases.sql`) loaded into a new `mariadb:10.6` container `ufj-a4-db` (network `ufj-a4-net`, alias `ufj-mariadb`), with the rendered baseline `cinder.conf` and a connection-only override. Ran 2023.1 `cinder-manage db sync` + `online_data_migrations` (image `ufj-ff-2023.1:1`, cinder 22.3.0) with the MariaDB general log on; then 2024.1 `db sync` (`ufj-ff-2024.1:1`); then the fix candidate. Containers, network and the one anonymous volume were removed afterwards. `backups*/` and other agents' containers were not touched |
| Status | Finding 1: **`LAB-VALIDATED`** (reproduced; scope: Cinder DB only, Tier A v2 data, MariaDB 10.6, PyPI code, no Galera). The fix test used a **mixed environment** (cinder 23.5.0 wheel installed `--no-deps` over the 2023.1 dependency set), so the corrective step is `PROPOSED-UNVERIFIED` until it runs in a proper 2023.2 image. Findings 2–4: `DOCUMENTED-UNVERIFIED` (source reading) |

## 1. Cinder `use_quota` NULL at H2 (R1o)

### Reproduction

- Rows in the v2 baseline (`cinder.volumes`): 9 volumes, one of them soft-deleted:
  `8da0d66e-384d-4cdb-9fd5-4d799958f19d`, `deleted=1`, `status='deleted'`, `created_at 2026-10-31 11:23:19`,
  `deleted_at 11:23:24` (created and deleted through the Ussuri API by the baseline script). Snapshots: 2, none deleted.
  It is a **volume**, not a snapshot.
- 2023.1 `cinder-manage db sync`: legacy 136 → 145, stamp `921e1a36b076`, then `c92a3e68beed`, `daa98075b90d`; all
  9 volumes `use_quota = NULL`.
- 2023.1 `cinder-manage db online_data_migrations`: "8 rows matched … volume, 8 migrated; 2 … snapshot, 2 migrated".
  The deleted volume stays NULL. **The general log shows the SQL the ODM issued:**
  `… FROM volumes … WHERE volumes.deleted = false AND volumes.use_quota IS NULL`, so the ODM filtered out deleted rows.
- 2024.1 `cinder-manage db sync`: `b8660621f1b9` applied, then `9ab1b092a404` fails with
  `DBDataError (1265, "Data truncated for column 'use_quota' at row 6")`. That is the R1o failure, reproduced exactly. The
  failure is not atomic: `alembic_version` stays at `b8660621f1b9` and `migrate_version` is already dropped.

### Cause in code

The installed **cinder 22.3.0** (last 2023.1 release on PyPI, tag dated 2024-10-31) contains:

```python
# cinder 22.3.0: cinder/db/sqlalchemy/api.py:8707 (read from the ufj-ff-2023.1:1 image)
query = model_query(context, getattr(models, resource_name)).filter_by(use_quota=None)
```

`model_query` without `read_deleted` uses the context's default (`'no'`), which adds `deleted = false`. The
`read_deleted='yes'` the architect saw at `cinder@origin/unmaintained/2023.1:cinder/db/sqlalchemy/api.py:8700-8717`
was added **after** the last 2023.1 release:

| Commit | Branch | Merged | In a release? |
|---|---|---|---|
| `0a0c534a2` "[stable-2023.2-only] Fix online data migrations" (Related-Bug **#2070475**) | stable/2023.2 | 2025-03-06 | **cinder 23.5.0** (only 2023.2 tag containing it) |
| `a3c90fb4c` "[stable-only] Fix online data migrations" (cherry-pick; merge `1c00d6490`) | unmaintained/2023.1 | 2025-08-13 | **none**: after 22.3.0, and no later 2023.1 tag |

Commit message of `a3c90fb4c`: "Online data migrations have been ignoring deleted volumes and snapshots which causes
upgrade failures during a DB sync when upgrading to 2024.1 … This patch was earlier merged only to the non-SLURP 2023.2
branch … therefore when upgrading from 2023.1 to 2024.1 the bug reappears."

So:
- the explanation is not that 2023.2 code was skipped, and it is not batching, ordering or `deleted` type semantics. The **released 2023.1 Cinder has
  upstream bug #2070475**, fixed only in an unreleased branch commit;
- my earlier claims V-C1/PC-C1 (and the Red Team's V6) were read at the branch head, not at the release tag the lab
  installs. That is a method error, mine and shared. I re-checked the other migration-relevant paths at the release tags the lab
  installs: `git diff <tag> <branch>` of `nova/db`, `nova/objects/instance*.py` (27.5.1), `keystone/common/sql`
  (23.0.2), `placement/{db,objects,cmd}` (9.0.0), `glance/db` (26.1.0) are identical. `neutron/db/migration` (22.2.1)
  differs only in the `NEUTRON_MILESTONES` list. `cinder/db` 24.5.0 vs `unmaintained/2024.1` differs only in
  `_messages_get_query`. `nova/db` 29.4.0 vs branch differs only in `service_destroy`. None of these changes a migration or an ODM.
  The Cinder ODM is the only material tag/branch divergence found.

### Classification

**Upstream Cinder bug, not a lab artefact, and not specific to skipping releases.** It hits:
- the **officially supported SLURP path 2023.1 → 2024.1** with released 2023.1 Cinder (≤ 22.3.0), for any database with
  a soft-deleted volume or snapshot whose `use_quota` is NULL. That means every deployment that existed before Xena and
  deleted a volume before the bridge ODM ran;
- the non-SLURP staircase 2023.1 → 2023.2 → 2024.1 only if 2023.2 Cinder is older than 23.5.0;
- Kolla images: Kolla builds Cinder from the branch tarball (`kolla@2023.1-eol:kolla/common/sources.py`,
  `cinder-${openstack_branch}.tar.gz`), so a 2023.1 image built after 2025-08-13 contains the fix, and earlier ones do not.
  Whether such images exist anywhere reachable is unknown.

It is also a gap in our procedure: the frozen pre-check **PC-C1** ("0 NULL `use_quota` before any ≥ 2024.1 sync",
`fast-forward-checks.md`) counts all rows, deleted included. It would have stopped the run **before** H2 had it been
executed as a gate at H1. In R1o it ran in observe mode, so the run went on to the DataError.

### Corrective step for the procedure (proposed)

1. **Keep PC-C1 as a hard gate after the bridge**: `SELECT COUNT(*) FROM cinder.volumes WHERE use_quota IS NULL` and the same for
   `snapshots`, with no `deleted` filter. Both must be 0 before any ≥ 2024.1 Cinder code runs.
2. **Add a Cinder-only 2023.2 hop between H1 and H2, with released cinder 23.5.0** under the 2023.2 upper-constraints:
   `cinder-manage db sync` (applies `89aa6f9639f9`) then `cinder-manage db online_data_migrations` until 0. It uses a
   **released, upstream-tested fix** and follows Cinder's normal N+1 step. The other services stay on S2c.
   Lab evidence (mixed environment, see Status): on a copy at H1 it reported "1 rows matched … volume, 1 migrated", set the
   deleted volume to `use_quota=1`, and the 2024.1 `db sync` then completed through `9c74c1c6971f`, exit 0.
   It also recovered the copy left half-migrated by the failed 2024.1 run (at `b8660621f1b9`). That recovery is not a
   procedure to rely on: it was a 2023.2 ODM against a 2024.1-partial schema.
   Needed before adoption: build `ufj-ff-2023.2:1` properly (2023.2 u-c, cinder 23.5.0) and re-run R1 with that hop.
3. Alternative: build the 2023.1 bridge Cinder from `unmaintained/2023.1` at or after `1c00d6490`. This is not a released
   version and must be stated as a branch build. It is less preferable than step 2.
4. **`cinder-manage db purge` (baseline v3) is not a fix.** It permanently deletes soft-deleted rows and is a data-retention decision
   for the data owner. It removed the coverage item "deleted volume", so V-C1 for deleted rows is untested in R1c.
   Strict R1 should use v2 with step 2, not v3.
5. **Method fix** (all agents): migration and ODM claims must be read at the **exact release tag** that is installed. A
   branch head is valid only when the image is built from it.

## 2. Neutron SC-PC-Q5 (two `vlan/physnet1` segments on one network)

- **Migrations.** `neutron@origin/stable/2026.1:…/yoga/expand/e981acd076d3_*` adds
  `UNIQUE(network_id, network_type, physical_network)` with no de-duplication (release note
  `add-networksegments-uniq-constraint-89e52b42ca2f7ec2.yaml`: added "to prevent race conditions on dynamic segment
  allocation. Operators having networks with multiple segments (e.g. when using hierarchical portbinding) should check
  that this constraint is not violated with the included upgrade-check"). The 2023.1 revision `fc153938cdc1`
  (`eeff5b3c81`, "db: add segment_index to the unique constraint", Partial-Bug #1956435, #1764738) drops it and creates
  `UNIQUE(network_id, network_type, physical_network, segment_index)`.
- **Ussuri allows the data through the API in normal operation.** The ML2 multi-provider create path calls
  `check_duplicate_segments` (`neutron@ussuri-eol:neutron/plugins/ml2/managers.py:120`). In neutron-lib 2.3.0 (Ussuri u-c)
  that rejects only **fully identical** segments (`tuple(sorted(s.items()))`). Two VLAN segments on `physnet1` with
  different segmentation IDs are accepted, and ML2 stores them with `segment_index` = list position
  (`managers.py:214-218`). Dynamic segments (hierarchical port binding) can produce the same pattern. **Production may have
  such networks.** The routed-networks segment API was not checked.
- **Meaning.** Such rows satisfy the final 2026.1 constraint (their `segment_index` values differ) but cannot pass the Yoga
  intermediate constraint, which every path executes, the supported staircase included. This is an **upstream upgrade-path
  limitation**, not a fast-forward artefact.
- **Pre-check.** PC-Q5 as frozen is correct for the blocking constraint. Add an informational query that also shows
  `segment_index`, `is_dynamic` and the number of bound ports per offending network, so the remediation can be chosen.
- **Remediation.** API only, on Ussuri, before the window, as a separate reviewed change:
  - **static** duplicates: re-model the network (e.g. new network with distinct physnets or a single VLAN segment, ports
    moved), which affects workloads;
  - **dynamic** duplicates: they belong to port bindings and are released when the bindings go, so plan port unbinding or
    removal with the network owner.

  Do **not** delete or edit `networksegments` rows by SQL. No upstream tool for this exists in Neutron (searched the history of
  `origin/stable/2026.1`). If a network cannot be re-modelled, this is a **blocking item for any path** (S1 included) and goes
  to the architect as a decision.

## 3. R0 amendments A1–A6: cited causes

| Id | Cause (source) | Assessment for the Red Team |
|---|---|---|
| A1 Boolean `CHECK (col IN (0,1))` only in migrated | SQLAlchemy 1.3's `Boolean(create_constraint=True)` default (Ussuri u-c `SQLAlchemy===1.3.16`) vs `False` from 1.4 (2023.1 u-c 1.4.41). Agent 5 verified both signatures in the images. Ussuri DDL created the checks; squashed initial revisions run under 1.4/2.0 do not. The count drop H1 141 → H4 125 is Neutron tables dropped or rebuilt | **Accept.** Values are 0/1 anyway; the checks only reject what the ORM never writes |
| A2 `shadow_alembic_version` only in the reference (`nova`, `nova_cell0`) | `nova@origin/stable/2026.1:nova/db/main/migrations/versions/8f2f1571d55b_initial_version.py:55-60`: `_create_shadow_tables()` does `meta.reflect(bind=connection)` and copies **every** table except a fixed skip list that does not include `alembic_version`. In a fresh build, Alembic has already created `alembic_version` when the initial revision runs (line 1610), so it gets shadowed. In the bridged DB the initial revision is **stamped, not executed**, so no shadow copy exists | **Accept.** An artefact of the reference build: an unused table (nothing archives into it) |
| A3 `shadow_quota_usages.resource` nullable (migrated) vs NOT NULL (reference) | Same file, line 107: `if table_name == 'quota_usages' and column.name == 'resources':` should match column `resource`. The comment says legacy `247_nullable_mismatch` was not applied to shadow tables, so the shadow should be nullable, but the misspelled column name means the override never fires and the reference copies NOT NULL. The **migrated** schema is the historically intended one | **Accept.** Harmless: the main table is NOT NULL, so archiving never writes NULL |
| A4 Cinder `quota_usages` unique key named `quota_usages_project_id_key` (migrated) vs `project_id` (reference) | Migrated: legacy `141_add_quota_usage_unique_constraint` uses `migrate.changeset.constraint.UniqueConstraint` with no name. sqlalchemy-migrate 0.13.0 `UniqueConstraint.autoname()` returns `"%s_%s_key" % (table.name, colnames[0])`. Reference: `cinder@origin/stable/2026.1:cinder/db/migrations/versions/921e1a36b076_initial.py:488` `sa.UniqueConstraint('project_id','resource','race_preventer')` unnamed, so MariaDB names it after the first column | **Accept as name-only.** Risk: a future Cinder migration dropping it by a hard-coded name would behave differently between the two. None exists through 2026.1 |
| A5 `neutron.portbindingports` dropped at H1, not H2 | `yoga/expand/8160f7a9cebb` is a Yoga revision and runs whenever Neutron is migrated with ≥ Yoga code. With S2c step 10 kept, that is at H1. `declared-differences.md` R-9 should have read "H2 (H1)" like the other Neutron rows. **My omission**. R-10 (`054e34dbe6b4`, a 2024.1 revision) correctly stays at H2, and R1b showed only R-9 at H1 | **Accept** (correct R-9's hop column) |
| A6 `placement.projects`/`users` +1 row each in R0 | `placement@origin/unmaintained/2023.1:placement/objects/consumer.py:create_incomplete_consumers` calls `project_obj.ensure_incomplete_project(ctx)` and `user_obj.ensure_incomplete_user(ctx)` **before** looking for consumers to migrate, on every run. The same code exists in Ussuri. In R0 the Ussuri ODM never ran at T0 (empty schema, no ODM), so the first ODM run (2023.1) inserted the sentinel rows. In the data baseline the Ussuri ODM ran before T0, so the rows already exist, and R1c indeed shows no such difference | **Accept as an R0-only artefact.** Declare as "R0 only: +1 `projects`, +1 `users` (sentinel `incomplete_consumer_*`)". V-P3 stays valid for data runs |

## 4. Status-tool findings

| Finding | Production-relevant? | Evidence and recommendation |
|---|---|---|
| `cinder-status upgrade check` "Service UUIDs: Failure" | **Yes.** `cinder@origin/stable/2026.1:cinder/cmd/status.py:_check_service_uuid` fails when any **non-deleted** volume has `service_uuid` NULL. The Queens ODM that fills it derives the UUID from `volume.host`, so a volume that failed scheduling (status `error`, `host` NULL, like the lab's `a-boot`) can never get one. Any production cloud with such volumes reports FAILURE at every hop. The check is a false positive for host-less volumes (my reading; no upstream bug looked up) | Kolla-Ansible does not run `cinder-status` during upgrade (no match in `kolla-ansible@origin/stable/2026.1:ansible/roles/cinder/tasks/upgrade.yml`), so it does not block automation. Pre-check: count `volumes` with `deleted=0 AND service_uuid IS NULL`, split by `host IS NULL`. Remediation is an owner decision: delete the error volumes through the API, or record and accept the FAILURE with this explanation. Rows with `host` set but no UUID are a real problem (run the ODM) |
| `keystone-status` cannot run without the Fernet repository | **Lab artefact** for the failure. Its checks are production-relevant: trust policies not empty, default roles immutable, policy JSON (`keystone@origin/stable/2026.1:keystone/cmd/status.py`) | Mount a copy of the Fernet and credential key repositories read-only in the one-shot (the baseline holds them: `volumes/ufj-keystone-keys.tar.gz`) and re-run. In production the Keystone container has them. Kolla-Ansible does not run `keystone-status` in its upgrade either |

## 5. Summary of required changes

1. Cinder: add the 2023.2 hop (cinder 23.5.0) with PC-C1 as a hard gate; re-run strict R1 on baseline **v2** (not v3).
2. All claims: read source at the installed release tags.
3. PC-Q5: an upstream path limitation; add the informational query; remediation through the API or a decision by the architect.
4. R0 amendments: A1–A6 have cited causes. Corrections: R-9's hop column; A6 is R0-only.
5. C9: treat Cinder "Service UUIDs" for host-less error volumes as a declared, explained FAILURE or remediate it through the API.
   Re-run `keystone-status` with the key repositories mounted.
