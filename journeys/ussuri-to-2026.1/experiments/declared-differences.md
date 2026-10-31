# Declared differences for the database fast-forward experiments (frozen before R1)

| Metadata | |
|---|---|
| Origin | Red Team RT-B-03(c) and RT-N-01 (`assessments/07-red-team-stage3-review.md`) |
| Author | Agent 4 — Database and Messaging Specialist |
| Model | Opus (claude-opus-5-5) |
| Date | 2026-10-31 |
| Amendments | **Amendment 1 (2026-10-31)**, §8: R0 items A1–A7 (Red Team Stage 5 rulings), Cinder hop H1b (DR-004), V-C1/V-C2 correction, step-10 decision, EXP-DB-02 pre-declaration. Items superseded in place are marked "~~…~~ → superseded by Amendment 1 / <id>"; nothing else in §0–§7 was changed |
| Status | `PROPOSED-UNVERIFIED`. The list is derived from migration source at `origin/stable/2026.1` and the bridge refs (`origin/unmaintained/2023.1`, `origin/unmaintained/2024.1`, `origin/stable/2025.1`). Nothing was executed. |
| Applies to | EXP-DB-01 (S2c), EXP-DB-02 (DB-level staircase, final checkpoint and the matching release checkpoints), EXP-DB-03 (S2a, final checkpoint), the idempotency re-run, EXP-RB-01 (inverse: Ussuri restore must equal T0 exactly) |
| Companion | `experiments/fast-forward-checks.md` (pre-checks, config parity, named stop conditions) |

## 0. Rules

1. **Freeze.** This file is frozen before R1 starts. One amendment is allowed, from the **R0 schema calibration run**
   (§3.3). R0 runs on an empty Ussuri schema (no rows), so it cannot learn anything from R1's data. It must happen and be
   reviewed before R1. After R1 starts, nothing is added for the runs in progress.
2. **Stop.** In any run, a schema difference, row-count change or fingerprint change that is not listed here is a stop
   condition (strategy §5.8). The run is recorded as `FAILED` for that checkpoint. A later amendment
   applies only to new runs and must say why the earlier stop was not a defect.
3. **Precision.** An entry names the database, the table (and column where relevant), the hop that causes it, the
   revision or online-migration function responsible (with source), and the expected direction or value. "Something in Neutron
   changed" is never a declaration.
4. **Minimal exclusions.** Every normalisation exclusion (§2) is also a place where a real defect would be hidden.
   Exclusions are column- and row-scoped. None is table-wide except bookkeeping tables, which are checked separately.

## 1. Checkpoints

| Id | State | Code that last wrote the DB |
|---|---|---|
| T0 | Ussuri baseline after Ussuri online migrations completed (exit 0) | Ussuri |
| H1 | after 2023.1 `db sync` (+ Cinder and Nova ODMs) | 2023.1 |
| H2 | after 2024.1 `db sync` + ODMs | 2024.1 |
| H3 | after 2025.1 `db sync` + ODMs | 2025.1 |
| H4 | after 2026.1 `db sync` + ODMs | 2026.1 |
| H4r | after a **second** 2026.1 `db sync` + ODMs on H4 (idempotency, RT-B-03(b)) | 2026.1 |

At each Hn there are two comparisons: (A) **migrated vs reference**, the schema built fresh by the same code on the same
server (`<db>_ref`), and (B) **migrated vs T0**, for row counts and fingerprints.

Glance, Placement and Neutron: if S2c step 10 is dropped (RT-N-11, default), their revisions first run at H2. The
"first executed at" column gives both variants: `H1 / H2` = with step 10 / without.

## 2. Comparison method and normalisation exclusions

### 2.1 Schema (comparison A)

The decision is based on `information_schema`, which is deterministic and sorted. `mariadb-dump --no-data` is kept only as a
human-readable artefact. Run against the migrated DB and against `<db>_ref` **on the same server
instance**, so that defaults and collation names are rendered identically:

```sh
# $DB = migrated schema name, run twice: once for $DB, once for ${DB}_ref; outputs schema/$DB.*.tsv
q() { mariadb --batch --skip-column-names -e "$1"; }
q "SELECT TABLE_NAME,ENGINE,TABLE_COLLATION FROM information_schema.TABLES WHERE TABLE_SCHEMA='$DB' AND TABLE_TYPE='BASE TABLE' ORDER BY 1"                                  > tables.tsv
q "SELECT TABLE_NAME,COLUMN_NAME,COLUMN_TYPE,IS_NULLABLE,COLUMN_DEFAULT,CHARACTER_SET_NAME,COLLATION_NAME,EXTRA FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$DB' ORDER BY 1,2" > columns.tsv
q "SELECT TABLE_NAME,INDEX_NAME,NON_UNIQUE,SEQ_IN_INDEX,COLUMN_NAME,IFNULL(SUB_PART,'') FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='$DB' ORDER BY 1,2,4"         > indexes.tsv
q "SELECT k.TABLE_NAME,k.CONSTRAINT_NAME,k.ORDINAL_POSITION,k.COLUMN_NAME,IFNULL(k.REFERENCED_TABLE_NAME,''),IFNULL(k.REFERENCED_COLUMN_NAME,''),IFNULL(r.UPDATE_RULE,''),IFNULL(r.DELETE_RULE,'')
   FROM information_schema.KEY_COLUMN_USAGE k LEFT JOIN information_schema.REFERENTIAL_CONSTRAINTS r
     ON r.CONSTRAINT_SCHEMA=k.CONSTRAINT_SCHEMA AND r.CONSTRAINT_NAME=k.CONSTRAINT_NAME AND r.TABLE_NAME=k.TABLE_NAME
  WHERE k.TABLE_SCHEMA='$DB' ORDER BY 1,2,3"                                                                                                                                      > keys.tsv
q "SELECT TABLE_NAME,CONSTRAINT_NAME,CHECK_CLAUSE FROM information_schema.CHECK_CONSTRAINTS WHERE CONSTRAINT_SCHEMA='$DB' ORDER BY 1,2"                                          > checks.tsv
q "SELECT EVENT_OBJECT_TABLE,TRIGGER_NAME,ACTION_TIMING,EVENT_MANIPULATION FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='$DB' ORDER BY 1,2"                             > triggers.tsv
q "SELECT TABLE_NAME FROM information_schema.VIEWS WHERE TABLE_SCHEMA='$DB' UNION ALL SELECT ROUTINE_NAME FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='$DB'"           > other.tsv
# then: diff -u ref/<file> migrated/<file>  (the reference's schema name is substituted to $DB before diffing)
```

A second, **name-insensitive** pass rewrites index and constraint names to `<table>:<sorted column list>:<type>`
and diffs again. Comparison A therefore yields two lists:
- **structural differences**: must each match an S-entry (§3);
- **name-only differences**: listed individually as S-N entries after R0. They are not ignored, because later migrations drop
  constraints and indexes by name (e.g. Keystone `99de3849d860`, Neutron `fc153938cdc1`).

### 2.2 Row counts and fingerprints (comparison B)

- Row counts: exact `SELECT COUNT(*)` for **every** base table of every database (table list from
  `information_schema.TABLES`), never `TABLE_ROWS`.
