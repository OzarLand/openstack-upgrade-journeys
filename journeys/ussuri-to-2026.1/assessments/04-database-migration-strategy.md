# 04 — Database migration strategy and "database fast-forward" experiment design

| Metadata | |
|---|---|
| Author | Agent 4 — Database and Messaging Specialist (Stage 1, independent investigation) |
| Model | Opus (claude-opus-5-5) |
| Date | 2026-10-31 |
| Status | Proposal. Every procedure is `PROPOSED-UNVERIFIED`; nothing was executed. |
| Inputs read | `00-mission-brief.md`; `04-database-migration-dependency-graph.md` (same author); upstream trees listed there; `kolla@<series>:kolla/template/repos.yaml`, `docker/base/mariadb.repo`, `docker/mariadb*/`; `kolla-ansible@<series>:ansible/roles/{mariadb,nova,nova-cell,cinder,keystone}/**`; OzarLand skills `openstack-kolla-ansible-operations` (host-and-database-operations), `openstack-incident-analysis` (control-plane-recovery), `openstack-change-review`; OzarLand `kolla-ansible-deployment-patterns/version-notes/` (2025.1→2026.1 lab). |

Skills applied. `openstack-change-review` supplied the decision gates, point of no return, stop conditions and
verification designed before execution. `openstack-kolla-ansible-operations` supplied what Kolla-Ansible runs (bootstrap/upgrade containers, MariaDB backup/restore,
`mariadb-recovery`) and its validation labels. `openstack-incident-analysis` gave the rule against acting on
Galera or RabbitMQ without a saved copy, and the reported failure of `rabbitmq-reset-state` with Khepri.

## 1. The problem in database terms

Three facts from the dependency graph decide the strategy:

1. **Nova, Keystone and Cinder need one intermediate code version** (bridge window Xena…2023.1; 2023.1 is in all
   three windows). In 2023.2+ the legacy → Alembic bridge is gone.
2. **Cinder's `use_quota` online migration must finish before any ≥ 2024.1 `db sync`**. Only Xena–2023.1 code carries it.
3. Nova's and Placement's online-migration code is cumulative to 2026.1. Glance's post-Ussuri data migrations are
   empty. Neutron's migrations are all still present.

There are two separate engines underneath: **MariaDB 10.3 (Ussuri) → 11.4 (2026.1)** and the Galera cluster
around it.

MariaDB per Kolla series (repo pins in `kolla@<ref>:kolla/template/repos.yaml` / `docker/base/mariadb.repo`):

| Series | Ubuntu/Debian repo | RPM |
|---|---|---|
| Ussuri, Victoria | 10.3 (`dlm.mariadb.com/repo/mariadb-server/10.3`) | CentOS 8: no MariaDB repo in Kolla, distribution package (10.3 expected; **not verified**) |
| Wallaby | Ubuntu 10.3, Debian 10.5 | distribution |
| Xena | 10.5 | 10.5 (`mariadb.repo` rhel/8) |
| Yoga, Zed, 2023.1 | 10.6 | 10.6 |
| 2023.2, 2024.1, 2024.2, 2025.1 | 10.11 | 10.11 |
| 2025.2, 2026.1 | 11.4 | 11.4 (`rhel/$releasever`) |

Kolla-Ansible runs `mysql_upgrade` (Ussuri) / `mariadb-upgrade` (2026.1) in an `upgrade_mariadb` one-shot container
after the MariaDB upgrade (`kolla@origin/stable/2026.1:docker/mariadb-server/extend_start.sh`, `KOLLA_UPGRADE`;
`kolla-ansible@origin/stable/2026.1:ansible/roles/mariadb/tasks/post-upgrade.yml`). The 2026.1 upgrade switches SST to
`rsync` during the restart sequence (`.../mariadb/tasks/upgrade.yml`). The Ussuri `galera.cnf` sets
`innodb_lock_schedule_algorithm = FCFS` (`kolla-ansible@ussuri-eol:ansible/roles/mariadb/templates/galera.cnf.j2`).
From memory, that variable no longer exists in recent MariaDB, so an Ussuri config must not be reused with a newer server
(**not verified**). Kolla sets `character-set-server = utf8`, `collation-server = utf8_general_ci` in both
Ussuri and 2026.1. 2026.1 also enables `log_bin=mysql-bin`.

