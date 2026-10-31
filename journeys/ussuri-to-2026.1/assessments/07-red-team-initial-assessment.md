# 07 — Red team initial assessment (independent, pre-registered)

| Field | Value |
|---|---|
| Author | Agent 7 — Independent Red Team Reviewer |
| Model | Fable 5.1 (claude-fable-5-1), independent of the architect's model |
| Date | 2026-10-31 |
| Status | `PROPOSED-UNVERIFIED` (code and docs read, nothing executed; written **before** reading any other agent's output) |
| Inputs read | `assessments/00-mission-brief.md`; OzarLand `SKILL.md` + `references/evidence-and-safety.md` + `references/upgrade-readiness.md` of `openstack-change-review`, and `SKILL.md` of `openstack-automation-review`, `openstack-incident-analysis`, `openstack-operational-decisions`; upstream trees under `/home/user/src/*` (refs: `ussuri-eol`, `xena-eom`, `yoga-eom`, `zed-eom`, `2023.1-eom`, `2023.2-eol`, `2024.1-eom`, `2024.2-eol`, `2025.1-eom`, `origin/stable/2026.1`, `releases@HEAD`) |
| Not read (by design) | anything else under `journeys/` or `lab/` |

Evidence vocabulary follows the brief: **Officially supported / Technically possible but unsupported / Experimentally validated / Not validated / Incompatible**. Every technical statement below is `DOCUMENTED-UNVERIFIED` (read in source, not executed) unless marked otherwise. Nothing in this document is validated in a lab or in production.

Skills that shaped this document: `openstack-change-review` (decision gates, point of no return, verification designed before execution), `openstack-operational-decisions` (gates before scoring, "keep as is" as an option, do not stack uncertainty), `openstack-automation-review` (Kolla-Ansible runs are automation: every skipped tag is a removed safeguard), `openstack-incident-analysis` (Galera bootstrap, RabbitMQ reset, direct DB edits and purges are the dangerous moves; evidence before action).

---

## 0. Summary of the strongest objections

1. **"One journey" is not one upgrade of OpenStack; it is three unrelated platform jumps stacked** — OpenStack 13 releases, the host OS (Ubuntu 18.04 / CentOS 8 → Ubuntu 24.04 / Rocky 10 / Debian 13), and the infrastructure services (MariaDB 10.3 → 11.4, RabbitMQ 3.8 → 4.2, libvirt 4.0 → ≥8.0 with ≥10.0 announced). Kolla-Ansible 2026.1 refuses the old host OS in `prechecks` and refuses the RabbitMQ jump in `version-check`. Any "direct" path that succeeds has had safeguards removed by hand.
2. **Nova, Keystone and Cinder 2026.1 cannot migrate an Ussuri database at all.** Their `db sync` is alembic-only (legacy sqlalchemy-migrate support removed in 2023.2), their alembic chains start with an *initial* revision that unconditionally `CREATE TABLE`s, and nothing in the 2026.1 trees stamps an existing database. The only ways through are (a) code from a release that still carries both systems (Xena/Yoga/Zed/2023.1), or (b) a manual `alembic stamp` — which is an act of faith about schema equality that must be proven, not assumed.
3. **Data migrations live in service code and are deleted later.** Concrete case: Cinder 2024.1 made `volumes.use_quota` / `snapshots.use_quota` NOT NULL *and in the same release removed the online data migration that fills those columns*. A database fast-forwarded from Ussuri (where the columns do not exist) through Yoga's schema (nullable, left NULL by design) into 2024.1 either fails the ALTER (strict SQL mode) or **silently coerces NULL to 0 = "do not count for quota"** (non-strict mode). This is the silent-loss pattern the team must prove absent for every service, not just this one.
4. **The compute envelope is Epoxy, not Ussuri.** Nova 2026.1 refuses to start any service while a `nova-compute` with service version < 68 exists (Ussuri = 51), and compute RPC 6.x removed 5.x compatibility. There is no rolling, mixed-version path from Ussuri computes; a workaround flag exists only to let control services start *before* computes update, not to run old computes.
5. **Rollback by "restore the DB" is not credible once new code has written**, and for strategy C the rollback problem moves to the data plane: images, volumes and running VMs with unrecorded machine types and Ussuri-era CPU models.

---

## 1. Evidence ledger (what the source trees say)

All items are **Observed in source** (read with `git show`), not executed.

### 1.1 Release lifecycle
| # | Statement | Source |
|---|---|---|
| E1 | Ussuri EOL 2024-02-20; Victoria/Wallaby/Xena EOL 2025-12-19; Yoga, Zed, 2023.1, 2024.1 *unmaintained*; 2023.2 EOL 2025-04-30; 2024.2 EOL 2026-04-29; 2025.1 moved to unmaintained 2026-10-02; 2025.2 and 2026.1 maintained | `releases@HEAD:data/series_status.yaml` |
| E2 | Consequence: every intermediate release' code the team would execute (Victoria…2024.2) is EOL or unmaintained upstream. Branch names `stable/<series>` for those no longer exist (tags `*-eol`, `*-eom`, or `unmaintained/<series>`) | `git branch -r` / `git tag` in each repo |

### 1.2 Nova
| # | Statement | Source |
|---|---|---|
| N1 | Ussuri main DB is sqlalchemy-migrate version **407**, API DB **072** | `nova@ussuri-eol:nova/db/sqlalchemy/migrate_repo/versions/407_placeholder.py`, `…/api_migrations/migrate_repo/versions/072_placeholder.py` |
| N2 | Last *real* legacy migrations are `402_train.py` (main) and `067_train.py` (API); 403–422 and 068–087 are placeholders | `nova@yoga-eom:nova/db/main/legacy_migrations/versions/`, `nova@yoga-eom:nova/db/api/legacy_migrations/versions/` |
| N3 | Yoga (and Xena, Zed, 2023.1) `db_sync` detects a migrate-controlled DB, requires it to be ≥ `MIGRATE_INIT_VERSION` (main 401, api 66), applies remaining legacy steps, then **stamps** alembic `8f2f1571d55b` / `d67eeaabee36` | `nova@yoga-eom:nova/db/migration.py` (`MIGRATE_INIT_VERSION`, `_init_alembic_on_legacy_database`) |
| N4 | Legacy migrations and this bridging logic were **removed** in commit `fd39e4b4be` ("db: Remove legacy migrations"), first contained in `2023.2-eol`. 2026.1 `db_sync` only calls `alembic upgrade head` and rejects numeric versions | `nova@stable/2026.1:nova/db/migration.py`; `nova@stable/2026.1:releasenotes/notes/remove-sqlalchemy-migrate-907c200314884d81.yaml` |
| N5 | 2026.1 alembic chain (main): `8f2f1571d55b` (initial, `down_revision=None`, `upgrade()` starts with `op.create_table('instances', …)` — **no existence guard**) → `16f1fbcab42b` → `ccb0fa1a2252` → `960aac0e09ea` → `1b91788ec3a6` (drops `migrate_version`) → `1acf2c98e646` → `13863f4e1612` → `d60bddf7a903` → `2903cd72dc14` | `nova@stable/2026.1:nova/db/main/migrations/versions/` |
| N6 | Online data migrations in 2026.1 still include all Ussuri ones plus `PciDevice.populate_dev_uuids` (Victoria) and `populate_instance_compute_id` (2023.2) | `nova@stable/2026.1:nova/cmd/manage.py` (`online_migrations`) |
| N7 | `SERVICE_VERSION` 51 (Ussuri) vs 72 (2026.1). `OLDEST_SUPPORTED_SERVICE_VERSION = 'Epoxy'` = 68. `raise_if_old_compute()` runs at **every** service start; only `[workarounds]disable_compute_service_check_for_ffu` downgrades it to a warning, documented as being for the window "before compute nodes have been able to update their service record" | `nova@stable/2026.1:nova/objects/service.py` (lines 40, 264–298), `nova/utils.py` (~1040–1083), `nova/service.py` (~287–293), `nova/conf/workarounds.py` (`disable_compute_service_check_for_ffu`) |
| N8 | Compute RPC 6.0 "Remove 5.x compatibility" (Ussuri computes speak 5.11) | `nova@stable/2026.1:nova/compute/rpcapi.py` (~395–400) |
| N9 | Upstream support envelope: N and N-2 coexistence since 2023.1; conductor fails to start if an older compute is detected; pre-2023.1 releases support only N/N+1 | `nova@stable/2026.1:doc/source/admin/upgrades.rst` (~50–64) |
| N10 | `nova-status upgrade check` (2026.1): Cells v2, Placement, Cinder API, policy JSON→YAML, **Older than N-1 computes**, **hw_machine_type unset (WARNING)**, **Service User Token Configuration (FAILURE if `[service_user]send_service_user_token` is false)** | `nova@stable/2026.1:nova/cmd/status.py` (~264–311) |
| N11 | Machine type recording started in Wallaby; instances created on Ussuri have **no recorded machine type**; `nova-manage libvirt set_machine_type` requires STOPPED/SHELVED and `--force` can change the guest ABI | `nova@stable/2026.1:releasenotes/notes/libvirt-store-and-change-default-machine-type-bf86b4973c4dee4c.yaml` |
| N12 | `MIN_LIBVIRT_VERSION (8,0,0)`, `MIN_QEMU_VERSION (6,2,0)`, `NEXT_MIN_LIBVIRT (10,0,0)`, `NEXT_MIN_QEMU (8,2,2)` vs Ussuri `(4,0,0)/(2,11,0)` | `nova@stable/2026.1:nova/virt/libvirt/driver.py` (~207–210); `nova@ussuri-eol:…/driver.py` (~225–233) |
| N13 | Nova flipped `enforce_scope`/`enforce_new_defaults` to True by default (note first in 2023.1) | `nova@stable/2026.1:releasenotes/notes/enable-enforce-scope-and-new-defaults-14db8c75b263b599.yaml` |

### 1.3 Keystone
| # | Statement | Source |
|---|---|---|
| K1 | Ussuri expand repo ends at **079** (`079_expand_update_local_id_limit.py`); Yoga's legacy repo also ends at 079 ("the great squash of migrations in yoga") | `keystone@ussuri-eol:keystone/common/sql/expand_repo/versions/`, `keystone@2023.1-eom:keystone/common/sql/upgrades.py` (~159–180) |
| K2 | 2023.1 still bridges: requires legacy ≥ 072, upgrades the three legacy repos, stamps alembic `27e647c0fad4`. Removed by commit `8c9462f6f` "db: Remove legacy migrations", first in `2023.2-eol` | same file; `git log -S'_init_alembic_on_legacy_database'` |
| K3 | 2026.1 `upgrades.py` has no legacy detection; `27e647c0fad4` `upgrade()` creates tables unguarded; `--migrate` is a no-op; `_validate_upgrade_order` refuses contract before expand | `keystone@stable/2026.1:keystone/common/sql/upgrades.py`, `…/migrations/versions/27e647c0fad4_initial_version.py` |
| K4 | Kolla upgrade runs `db_sync --expand`, `--migrate`, then `--contract` on the last keystone host | `kolla@stable/2026.1:docker/keystone/keystone/extend_start.sh` (~24–37); `kolla-ansible@stable/2026.1:ansible/roles/keystone/tasks/upgrade.yml` |

### 1.4 Cinder
| # | Statement | Source |
|---|---|---|
| C1 | Ussuri legacy version **136**; Yoga legacy goes to **145** with real steps `140_create_project_default_volume_type`, `141_add_quota_usage_unique_constraint`, `145_add_use_quota_fields` (adds `use_quota` **nullable**, comment: existing rows left NULL "to allow rolling upgrades with the online data migration pattern") | `cinder@ussuri-eol:cinder/db/sqlalchemy/migrate_repo/versions/`, `cinder@yoga-eom:cinder/db/legacy_migrations/versions/145_add_use_quota_fields.py` |
| C2 | Zed/2023.1 bridge legacy→alembic (`MIGRATE_INIT_VERSION = 134`, stamp `921e1a36b076`); removed by `e9dccb93b` "db: Remove legacy migrations", first in `2023.2-eol` | `cinder@zed-eom:cinder/db/migration.py`; `cinder@stable/2026.1:cinder/db/migration.py` |
| C3 | `volume_use_quota_online_data_migration` / `snapshot_use_quota_online_data_migration` exist in Yoga…2023.2 and are **gone in 2024.1** | `cinder@2023.2-eol:cinder/cmd/manage.py` (~166–168) vs `cinder@2024.1-eom:cinder/cmd/manage.py` |
| C4 | `9ab1b092a404_make_use_quota_non_nullable` first appears in **2024.1** and does `ALTER COLUMN use_quota … nullable=False, server_default=true` with the comment "the online migrations from the previous release must already have been run" | `cinder@2024.1-eom:cinder/db/migrations/versions/`; `cinder@stable/2026.1:…/9ab1b092a404_make_use_quota_non_nullable.py` |
| C5 | `cinder-status upgrade check` includes "Removed Drivers"; 2026.1 release notes list dozens of drivers removed/unsupported since Ussuri | `cinder@stable/2026.1:cinder/cmd/status.py` (~243–254); `releasenotes/notes/*remov*driver*`, `*unsupported*` |
| C6 | Cinder still ships `enforce_scope=False, enforce_new_defaults=False` defaults | `cinder@stable/2026.1:cinder/policy.py` (~36–42) |

### 1.5 Neutron, Glance, Placement
| # | Statement | Source |
|---|---|---|
| Q1 | Neutron: every Ussuri migration file is still present in 2026.1; `CONTRACT_HEAD` unchanged (`5c85685d616d`, Newton); no contract migrations after Newton; expand chain continuous Ussuri→2026.1 | `neutron@*/neutron/db/migration/alembic_migrations/versions/` (comm of file lists), `CONTRACT_HEAD`, `EXPAND_HEAD` |
| Q2 | `neutron-status upgrade check` has 12 checks (port MAC, NetworkSegments unique constraint, binding profile, extra DHCP options, duplicated HA network, tag limits, RBAC `target_project`, …) — several are **data** sanity checks that can fail on old data | `neutron@stable/2026.1:neutron/cmd/upgrade_checks/checks.py` (~234–258) |
| Q3 | Neutron flipped RBAC defaults too (`enable-enforce-scope-and-new-defaults-1f82a9eb71125f5d.yaml`; release not pinned here) | `neutron@stable/2026.1:releasenotes/notes/` |
| G1 | Glance alembic chain continuous Ussuri→2026.1 (E-M-C triplets per release; `2024_1_expand01_add_cache_tables`); data migrations present (`train_migrate01_backend_to_store` already in Ussuri) | `glance@*/glance/db/sqlalchemy/alembic_migrations/{versions,data_migrations}/` |
| G2 | `location_strategy` removed; `show_multiple_locations` deprecated; `enable_image_import` removed; sqlite cache driver deprecated; RBAC defaults flipped (2023.1) | `glance@stable/2026.1:releasenotes/notes/removed-location-strategy-functionality-b1b562e68608a6f8.yaml`, `enable-enforce-scope-and-new-defaults-ef543183e6c2eabb.yaml`, others |
| P1 | Placement alembic chain continuous (`b4ed3a175331` → `b5c396305c25` → `611cd6dffd7b` → `422ece571366` consumer types → `a082b8bb98d0`) | `placement@*/placement/db/sqlalchemy/alembic_migrations/versions/` |

### 1.6 Toolchain / libraries
| # | Statement | Source |
|---|---|---|
| L1 | Ussuri upper-constraints: SQLAlchemy 1.3.16, sqlalchemy-migrate 0.13.0, alembic 1.4.2, oslo.db 8.1.1, Python 3.6–3.8. 2026.1: SQLAlchemy 2.0.46, alembic 1.18.4, oslo.db 18.0.0, no sqlalchemy-migrate | `requirements@ussuri-eol:upper-constraints.txt`, `requirements@stable/2026.1:upper-constraints.txt`, `nova@ussuri-eol:setup.cfg` |
| L2 | oslo.db 2026.1 no longer ships `oslo_db/sqlalchemy/migration.py` nor `migration_cli/ext_migrate.py` | `git ls-tree` of `oslo.db@stable/2026.1` vs `ussuri-eol` |

### 1.7 Kolla / Kolla-Ansible
| # | Statement | Source |
|---|---|---|
| KA1 | Host OS support: Ussuri = CentOS 8, Debian 10, RHEL 8, Ubuntu 18.04; 2026.1 = CentOS Stream 10, Debian 13, Rocky 10, Ubuntu 24.04. `prechecks` **asserts** the host is in the list | `kolla-ansible@ussuri-eol:doc/source/user/support-matrix.rst`; `kolla-ansible@stable/2026.1:doc/source/user/support-matrix.rst`, `ansible/roles/prechecks/tasks/host_os_checks.yml` |
| KA2 | Base images: Ussuri CentOS 8 / Debian 10 / Ubuntu 18.04; 2026.1 CS10 / Debian trixie / Rocky 10 / Ubuntu 24.04 | `kolla@ussuri-eol:kolla/common/config.py`, `kolla@stable/2026.1:kolla/common/config.py` |
| KA3 | MariaDB 10.3 (Ussuri) → 11.4 (2026.1). Upgrade role: set SST to rsync, redeploy, set back, then `mariadb-upgrade` via `KOLLA_UPGRADE`. **No MariaDB version-path check** exists. ProxySQL now mandatory, clustercheck removed on upgrade | `kolla@*/kolla/template/repos.yaml`; `kolla-ansible@stable/2026.1:ansible/roles/mariadb/tasks/{upgrade,post-upgrade}.yml`; `kolla@stable/2026.1:docker/mariadb/mariadb-server/extend_start.sh` (~46–57); `releasenotes/notes/drop-clustercheck-and-haproxy-support-for-mariadb-*.yaml` |
| KA4 | RabbitMQ 3.8 (Ussuri, `centos-rabbitmq-38`) → 4.2 (2026.1). `version-check.yml` **asserts** minor+1 or an explicit path in `rabbitmq_allowed_upgrades` (only `3.13→4.x`, `4.0→4.x`). Docs: "does not support jumping two versions in one upgrade"; durable/quorum queue change requires `kolla-ansible rabbitmq-reset-state` with all consumers stopped | `kolla-ansible@stable/2026.1:ansible/roles/rabbitmq/tasks/version-check.yml`, `ansible/roles/rabbitmq/defaults/main.yml` (~132–139), `doc/source/user/operating-kolla.rst` (~177–185), `doc/source/reference/message-queues/rabbitmq.rst` (~114–192) |
| KA5 | `rabbitmq-reset-state` = `stop_app; force_reset || reset; start_app` (comment: `force_reset` unsupported with Khepri) | `kolla-ansible@stable/2026.1:ansible/roles/rabbitmq/tasks/reset-state.yml` |
| KA6 | Nova upgrade: runs `nova-status upgrade check` **with the new image**, fails only when rc ∉ {0,1} (FAILURE blocks, WARNING passes); `nova_safety_upgrade` default false; conductor/API `db sync` via `KOLLA_UPGRADE`; `online_data_migrations` via `KOLLA_OSM` afterwards | `kolla-ansible@stable/2026.1:ansible/roles/nova/tasks/upgrade.yml`, `ansible/roles/nova-cell/tasks/{upgrade,rolling_upgrade,online_data_migrations,version-check}.yml`; `kolla@stable/2026.1:docker/nova/nova-api/extend_start.sh` |
| KA7 | Nova-cell `version-check.yml` only prevents a libvirt **downgrade**; there is no check that the running QEMU can live-migrate to the new one | same |
| KA8 | Brief (Reported, to verify): Docker Hub `kolla/*` Ussuri…Yoga tags answer 401 / `inactive` — intermediate-release images may have to be **built** from EOL distro repositories | `00-mission-brief.md` |

---

## 2. Hypotheses and unsupported assumptions, per strategy

### Strategy A — direct in-place upgrade with Kolla-Ansible 2026.1

**My hypothesis:** *Incompatible* as an unattended `kolla-ansible upgrade`; *Technically possible but unsupported* only after disabling at least four independent safeguards, at which point it is no longer "Kolla-Ansible's upgrade" but a hand-built procedure wearing its clothes.

Assumptions the team is likely to make, and why they fail:

| Assumption | Why it is unsupported |
|---|---|
| "Kolla-Ansible will migrate whatever it finds" | `prechecks` asserts host OS (KA1); `rabbitmq/version-check` asserts the 3.8→4.2 jump is invalid (KA4); `nova-status` returns FAILURE if `[service_user]send_service_user_token` is unset (N10). Each requires `--skip-tags` or config edits to pass. |
| "`nova-manage db sync` with 2026.1 will bring the Ussuri schema forward" | It will try to `CREATE TABLE instances` on a populated database (N4, N5). Same for Keystone (K3) and Cinder (C2). The run fails; the failure mode after a *partial* alembic transaction on MySQL DDL (non-transactional) is a half-created set of tables in the live database. |
| "Mixed Ussuri computes / 2026.1 control plane is a rolling upgrade" | Refused at start (N7), RPC incompatible (N8), outside the documented envelope (N9). |
| "Upgrade = container swap, hosts stay" | Hosts must change OS family/version (KA1); on a compute that means reinstall, i.e. every VM moves at least once anyway. The `nova_libvirt` container's QEMU (24.04 userland) running on a 4.15/4.18 kernel host is untested territory and not what the support matrix describes. |
| "RabbitMQ state does not matter, we recreate it" | True only if **all** consumers are stopped first; otherwise old classic/HA-policy queues collide with durable/quorum declarations (`PRECONDITION_FAILED`) — KA4 docs make the stop-everything order explicit. |

### Strategy B — database fast-forward (run intermediate releases' migrations sequentially, deploy only 2026.1)

**My hypothesis:** *Technically possible but unsupported*, and **only** if the "fast-forward" includes the **data** migrations and status checks of each hop, executed with the hop's own code under the hop's own Python/SQLAlchemy constraints. Treating it as "run alembic/migrate scripts in a loop" will corrupt or lose data in at least one known place (C1–C4).

Assumptions and traps:

| Assumption | Reality |
|---|---|
| "All historical migrations are still in the 2026.1 tree" | False for Nova, Keystone, Cinder (N4, K2, C2): the pre-alembic history is gone and the alembic initial revisions are not idempotent. True (so far as file lists show) for Neutron, Glance, Placement (Q1, G1, P1). |
| "Alembic heads == consistent data" | A head only proves DDL ran. Cinder `use_quota` (C1–C4), Nova `populate_instance_compute_id`, `populate_dev_uuids` (N6), Placement consumer types/incomplete consumers (P1, `placement-status`) are *data* steps outside alembic. Heads will be "up to date" while rows are NULL or semantically wrong. |
| "We can stamp the alembic initial revision because 402 == 8f2f1571d55b" | Plausible for Nova (N2) and Keystone (K1) **but unproven**: `16f1fbcab42b` exists precisely because shadow tables differed from the model. A stamp must be backed by a schema diff (see acceptance criteria), not by reading placeholder file names. For Cinder a stamp is **wrong**: 137–145 are real schema changes absent from Ussuri. |
| "Old `*-manage` code will run on the lab host" | Ussuri–Wallaby need Python ≤3.8, SQLAlchemy 1.3, sqlalchemy-migrate 0.13 (L1); 2026.1 oslo.db has no migrate support (L2); the lab host is Python 3.13. Each hop needs its own container/venv with that hop's `upper-constraints.txt`, from EOL branches; wheel availability for py3.6/3.8 is `unknown`. |
| "`db sync` success == migration success" | `*-manage` exits 0 after DDL; it does not run `*-status upgrade check` nor online migrations. Kolla's own flow runs `online_data_migrations` as a separate step (KA6) and nova-status *before* the sync. |
| "The order within a hop does not matter" | Keystone refuses contract before expand (K3); Cinder 2024.1 requires 2023.2's online migrations to have completed (C4); Nova `1b91788ec3a6` drops `migrate_version` — after it, no legacy tool can ever read the DB again (point of no return). |
| "MySQL will fail loudly if data is wrong" | Only in strict `sql_mode`. Kolla's MariaDB `sql_mode` across 10.3→11.4 defaults is `unknown` here; in non-strict mode `ALTER … NOT NULL` turns NULL into 0/'' silently (C4). |
| "RabbitMQ / Galera state can be ignored because we redeploy" | For the DB: MariaDB 10.3 → 11.4 must be `mariadb-upgrade`d (KA3) — the Kolla role has no version-path guard, and whether a direct 10.3 → 11.4 `mariadb-upgrade` is supported by MariaDB (and Galera 3 → 4 wsrep provider change) is `unknown` from local evidence — treat as unsupported until shown. |
| "Rollback = restore the DB dump" | Valid only until the first new-code write and only if the *compute hosts, images and volumes* are also at the old state. After `1b91788ec3a6` or Keystone contract, old code cannot even read the DB version. |

### Strategy C — parallel 2026.1 cloud with resource/workload migration

**My hypothesis:** the only strategy that is *Officially supported* at the OpenStack layer (a fresh 2026.1 deployment is supported; nothing is "upgraded"), but the hard problems move from schema to **identity, data plane and semantics**. The team will under-estimate it because its risks do not show up as a failing command.

Assumptions and traps:

| Assumption | Reality |
|---|---|
| "A fake-driver / API-only lab proves workload preservation" | It proves API shape only. Real risks are: Ussuri guests with **unrecorded machine type** (N11) being re-created on QEMU ≥ 8 with a different default machine type / CPU model → guest ABI change, boot failure, licensing re-activation, PCI topology change; image formats and `hw_*` properties; Ceph/LVM volume transfer; MTU/overlay differences. None is visible with the fake driver. |
| "IDs can be preserved" | Project/user/domain IDs: possible only if Keystone is re-created with the same IDs (a DB copy — which drags Keystone's DB through strategy B) or via the API (new IDs → every tenant's `clouds.yaml`, Heat stacks, Terraform state, Octavia/Magnum references, Cinder/Glance ownership columns break). Instance UUIDs cannot be preserved via the API. Port MAC/IP can, floating IPs only if the external network is shared or re-addressed. |
| "Quotas, policies and RBAC carry over" | New-defaults RBAC is on in Nova/Glance/Neutron (N13, G2, Q3): service accounts and integrations with legacy `admin`-everywhere assumptions change behaviour. Must be tested against the real users and automation. |
| "Rollback is trivial: the old cloud still exists" | Only while the old cloud is not drained and its hardware not re-purposed. After hosts are reinstalled into the new cloud, the rollback target shrinks every day; data moved (volumes, images) must be moved *back* — define the point of no return per workload, not per cloud. |
| "Downtime is per-VM, so it is small" | Each VM needs at least one cold move (snapshot/export → import) unless shared storage lets you re-attach; snapshot of a Ussuri instance to Glance then boot on 2026.1 changes the instance's machine type and probably its disk bus; cloud-init re-runs with a new instance-id. |

### Strategy D — hybrids (DB fast-forward for some services, API-level reconstruction for others)

**My hypothesis:** inherits the *worst* of B and C unless the split is made along a dependency-safe line. Cross-service foreign references (project IDs in Nova/Cinder/Glance/Neutron rows; image IDs in instances; volume IDs in BDMs; port IDs in instance_info_caches; `consumer` UUIDs in Placement) make "Keystone via B, everything else via C" or vice-versa fragile.

Traps:
- If Keystone is fast-forwarded (to keep IDs) but Nova is rebuilt via API, Placement allocations and `instance_mappings` are recreated under the same project IDs — fine — but **Cinder** volumes imported via `cinder manage` get new IDs and lose snapshots/backups lineage, and `volume_attachment` history is gone.
- If Nova is fast-forwarded (to keep instance UUIDs) the compute envelope (N7) still forces every compute to be *reinstalled and re-registered*; the instances' `host`/`node`/`compute_id` rows point to hosts that no longer exist → every instance needs `evacuate`-like reconciliation: this is the "fence before evacuating" hard rule of `openstack-incident-analysis`, applied to the entire fleet.
- A hybrid multiplies the number of distinct procedures that must each be rehearsed; `openstack-operational-decisions`: do not stack uncertainty.

---

## 3. Numbered risk register (with evidence)

| # | Risk | Strategy | Severity | Evidence |
|---|---|---|---|---|
| R1 | 2026.1 `nova-manage db sync` / `keystone-manage db_sync` / `cinder-manage db sync` on an Ussuri DB attempts `CREATE TABLE` on existing tables; MySQL DDL is non-transactional → partial state | A, B, D | Blocking | N4, N5, K3, C2 |
| R2 | Cinder `use_quota` NULL rows reach `9ab1b092a404` after the filling online migration was deleted → ALTER fails (strict) or **silent coercion to false** (non-strict) → quota accounting wrong forever | B, D | Blocking (silent data loss) | C1–C4 |
| R3 | Nova control services refuse to start with any compute service version < 68; Ussuri computes are 51; RPC 5.x removed | A, B, D | Blocking | N7, N8, N9 |
| R4 | `[workarounds]disable_compute_service_check_for_ffu=True` used as a permanent setting instead of a startup-window workaround → mixed-version fleet runs outside any tested path | A, B | Major | N7 |
| R5 | `alembic stamp` of initial revisions without a proven schema identity; Cinder stamp is provably wrong (137–145) | B, D | Blocking | N2, N3, K1, C1 |
| R6 | `1b91788ec3a6` (Nova), `89aa6f9639f9` (Cinder) drop `migrate_version`; Keystone `--contract`: after these, no older code can read the DB → unannounced point of no return | B | Major | N5, C4, K3 |
| R7 | Host OS must jump 18.04/CentOS 8 → 24.04/Rocky 10/Debian 13; `prechecks` asserts it; compute hosts therefore get reinstalled → every VM moves anyway | A, B, D | Blocking for "in place" | KA1, KA2 |
| R8 | MariaDB 10.3 → 11.4 in one `mariadb-upgrade`; Galera provider 3 → 4; no version-path guard in the role; whether MariaDB supports skipping majors is `unknown` here | A, B, D | Major | KA3 |
| R9 | RabbitMQ 3.8 → 4.2 refused by `version-check`; skipping the tag bypasses the feature-flag/Khepri sequence; `force_reset` unsupported with Khepri | A, B | Major | KA4, KA5 |
| R10 | Old classic/HA queues meet durable/quorum/stream declarations → `PRECONDITION_FAILED`, services crash-loop; `rabbitmq-reset-state` run while consumers are alive recreates the old queues | A, B, D | Major | KA4 docs (~122–161) |
| R11 | Instances with unrecorded machine type (every Ussuri-created guest) land on QEMU ≥ 8 defaults; `nova-status` only WARNs; `set_machine_type --force` can change ABI | A, B, C, D | Major (silent guest breakage) | N10, N11, N12 |
| R12 | libvirt 4.0 → ≥ 8.0/10.0 and QEMU 2.11 → ≥ 6.2/8.2: live migration *from* Ussuri hosts to 2026.1 hosts is cross-many-major; CPU model names and machine type versions (`pc-i440fx-bionic` style distro types) may not exist on the target | A, C, D | Major | N12; distro machine types: `unknown` |
| R13 | RBAC new defaults on by default in Nova, Glance, Neutron → service users / automation / Horizon flows lose or gain rights; Cinder still off → inconsistent experience | all | Major | N13, G2, Q3, C6 |
| R14 | `nova-status` FAILURE (service user token) blocks Kolla's upgrade; the "fix" of flipping config without understanding it changes Nova↔Cinder/Glance auth semantics | A | Minor–Major | N10, KA6 |
| R15 | Neutron data sanity checks (`neutron-status`) can fail on 13-release-old data (duplicate HA networks, binding profiles, tags, RBAC target_project) and are not fixed by schema migration | A, B, D | Major | Q2 |
| R16 | Glance `location_strategy` removed, `show_multiple_locations` deprecated, cache driver changes: config carried from Ussuri rejected or silently ignored | all | Minor–Major | G2 |
| R17 | Cinder backend drivers removed/unsupported since Ussuri → `cinder-volume` refuses to start; volumes unreachable after cut-over | A, B, C, D | Blocking if backend affected | C5 |
| R18 | Running EOL-release `*-manage` code requires py3.6–3.8 + SQLAlchemy 1.3 + sqlalchemy-migrate environments built from EOL constraints; wheels/base images may be unavailable → the fast-forward tooling itself is unreproducible | B, D | Major | L1, L2, KA8 |
| R19 | Intermediate Kolla images for any hop are not pullable (brief) → must be built from EOL distro repos; builds not reproducible later → `NEEDS-REVALIDATION` forever | any hop-based plan | Major | KA8 |
| R20 | "Restore the DB dump" rollback assumed while images/volumes/VM state/compute registrations have moved on → inconsistent platform after restore (orphan allocations, phantom hosts) | all | Blocking as stated | `openstack-change-review` §6; N5/K3 for the DB side |
| R21 | Strategy C: project/user ID change breaks every external reference (Heat, Terraform, Magnum, Octavia, billing); instance UUIDs cannot be preserved via API | C, D | Major | (design-level; no code evidence needed) |
| R22 | Strategy C: snapshot-and-reimport changes instance-id → cloud-init first-boot behaviour, host keys, licensing; machine type/disk bus change | C, D | Major | N11 |
| R23 | Keystone: tokens issued by Ussuri invalid after cut-over (expected) but **Fernet key repository** must be carried if any long-lived token/trust/credential encryption continuity is required; credential keys likewise | A, B, C, D | Minor–Major | (Keystone key repos are files, not DB; not inspected in code here — `unknown`) |
| R24 | Automation review: every `--skip-tags <check>` in the runbook is a deleted safeguard with no compensating control | A, B | Blocking if present | KA4, KA6, KA7 |

---

## 4. Pre-registered acceptance criteria

These are written **before** any experiment so later results are judged against them, not against the team's narrative. A criterion not met = the claim stays `Not validated`.

### 4.1 Criteria per claim type

| Claim type | Minimum evidence to accept | Explicitly *not* sufficient |
|---|---|---|
| "Schema migrated" | (a) `*-manage db version` / alembic `current` at the 2026.1 head **and** (b) a schema diff (`mysqldump --no-data`, normalised) of the migrated DB vs a DB created by a *fresh* 2026.1 `db sync`, showing **zero** differences in tables, columns, types, nullability, defaults, indexes, FKs, charset/collation **and** (c) `*-manage db sync` is idempotent when re-run | heads matching; "services started"; schema diff with "only cosmetic" differences left unexplained |
| "Data migrated" | (a) all `*-manage db online_data_migrations` report 0 remaining for every hop whose next hop depends on them; (b) **row-level invariants** checked before/after on a copy of a *production-like* DB (e.g. `SELECT COUNT(*) FROM volumes WHERE use_quota IS NULL`; counts of instances/volumes/ports/images per project unchanged; sum of quota usages recomputed = stored); (c) `sql_mode` recorded and strict for the run | "no errors in the log"; synthetic DB with 3 rows |
| "Service accepts the DB" | each `*-status upgrade check` run **with the 2026.1 code against the migrated DB** returns 0 (WARNINGs listed and individually accepted by the owner); then an end-to-end capability test (create/attach/boot/network/delete) on the migrated data **plus** operations on *pre-existing* resources (resize, snapshot, attach, port update, image download, token for a pre-existing user) | fresh-deployment smoke test; services "up" |
| "Old objects deserialise" | For Nova: list/show/action on pre-existing instances with request_specs, migration_context, pci_requests, numa_topology, BDMs created on Ussuri; conductor/scheduler logs free of `IncompatibleObjectVersion`/`ObjectActionError`/`KeyError` over the observation period | fake driver boot of new instances |
| "Rollback works" | Executed once in the lab from the step named as point of no return minus one: restore DB **and** re-register services, prove old code starts and serves pre-existing resources; document what is lost | "we have a dump" |
| "Workload preserved" (A/B/D) | The *same* guest (same UUID, same disk, same MAC/IP, same machine type string as read via `virsh dumpxml` before) is running after; libvirt XML diff before/after reviewed for machine type, CPU model, disk bus, PCI addresses | VM count equal |
| "Workload migrated" (C) | Per workload class: boot-and-reach test after import, ABI check (machine type, CPU model) agreed as acceptable by the owner, cloud-init behaviour documented, licensing checked; rollback (move back) exercised for one representative VM | API resource exists on new cloud |
| "Procedure reproducible" | Second operator executes the written runbook on a clean copy without the author; all tool images/venvs pinned by digest/constraints and archived | author re-runs it |
| "Kolla-Ansible completed" | `kolla-ansible upgrade` exit 0 **with zero `--skip-tags`** and zero edits to role tasks; any check bypass is recorded as a finding with its compensating control | exit 0 after skipping checks |

### 4.2 Criteria per strategy

**A — direct in-place.** Accept as *Technically possible but unsupported* only if **all** hold: `prechecks` passes on the real host OS (i.e. hosts already reinstalled — then it is not in-place), RabbitMQ version-check passes without override, Nova/Keystone/Cinder `db sync` succeed without stamping, nova-status returns 0, and a Ussuri-created instance survives (4.1 "Workload preserved"). I pre-register that R1, R3, R7 and R9 make this set unattainable; a result claiming otherwise must show which evidence item (N4/N5/N7/KA1/KA4) is wrong.

**B — DB fast-forward.** Accept as *Technically possible but unsupported* only if:
1. The hop list is derived from code, not convenience: at least one hop runs code that still carries *both* legacy and alembic for Nova (Xena–2023.1), Keystone (Yoga–2023.1 — alembic files exist in Yoga; bridging confirmed in 2023.1), Cinder (Zed–2023.1); Cinder's `use_quota` online migrations run with ≤ 2023.2 code **before** any 2024.1+ `db sync`; Nova `online_data_migrations` run after 2023.2 schema.
2. Every hop: schema diff vs fresh deployment of that hop = 0 (4.1), `*-status upgrade check` of the *next* hop = 0, online migrations = 0 remaining.
3. The run is on a **copy of the real production DB** (anonymised if needed), with strict `sql_mode`, and row-level invariants hold.
4. MariaDB path (10.3 → 11.4, Galera 3 → 4) is either demonstrated with `mariadb-upgrade` logs and `SHOW STATUS LIKE 'wsrep_%'` healthy on a 3-node lab, or replaced by logical dump/restore into a fresh 11.4 cluster (then say so: it is a rebuild, not an upgrade).
5. RabbitMQ is **rebuilt**, not upgraded, with all consumers stopped first; documented as such.
6. Compute fleet: a written answer to "how does an instance whose `host` row names a reinstalled compute get back under a 2026.1 `nova-compute`?" validated on one host with one Ussuri-created VM (4.1 "Workload preserved").
7. Rollback exercised at the last point before `1b91788ec3a6` / Keystone contract / Cinder `89aa6f9639f9`; documented as impossible after.

**C — parallel cloud.** Accept as *Officially supported deployment + unsupported migration* only if: ID strategy decided and tested against every external integration; per-workload-class migration rehearsed including the ABI check; floating IP / provider network cut-over plan tested; quota/RBAC parity tested with real users; rollback (move back) exercised; capacity plan shows both clouds fit during the migration window; point of no return defined per host re-purposed.

**D — hybrid.** Accept only if the split line is justified by a dependency table (which IDs cross the line and how each is preserved), **and** each half independently meets its B or C criteria, **and** the combined rehearsal is run end to end on a production-like copy. A hybrid that exists to avoid a hard part of B or C must name that hard part.

### 4.3 What would make me withdraw an objection
- R1/R5: a schema diff of zero between (Ussuri DB + stamp + 2026.1 alembic) and (fresh 2026.1) for Nova and Keystone — then stamping Nova/Keystone is *Technically possible but unsupported* rather than reckless. (Cinder: no stamp; needs Zed/2023.1 code.)
- R2: a lab log showing `9ab1b092a404` applied with strict mode on a DB containing Ussuri-created volumes **after** 2023.2 online migrations reached 0 remaining.
- R8: MariaDB vendor documentation (not reachable from here) explicitly supporting 10.3 → 11.4 `mariadb-upgrade`, plus a 3-node lab run.
- R11/R12: `virsh dumpxml` diffs of Ussuri-created guests before and after, showing identical machine type and CPU model, or an explicit owner acceptance of the change.

---

## 5. Commands that must never appear in the runbook without explicit safeguards

Safeguard = named approver, pre-check output recorded, backup verified restorable, scope bounded, verification step defined, and the step labelled `state-changing` (rule 2/4/6 of the evidence-and-safety rules). "Dangerous" is about consequence, not about the tool.

| Command | Why | Minimum safeguard |
|---|---|---|
| `alembic stamp …`, `neutron-db-manage stamp`, `keystone-manage db_sync --expand/--contract` out of order, any manual insert into `alembic_version` / `migrate_version` | Declares a schema state that may not exist; later migrations then ALTER the wrong shape silently | Schema diff = 0 proven and attached; only on a copy first; approver named |
| `nova-manage db archive_deleted_rows --purge`, `nova-manage db purge --all`, `cinder-manage db purge`, `keystone-manage token_flush`-style purges | Irreversible deletion; archive first changes row counts used as invariants | Never during the journey; if used to shrink the DB beforehand, archive without `--purge`, verified backup, owner approval |
| `kolla-ansible rabbitmq-reset-state`, `rabbitmqctl force_reset/reset`, `rabbitmqctl purge_queue` | Discards in-flight RPC/notifications; with Khepri `force_reset` fails; run with consumers alive recreates old queue types | All consumers stopped and verified (`rabbitmqctl list_consumers` empty), decision recorded that loss of in-flight operations is accepted |
| `kolla-ansible mariadb-recovery`, `galera_new_cluster`, `--wsrep-new-cluster`, editing `grastate.dat` | Bootstrapping the wrong node discards committed transactions | Most advanced node identified (`seqno`, `safe_to_bootstrap`, `--wsrep-recover`) and recorded before any bootstrap |
| `mariadb-upgrade` / `mysql_upgrade` across majors | One-way; failure leaves mixed system tables | Verified logical and physical backup; run on a copy first; version path supported in vendor docs |
| Direct `mysql`/`mariadb` DML/DDL on service databases (`UPDATE instances SET host=…`, `DELETE FROM …`, `ALTER TABLE …`) | Bypasses object versioning and invariants; invisible to tools | Backup, one record at a time, before/after row shown, verification query, approver |
| `nova-manage libvirt set_machine_type --force`, `nova-manage libvirt update_machine_type` on fleets | Can change guest ABI | Per-instance owner acceptance; never `--force` in bulk |
| `openstack server evacuate`, `nova-manage cell_v2 delete_host`, `openstack compute service delete`, `openstack compute service set --down --forced-down` | Can start a second copy of a guest on shared storage, orphan allocations | Fence first (power state proven off), then forced-down, then evacuate; one host at a time |
| `kolla-ansible … --skip-tags <any check>` (`rabbitmq-version-check`, `nova-libvirt-version-check`, `nova-libvirt-script-check`, `prechecks`) | Each tag is an upstream safeguard | Written compensating control and approver per tag; appears in the decision record as a deviation |
| `docker system prune`, `docker volume rm`, `podman system prune`, removing `/var/lib/docker/volumes/{mariadb,rabbitmq,nova_compute,nova_libvirt,glance,…}` | Destroys state volumes (DB data dir, queue data, instance disks, libvirt state) | Never on hosts carrying state; explicit volume names only; backup verified |
| `kolla-ansible destroy`, `cinder-manage db sync` on a wrong `connection`, any `*-manage` run with a config pointing at production while "testing" | Catastrophic scope error | `connection` string echoed (redacted) and confirmed per run; lab and prod credentials never on the same host |
| `openstack image delete`/`volume delete` "orphans" during reconciliation | "Junk" is an owner judgement, not an execution (`openstack-automation-review` §2) | Owner approval per project; soft-delete/quarantine first |
| `glance-manage db purge`, `glance-manage db contract` while old API nodes run | Contract removes columns/triggers old code uses | All glance-api on new code first |
| Setting `[workarounds]disable_compute_service_check_for_ffu=True` | Disables the only guard against mixed-version fleets | Time-boxed, removed and services restarted before declaring done; recorded |

---

## 6. Rollback assumptions that would fail (summary)

1. **"Restore the DB dump" after any 2026.1/new-hop write** — services wrote object versions, Placement allocations and compute records that the old code cannot reconcile; Galera restore on 11.4 → 10.3 is a downgrade (not supported by `mariadb-upgrade`; needs logical dump).
2. **"Old containers still exist locally"** — but the host OS has changed; Ussuri images do not run on hosts the Ussuri `prechecks` rejects (24.04 is not in the Ussuri list, KA1 mirror image).
3. **"RabbitMQ can be reset back"** — yes, but the old Ussuri `transport_url`/policies must be redeployed; in-flight state is lost twice.
4. **"Keep the old cloud as rollback" (C)** — only until its hardware is re-purposed and data moved; define per-workload return paths.
5. **"Roll back one hop" (B)** — impossible after `1b91788ec3a6`, `89aa6f9639f9` or Keystone contract without the pre-hop dump; the hop list must mark these.

---

## 7. What I could not verify / open questions

- **MariaDB 10.3 → 11.4 and Galera 3 → 4 direct upgrade support** — vendor docs unreachable (network block); `unknown`. Would be established by the MariaDB upgrade documentation for each major and a 3-node lab run.
- **Whether Ubuntu 24.04 / Rocky 10 QEMU carries the distro-versioned machine types of Ubuntu 18.04 / CentOS 8 QEMU** (e.g. `pc-i440fx-bionic`) and whether CPU model names used by Ussuri guests exist — `unknown`; `qemu-system-x86_64 -machine help` on both images would show it.
- **Exact releases of Neutron's and Keystone's RBAC default flips** — notes exist (Q3); release not pinned in this pass.
- **Kolla `sql_mode` / MariaDB strict mode defaults in the Ussuri and 2026.1 images** — not inspected; it decides whether R2 fails loudly or silently.
- **Keystone Yoga/Zed bridging behaviour** — alembic files exist from Yoga; I confirmed the bridging code in 2023.1 only.
- **Nova serialized-object compatibility across 13 releases** (request_specs, migration_context, pci_requests, numa_topology) — not provable by reading; only the deserialisation test in §4.1 settles it.
- **Availability of EOL wheels/base images to build hop environments and Kolla intermediate images** — brief reports 401/inactive on Docker Hub `kolla/*`; PyPI availability for py3.6–3.8 pins not tested.
- **Horizon, Heat, Octavia, Magnum, Barbican, Designate, Ironic and other enabled services** — not assessed; each has its own migration history, deprecations and possibly removed features. The enabled-service list of the real cloud is `unknown` to me.
- **Whether the real cloud's Cinder backend / Neutron plugin (OVS vs OVN, linuxbridge) / Glance stores are among those removed** — `unknown`; `cinder-status upgrade check` ("Removed Drivers") and `neutron-status` must be run with 2026.1 code against a DB copy.
- **SLURP policy text** — `releases` repo's `release_models.rst` in the local clone did not contain the SLURP section I expected; the brief's statement (SLURP→SLURP supported, i.e. 2023.1 → 2024.1 → 2025.1 → 2026.1) is **not independently confirmed here** from local evidence. Note that Nova's own code encodes the envelope as `OLDEST_SUPPORTED_SERVICE_VERSION` (N7), which is the enforceable truth regardless of policy wording.

---

Decision support only. State-changing steps mentioned above require approval by the accountable owner and should be executed under your change process. Validation: nothing in this document has been executed; all technical claims are `DOCUMENTED-UNVERIFIED` from source reading, and nothing here is validated in production.