- Fingerprints: **per row**, for every table that exists at T0, over **all columns that exist at T0** minus the exclusions
  of §2.3, keyed by primary key. Written sorted to a file and diffed. That shows *which* rows changed, not only that
  something did:

```sql
-- generated per table from information_schema.COLUMNS at T0 (column list frozen at T0, renames mapped per §5)
SELECT CONCAT_WS(':', <pk cols>) AS k,
       SHA2(CONCAT_WS(0x1F, COALESCE(<c1>,0x00), COALESCE(<c2>,0x00), ...), 256) AS h
  FROM <db>.<table> ORDER BY k;
```

  BLOB/TEXT columns (`request_specs.spec`, `instance_extra.*`, `ml2_port_bindings.profile`, `credential.encrypted_blob`,
  `image_properties.value`, …) are hashed whole. Tables without a primary key use all T0 columns as the key.
- Columns added by a migration are not in the T0 column list. Their **values** are checked by the targeted queries
  given in §4–§5 (e.g. `use_quota` distribution, `compute_id` coverage).
- Seed rows created by migrations, like the Neutron default SG rule templates and the Cinder default quota classes, are additionally compared
  **migrated vs reference** on their non-random columns (§5).

### 2.3 Normalisation exclusions (complete list)

| Id | Excluded | Scope | Why it is legitimate | What it could hide |
|---|---|---|---|---|
| N-1 | `AUTO_INCREMENT` table option and `TABLE_ROWS`, `DATA_LENGTH`, `INDEX_LENGTH`, `CREATE_TIME`, `UPDATE_TIME` | schema (A) | Counters and statistics, not structure | nothing structural |
| N-2 | Column ordinal position (`ORDINAL_POSITION`; columns compared as a sorted set) | schema (A) | `ADD COLUMN` appends; squashed initial migrations declare columns in another order; the ORM addresses columns by name | a `SELECT *`-dependent consumer outside OpenStack (record whether any exists) |
| N-3 | `updated_at` | rows of tables written by an online migration or a data migration: Nova `instances`, `pci_devices`; Cinder `volumes`, `snapshots`, `volume_admin_metadata`, `quota_classes`, `quotas`, `quota_usages`, `reservations`; Neutron `ports`, `ml2_port_bindings`, `network_segment_ranges`, `tags` (via `standardattributes`); everywhere **only** for rows whose other columns match T0 or a declared transformation | ORM `onupdate` sets it when an ODM saves a row | an unexpected write that changed only `updated_at` (detected anyway by H4r, where nothing may change) |
| N-4 | `created_at` / `deleted_at` of rows **created or soft-deleted by a migration**: Cinder `quota_classes` rows of §5 C-5 (`created_at = datetime.now()`), rows soft-deleted by C-6 and C-9 (`deleted_at = utcnow()`) | those rows only, identified by key | wall-clock values set at migration time | nothing else; their presence and non-time columns are checked |
| N-5 | Migration-time random identifiers: `neutron.securitygroupdefaultrules.id` (`uuidutils.generate_uuid()`) and the `standard_attr_id` / `standardattributes.id` of the four rows created with them; `nova.pci_devices.uuid` values filled by `populate_dev_uuids` | those rows/columns only | generated at run time, so they differ between runs and from the reference | duplicates (checked: UUIDs unique and non-NULL) |
| N-6 | Bookkeeping tables `alembic_version`, `alembic_version_*` (Neutron sub-projects), `migrate_version` | data (B) | checked separately by C2/C3 against the code heads and §3 S-1 | nothing; they have their own check |

Nothing else is normalised. In particular: no blanket ignore of `deleted`, no ignore of `created_at` on pre-existing rows,
no case- or whitespace-folding of values, no ignore of index or constraint names.

### 2.4 Idempotency (H4 → H4r)

Comparison of H4r against H4: **zero** schema difference (including names, without N-2) and **zero** row difference
(including `updated_at`, i.e. without N-3/N-4). Every `db sync` exits 0. Every ODM reports `0` found or only the residues
already declared in §4 N-R1 and exits 0. Any change is a stop.

### 2.5 Rollback rehearsal (EXP-RB-01)

The Ussuri restore from the pre-bridge dump must equal T0 **exactly**: comparison A and B with no exclusions except N-1.

## 3. Declared schema differences, migrated vs reference (comparison A)

### 3.1 Bookkeeping tables

| Id | Database | Hops | Difference | Source |
|---|---|---|---|---|
| S-1a | `nova`, `nova_cell0`, `nova_api`, `cinder` | H1 only (cinder: H1 only; ~~dropped at H2~~ → superseded by Amendment 1 / AM1-H1b: dropped at **H1b**) | Migrated has `migrate_version` (reference built by 2023.1 alembic does not). Rows: `nova` 422, `nova_api` 87 (legacy repos run to their last placeholder), `cinder` 145 | `nova@origin/unmaintained/2023.1:nova/db/migration.py` (`migrate_api.upgrade` then `stamp`); `cinder@origin/unmaintained/2023.1:cinder/db/migration.py` |
| S-1b | same | H2–H4 | **No difference**: dropped by `1b91788ec3a6`, `cdeec0c85668` (Nova), `89aa6f9639f9` (Cinder), all guarded `if 'migrate_version' in tables` | `nova@origin/stable/2026.1:nova/db/{main,api}/migrations/versions/`; `cinder@origin/stable/2026.1:cinder/db/migrations/versions/89aa6f9639f9_*.py` |
| S-1c | `keystone` | H1–H4 (**persistent**) | Migrated keeps `migrate_version`. Rows for `keystone_expand`, `keystone_data_migrate`, `keystone_contract` = 79, plus any row of the old Ussuri `keystone` repo (109) present at T0. No Keystone Alembic revision references `migrate_version` (searched every file under `keystone@origin/stable/2026.1:keystone/common/sql/migrations/versions/`) | as cited |
| S-1d | `glance`, `placement`, `neutron` | H1–H4 | If `migrate_version` exists at T0 it persists; none of their Alembic revisions drops it (searched `glance@…/alembic_migrations/`, `placement@…/alembic/versions/`). Expected absent at T0 for Placement and Neutron; for Glance record at T0 | as cited |

### 3.2 Structural differences predicted from source

| Id | Database | Hops | Difference | Status |
|---|---|---|---|---|
| S-2 | `glance`, `placement`, `neutron` | H1–H4 | ~~**None.**~~ → superseded by Amendment 1 / A7 (S-2.1: one transient enum difference at H2; DDL built from library constants is release-dependent). Otherwise: **None.** The reference is built by running the same complete script chain from the first revision (`liberty_initial`, `b4ed3a175331_initial`, `kilo_initial`), so migrated and reference execute identical DDL; only the data present differs | prediction; any structural diff here = stop |
| S-3 | `nova`, `nova_cell0`, `nova_api`, `keystone`, `cinder` | H1–H4 | Possible differences between a schema built by Ussuri-era legacy DDL (SQLAlchemy 1.3) and one built by the squashed Alembic initial revisions. Candidate classes: (i) Boolean `CHECK (col IN (0,1))` constraints created by SQLAlchemy 1.3 `Boolean` types at T0 that the reference does not have; (ii) index/constraint naming (→ S-N list); (iii) server defaults rendered differently. **Only differences observed in R0 and explained by a cited revision or SQLAlchemy behaviour may be declared** (§3.3) | candidate classes, not declarations |

