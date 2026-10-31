# 04 — Backup, recovery and consistency requirements (Ussuri → 2026.1)

| Metadata | |
|---|---|
| Author | Agent 4 — Database and Messaging Specialist (Stage 1, independent investigation) |
| Model | Opus (claude-opus-5-5) |
| Date | 2026-10-31 |
| Status | Requirements derived from source reading; all procedures `PROPOSED-UNVERIFIED` unless a cited OzarLand label says otherwise |
| Inputs read | `00-mission-brief.md`; `04-database-migration-dependency-graph.md`, `04-database-migration-strategy.md`, `04-messaging-compatibility.md` (same author); OzarLand `openstack-kolla-ansible-operations/references/host-and-database-operations.md` (KA-OPS-12…21, 24…26), `openstack-incident-analysis/references/control-plane-recovery.md` (IA-CP-05/06/11), `openstack-change-review/SKILL.md`; `kolla-ansible@{ussuri-eol,origin/stable/2026.1}:ansible/roles/{mariadb,keystone,nova}/**`; `kolla@origin/stable/2026.1:docker/mariadb-server/extend_start.sh` |

## 1. Principles

1. **Schema migrations are one-way.** No OpenStack project supports downgrading a schema. After the first
   bridge `db sync` (Keystone in the proposed order), the **only** way back to Ussuri is to restore the Ussuri
   database *and* run the Ussuri images (`openstack-change-review`: point of no return).
2. **Galera is not a backup.** It replicates a bad migration to every node within seconds
   (`openstack-kolla-ansible-operations`, "MariaDB backup and restore").
3. **A backup counts only after it has been restored and checked.** It must be restored on another machine with the
   same engine version and pass the consistency checks below. That is what "known-good state" means here.
4. **The database is only part of the state.** Rolling back the DB while hypervisors, Ceph/LVM, OVS/OVN and image
   stores move on creates divergence. Every rollback plan must say what else is frozen in the window.
5. **Never repair by hand-editing migration bookkeeping** (`alembic_version`, `migrate_version`) or business rows
   during the window. A refusal from a migration tool is a stop condition (strategy §5.8).

## 2. What must be backed up before the point of no return

| Item | Why | How (Kolla-Ansible / generic) | Verification |
|---|---|---|---|
| All OpenStack databases, physical | Fast full restore of the Ussuri state | `kolla-ansible mariadb-backup` needs `enable_mariabackup` and a reconfigure first (KA-OPS-12, `LAB-VALIDATED` on 2026.1 only; behaviour on Kolla-Ansible 10.x **not verified**). Alternative: stop the cluster and copy **every node's** datadir volume (KA-OPS-17/18 practice) | Restore on an isolated host with MariaDB 10.3 (library image), start, `mariadb-check --all-databases`, run the T0 fingerprint script (strategy §5.5): identical |
| All OpenStack databases, logical | Engine-independent, diffable, needed for E2 and for auditing | `mysqldump --single-transaction --routines --triggers --events --hex-blob` per DB, taken **after all services are stopped** | Import into a scratch 10.3 server; row counts and fingerprints equal to the physical restore |
| `mysql` system DB / grants | Kolla-Ansible re-creates users from `passwords.yml`; external users (monitoring, billing) may exist | Logical dump of `mysql.user`/grants (`SHOW GRANTS` per user) | List compared after 2026.1 deploy |
| `/etc/kolla` (globals, inventory, `passwords.yml`, `config/` overrides) | DB passwords, cell URLs, RabbitMQ credentials, every override | Encrypted archive off-host (KA-OPS-22 practice) | Checksums; one test decrypt |
| Keystone Fernet keys (`keystone_fernet_tokens` volume) | Token validation across the cut-over; losing them invalidates all tokens (recoverable) | Copy volume | Keys count equal on all controllers |
| Keystone credential encryption keys | `keystone.credential.encrypted_blob` (EC2, TOTP, …) cannot be read without them. **Where Kolla Ussuri keeps them was not found in `kolla-ansible@ussuri-eol:ansible/roles/keystone`** | Locate on the platform (`[credential] key_repository`, default `/etc/keystone/credential-keys/`) and copy | After a restore, `openstack credential list` / `show` decrypts without error |
| Other at-rest keys referenced from DB rows (Barbican KEK in config, Octavia certs, etc., if enabled) | Encrypted DB content | From `/etc/kolla` / volumes | Per service |
| Ussuri **container images** (all, by digest) | Rollback needs them. Docker Hub `kolla/*` answers 401 per the brief, so lost images may be unrecoverable | `docker save` from a controller and a compute, or push to a local registry; record digests | `docker load` on an isolated host; image digests match |
| RabbitMQ definitions export and the old `rabbitmq` volume (kept, not deleted) | Rollback to Ussuri only | `rabbitmqctl export_definitions`; rename/keep volume | Not needed for 2026.1 |
| Glance file store, Cinder backend metadata, Nova instance dirs | Rows point to them | Out of scope for this agent; owners must confirm they are frozen or backed up | — |