OzarLand lab evidence (not this mission): a Kolla-Ansible 2025.1 → 2026.1 upgrade went 10.11 → 11.4.13 "without
incident" (`kolla-ansible-deployment-patterns/version-notes/2025.1-to-2026.1.md`).

## 2. Strategy options

### S1 — Sequential supported upgrade (reference)

Deploy every release: Ussuri → V → W → X → Y → Z → 2023.1 (N+1), then 2023.1 → 2024.1 → 2025.1 → 2026.1 (SLURP).
Every `db sync` and online migration runs with its own release, MariaDB and RabbitMQ advance with the Kolla images, and
upstream has tested each hop. **Officially supported.** The cost is 9 Kolla upgrades. It also needs every
intermediate Kolla image, which is a problem of its own: Docker Hub `kolla/*` answers 401 per the brief, and the
mirror availability belongs to other agents.

### S2 — Database fast-forward (DB-only FFU)

Stop the platform. Run each required release's **migration code only**, offline, in one-shot containers or virtualenvs that
contain that release's service code and its upper-constraints, with a config file pointing at the database. Then
deploy 2026.1 once. Variants:

| Variant | Code versions that run `db sync` / online migrations | Pros | Cons |
|---|---|---|---|
| **S2a minimal** | Ussuri (ODM finish, platform running) → **2023.1** → **2026.1** | 2 offline hops | Skips upstream-tested hops V–Z and 2024.1, 2025.1 |
| **S2b conservative** | Ussuri → V → W → X → Y → Z → 2023.1 → 2024.1 → 2025.1 → 2026.1 (each: sync + ODM) | Mirrors the supported order exactly at DB level | 9 offline hops, 9 Python environments; still no running intermediate services |
| **S2c SLURP-aligned** (recommended for the experiment's main line) | Ussuri → 2023.1 → 2024.1 → 2025.1 → 2026.1 | After the bridge, follows the officially supported SLURP chain hop by hop | 4 offline hops |

Status of S2 in every variant: **Technically possible but unsupported**; Not validated. Nova's guide documents running
`api_db sync` / `db sync` from "the code for the next version … in a venv"
(`nova@origin/stable/2026.1:doc/source/admin/upgrades.rst`). Running one release ahead in a venv is documented.
Skipping releases while doing so is not.

**What S2 cannot cover (risks, in order of importance)**

1. **Object blobs and lazy data migrations.** Nova stores serialized versioned objects in the DB
   (`request_specs.spec`, `instance_extra.{numa_topology,pci_requests,flavor,vcpu_model,migration_context,…}`,
   `build_requests.instance`). Some of these are upgraded *on load/save* by running services, not by
   `online_data_migrations`. In S2 no Victoria…2025.2 service ever loads and re-saves them. Whether 2026.1 objects
   load every Ussuri-era primitive correctly is **unknown**. The experiment must load every instance and request
   spec through 2026.1 code or APIs. The same question applies to Neutron `ml2_port_bindings.profile` (fix tools exist) and
   Cinder `volume_attachment.connection_info`.
2. **Start-up reconciliation that normally happens at every release** (nova-compute updating compute node, resource
   provider and service records; Neutron agents resyncing; Placement inventories). In S2 it happens once, at
   2026.1. Nova's service-version gate fails until the computes have started on 2026.1, so
   `[workarounds]disable_compute_service_check_for_ffu` is needed. `nova-status upgrade check` still reports FAILURE,
   and Kolla-Ansible 2026.1 aborts the Nova upgrade on rc ∉ {0,1}
   (`kolla-ansible@origin/stable/2026.1:ansible/roles/nova/tasks/upgrade.yml`). This needs a design from the
   orchestration/Nova agents. **Do not** use `forced_down` or delete compute service records to get past it: that changes
   real state.
3. **Untested code jumps.** Upstream CI tests N→N+1 and SLURP, not Ussuri → 2023.1. The legacy scripts in 2023.1 are
   the final versions of the Victoria–Wallaby migrations, which helps, but the combination is untested.
4. **One-shot environment ≠ Kolla image.** PyPI + upper-constraints builds are not the binaries Kolla would run.
   Whatever is validated in the lab must be exactly what runs in production: the same image digest, pushed to a local
   registry, with no rebuild in the window.
5. **Point of no return** = the first bridge `db sync` (schema changes; OpenStack does not support downgrades). After it,
   recovery means restoring the Ussuri backup with the Ussuri images (see `04-recovery-consistency-requirements.md`).
6. **Long DDL under Galera.** DDL is replicated with total-order isolation by default and blocks the whole
   cluster (from knowledge; not verified here). Run the migrations on a **single node with wsrep off**, then
   rebuild the cluster by SST. Tables that may be large and are altered: Nova `instances`, `shadow_instances`,
   `migrations`, `shadow_migrations` (`1acf2c98e646`), `block_device_mapping` + shadow (`ccb0fa1a2252`),
   `shadow_instance_type_extra_specs` charset conversion (`16f1fbcab42b`), `instances` index drop (`960aac0e09ea`);
   Cinder `volumes`, `snapshots` (`145`, `9ab1b092a404`, `daa98075b90d`, `c92a3e68beed`), `reservations`
   (`b8660621f1b9`); Keystone `revocation_event` (`742c857f1dfb`); Neutron `ports` (indexes), `tags`
   (`d553edeb540f` table rebuild); Placement `inventories`, `resource_providers` (index drops). Archiving and purging
   before the window shrinks them (`nova-manage db archive_deleted_rows` then `purge`; `cinder-manage db purge`;
   `glance-manage db purge`). These are **supported, state-changing** commands; take a backup first and agree retention
   with the data owners.
7. **Data-dependent failures and silent data changes**: Neutron unique constraints (quotas, networksegments) fail on
   duplicates. Neutron `b1bca967e19d` **deletes** duplicate `network_segment_ranges` rows. Keystone
   `b4f8b3f584e0` adds a unique constraint on trusts. Cinder `9c74c1c6971f` inserts quota defaults from the config file used.
   All need read-only pre-checks (section 4).

### S3 — Logical re-platform: export data and import it into a fresh 2026.1 schema

Rejected. It means writing table-by-table transforms between unrelated schema versions: direct database
manipulation that no upstream project supports. It loses every guarantee the migration scripts give. **Incompatible**
with the brief's data-integrity priority.

### Engine path options (independent of S2 variant)

| Option | Description | Status |
|---|---|---|
| E1 stepwise in place | 10.3 → 10.5 → 10.6 (bridge hop) → 10.11 → 11.4 on one node, wsrep off, `mariadb-upgrade` and `mariadb-check` after each | Follows the versions Kolla shipped; each step is a documented MariaDB major upgrade (MariaDB rules **not verified here**: mariadb.com unreachable) |
| E2 dump/restore | `mariadb-dump` per DB from 10.3, restore into an empty 11.4 (or into 10.6 for the bridge hop) | Avoids on-disk format steps; restore time on large DBs; definers/triggers/charset must be checked |
| E3 direct in place 10.3 → 11.4 | Start 11.4 on a 10.3 datadir, then `mariadb-upgrade` | **Not validated**; whether MariaDB supports skipping majors in place is unknown here; test only |

Galera rule for every option (`openstack-kolla-ansible-operations`, KA-OPS-14/18): stop all nodes, keep a copy of
every node's datadir, upgrade **one** node, bootstrap the new cluster from it, then empty the others so they join by
SST. Rolling Galera upgrades across several majors are not an option (from knowledge; not verified here).

Recommended pairing to test: the bridge code runs on the MariaDB its release shipped (2023.1 ↔ 10.6), 2024.1/2025.1 on
10.11, and 2026.1 on 11.4. A second line runs all code against 11.4 to see whether the engine order matters.

## 3. Recommended S2c run order (what the lab replicates and what production would do)

All steps on a **copy** in the lab. In production only after the experiment passes and the change review approves.

| # | Step | Code | Label |
|---|---|---|---|
| 0 | `nova-manage db online_data_migrations` and `placement-manage db online_data_migrations` until exit 0; `cinder-manage db online_data_migrations`; `nova-manage db archive_deleted_rows --until-complete` (optional, agreed) | Ussuri, running platform | State-changing (supported) |
| 1 | Read-only data pre-checks (section 4) | SQL / Ussuri status tools | Read-only |
| 2 | Stop all OpenStack services; queues drained (`04-messaging-compatibility.md`) | — | State-changing |
| 3 | Backups: physical (`kolla-ansible mariadb-backup` if enabled, or `mariabackup`) **and** logical per DB; checksums; off-host copy; restore test | — | Read-only for DB |
| 4 | Stop Galera; copy every node's datadir; start one node wsrep-off (or restore into a standalone server) | — | Destructive for cluster membership (undo: copies) |
| 5 | Engine to 10.6 (E1 or E2) | — | State-changing; **point of no return for in-place E1** |
| 6 | `keystone-manage db_sync` | 2023.1 | **Point of no return (schema)** |
| 7 | `nova-manage api_db sync`; `nova-manage db sync --local_cell` with `[database]` → cell0, then → cell1 | 2023.1 | State-changing |
| 8 | `cinder-manage db sync`; `cinder-manage db online_data_migrations` until 0 remaining | 2023.1 | State-changing |
| 9 | `nova-manage db online_data_migrations` until exit 0 | 2023.1 | State-changing |
| 10 | `glance-manage db sync`, `placement-manage db sync`, `neutron-db-manage upgrade heads` (aligns all services at 2023.1) | 2023.1 | State-changing |
| 11 | Checks (section 5) | 2023.1 | Read-only |
| 12 | Engine to 10.11; repeat 6–11 with 2024.1, then 2025.1 (Cinder ODM: `remove_temporary_admin_metadata`) | 2024.1, 2025.1 | State-changing |
| 13 | Engine to 11.4; repeat 6–11 with 2026.1 | 2026.1 | State-changing |
| 14 | Rebuild Galera from the migrated node; deploy 2026.1 control plane (separate plan for the Nova gate) | Kolla-Ansible 22.x | State-changing |

Keystone first, because its `db_sync` needs only its own DB and it is the smallest. Order among the other services is free
by code (no cross-service DB references), **except** that Nova's online migrations need the API DB and every cell
DB at the same code version.

## 4. Read-only pre-checks (before step 2)

| Check | Query / command (read-only) | Expected |
|---|---|---|
| Legacy versions | `SELECT * FROM <db>.migrate_version;` for nova, nova_api, nova_cell0, keystone, cinder | nova/nova_cell0 407, nova_api 72, keystone_expand/data/contract 79, cinder 136 |
| Alembic heads | `SELECT * FROM glance.alembic_version; placement.alembic_version; neutron.alembic_version` | glance `ussuri_contract01` (+ expand), placement `b5c396305c25`, neutron Ussuri expand head + Newton contract head |
| Leftover triggers | `SELECT TRIGGER_SCHEMA, TRIGGER_NAME FROM information_schema.TRIGGERS;` | none for keystone/glance |
| Nova ODM done | Ussuri `nova-manage db online_data_migrations` | exit 0 |
| In-flight Nova work | `SELECT COUNT(*) FROM nova_api.build_requests;` instances with `task_state IS NOT NULL AND deleted=0`; `migrations` not in final status | 0, or each explained |
| Cinder untyped / transitional | volumes `status` in (`creating`,`attaching`,`detaching`,`migrating`,`backing-up`,…) | 0 or explained |
| Glance Train data migration | `SELECT COUNT(*) FROM glance.image_locations WHERE INSTR(meta_data,'"backend":')>0;` | 0 |
| Neutron quotas duplicates | `SELECT project_id,resource,COUNT(*) c FROM neutron.quotas GROUP BY 1,2 HAVING c>1;` | empty |
| Neutron segment duplicates | `… FROM neutron.networksegments GROUP BY network_id,network_type,physical_network HAVING COUNT(*)>1` (NULL physnet excluded) | empty |
| Neutron segment range duplicates | `… FROM neutron.network_segment_ranges GROUP BY \`default\`,network_type,IFNULL(physical_network,''),minimum,maximum HAVING COUNT(*)>1` | empty (otherwise rows **will be deleted** by `b1bca967e19d`) |
| Neutron dropped plugin tables | row counts of tables in `054e34dbe6b4` `TABLES_TO_DROP` that exist | 0 rows |
| Keystone trust duplicates | `… FROM keystone.trust GROUP BY trustor_user_id,trustee_user_id,project_id,impersonation,expires_at HAVING COUNT(*)>1` | empty |
| Charsets | `SELECT TABLE_SCHEMA,TABLE_NAME,TABLE_COLLATION FROM information_schema.TABLES WHERE TABLE_SCHEMA IN (…)` | recorded; non-utf8 tables explained |
| Sizes | `SELECT TABLE_SCHEMA,TABLE_NAME,TABLE_ROWS,DATA_LENGTH+INDEX_LENGTH FROM information_schema.TABLES ORDER BY 4 DESC LIMIT 30;` | input to DDL timing |
| Cell mappings | `SELECT id,uuid,name FROM nova_api.cell_mappings;` (do **not** print `database_connection`/`transport_url`, they hold passwords) | cell0 + cell1 |

If a duplicate is found, the fix is a **separate reviewed change on Ussuri** with supported tooling (Neutron's
sanitize/remove-duplicate tools, API deletes). It is never an ad-hoc `DELETE` during the window.

## 5. Experiment design (for the lab engineer, this environment)

### 5.1 Goal and success criteria

Determine, on disposable copies, whether S2a and S2c turn an Ussuri dataset into a 2026.1 database that is
(a) at the code heads, (b) schema-identical to a fresh 2026.1 schema built by the same code on the same server,
apart from a pre-declared list of expected differences, (c) row-preserving, apart from pre-declared transformed columns,
and (d) readable by 2026.1 services. Also measure durations and find the failure modes predicted in the dependency
graph (negative tests).

### 5.2 Constraints of this environment

4 vCPU, 15 GB RAM, ~30 GB disk, Docker 29, no KVM. Docker Hub **library** images only, with a hit anonymous
rate limit (`toomanyrequests` seen on 2026-10-31): pull each image once and `docker save` it. PyPI is reachable.
docs/opendev/quay are blocked. No Kolla images. Budget about 8 GB for images and venvs, 10 GB for DB copies.

### 5.3 Building blocks

| Block | How | Notes |
|---|---|---|
| MariaDB servers | `mariadb:10.3`, `10.5`, `10.6`, `10.11`, `11.4` (library) | `mariadb:10.3/10.5/10.11/11.4` manifests answered on 2026-10-31; 10.6 not checked (rate limit). One container per version, datadir on a named volume per hop; config file mimicking Kolla (`character-set-server=utf8`, `collation-server=utf8_general_ci`, `innodb_autoinc_lock_mode=2`, `binlog_format=ROW`, `log_bin` for the 2026.1 line), **no** `innodb_lock_schedule_algorithm` on ≥ 10.6 |
| Python | `python:3.8-slim` for Ussuri and 2023.1; `python:3.10-slim` for 2024.1 and 2025.1 (their u-c carry `python_version` markers for 3.8/3.9/3.10 and 3.9/3.10 respectively); `python:3.12-slim` for 2026.1 (`requires-python = ">=3.10"`) | If Ussuri code fails on 3.8, fall back to `python:3.6` (Ussuri's classifiers list 3.6/3.7). Python support per series is read from classifiers/markers, not tested |
| Code env per series | `pip install -c uc-<series>.txt nova==… neutron==… keystone==… glance==… cinder==… openstack-placement==… PyMySQL` (versions in dependency graph §2); `uc-<series>.txt` = `git -C /home/user/src/requirements show <ref>:upper-constraints.txt`. Build once per series as an image, record `pip freeze` and the image digest | Service packages are not in u-c (except neutron in old series); pin them explicitly. If co-installation conflicts, use one image per service |
| Configs | Minimal per service: `[database] connection=mysql+pymysql://<lab user>:<lab pw>@<host>/<db>`; Nova also `[api_database]`; Placement `[placement_database]`; Cinder quota options equal to production (they feed `9c74c1c6971f`); Neutron `core_plugin`/`service_plugins` as production; installed Neutron sub-projects as production | Lab-only credentials |
| Cell mappings | Keep rows byte-identical: give the lab MariaDB container the hostname/IP that `cell_mappings.database_connection` points to (Docker network with that subnet + `--ip`, or `--network-alias` for a hostname), and the same DB user/password **only inside the isolated lab**. Alternative: `nova-manage cell_v2 update_cell` on the lab copy (supported command), then exclude `cell_mappings` from hash comparison | Never edit `cell_mappings` with SQL |

### 5.4 Baseline dataset (what must exist to make the result meaningful)

Two tiers; do Tier A first.

**Tier A — synthetic Ussuri dataset, produced by Ussuri code itself.** Create schemas with Ussuri tools (`keystone-manage
db_sync`, `nova-manage api_db sync`, `nova-manage cell_v2 map_cell0`, `create_cell`, `db sync`, `glance-manage db_sync`,
`cinder-manage db sync`, `placement-manage db sync`, `neutron-db-manage upgrade heads`) on `mariadb:10.3`. Then generate data through the
**Ussuri APIs** running in the Ussuri image: keystone (uwsgi or `keystone-wsgi-public`), placement-api, glance-api (file
store), cinder-api/scheduler/volume (fake/LVM-less driver), neutron-server (ML2, no agents or fake agent records),
nova-api/conductor/scheduler + one or two `nova-compute` with `compute_driver=fake.FakeDriver`, and RabbitMQ from the
library image (3.8 if pullable). Driving the APIs (not SQL inserts) keeps the data shapes realistic. Required content:

- Keystone: ≥3 domains, projects (nested), users (local + one federated mapping/IdP), group/role assignments incl.
  inherited and system scope, application credentials, trusts, EC2/TOTP **credentials** (encrypted: keep the
  credential key repository with the dataset), revocation events (revoke tokens), endpoint groups.
- Nova: flavors with extra specs, aggregates/AZs, key pairs, server groups; instances in ACTIVE, SHUTOFF, ERROR (no
  host), deleted, soft-deleted; resized/migrated instances (fake driver), instances with BDMs (volume-backed),
  NUMA/pinned flavor (fake driver host topology), PCI request blobs if achievable; then `archive_deleted_rows` for some
  rows so `shadow_*` tables hold data; `instance_actions` history; `request_specs` and `instance_extra` populated.
  Two cells are optional: cell0 + cell1 is mandatory.
- Placement: providers from the fake computes, a nested provider and custom traits/resource classes,
  allocations, an aggregate.
- Cinder: volume types (incl. `__DEFAULT__`), volumes available/in-use/deleted, snapshots, backups records, a volume
  in a migrated/temporary state if possible, quotas and quota usages per project, a group.
- Glance: images public/private/shared/community/hidden, multiple locations, properties, tags, members, a task.
- Neutron: networks (VLAN/flat/VXLAN segments; multi-segment), subnets v4/v6, subnet pools, ports with bindings and
  `extra_dhcp_opts`, routers with gateways, floating IPs, port forwarding, security groups and rules, QoS policies,
  RBAC policies, tags, network segment ranges (if the plugin is enabled), quotas.

**Tier B — copy of the production Ussuri database** (only with the data owner's written approval: it contains password
hashes, cell URLs with DB passwords, encrypted credentials, PII). Restore it on an isolated, encrypted lab volume and destroy it
afterwards. It is the only realistic test of object-blob compatibility and DDL durations. Tier A is enough to validate the
mechanism; Tier B is needed before production approval.

**Scale probe (optional).** To extrapolate DDL time, multiply Tier A rows with the Ussuri APIs (fake driver boots) to
tens of thousands of instances. Inserting rows with SQL is acceptable **only** on a disposable timing copy and only to
measure ALTER time, never to validate correctness.

### 5.5 Baseline capture (`T0`, on the Ussuri dataset)

1. Physical copy of the datadir volume (`docker run --rm -v … tar`) and a logical dump per DB:
   `mariadb-dump --single-transaction --routines --triggers --events --hex-blob --databases <db>` (from the
   10.3 server use `mysqldump`). Record sha256 of each artefact.
2. Schema-only dump per DB: `--no-data --skip-comments --skip-dump-date`, normalised (strip `AUTO_INCREMENT=n`).
3. `information_schema` snapshot: TABLES (engine, collation, rows), COLUMNS (type, nullability, default, charset,
   collation), STATISTICS (indexes), KEY_COLUMN_USAGE/REFERENTIAL_CONSTRAINTS (FKs), TRIGGERS.
4. Exact row counts: `SELECT COUNT(*)` for every table (not `TABLE_ROWS`).
5. Row fingerprints for protected tables. Hash the **business-key columns only**, so that added columns do not change the
   value: e.g. `SELECT COUNT(*), BIT_XOR(CRC32(CONCAT_WS('|',uuid,project_id,user_id,vm_state,host,node,deleted))) FROM nova.instances`.
   Similar per table: `nova_api.{instance_mappings,cell_mappings(id,uuid,name),request_specs(instance_uuid,MD5(spec)),key_pairs,flavors,flavor_extra_specs}`,
   `nova.{instances,instance_extra(instance_uuid, MD5 of each blob),block_device_mapping,migrations,instance_actions,shadow_instances}`,
   `cinder.{volumes,snapshots,volume_types,quotas,quota_usages,backups,volume_attachment}`,
   `glance.{images,image_locations,image_properties,image_members,image_tags}`,
   `keystone.{project,user,local_user,password,assignment,credential(id,MD5(encrypted_blob)),trust,application_credential,revocation_event}`,
   `neutron.{networks,networksegments,subnets,ports,ipallocations,ml2_port_bindings,routers,floatingips,securitygroups,securitygrouprules,quotas,network_segment_ranges}`,
   `placement.{resource_providers,inventories,allocations,consumers,traits,resource_provider_traits}`.
   Put the queries in one versioned script; the same script runs at every checkpoint.
6. API-level inventory with Ussuri services running: `openstack server list --all-projects --long -f json`,
   `server show` for each instance, `volume list --all-projects`, `image list`, `port list`, `network list`,
   `resource provider list` + allocations, `project/user/role assignment list`. Store as JSON.

### 5.6 Checks after each hop (`T1…Tn`)

| # | Check | Pass condition |
|---|---|---|
| C1 | Exit codes and logs of every command | 0 (ODM: 0 at the end), no ERROR/Traceback |
| C2 | Versions: `nova-manage api_db version`, `nova-manage db version` (cell0, cell1), `keystone-manage db_version` (expand/contract), `cinder-manage db version`, `glance-manage db version` + `glance-manage db check`, `placement-manage db version`, `neutron-db-manage current` + `check_migration` + `has_offline_migrations` | Equal to the code's heads (`alembic heads` of that package's script directory); glance check exit 0; neutron no offline migrations |
| C3 | `migrate_version` table | Present after the bridge (still recorded); gone after 2023.2+ hops (dropped by `1b91788ec3a6`, `cdeec0c85668`, `89aa6f9639f9`) |
| C4 | Schema diff against a **reference schema**: on the same server, create `<db>_ref` databases with the same code (fresh `db sync`; Nova via `--local_cell` and `api_db sync`) and diff the normalised schema dumps and `information_schema` snapshots | Only differences on the pre-declared list (e.g. table/column collations inherited from older defaults, shadow-table history, index names). Any other difference = stop |
| C5 | Row counts | Equal to T0 for every table, except tables whose change is declared (e.g. `migrate_version` dropped, Cinder default quota class rows added by `9c74c1c6971f`, Neutron dropped plugin tables) |
| C6 | Row fingerprints | Equal to T0, except declared transformations (Nova `instances.compute_id` filled, Cinder `use_quota` filled, Glance none, Neutron `network_segment_ranges.physical_network` NULL→'') |
| C7 | Online migration summary tables | Saved; any "found but not done" rows explained (e.g. instances whose compute node record is gone) |
| C8 | Engine | `mariadb-upgrade` output OK; `mariadb-check --all-databases --check-upgrade` clean; no errors in the server error log; `SHOW WARNINGS` empty after DDL |
| C9 | Status tools that work offline: `neutron-status upgrade check`, `cinder-status upgrade check`, `keystone-status upgrade check`, `glance-status upgrade check`, `placement-status upgrade check` | No FAILURE; warnings explained |
| C10 | Durations per command and per DDL (`time`, error log timestamps) | Recorded; extrapolated to production table sizes |

After the final hop also:

| # | Check | Pass condition |
|---|---|---|
| F1 | Start 2026.1 keystone, placement-api, glance-api, cinder-api, neutron-server, nova-api and nova-conductor (with `[workarounds]disable_compute_service_check_for_ffu=True`) against the migrated DB, plus a 2026.1 RabbitMQ (library image) | Services start; no traceback on load |
| F2 | Re-run the API inventory of T0 with 2026.1 clients; `server show` **for every instance**, `volume show` for every volume, `port show` for every port (forces object/blob loading) | Same set of IDs and same key attributes as T0; zero 500 errors |
| F3 | `nova-status upgrade check` | Expected: "Older than N-1 computes" FAILURE until a 2026.1 `nova-compute` (fake driver) has started; then SUCCESS. Record both |
| F4 | Start one 2026.1 `nova-compute` with the fake driver under the same host name as a baseline compute | It updates its service and compute node records; `nova-manage db online_data_migrations` → 0 afterwards |

### 5.7 Experiment matrix

| Run | Path | Engine line | Dataset | Purpose |
|---|---|---|---|---|
| R1 | S2c | E1 (10.3→10.5→10.6→10.11→11.4) | Tier A | Main line |
| R2 | S2a | E1 | Tier A | Is the minimal path equal to R1? Compare final schema and fingerprints R1 vs R2 |
| R3 | S2c | E2 (dump/restore at 10.6 and 11.4) | Tier A | Engine alternative |
| R4 | S2c | E3 (10.3 → 11.4 direct) | Tier A copy | Only to learn whether it works; not a candidate without upstream support |
| N1 | Ussuri → 2026.1 code directly (Nova, Keystone, Cinder) | 11.4 | Tier A copy | Confirm the predicted refusal; record the exact error |
| N2 | Bridge without Cinder ODM, then 2024.1 | 10.11 | Tier A copy | Observe `9ab1b092a404` with NULL `use_quota` under oslo.db's `sql_mode`; record whether it fails or coerces |
| N3 | Duplicate rows (quotas / networksegments / segment ranges) added **by SQL on a disposable copy** | 11.4 | Tier A copy | Confirm the failure/deletion behaviour; label the data as test-only |
| R5 | Best of R1–R3 | — | Tier B | Before any production decision |

### 5.8 Stop conditions (any one stops the run; resuming is a new decision)

- A command exits non-zero, or an online migration returns 2.
- Any schema difference against the reference that is not on the declared list.
- Any row count or fingerprint change in a protected table that is not declared.
- Any need to stamp, edit `alembic_version`/`migrate_version`, or change rows by hand to continue. **Do not continue
  in that case**; record and escalate.
- The engine logs corruption, crash recovery or upgrade errors, or `mariadb-check` reports problems.
- F2 shows a missing resource, a 500, or a different attribute for any resource.
- A DDL extrapolated to production size exceeds the agreed window (value to be set by the change owner).
- Disk usage above 85 % (copies multiply quickly) or memory pressure kills containers. Fix the lab, then restart the run from
  its T0 copy.

### 5.9 Evidence to keep

Commands as run (secrets redacted), image digests, `pip freeze` per env, exit codes, timings, full logs, the check
script and its outputs per checkpoint, schema diffs, and the declared expected-difference list (written **before** R1).
Store everything under `journeys/ussuri-to-2026.1/experiments/` per the architect's layout. Mark results `LAB-VALIDATED`
only for what actually ran, with dataset tier and versions.

## 6. Decision gates for using S2 in production (from `openstack-change-review`)

Not ready unless all of these hold: R1 and R2 (or R3) pass C1–C10 and F1–F4. R5 on a production copy passes.
Restore of the Ussuri backup has been rehearsed with the Ussuri images present locally. The Nova service-version start-up
plan is designed and tested. Notification consumers' owners accept message loss. A named owner approves the point of no return.
Otherwise the recommendation falls back to S1 or to a hybrid in which the S2 bridge is
replaced by deploying 2023.1.

## 7. Open questions / what I could not verify

- Every outcome above is a prediction; the matrix in 5.7 is designed to settle them.
- MariaDB's official rules for skipping majors in place, and Galera rolling compatibility: mariadb.com unreachable.
- Ussuri on CentOS 8: exact distribution MariaDB version: not in Kolla's source; read it from the running image.
- Whether Nova 2026.1 objects load every Ussuri-era blob (F2 will tell, Tier B decides).
- Whether all six services' packages of one series co-install with that series' u-c on the chosen Python. If they do
  not, build one image per service.
- How the 2026.1 Kolla-Ansible Nova upgrade (which runs `nova-status` and aborts on FAILURE) can be driven after a DB
  fast-forward without bypassing checks: needs the Kolla-Ansible/Nova agents.
- Services other than the six analysed (Heat, Octavia, Barbican, …) and Neutron sub-projects: not analysed.