### 3.3 R0 calibration (the single allowed amendment)

R0 = the full S2c path on an **empty** Ussuri schema, created with Ussuri tools only (`db sync` of each service; Nova
`cell_v2 map_cell0`/`create_cell`; no rows beyond what the migrations seed), followed by comparison A at H1–H4. For each
difference R0 shows, Agent 4 writes an S-3.x or S-N.x entry here with its cause. A Red Team reviewer accepts or rejects each
entry before R1. A difference whose cause cannot be cited is not declared: it blocks R1 until explained. Because R0 holds no
rows, it cannot absorb data-dependent defects into the list.

*Amendment section (to be filled after R0, before R1):*

| Id | Database.table | Difference | Cause (source) | Accepted by / date |
|---|---|---|---|---|
| A1–A7 | see **§8 Amendment 1** | | | Red Team `assessments/07-red-team-stage5-results-review.md` §2, 2026-10-31 |

## 4. Declared row-count changes vs T0 (comparison B)

"Δ" is the change in `COUNT(*)` against T0. Every table not listed must have Δ = 0.

| Id | Database.table | Δ | First executed at | Cause (source) |
|---|---|---|---|---|
| R-1 | `nova.migrate_version`, `nova_cell0.migrate_version`, `nova_api.migrate_version`, `cinder.migrate_version` | table gone (H2+) | H2 (cinder: ~~H2~~ → **H1b**, Amendment 1 / AM1-H1b) | S-1b |
| R-2 | `nova.alembic_version`, `nova_cell0.alembic_version`, `nova_api.alembic_version`, `keystone.alembic_version` (2 rows), `cinder.alembic_version` | new table | H1 | auto-stamp at the bridge |
| R-3 | `nova_api.build_requests` | 0 (precondition PC-N3: no rows at T0) | H1 | `b30f573d3377` drops 15 columns |
| R-4 | `cinder.default_volume_types` | new, 0 rows | H1 | legacy `140` |
| R-5 | `cinder.quota_classes` | **+0 to +2** (`default`/`backups`, `default`/`backup_gigabytes`, each only if no non-deleted row exists) | H2 | `9c74c1c6971f`. Exact Δ predicted from T0 (`SELECT resource FROM quota_classes WHERE class_name='default' AND deleted=0`) and written into the run record **before** H2 |
| R-6 | `neutron.securitygroupdefaultrules` | new, **4** rows | H2 | `2023.2/expand/c33da356b165` (only if the table does not exist; it does not at T0) |
| R-7 | `neutron.standardattributes` | **+4** (`resource_type='securitygroupdefaultrules'`) | H2 | same |
| R-8 | `neutron.porttrusted` | new; rows = number of `ml2_port_bindings` whose JSON profile has a `trusted` key at T0 (count predicted at T0) | H3 | `2024.2/expand/5bcb7b31ec7d` |
| R-9 | `neutron.portbindingports` | table dropped; precondition PC-Q2: **0 rows at T0** | ~~H2~~ → **H1** with step 10 (Amendment 1 / A5) | `yoga/expand/8160f7a9cebb` |
| R-10 | Neutron legacy plugin tables in `TABLES_TO_DROP` (Cisco, VMware, Brocade, Nuage, `cisco_csr_identifier_map`) that exist at T0 | tables dropped; precondition PC-Q3: **0 rows** in each | H2 | `2024.1/expand/054e34dbe6b4` |
| R-11 | `neutron.network_segment_ranges` | **−d**, where d = duplicates per (`default`, `network_type`, `IFNULL(physical_network,'')`, `minimum`, `maximum`) minus one, computed at T0. **Production and main runs: d must be 0** (PC-Q4). Non-zero only on the N3 negative copy | H4 | `2026.1/expand/b1bca967e19d` (`clear_duplicate_values`) |
| R-12 | `glance.node_reference`, `glance.cached_images` | new, 0 rows | H2 (H1) | `2024_1_expand01_add_cache_tables` |
| R-13 | `placement.consumer_types` | new, 0 rows | H2 (H1) | `422ece571366` |
| R-14 | `nova.share_mapping`, `nova_cell0.share_mapping` | new, 0 rows | H2 | `13863f4e1612` (recreated by `d60bddf7a903` at H3) |
| R-15 | Neutron tables created empty by post-Ussuri revisions (e.g. `address_groups`, `addressgrouprbacs`; the full list is **generated** by diffing the T0 table list against the reference schema at each hop, not written by hand) | new, 0 rows | H2 (H1) | revisions under `neutron@origin/stable/2026.1:neutron/db/migration/alembic_migrations/versions/{victoria … 2026.1}/expand/`; every new table must have 0 rows except R-6 and R-8 |

## 5. Declared value transformations vs T0 (fingerprint changes)

Every changed row in a T0 table must be explained by one of these entries. The listed checks run at the hop given.

### Nova (`nova`, `nova_cell0`, `nova_api`)

| Id | Table.column | Hop | Transformation | Check | Source |
|---|---|---|---|---|---|
| V-N1 | `pci_devices.uuid` | H1 | NULL → random UUID (N-5) | after: `COUNT(*) WHERE uuid IS NULL` = 0; UUIDs unique; rows changed = rows NULL at T0 | `PciDevice.populate_dev_uuids` (`nova/objects/pci_device.py`), in the ODM tuple from Wallaby to 2026.1 |
| V-N2 | `instances.compute_id` (new column) | H2 | NULL → `compute_nodes.id` matching (`host`, `node`), **including deleted instance rows** (the query does not filter `deleted`). Not a T0 column, so no fingerprint change except `updated_at` (N-3) | after: residue `COUNT(*) WHERE compute_id IS NULL` = number of T0 instances whose (`host`,`node`) has no `compute_nodes` row (predicted at T0, includes ERROR-without-host instances; **N-R1**) | `instance_obj.populate_instance_compute_id` (`nova/objects/instance.py`), in the tuple from 2023.2 |
| V-N3 | `migrations.dest_compute_id`, `shadow_instances.compute_id`, `shadow_migrations.dest_compute_id` (new) | H2 | stay NULL for existing rows (no ODM fills them) | `COUNT(*) WHERE … IS NOT NULL` = 0 | `1acf2c98e646` |
| V-N4 | `block_device_mapping` (+ shadow) `encrypted`, `encryption_*` (new) | H1 | NULL | — | `ccb0fa1a2252` |
| V-N5 | `console_auth_tokens.tls_port` (new) | H3 | NULL | — | `2903cd72dc14` |
| V-N6 | `nova_api.build_requests` dropped columns | H1 | values lost; allowed only because PC-N3 requires 0 rows | — | `b30f573d3377` |
| V-N7 | Every Ussuri ODM (`migrate_quota_*`, `migration_migrate_to_uuid`, `BlockDeviceMapping.populate_uuids`, `populate_missing_availability_zones`, `populate_queued_for_delete`, `migrate_empty_ratio`, `fill_virtual_interface_list`, `populate_user_id`) | H1–H4 | **No change**: T0 is taken after the Ussuri ODMs reached exit 0, so they must report 0 found | ODM summary tables: 0 for each at every hop | `nova@ussuri-eol:nova/cmd/manage.py` |
| V-N8 | `services`, `compute_nodes` | H1–H4 | **No change** in DB-only hops (no migration or ODM writes them). Changes from EXP-SVC (version bump to 72, `forced_down` per DR-003) are outside this file and recorded by EXP-SVC-01 | fingerprint = T0 | — |