Backups contain secrets and personal data (password hashes, `cell_mappings` URLs with DB passwords, encrypted
credentials). They must be encrypted at rest, access-logged, and destroyed after the retention period agreed by the
data owner. The same rules apply to lab copies (Tier B).

## 3. Recovery paths

| Situation | Recovery | Preconditions | Validation status |
|---|---|---|---|
| Failure **before** the first bridge `db sync` (pre-checks, stop, backup) | Restart Ussuri services; nothing changed in schema | Ussuri images and config untouched | `PROPOSED-UNVERIFIED` |
| Failure **during** the offline hops (lab or production) | Stop. Discard the working node's datadir. Re-seed from the physical backup (or T0 copy). Retry only after root cause, as a new decision | Work done on a single wsrep-off node with the other nodes' datadirs kept | `PROPOSED-UNVERIFIED` |
| Failure after 2026.1 control plane started, before workloads changed | Full Ussuri restore: stop 2026.1 containers, restore DB (Galera restore procedure KA-OPS-14: `LAB-VALIDATED` on 2026.1 only), restore `/etc/kolla`, deploy Ussuri images from the saved set, old RabbitMQ volume, flush Memcached | Ussuri images loadable; Kolla-Ansible 10.x venv kept; Galera nodes emptied before joining | `PROPOSED-UNVERIFIED`; KA-OPS-14 not validated on 10.x |
| Failure after users/workloads changed state on 2026.1 | Roll **forward** (fix on 2026.1). A restore would lose every change since cut-over while hypervisors, volumes and ports kept them | Decision by the accountable owner; incident process | — |
| Galera fully stopped during the window | `kolla-ansible mariadb-recovery` (KA-OPS-17/18 `LAB-VALIDATED` on 2026.1); copy every node's datadir first | Every node reachable; read `grastate.dat` first | as cited |

The rollback window closes when the platform is reopened to users. The change record must say so explicitly.

## 4. Consistency requirements (what "the migrated database is consistent" means)

A migrated database is accepted only if **all** of the following hold. The checks are defined in strategy §5.5–5.6 and
run identically in lab and production.

1. **At the code heads.** For each service, the recorded revision equals the heads of the code that will run:
   - Nova: `nova-manage api_db version`, `nova-manage db version` for cell0 and every cell;
   - Keystone: `keystone-manage db_version` (expand and contract heads);
   - Cinder: `cinder-manage db version`;
   - Glance: `glance-manage db version` and `glance-manage db check` exit 0 (exit 3/4/5 means expand/migrate/contract pending; `glance@origin/stable/2026.1:glance/cmd/manage.py:check`);
   - Placement: `placement-manage db version`;
   - Neutron: `neutron-db-manage current`, `neutron-db-manage check_migration`, `neutron-db-manage has_offline_migrations` (none expected; contract branch unchanged since Newton).
2. **No pending data migrations.** `nova-manage db online_data_migrations`, `placement-manage db
   online_data_migrations` and `cinder-manage db online_data_migrations` return 0. Rows reported "found, not
   migratable" (e.g. Nova instances whose compute node record no longer exists) are listed and explained one by one.
   Cinder: `SELECT COUNT(*) FROM cinder.volumes WHERE use_quota IS NULL` = 0 **before** any ≥ 2024.1 code runs.
