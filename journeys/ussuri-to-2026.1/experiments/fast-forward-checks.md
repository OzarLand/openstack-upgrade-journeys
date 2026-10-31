# Fast-forward checks: pre-checks, config parity and named stop conditions

| Metadata | |
|---|---|
| Origin | Red Team RT-N-02 (config parity), RT-N-03 (Glance pre-check as a named stop condition), RT-N-04, RT-N-07; consolidates `assessments/04-database-migration-strategy.md` §4 |
| Author | Agent 4 — Database and Messaging Specialist |
| Model | Opus (claude-opus-5-5) |
| Date | 2026-10-31 |
| Status | `PROPOSED-UNVERIFIED` (from source; nothing executed) |
| Applies to | Every lab run (T0 and before each hop) and the production pre-check list. Referenced from `declared-differences.md` |

Every check here is **read-only** unless marked otherwise. A failed check is a **named stop condition**. The run (or
production change) does not proceed. The fix is a separate, reviewed change on Ussuri with supported tooling, never an
ad-hoc SQL edit during the window. On disposable *negative copies* the deliberate violation is the purpose of the run.

## 1. Pre-checks (PC) on the Ussuri database, before T0 / before the window

| Id | Check | Command / query | Pass | If it fails | Why (source) |
|---|---|---|---|---|---|
| PC-V1 | Legacy versions inside the bridge window | `SELECT repository_id, version FROM <db>.migrate_version;` for `nova`, `nova_cell0`, `nova_api`, `keystone`, `cinder` | nova/nova_cell0 ≥ 401 (expected 407), nova_api ≥ 66 (72), keystone repos ≥ 72 (**record 078 or 079**, RT-N-04), cinder ≥ 134 (136) | STOP: DB below the bridge's `MIGRATE_INIT_VERSION` | `nova@origin/unmaintained/2023.1:nova/db/migration.py`, keystone/cinder equivalents |
| PC-V2 | Alembic-managed services at Ussuri heads | `SELECT * FROM glance.alembic_version; placement.alembic_version; neutron.alembic_version;` | glance includes `ussuri_contract01`, placement `b5c396305c25`, neutron = Ussuri expand head + Newton contract head | STOP | dependency graph §4.4–4.6 |
| PC-O1 | Ussuri online migrations complete | Ussuri `nova-manage db online_data_migrations`, `placement-manage db online_data_migrations`, `cinder-manage db online_data_migrations` | exit 0 for each | STOP (finish them on Ussuri) | Nova upgrade guide: ODMs complete before the next upgrade |
| **PC-G1** (RT-N-03) | **Glance: no pending data migration from earlier releases.** 2026.1 runs none at all | (a) Ussuri `glance-manage db check` (exists in Ussuri, `glance@ussuri-eol:glance/cmd/manage.py:93`); (b) `SELECT COUNT(*) FROM glance.image_locations WHERE INSTR(meta_data,'"backend":')>0;` | (a) exit 0 ("Database is up to date"); (b) = 0. Both are needed: Ussuri's `db check` only tests `ussuri*` data-migration modules (`glance@ussuri-eol:…/data_migrations/__init__.py`, `startswith(release)`), so it cannot see Train leftovers. Query (b) can | **STOP.** (a) exit 3/4/5 means expand/migrate/contract pending on Ussuri: run Ussuri `glance-manage db sync` in a separate change and re-check. (b) > 0: rows the Train data migration did not convert; Ussuri `glance-manage db migrate` (whose `CURRENT_RELEASE='ussuri'` does **not** include `train_migrate01`) cannot fix them. Escalate; no SQL fix in the window | `glance@origin/stable/2026.1:glance/db/sqlalchemy/alembic_migrations/data_migrations/__init__.py` (`CURRENT_RELEASE` only), `…/train_migrate01_backend_to_store.py` |
| PC-G2 | No leftover Glance/Keystone triggers | `SELECT TRIGGER_SCHEMA, TRIGGER_NAME FROM information_schema.TRIGGERS;` | none for `glance`, `keystone` | STOP | leftovers of interrupted rolling upgrades |
| PC-N1 | No in-flight Nova work | `SELECT COUNT(*) FROM nova.instances WHERE deleted=0 AND task_state IS NOT NULL;` (each cell); `SELECT status, COUNT(*) FROM nova.migrations WHERE deleted=0 GROUP BY 1;` | 0; only final migration states | STOP | transitional states survive the jump unhandled |
| PC-N2 | Cell mappings readable | `SELECT id, uuid, name FROM nova_api.cell_mappings;` (never select the URL columns into logs) | cell0 + every cell; the lab resolves their DB host (strategy §5.3) | STOP | ODMs `target_cell` through these URLs |
| PC-N3 | No build requests | `SELECT COUNT(*) FROM nova_api.build_requests;` | 0 | STOP (`b30f573d3377` drops columns) | declared-differences R-3 |
| PC-N4 | `compute_id` residue predicted | count instances (all, incl. deleted) whose (`host`,`node`) has no `compute_nodes` row | recorded (becomes N-R1) | — | `populate_instance_compute_id` |
| PC-C1 | Cinder `use_quota` complete **before** any ≥ 2024.1 `db sync` (checked at H1, not at T0) | `SELECT COUNT(*) FROM cinder.volumes WHERE use_quota IS NULL; … snapshots …` | 0 after the 2023.1 ODM | **STOP before H2** | `9ab1b092a404`; and V-C9 then erases the `temporary` metadata |
| PC-C2 | Cinder transitional states | `SELECT status, migration_status, COUNT(*) FROM cinder.volumes WHERE deleted=0 GROUP BY 1,2;` | no `creating`, `attaching`, `detaching`, `migrating`, `backing-up`, …; `target:%` only if a migration is known stuck | STOP / explain | — |
| PC-C3 | Predictions for declared transformations | `use_quota` split (V-C1), `default` quota classes present (R-5), `consistencygroups` rows (V-C6), `temporary` admin metadata (V-C9) | recorded in the run record before H1 | — | declared-differences §4–5 |
| PC-K1 | No duplicate trusts | `SELECT trustor_user_id, trustee_user_id, project_id, impersonation, expires_at, COUNT(*) c FROM keystone.trust GROUP BY 1,2,3,4,5 HAVING c>1;` | empty | STOP (`b4f8b3f584e0` fails) | V11 |
| PC-K2 | Password hashers recorded | count of `keystone.password.password_hash` by prefix (`$6$` = sha512_crypt) | recorded; non-zero `$6$` = user impact on 2026.1 (V19), owner informed | — | `keystone@origin/stable/2026.1:keystone/common/password_hashing.py` |
| PC-Q1 | No duplicate Neutron quotas | `SELECT project_id, resource, COUNT(*) c FROM neutron.quotas GROUP BY 1,2 HAVING c>1;` | empty | STOP | `f010820fc498` |
| PC-Q2 | `portbindingports` empty | `SELECT COUNT(*) FROM neutron.portbindingports;` | 0 | STOP (table dropped) | `8160f7a9cebb` |
| PC-Q3 | Legacy plugin tables empty | `COUNT(*)` for every table of `054e34dbe6b4` `TABLES_TO_DROP` that exists | 0 each | STOP | R-10 |
| PC-Q4 | No duplicate segment ranges | `SELECT \`default\`, network_type, IFNULL(physical_network,''), minimum, maximum, COUNT(*) c FROM neutron.network_segment_ranges GROUP BY 1,2,3,4,5 HAVING c>1;` | empty | STOP (otherwise rows are **deleted** by `b1bca967e19d`) | R-11 |
| PC-Q5 | No duplicate network segments | `SELECT network_id, network_type, physical_network, COUNT(*) c FROM neutron.networksegments WHERE physical_network IS NOT NULL GROUP BY 1,2,3 HAVING c>1;` | empty | STOP | `e981acd076d3`, `fc153938cdc1` |
| PC-Q6 | No duplicate HA networks per project | `SELECT project_id, COUNT(*) c FROM neutron.ha_router_networks GROUP BY 1 HAVING c>1;` | empty | STOP | `682c319773d7` |
| PC-Q7 | Port data formats | Ussuri-available checks plus the 2026.1 `neutron-status upgrade check` run **after** H4 (its port-MAC and binding-profile checks); fixes only with `neutron-sanitize-port-mac-addresses`, `neutron-sanitize-port-binding-profile-allocation`, `neutron-remove-duplicated-port-bindings` (shipped in 2026.1) | no FAILURE | STOP | `neutron@origin/stable/2026.1:neutron/cmd/upgrade_checks/checks.py` |
| PC-E1 | Engine `sql_mode` recorded (RT-N-07) | `SELECT @@GLOBAL.sql_mode;` per engine version; inside every one-shot run, the session mode the tool uses (log `SELECT @@SESSION.sql_mode` through the same oslo.db engine, e.g. a one-line Python call with the service's config) | recorded; expected strict (`TRADITIONAL` from oslo.db) | STOP if a migration command runs under a non-strict session outside N2 | V17 |
| PC-E2 | Sizes | `SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_ROWS, DATA_LENGTH+INDEX_LENGTH FROM information_schema.TABLES ORDER BY 4 DESC LIMIT 30;` | recorded | — | DDL timing |

## 2. Config parity of the one-shot containers (RT-N-02)

**Principle.** The one-shot container does not get a hand-written config. It is given the **production rendered config
files** (the Kolla-generated `/etc/kolla/<service>/<service>.conf` of the Ussuri platform, copied with secrets kept in
the secured lab), followed by a **second `--config-file`** that overrides only the connection options. oslo.config
gives the later file precedence. Parity is then true by construction, and the check below proves it.

Override file (only these keys may appear): `[database] connection`, `[api_database] connection` (Nova),
`[placement_database] connection` (Placement), and `[DEFAULT] transport_url` set to an unreachable value (no tool in
this procedure needs RabbitMQ; a reachable broker would let a mistake reach production queues).

Options that change what a migration or online migration writes (verified in source; must equal production):

| Id | Service | Option(s) | Used by | Source |
|---|---|---|---|---|
| CP-C1 | Cinder | `[DEFAULT] quota_backups`, `quota_backup_gigabytes` | `9c74c1c6971f` inserts them as default quota-class `hard_limit` | `cinder@origin/stable/2026.1:cinder/db/migrations/versions/9c74c1c6971f_*.py` |
| CP-N1 | Nova | `[DEFAULT] default_availability_zone` | `populate_missing_availability_zones` | `nova@origin/stable/2026.1:nova/availability_zones.py` |
| CP-N2 | Nova | `cpu/ram/disk_allocation_ratio`, `initial_*_allocation_ratio` | `migrate_empty_ratio` | `nova/objects/compute_node.py:migrate_empty_ratio` |
| CP-N3 | Nova | `[api_database] connection` + the cell URLs stored in `cell_mappings` | every cross-cell ODM | `nova/objects/instance_mapping.py` |
| CP-P1 | Placement | `[placement] incomplete_consumer_project_id`, `incomplete_consumer_user_id` | `create_incomplete_consumers` | `placement@origin/stable/2026.1:placement/conf/placement.py` |
| CP-Q1 | Neutron | `[DEFAULT] core_plugin`, `service_plugins`, **installed sub-project packages** (fwaas, vpnaas, dynamic-routing, sfc, …) | which Alembic branches/version tables exist and are migrated | `neutron-db-manage` branch discovery |
| CP-G1 | Glance | none found in migrations (only `env.py` reads `CONF` for the connection) | — | searched `glance@origin/stable/2026.1:glance/db/sqlalchemy/alembic_migrations/` |
| CP-K1 | Keystone | none affecting the schema path found | — | — |

The Neutron migration scripts were searched for `cfg.CONF` with no match. Sub-project presence is therefore the parity item
that matters (CP-Q1).

**Parity check (C1 addition, read-only, per one-shot run):**

```sh
# inside the one-shot container, with exactly the --config-file list used for the run
python3 - <<'PY' > /evidence/<run>/<service>-effective.txt
from oslo_config import cfg
# register the service's options, e.g. for cinder: import cinder.common.config, cinder.quota
...  # per service: import the modules that register the options in the table above
cfg.CONF(['--config-file', '/etc/<svc>/<svc>.conf', '--config-file', '/etc/<svc>/override.conf'], project='<svc>')
for group, name in OPTIONS:   # the CP list for this service + the override keys
    v = getattr(cfg.CONF[group] if group != 'DEFAULT' else cfg.CONF, name)
    print(group, name, '<redacted>' if 'connection' in name or name == 'transport_url' else v)
PY
pip freeze > /evidence/<run>/<service>-pip-freeze.txt      # Neutron: sub-project packages must match CP-Q1
```

Pass: every CP value equals the value in the production rendered file (diff of the two dumps). The only differences are
the redacted override keys. The Neutron `pip freeze` contains exactly the production sub-projects. Fail = **STOP** (named
stop condition SC-CP).

## 3. Named stop conditions (summary)

| Name | Trigger |
|---|---|
| SC-PC-<id> | any PC check of §1 not passing |
| **SC-GLANCE** | PC-G1 (a) or (b) fails (RT-N-03) |
| SC-CP | config parity mismatch (§2) |
| SC-CMD | any migration/ODM command non-zero (ODM: exit 2, or not 0 after completion) |
| SC-DIFF | schema/row/fingerprint change not in `declared-differences.md` |
| SC-IDEMP | any change between H4 and H4r |
| SC-HAND | any need to stamp, edit bookkeeping tables or edit rows by hand |
| SC-ENGINE | engine upgrade/check errors, crash recovery, corruption messages |

Each stop is recorded with its evidence. Resuming is a new decision.