### Cinder

| Id | Table.column | Hop | Transformation | Check | Source |
|---|---|---|---|---|---|
| V-C1 | `volumes.use_quota` (new, legacy `145`) | H1 | NULL → `False` if `migration_status LIKE 'target:%'` or a **non-deleted** admin-metadata row `temporary='True'`; otherwise `True`. ~~Applied to deleted rows as well (`read_deleted='yes'`)~~ → superseded by Amendment 1 / V-C1a, V-C1b (22.3.0 skips deleted rows; they are migrated at H1b by 23.5.0) | ~~after H1: 0 NULL~~ → see V-C1a/V-C1b; the predicted False/True split computed at T0 matches exactly | `cinder@origin/unmaintained/2023.1:cinder/db/sqlalchemy/api.py:volume_use_quota_online_data_migration` |
| V-C2 | `snapshots.use_quota` (new) | H1 | NULL → `True` for **every** snapshot, ~~including deleted and~~ temporary backup snapshots (the code states it cannot identify temporary snapshots) → deleted snapshots: superseded by Amendment 1 / V-C2a, V-C2b | ~~0 NULL~~; all True (see V-C2a/V-C2b) | `snapshot_use_quota_online_data_migration` |
| V-C3 | `use_quota` nullability | H2 | becomes NOT NULL, `server_default` true | schema vs reference; no NULL present before H2 (else stop: PC-C1) | `9ab1b092a404` |
| V-C4 | `quota_usages.race_preventer` (new, legacy `141`) | H1 | NULL for existing rows | — | legacy `141` |
| V-C5 | `quota_classes` rows of R-5 | H2 | inserted, `hard_limit` = one-shot config `quota_backups` / `quota_backup_gigabytes` (must equal production: config parity CP-C1), `created_at = datetime.now()` (local time of the container, N-4) | non-time columns equal to the predicted values and to the reference's seed rows | `9c74c1c6971f` |
| V-C6 | `quota_classes`, `quotas`, `quota_usages`, `reservations` rows with `resource='consistencygroups'` and `deleted=0` | H2 | soft-deleted: `deleted=1`, `deleted_at=utcnow()` (N-4); `quota_usages` also `race_preventer=NULL` | rows changed = predicted set at T0 | `b7b88f50aab5`; `cinder/db/sqlalchemy/models.py` `delete_values()` |
| V-C7 | `quotas`, `quota_classes`, `reservations` `.resource` | H2 | type widened to `VARCHAR(300)`; values unchanged | values equal T0 | `b8660621f1b9` (on error it only logs; then the schema diff shows it: stop) |
| V-C8 | `volumes.shared_targets` | H1 | becomes nullable; values unchanged | values equal T0 | `c92a3e68beed` |
| V-C9 | `volume_admin_metadata` rows with `key='temporary'` and `deleted=0` | H2 (first hop running 2024.1 ODMs) | soft-deleted (`deleted=1`, `deleted_at`, N-4). **Ordering consequence:** this erases the information V-C1 needs, so V-C1 must have completed at H1 (PC-C1) | rows changed = predicted set at T0 | `remove_temporary_admin_metadata_data_migration` (`cinder@origin/stable/2026.1:cinder/db/sqlalchemy/api.py`), in the tuple from 2024.1 |

### Keystone

| Id | Table.column | Hop | Transformation | Source |
|---|---|---|---|---|
| V-K1 | Legacy `079_*_update_local_id_limit` | H1 | **Only if T0 is at 078** (PyPI 17.0.1, RT-N-04): applied at the bridge. Record the T0 version. The schema effect is checked by comparison A; values unchanged | `keystone@origin/unmaintained/2023.1:keystone/common/sql/legacy_migrations/*/versions/079_*` |
| V-K2 | `mapping.schema_version` (new, NOT NULL, `server_default '1.0'`) | H2 | `'1.0'` for every existing mapping | `2024.1/expand/47147121_*` |
| V-K3 | `service_provider.relay_state_prefix` | H2 | server default removed; values unchanged | `bobcat/expand/11c3b243b4cb_*` |
| V-K4 | `trust`, `access_rule`, `project_tag` constraints and indexes | H2 | schema only; values unchanged; **fails if duplicate trusts exist** (PC-K1) | `bobcat/expand/b4f8b3f584e0_*`, `bobcat/contract/99de3849d860_*`, `c88cdce8f248_*` |
| V-K5 | `project_endpoint_group`, `revocation_event` indexes | H4 | schema only | `2025.2/expand/e8725d6fa226_*`, `2026.1/expand/742c857f1dfb_*` |
| V-K6 | `credential.encrypted_blob`, `password.password_hash` | all | **No change.** Hasher migration happens at login, not in the DB migration; credential re-encryption is a separate command not run here | fingerprint = T0 |

### Glance

| Id | Table.column | Hop | Transformation | Source |
|---|---|---|---|---|
| V-G1 | `tasks.user_id`, `tasks.image_id`, `tasks.request_id` (new) | H2 (H1) | NULL for existing tasks | `wallaby_expand01_add_user_imageid_requestid_to_tasks` |
| V-G2 | `image_locations.meta_data` and everything else | all | **No change.** 2026.1 runs no data migration (`CURRENT_RELEASE='2026_1'` has no module); post-Ussuri modules all `has_migrations() → False` | `glance@origin/stable/2026.1:glance/db/sqlalchemy/alembic_migrations/data_migrations/` |

### Placement

| Id | Table.column | Hop | Transformation | Source |
|---|---|---|---|---|
| V-P1 | `consumers.consumer_type_id` (new) | H2 (H1) | NULL for existing consumers | `422ece571366` |
| V-P2 | index drops on `inventories`, `placement_aggregates`, `resource_providers` | H2 | schema only | `a082b8bb98d0` |
| V-P3 | ODMs `set_root_provider_ids`, `create_incomplete_consumers` | all | **No change** (completed on Ussuri before T0) | `placement@origin/stable/2026.1:placement/cmd/manage.py` |

### Neutron