3. **Schema equals a fresh schema of the same code on the same server**, except for the declared list
   (`mysqldump --no-data` + `information_schema` diff against `<db>_ref` built by the same release). Pay attention to
   column charset/collation, nullability (`use_quota`), indexes and FKs. Old schemas created under `utf8`
   (= utf8mb3) keep that. A table created later without an explicit charset may get the server default. Mixed collations
   across joined tables must be listed.
4. **No data lost or altered beyond declared transformations.** Row counts per table and business-key fingerprints
   per protected table equal T0, except the declared ones: Nova `instances.compute_id`; Cinder `use_quota`, default
   backup quota classes, soft-deleted consistencygroup quota rows; Neutron segment-range normalisation and dropped legacy
   plugin tables (which must have been empty); `migrate_version` dropped.
5. **Engine healthy.** `mariadb-upgrade` completed (Kolla runs it as `upgrade_mariadb`), `mariadb-check
   --check-upgrade` clean, no corruption or crash-recovery messages, no DDL warnings.
6. **Readable by the new code.** Every instance, volume, image, port and project can be read through the 2026.1 APIs
   (strategy F2), and the API inventory matches T0.
7. **Status tools.** `nova-status`, `neutron-status`, `cinder-status`, `keystone-status`, `glance-status`,
   `placement-status upgrade check` (2026.1) have no unexplained FAILURE. The expected Nova "Older than N-1 computes"
   failure lasts only until all computes run 2026.1 (`nova@origin/stable/2026.1:nova/cmd/status.py`).
8. **Galera rebuilt.** `wsrep_cluster_size` = node count, `Primary`, `Synced` on all nodes (KA-OPS-18 verify step);
   the T0 fingerprints computed on **each** node are equal.
9. **RabbitMQ / Memcached** (messaging doc §6–7): fresh cluster healthy, all quorum queues/streams with full
   membership, Memcached empty at start.

## 5. Requirements on the platform before the window (Ussuri side)

- Ussuri online migrations complete (Nova, Placement; Cinder's Ussuri list too) with Ussuri code.
- No long-running operations: no instance with `task_state`, no `migrations` in progress, no volume in a transitional
  state, no image in `saving`/`importing`, no `build_requests`.
- Read-only data pre-checks (strategy §4) clean, or each finding fixed by a separate reviewed change with supported
  tools before the window.
- Optional, agreed with data owners: archive and purge soft-deleted rows to shorten DDL. Supported and state-changing;
  needs a backup first.
- Disk: free space on the migration node ≥ 3 × the largest database (datadir copy + logical dump + DDL table
  rebuilds). Exact factor **not measured**; take it from R5.
- Time: window length set from the R5 timings plus margin, with a decision point after the bridge hop (continue,
  or restore Ussuri).

## 6. Classification

| Item | Status |
|---|---|
| `kolla-ansible mariadb-backup` / Galera restore / `mariadb-recovery` | `LAB-VALIDATED` on Kolla-Ansible 22.x (OzarLand); **Not validated** on 10.x (Ussuri) |
| Schema downgrade after a migration | **Incompatible** (unsupported upstream) |
| Restore-based rollback to Ussuri before reopening | **Technically possible**; Not validated; depends on saved Ussuri images |
| Consistency criteria 1–9 | Proposed; checks are Officially supported tools plus read-only SQL; the composite procedure is `PROPOSED-UNVERIFIED` |

## 7. Open questions / what I could not verify

- Where the Ussuri deployment keeps Keystone credential encryption keys (not found in the Ussuri Kolla-Ansible keystone
  role). Losing them makes `keystone.credential` unreadable.
- Whether `kolla-ansible mariadb-backup` works as described on Kolla-Ansible 10.x (only 2026.1 labs are cited).
- Real database sizes, and hence window length and disk factor: needs `information_schema` from production.
- Whether the Ussuri images and Kolla-Ansible 10.x environment are still fully present locally (precondition for any
  rollback): to be inventoried by the deployment agents.
- Which other stateful systems (Ceph, OVN DBs, Glance store) are frozen during the window: owners to confirm.