| Id | Table.column | Hop | Transformation | Source |
|---|---|---|---|---|
| V-Q1 | `ports.device_owner` | H2 (H1) | `network:dhcp` → `network:distributed` where `device_id LIKE 'ovnmeta%'`. Predicted count at T0; expected 0 with ML2/OVS | `victoria/expand/fd6107509ccd_*` |
| V-Q2 | `address_groups` (+ `standard_attr_id`, `description` dropped) | H2 (H1) | table did not exist at Ussuri, so no rows; nothing to transform | `victoria/expand/1ea5dab0897a_*`, `wallaby/expand/26d1e9f5c766_*` |
| V-Q3 | RBAC tables (`networkrbacs`, `qospolicyrbacs`, `securitygrouprbacs`, `addressscoperbacs`, `subnetpoolrbacs`; `addressgrouprbacs` is empty): column `target_tenant` → `target_project` | H2 (H1) | **rename**; fingerprints map `target_tenant`(T0) to `target_project` (values identical) | `yoga/expand/1ffef8d6f371_*` |
| V-Q4 | `portforwardings`: `socket` → `internal_ip_address` + `internal_port_start/end`; `external_port` → `external_port_start/end`; old columns dropped | H2 (H1) | the new columns must equal the split of the T0 values (`socket = ip:port` → start = end = port; `external_port` → start = end); verified per row | `zed/expand/I43e0b669096_*` (`migrate_values`) |
| V-Q5 | `subnets.in_use` | H2 | column dropped; values lost (transient flag) | `2023.2/expand/93f394357a27_*` |
| V-Q6 | R-6/R-7 seed rows | H2 | four template rules (ingress/egress × IPv4/IPv6 as in `default_template_rules`). Non-random columns equal the reference's four rows; `id`, `standard_attr_id` excluded (N-5) | `2023.2/expand/c33da356b165_*` |
| V-Q7 | `ml2_port_bindings.profile` | H3 | for rows whose JSON has `trusted`: key removed (profile becomes `''` if then empty); value moved to `porttrusted.trusted` (`bool_from_string`) | `2024.2/expand/5bcb7b31ec7d_*` |
| V-Q8 | `tags` | H4 | table converted to `utf8mb4` / `utf8mb4_bin`. Values byte-equal to T0 (compare `HEX(tag)`), row count equal | `2025.2/expand/d553edeb540f_*` |
| V-Q9 | `network_segment_ranges.physical_network` | H4 | NULL → `''`; column NOT NULL, default `''`; plus R-11 deletions (0 in main runs) | `2026.1/expand/b1bca967e19d_*` |
| V-Q10 | `quotas`, `networksegments`, `ha_router_networks` | H2 | new unique constraints only; **fail on duplicates** (PC-Q1, PC-Q5, PC-Q6); values unchanged | `wallaby/expand/f010820fc498_*`, `yoga/expand/e981acd076d3_*` + `2023.1/expand/fc153938cdc1_*`, `2023.2/expand/682c319773d7_*` |

## 6. Residues that are declared, not failures

| Id | Residue | Expected size | Rule |
|---|---|---|---|
| N-R1 | Nova `populate_instance_compute_id` "found but not migrated" rows (instances whose (`host`,`node`) has no `compute_nodes` row, incl. ERROR-without-host) | equal to the T0 prediction | ODM exit code at H2–H4 is 0 when nothing else is pending; if the tool reports these rows as "found" on every run, that is recorded, not forced. Any other residue = stop |

## 7. Open points

- S-3 candidate classes are predictions until R0 shows them.
- Exact list for R-15 is produced from the reference schema at each hop, not by hand.
- Whether `nova-manage db online_data_migrations` returns 0 or 1 when only N-R1 residues remain is not determined from
  source here; R1 records it, and the rule above applies.

## 8. Amendment 1 (2026-10-31)

| Field | Value |
|---|---|
| Date | 2026-10-31 |
| Author | Agent 4 (owner of this list) |
| Triggers | (1) EXP-DB-R0 calibration findings A1–A6 and the Red Team's added A7; (2) EXP-DB-01 R1o failure at H2 (Cinder `9ab1b092a404`), root cause in `experiments/EXP-DB-01-root-cause-analysis.md`, decision **DR-004** (Cinder-only 2023.2 step + PC-C1 hard gate); (3) Red Team RT-B-08, RT-B-09, RT-N-11, RT-N-22, RT-N-23 |
| Ruling reference | `assessments/07-red-team-stage5-results-review.md` §2 (A1 ACCEPT-WITH-CONDITION, A2 ACCEPT, A3 ACCEPT-WITH-CONDITION, A4 ACCEPT-WITH-CONDITION, A5 ACCEPT after step-10 decision, A6 ACCEPT-WITH-CONDITION, A7 DECLARE), §4.3, §5 |
| Effect on runs | Applies to runs started **after** this amendment. Runs already made (R1, R1b, R1o, R1c) keep their `FAILED` status (rule 0.2). The comparator (`ff/tools/compare.py`) is part of the frozen artefact from now on (Red Team §6): any change to it is a dated amendment here, and live outputs stay immutable |
| Rule 0.1 note | The R0 amendment window is used once, here. AM1-H1b, AM1-VC and AM1-S10 are not R0 items: they follow a decision record (DR-004) and a source-verified correction, and are dated as such. They declare nothing that a run has already shown as undeclared, except the Cinder items, whose failure stays recorded |

### 8.1 Step-10 decision (RT-N-11 / A5): **keep step 10**

Glance, Placement and Neutron are migrated at **every** hop (H1 = 2023.1, H2, H3, H4), as `ff/30-hop.sh` already does
and as R0/R1b/R1c were run. Reasons:

1. All services sit on the same release at every checkpoint, so every checkpoint is a coherent database set for
   inspection and for rollback rehearsal (EXP-RB-01).
2. Every service passes through the SLURP releases 2023.1 → 2024.1 → 2025.1, the upstream-supported skip chain.
3. The existing calibration (R0) and data runs were made this way. Dropping step 10 would require a new R0 (Red Team A5).
4. Cost: about 10 s per hop, plus the transient A7 class, which converges at H3.

Consequences: for Glance, Placement and Neutron, the "first executed at" column reads the **H1** variant wherever the frozen
text gives "H2 (H1)". The comparator must use that variant (R-9 at H1; R-10, R-6, R-7 remain H2 because their revisions are
2023.2/2024.1). If the architect overrides this decision, A5 and A7 are void, R0 must be re-run and this section is superseded
by a new amendment.

### 8.2 R0 items A1–A7

| Id | Entry | Hops | Declaration (exact) | Cause (source) | Conditions (Red Team) and how they are met | Accepted by / date |
|---|---|---|---|---|---|---|
| **A1** → S-3.1 | Boolean `CHECK (col IN (0,1))` present only in the migrated schema | H1 (141) → H2…H4r (125); permanent, also in Tier B | Exactly the per-column list of §8.7. At each hop the only allowed change to the set is the **disappearance** of a listed constraint whose column or table is dropped by a cited revision. The 16 that disappear between H1 and H2 are struck through in §8.7: 15 on tables dropped by `054e34dbe6b4` (R-10) and `subnets.in_use` dropped by `93f394357a27` (V-Q5). Any CHECK not in §8.7, or an addition, is a stop | Ussuri u-c `SQLAlchemy===1.3.16` (`Boolean(create_constraint=True)` default) vs `1.4.41`+ from 2023.1 (`False`). Nova's squashed revisions spell `create_constraint=False` (`8f2f1571d55b_initial_version.py:253,1045,…`). Cinder's initial keeps `create_constraint=True` on some `deleted` columns (`921e1a36b076_initial.py:87,109,…`), so the class is **per column, not a rule** | (1) per-column list: §8.7, extracted from `evidence/EXP-DB-R0/H1/schema-diff.txt` and `H4/schema-diff.txt` (H2 = H3 = H4 = H4r verified identical); (2) disappearances written down: §8.7; (3) EXP-DB-02 pre-declaration: §8.5; (4) permanent: yes | Red Team Stage 5 §2, 2026-10-31 |
| **A2** → S-3.2 | `shadow_alembic_version` (table, `version_num`, PK) only in the reference | `nova`, `nova_cell0`, H1–H4r | Reference-only table, 0 rows | `nova@origin/stable/2026.1:nova/db/main/migrations/versions/8f2f1571d55b_initial_version.py:55-60` (`_create_shadow_tables`: `meta.reflect()` of every table, skip list without `alembic_version`; called at line 1610 after Alembic has created its version table). A bridged DB is stamped, not built, so it has no such shadow | none | Red Team Stage 5 §2, 2026-10-31 |
| **A3** → S-3.3 | `shadow_quota_usages.resource`: nullable (migrated) vs NOT NULL (reference) | `nova`, `nova_cell0`, H1–H4r | Exactly this nullability difference | Same file, lines 103–109: the override tests `column.name == 'resources'` (typo), so the intended nullable copy (legacy `247_nullable_mismatch` not applied to shadows) never happens in the reference | **Condition:** after H4r, on a disposable copy of the H4r database (not inside the H4r comparison), run 2026.1 `nova-manage db archive_deleted_rows --all-cells --until-complete --verbose` for cell1 and cell0. Pass = exit 0 or 1 (1 = rows archived), no error. Rows moved main → `shadow_*` are expected only on that copy and are not compared with T0 | Red Team Stage 5 §2, 2026-10-31 |
| **A4** → S-N.1 | `cinder.quota_usages` unique key on (`project_id`,`resource`,`race_preventer`) named `quota_usages_project_id_key` (migrated) vs `project_id` (reference); structure identical | H1–H4r | Name-only difference, this constraint only | Neither side names it. Migrated: `cinder@22.3.0:cinder/db/legacy_migrations/versions/141_add_quota_usage_unique_constraint.py:35-38` (`migrate.changeset.constraint.UniqueConstraint(...)` unnamed → sqlalchemy-migrate 0.13.0 `UniqueConstraint.autoname()` = `"%s_%s_key" % (table, colnames[0])`). Reference: `cinder@origin/stable/2026.1:cinder/db/migrations/versions/921e1a36b076_initial.py:488` unnamed `sa.UniqueConstraint(...)` → MariaDB names it after the first column | **Condition (2) met:** grep of every file under `cinder@origin/stable/2026.1:cinder/db/migrations/versions/` for `quota_usages`: only `921e1a36b076_initial.py` matches (create and a `batch_alter_table('quota_usages')` resizing `resource`). No revision drops or alters a `quota_usages` constraint or index by name; `b7b88f50aab5` works on the `QuotaUsage` model rows only | Red Team Stage 5 §2, 2026-10-31 |
| **A5** | Hop correction | — | R-9 first executed at **H1** (step 10 kept, §8.1) | `yoga/expand/8160f7a9cebb` is a Yoga revision | step-10 decision made first: §8.1 | Red Team Stage 5 §2, 2026-10-31 |
| **A6** → V-P4 | `placement.projects` +1 and `placement.users` +1 (sentinel `external_id` = `[placement] incomplete_consumer_project_id` / `_user_id`, default `00000000-0000-0000-0000-000000000000`) | first hop whose Placement ODM runs (H1 with step 10) | Δ = **+1 / +1 only if** the sentinel row is absent at T0. Predicted at T0 by `SELECT COUNT(*) FROM placement.projects WHERE external_id='<incomplete_consumer_project_id>'` (and `users`). 0 → +1 expected, 1 → Δ 0. For datasets whose Ussuri ODM ran (PC-O1), V-P3 "no change" stands | `placement@9.0.0:placement/objects/consumer.py:27,37,40` (`create_incomplete_consumers` calls `project_obj.ensure_incomplete_project(ctx)` and `user_obj.ensure_incomplete_user(ctx)` **before** searching for consumers, on every run); `placement/objects/project.py:24-36` (insert if absent); `placement/objects/user.py:24`; defaults `placement/conf/placement.py:35-56`. Same code in Ussuri, so the Ussuri ODM at T0 creates the rows on real data | (1) function cited; (2) predicted at T0; (3) V-P3 kept | Red Team Stage 5 §2, 2026-10-31 |
| **A7** → S-2.1 | `neutron.portnumaaffinitypolicies.numa_affinity_policy`: migrated `enum('required','preferred','legacy')`, reference adds `'socket'` | **H2 only** (transient) | Exactly this column; must be **absent at H3, H4, H4r** (converged, verified by comparison A). Present at any other hop = stop | `neutron@origin/stable/2026.1:…/wallaby/expand/532aa95457e2_port_numa_affinity_policy.py:41-43` (`sa.Enum(*n_const.PORT_NUMA_POLICIES)`, a **library constant**): created at H1 by 2023.1 code with `neutron-lib===3.4.3` (u-c `requirements@origin/unmaintained/2023.1`); the 2024.1 reference with `3.11.1`; `2024.2/expand/175fa80908e1_add_numa_policy_socket.py` adds the value at H3 | none; table has 0 rows at T0 (did not exist in Ussuri) | Red Team Stage 5 §2, 2026-10-31 |

### 8.3 Cinder step H1b (DR-004) and corrected Cinder entries

**AM1-H1b. New checkpoint.** H1b sits between H1 and H2, on the H1 engine (MariaDB 10.6; record it. Kolla 2023.2 shipped
10.11, which is not needed for a Cinder-only step). Code: **cinder 23.5.0** under `requirements@2023.2-eol`
upper-constraints, in a proper `ufj-ff-2023.2` image (not the mixed environment of the RCA). Commands:
`cinder-manage db sync`, then `cinder-manage db online_data_migrations` until exit 0. Comparison A at H1b: Cinder only,
against `cinder_ref` built by 23.5.0. Other databases are unchanged from H1 (comparison B: 0 differences outside `cinder`).

| Id | Entry | Hop | Declaration | Source |
|---|---|---|---|---|
| AM1-H1b-S | `cinder.migrate_version` | H1b | dropped by `89aa6f9639f9` (2023.2 revision, guarded). S-1a/R-1 for cinder end at H1b instead of H2 | `cinder@23.5.0:cinder/db/migrations/versions/89aa6f9639f9_*.py` |
| AM1-H1b-A | schema vs `cinder_ref` (23.5.0) | H1b | only A1 (Cinder rows of §8.7) and A4 | — |
| **V-C1a** (replaces V-C1 at H1) | `volumes.use_quota` at H1 (cinder **22.3.0**) | H1 | Set for **non-deleted** rows only (rule as V-C1). **Soft-deleted rows stay NULL.** Expected NULL count after H1 = soft-deleted volumes at T0 (predicted) | `cinder@22.3.0:cinder/db/sqlalchemy/api.py:8707` (`model_query` without `read_deleted` → admin context default `'no'`, `cinder/context.py`) |
| **V-C1b** | `volumes.use_quota` of soft-deleted rows | H1b | NULL → value by the same rule. For deleted volumes the `temporary` admin metadata is read through the relationship that joins **non-deleted** admin metadata only (`cinder@23.5.0:cinder/db/sqlalchemy/models.py` `VolumeAdminMetadata.volume` primaryjoin `… VolumeAdminMetadata.deleted == False`), so a deleted temporary volume whose metadata was soft-deleted with it gets `True`. Predicted per row at T0 | `cinder@23.5.0:cinder/db/sqlalchemy/api.py:8708-8709` (`read_deleted='yes'`), commit `0a0c534a2` (bug #2070475) |
| **V-C2a** (replaces V-C2 for deleted rows at H1) | `snapshots.use_quota` | H1 | non-deleted → `True`; soft-deleted stay NULL | as V-C1a |
| **V-C2b** | `snapshots.use_quota` of soft-deleted rows | H1b | NULL → `True` | as V-C1b |
| PC-C1 gate | — | **after H1b, before H2** | 0 NULL in `volumes` and `snapshots`, **deleted included**; otherwise STOP (`fast-forward-checks.md` PC-C1, Amendment 1) | DR-004 |
| N-3 scope | `updated_at` of the rows of V-C1b/V-C2b | H1b | excluded as in N-3 | — |

Unchanged: V-C3 (`9ab1b092a404` at H2) now runs on a column without NULLs, and V-C9 still runs at H2, after V-C1b.

### 8.4 Hop table after Amendment 1

T0 → H1 (2023.1, all services, step 10) → **H1b (Cinder 23.5.0 only)** → PC-C1 gate → H2 (2024.1) → H3 (2025.1) → H4
(2026.1) → H4r. EXP-RB-01's "last point before the drops" for Cinder is now **H1** (`89aa6f9639f9` runs at H1b).

### 8.5 Pre-declaration for EXP-DB-02 (DB-level staircase), RT-N-22

The comparison EXP-DB-01 (S2c) vs EXP-DB-02 (staircase, final checkpoint and the shared checkpoints 2023.1, 2024.1,
2025.1, 2026.1) may differ **only** in:

1. **The A1 CHECK set.** The staircase runs Victoria (u-c `SQLAlchemy===1.3.19`) and Wallaby (`1.3.23`) code. From Xena on, the u-c pin is 1.4.x
   (`requirements@<series>-eol:upper-constraints.txt`). Every Boolean column created by a revision **executed at the Victoria or
   Wallaby hop** therefore gets a CHECK in EXP-DB-02, while S2c creates it with 2023.1 code (1.4.41) and gets none, unless the
   revision passes `create_constraint=True` explicitly. Predicted from source:
   - `cinder.quota_usages.race_preventer` (legacy `141`, Wallaby, plain `sa.Boolean`): CHECK in EXP-DB-02 only.
   - `cinder.default_volume_types.deleted` (legacy `140`, Victoria): `sa.Boolean(create_constraint=True, name=None)`, so a
     CHECK on both sides and no difference.
   - Neutron Victoria/Wallaby expand revisions: none creates a Boolean column (`49d8622c5221` only alters a server default).
     Predicted: no difference.
   - Nova and Keystone: no schema change at Victoria/Wallaby. Predicted: no difference.

   The actual difference set must be a subset of "Boolean columns created by revisions executed with SQLAlchemy 1.3 in the
   staircase". Each observed item is cited to its revision before EXP-DB-02 counts as compared.
2. **A7-type enums.** Neutron tables created from library constants are created in EXP-DB-02 at the hop of their revision, with
   that hop's neutron-lib: `portnumaaffinitypolicies` at Wallaby (`neutron-lib===2.10.2`). They must converge by the
   **2024.2/2025.1** checkpoint. A difference at a shared checkpoint is allowed only for the RT-N-23 candidates below and only
   until their converging revision.

Nothing else is excused between 01 and 02.

### 8.6 RT-N-23: DDL built from library constants (candidates)

Grep of Neutron, Glance and Placement migration chains at `origin/stable/2026.1` for `sa.Enum(*<const>)` and
constant-derived lengths:

| Revision | Construct | Risk |
|---|---|---|
| `wallaby/expand/532aa95457e2` | `sa.Enum(*n_const.PORT_NUMA_POLICIES)` | **A7**, realised; converges via `2024.2/expand/175fa80908e1` |
| `yoga/expand/c181bb1d89e4` | `sa.Enum(*n_const.VALID_DIRECTIONS_AND_ANY…)` | candidate if the constant changed between neutron-lib versions; not observed in R0 |
| `2023.2/expand/c33da356b165` | `sa.Enum(constants.INGRESS_DIRECTION, …)` (named members) | low |
| many (`victoria/1ea5dab0897a`, `yoga/76df7844a8c6`, `zed/I43e0b669096`, …) | `sa.String(length=db_const.*_FIELD_SIZE)` | low (sizes stable); comparison A would show a change |
| pre-Victoria Neutron revisions | no `sa.Enum(*const…)` found | — |
| Glance, Placement | no library-constant DDL (only literal enums in Ocata Glance revisions) | none |

R0 showed only A7 for the library versions in the lab images. A different `neutron-lib` pin, as in Kolla images or Tier B
production code, can show more. Such differences are classified with this table and are never excused without a citation.

### 8.7 A1 per-column list (S-3.1)

Source: `evidence/EXP-DB-R0/H1/schema-diff.txt` (141 entries). Struck-through entries are present at H1 and absent from H2
on, removed with their table (R-10) or column (V-Q5). H2 = H3 = H4 = H4r (125), verified identical.

| Database | Table: Boolean columns with `CHECK (col IN (0,1))` (MariaDB auto-name) | Count |
|---|---|---|
| `cinder` | `attachment_specs`: deleted (CONSTRAINT_1); `backup_metadata`: deleted (CONSTRAINT_1); `clusters`: deleted (CONSTRAINT_1), disabled (CONSTRAINT_2), frozen (CONSTRAINT_3); `group_type_specs`: deleted (CONSTRAINT_1); `group_types`: deleted (CONSTRAINT_1), is_public (CONSTRAINT_2); `group_volume_type_mapping`: deleted (CONSTRAINT_1); `groups`: deleted (CONSTRAINT_1); `messages`: deleted (CONSTRAINT_1); `quotas`: deleted (CONSTRAINT_1); `services`: deleted (CONSTRAINT_1), disabled (CONSTRAINT_2), frozen (CONSTRAINT_3); `snapshot_metadata`: deleted (CONSTRAINT_1); `snapshots`: deleted (CONSTRAINT_1); `transfers`: deleted (CONSTRAINT_1), no_snapshots (CONSTRAINT_2); `volume_admin_metadata`: deleted (CONSTRAINT_1); `volume_attachment`: deleted (CONSTRAINT_1); `volume_metadata`: deleted (CONSTRAINT_1); `volume_type_extra_specs`: deleted (CONSTRAINT_1); `volume_types`: deleted (CONSTRAINT_1), is_public (CONSTRAINT_2); `volumes`: bootable (CONSTRAINT_2), deleted (CONSTRAINT_1), multiattach (CONSTRAINT_3), shared_targets (CONSTRAINT_4); `workers`: deleted (CONSTRAINT_1) | 30 |
| `glance` | `images`: os_hidden (CONSTRAINT_4) | 1 |
| `keystone` | `assignment`: inherited (CONSTRAINT_1); `endpoint`: enabled (CONSTRAINT_1); `identity_provider`: enabled (CONSTRAINT_1); `project`: enabled (CONSTRAINT_1); `service`: enabled (CONSTRAINT_1); `service_provider`: enabled (CONSTRAINT_1); `system_assignment`: inherited (CONSTRAINT_1); `token`: valid (CONSTRAINT_1); `trust`: impersonation (CONSTRAINT_1); `user`: enabled (CONSTRAINT_1) | 10 |
| `neutron` | `address_scopes`: shared (CONSTRAINT_1); `agents`: admin_state_up (CONSTRAINT_1), resources_synced (CONSTRAINT_2); `bgp_speakers`: advertise_floating_ip_host_routes (CONSTRAINT_1), advertise_tenant_networks (CONSTRAINT_2); `brocadeports`: ~~admin_state_up (CONSTRAINT_1)~~; `cisco_hosting_devices`: ~~admin_state_up (CONSTRAINT_1)~~; `cisco_ml2_n1kv_vlan_allocations`: ~~allocated (CONSTRAINT_1)~~; `cisco_ml2_n1kv_vxlan_allocations`: ~~allocated (CONSTRAINT_1)~~; `cisco_ml2_nexusport_bindings`: ~~is_provider_vlan (CONSTRAINT_1)~~; `cisco_router_mappings`: ~~auto_schedule (CONSTRAINT_1)~~; `externalnetworks`: is_default (CONSTRAINT_1); `firewall_policies`: audited (CONSTRAINT_2), shared (CONSTRAINT_1); `firewall_rules`: enabled (CONSTRAINT_2), shared (CONSTRAINT_1); `firewalls`: admin_state_up (CONSTRAINT_2), shared (CONSTRAINT_1); `flavors`: enabled (CONSTRAINT_1); `healthmonitors`: admin_state_up (CONSTRAINT_1); `ipsec_site_connections`: admin_state_up (CONSTRAINT_1); `logs`: enabled (CONSTRAINT_1); `maclearningstates`: ~~mac_learning_enabled (CONSTRAINT_1)~~; `members`: admin_state_up (CONSTRAINT_1); `meteringlabelrules`: excluded (CONSTRAINT_1); `meteringlabels`: shared (CONSTRAINT_1); `ml2_brocadeports`: ~~admin_state_up (CONSTRAINT_1)~~; `ml2_geneve_allocations`: allocated (CONSTRAINT_1); `ml2_gre_allocations`: allocated (CONSTRAINT_1); `ml2_nexus_vxlan_allocations`: ~~allocated (CONSTRAINT_1)~~; `ml2_ucsm_port_profiles`: ~~created_on_ucs (CONSTRAINT_1)~~; `ml2_vlan_allocations`: allocated (CONSTRAINT_1); `ml2_vxlan_allocations`: allocated (CONSTRAINT_1); `network_segment_ranges`: default (CONSTRAINT_1), shared (CONSTRAINT_2); `networkgateways`: ~~default (CONSTRAINT_1)~~; `networks`: admin_state_up (CONSTRAINT_1), vlan_transparent (CONSTRAINT_3); `networksecuritybindings`: port_security_enabled (CONSTRAINT_1); `networksegments`: is_dynamic (CONSTRAINT_1); `nsxv_router_ext_attributes`: ~~distributed (CONSTRAINT_1)~~, ~~service_router (CONSTRAINT_2)~~; `nuage_subnet_l2dom_mapping`: ~~nuage_managed_subnet (CONSTRAINT_1)~~; `pools`: admin_state_up (CONSTRAINT_1); `ports`: admin_state_up (CONSTRAINT_1); `portsecuritybindings`: port_security_enabled (CONSTRAINT_1); `portuplinkstatuspropagation`: propagate_uplink_status (CONSTRAINT_1); `qosqueues`: ~~default (CONSTRAINT_1)~~; `quotausages`: dirty (CONSTRAINT_1); `router_extra_attributes`: distributed (CONSTRAINT_1), ha (CONSTRAINT_3), service_router (CONSTRAINT_2); `routers`: admin_state_up (CONSTRAINT_1), enable_snat (CONSTRAINT_2); `securitygroups`: stateful (CONSTRAINT_1); `serviceprofiles`: enabled (CONSTRAINT_1); `subnet_dns_publish_fixed_ips`: dns_publish_fixed_ip (CONSTRAINT_1); `subnetpools`: is_default (CONSTRAINT_2), shared (CONSTRAINT_1); `subnets`: enable_dhcp (CONSTRAINT_1), ~~in_use (CONSTRAINT_2)~~; `trunks`: admin_state_up (CONSTRAINT_1); `vips`: admin_state_up (CONSTRAINT_1); `vpnservices`: admin_state_up (CONSTRAINT_1) | 64 |
| `nova` | `block_device_mapping`: delete_on_termination (CONSTRAINT_1), no_device (CONSTRAINT_2); `cells`: is_parent (CONSTRAINT_1); `dns_domains`: deleted (CONSTRAINT_1); `fixed_ips`: allocated (CONSTRAINT_1), leased (CONSTRAINT_2), reserved (CONSTRAINT_3); `floating_ips`: auto_assigned (CONSTRAINT_1); `instance_types`: disabled (CONSTRAINT_1), is_public (CONSTRAINT_2); `instances`: auto_disk_config (CONSTRAINT_2), disable_terminate (CONSTRAINT_4), locked (CONSTRAINT_1), shutdown_terminate (CONSTRAINT_3); `networks`: injected (CONSTRAINT_1), multi_host (CONSTRAINT_2); `services`: disabled (CONSTRAINT_1) | 17 |
| `nova_api` | `flavors`: disabled (CONSTRAINT_1), is_public (CONSTRAINT_2) | 2 |
| `nova_cell0` | `block_device_mapping`: delete_on_termination (CONSTRAINT_1), no_device (CONSTRAINT_2); `cells`: is_parent (CONSTRAINT_1); `dns_domains`: deleted (CONSTRAINT_1); `fixed_ips`: allocated (CONSTRAINT_1), leased (CONSTRAINT_2), reserved (CONSTRAINT_3); `floating_ips`: auto_assigned (CONSTRAINT_1); `instance_types`: disabled (CONSTRAINT_1), is_public (CONSTRAINT_2); `instances`: auto_disk_config (CONSTRAINT_2), disable_terminate (CONSTRAINT_4), locked (CONSTRAINT_1), shutdown_terminate (CONSTRAINT_3); `networks`: injected (CONSTRAINT_1), multi_host (CONSTRAINT_2); `services`: disabled (CONSTRAINT_1) | 17 |
