# 02 — Unsupported transitions report

| Field | Value |
|---|---|
| Author | Agent 2 — OpenStack Release Compatibility Expert (Stage 1, independent investigation) |
| Model | Opus (claude-opus-5-5) |
| Date | 2026-10-31 |
| Status | `DOCUMENTED-UNVERIFIED` for every finding; every proposed shortcut below is `PROPOSED-UNVERIFIED`. Nothing was executed. |
| Inputs read | `00-mission-brief.md`; OzarLand skills `openstack-change-review` (SKILL.md + `references/upgrade-readiness.md`) and `openstack-operational-decisions` (SKILL.md); upstream repos in `/home/user/src` (refs listed in `../compatibility-matrix.md` §1); oslo.policy/oslo.messaging sdists from PyPI (release notes only). No other `assessments/` file was read. |
| Companion files | `../compatibility-matrix.md` (all citations in detail), `../dependency-graph.md` (Mermaid graphs) |

## 1. Answer in one paragraph

No OpenStack project supports upgrading a Ussuri deployment directly to 2026.1. Before 2023.1 only N→N+1 upgrades are
supported; from 2023.1 the SLURP rule adds 2023.1→2024.1→2025.1→2026.1. The only **officially supported** route is
therefore U→V→W→X→Y→Z→2023.1→2024.1→2025.1→2026.1. At the code level, three services — **Nova, Keystone and Cinder** —
make a direct jump **incompatible**: their 2023.2-and-later code can no longer read a database still under
sqlalchemy-migrate control, and Cinder 2024.1+ additionally needs an online data migration that only Xena–2023.2 code
ships. Glance, Neutron, Placement and Horizon have intact migration chains, so for them a direct jump is
**technically possible but unsupported**. The smallest set of releases whose *code must execute* is
**{2023.1 (or Zed), 2026.1}**; whether that is enough to *operate* safely is not established (object compatibility,
compute service versions, RabbitMQ/MariaDB hops, deployment tooling).

## 2. Method and how the skills shaped it

- Evidence: release policy (`releases` repo), per-release upgrade docs, release notes per branch (notes attributed to
  the first branch that contains them), migration code (`INIT_VERSION` constants, presence of legacy repositories,
  migration docstrings), `*-status` check lists, `upper-constraints.txt` and `setup.cfg`/`pyproject.toml`.
- `openstack-change-review` (references/upgrade-readiness.md): applied the "Lifecycle facts to confirm" (SLURP is a
  promise between consecutive SLURPs only; more than one SLURP behind means hopping through each), the Nova rolling
  sequence (online data migrations are a hard prerequisite of the *next* upgrade), the Neutron expand/contract point of
  no return, the RBAC section, and "things outside OpenStack that must support the jump". Its decision gates are used
  in §6 to grade each shortcut: an option without credible recovery or sufficient evidence is "not ready", not
  "risky but fine".
- `openstack-operational-decisions`: options in §6 always include "keep as is / follow the supported path", each
  option states the risk of changing and of staying, and gates are applied before any preference.

## 3. Incompatible transitions (code cannot process the source state)

| # | Transition | Service | Evidence | Why it fails | Classification |
|---|---|---|---|---|---|
| I1 | Ussuri DB → `nova-manage db sync` / `api_db sync` of **2023.2 or later** | Nova | Legacy migrations removed by commit `fd39e4b4be` (2023-02-01), note `nova@2023.2-eol:releasenotes/notes/remove-sqlalchemy-migrate-907c200314884d81.yaml`; `nova@2023.2-eol:nova/db/migration.py:db_sync` only calls alembic `upgrade` | A Ussuri DB has a `migrate_version` row (main 407, api 072) and no `alembic_version`; alembic would start at `8f2f1571d55b_initial_version` and try to create tables that already exist. The stamp-on-legacy logic (`_init_alembic_on_legacy_database`) exists only in Xena–2023.1. | **Incompatible** |
| I2 | Ussuri DB → `keystone-manage db_sync` of **2023.2 or later** | Keystone | Commit `8c9462f6f` (2023-02-28), `keystone@2023.2-eol:releasenotes/notes/remove-sqlalchemy-migrate-a4fa47685c7e28c6.yaml`; stamping only in `keystone@origin/unmaintained/zed` and `…/2023.1:keystone/common/sql/upgrades.py` | Same mechanism; Keystone's alembic baseline `27e647c0fad4` is only stamped by Zed/2023.1 code. | **Incompatible** |
| I3 | Ussuri DB → `cinder-manage db sync` of **2023.2 or later** | Cinder | Commit `e9dccb93b` (2023-02-17), `cinder@2023.2-eol:releasenotes/notes/remove-sqlalchemy-migrate-c62b541fd5f4ab10.yaml`; stamping in `cinder@xena-eol..origin/unmaintained/2023.1:cinder/db/migration.py` | Same mechanism (migrate 136, alembic baseline `921e1a36b076`). | **Incompatible** |
| I4 | Cinder DB without completed `use_quota` online migration → db sync of **2024.1 or later** | Cinder | `cinder@origin/unmaintained/2024.1:cinder/db/migrations/versions/9ab1b092a404_make_use_quota_non_nullable.py` ("the online migrations from the previous release must already have been run"); `volume_use_quota_online_data_migration` / `snapshot_use_quota_online_data_migration` present in `cinder/cmd/manage.py` Xena…2023.2 only; doc rule in `cinder@origin/stable/2026.1:doc/source/admin/upgrades.rst` lines 69-73, 274-288 | `ALTER … NOT NULL` on columns with NULLs either fails (strict SQL mode) or silently coerces values (non-strict) — the latter would corrupt quota accounting. 2024.1+ code no longer contains the migration that fills the column. | **Incompatible** |
| I5 | Any `nova-compute` row (not deleted, not forced down) older than the target's `OLDEST_SUPPORTED_SERVICE_VERSION` → start 2026.1 nova-api/conductor/scheduler | Nova | `nova@origin/stable/2026.1:nova/objects/service.py` (`'Epoxy'`, version 68), `nova/utils.py:raise_if_old_compute`, `nova@wallaby-eol:releasenotes/notes/prevent-starting-services-with-old-compute-fc80b4ff58a2aaea.yaml` | Ussuri computes report version 51; control services refuse to start (`TooOldComputeService`). A rolling control-plane-first upgrade across the gap is impossible; every compute must be at ≥ Epoxy before control services run, which means a full compute-service stop. | **Incompatible** (for rolling); stop-the-world only |
| I6 | Old migration code (Xena–2023.1) run with 2026.1 libraries | Nova, Keystone, Cinder | sqlalchemy-migrate does not support SQLAlchemy 2.x (`oslo.db@2023.2-eol:releasenotes/notes/remove-sqlalchemy-migrate-f69c805004e6bac1.yaml`); 2026.1 pins SQLAlchemy 2.0.46 and no sqlalchemy-migrate (`requirements@origin/stable/2026.1:upper-constraints.txt`) | Old code must run with its own constraints (SQLAlchemy 1.4.x, sqlalchemy-migrate 0.13.0, Python 3.8–3.10). | **Incompatible** to mix runtimes |
| I7 | JSON policy files → 2026.1 | all API services | `oslo_policy-5.0.0.tar.gz:releasenotes/notes/remove-json-format-support-e6a32981dff45139.yaml`; 2026.1 pin oslo.policy 5.0.0 | Custom `policy.json` is not loaded. | **Incompatible** (convert first) |
| I8 | Neutron ML2 Linux Bridge → 2025.1 or later | Neutron | `neutron@origin/stable/2025.1:releasenotes/notes/remove-linuxbridge-driver-d0df60e5cf8ab3bc.yaml` | Driver removed. Not relevant if the deployment is ML2/OVS (Kolla default) — to be confirmed. | **Incompatible** if used |
| I9 | Cinder v2 API consumers → Xena or later | Cinder (+ clients, Horizon) | `cinder@xena-eol:releasenotes/notes/remove-api-v2-dadd877ee5457f79.yaml` | v2 endpoints gone. | **Incompatible** for v2 clients |
| I10 | Ussuri NUMA (non-pinned) instances on Victoria–Zed computes | Nova | `nova@origin/unmaintained/2023.1:releasenotes/notes/instance-numa-object-upgrade-afa5bb96149ca2f5.yaml` (fix first present on 2023.1 branch; absent from `victoria-eol` … `origin/unmaintained/zed` trees) | Instances created Liberty–Ussuri with `hw:mem_page_size`/`hw:numa_nodes` but no pinning cannot start on V–Z computes. Matters only if intermediate computes are actually deployed. | **Incompatible** on V–Z computes |
| I11 | Keystone users with `sha512_crypt` hashes → 2026.1 | Keystone | `keystone@origin/stable/2025.1:releasenotes/notes/sha512_crypt_deprecation-91a19080f1e884e4.yaml`; hasher list in `keystone@origin/stable/2026.1:keystone/common/password_hashing.py` | Such users cannot authenticate; passwords must be rotated. Only if such hashes exist (unknown). | **Incompatible** for affected users |
| I12 | Python 3.6 runtime (Ussuri images) → Zed+ code | all | `python_requires >=3.8` from Zed, `>=3.10` from 2025.2 (`<svc>@<ref>:setup.cfg`, `pyproject.toml`) | Interpreter must change; Kolla images change base OS (Ubuntu 18.04 → 24.04). | **Incompatible** to reuse |

## 4. Possible but unsupported transitions

| # | Transition | Service | Why it is technically possible | What is unsupported / unproven | Classification |
|---|---|---|---|---|---|
| T1 | Ussuri DB → 2026.1 db sync | Glance | Full alembic chain `liberty_initial` … `2024_1_*` still shipped (`glance@origin/stable/2026.1:glance/db/sqlalchemy/alembic_migrations/versions/`); `glance-manage db sync` runs expand, data migrations and contract | Skips 12 releases; config options removed in between (registry, `owner_is_tenant`, `admin_role`, `location_strategy`…); image format safety check now on by default. | Technically possible but unsupported |
| T2 | Ussuri DB → 2026.1 `neutron-db-manage upgrade heads` | Neutron | Every milestone LIBERTY…2025_2 kept in `neutron@origin/stable/2026.1:neutron/db/migration/__init__.py`; expand and contract trees present for every series | Data-quality checks introduced in between (`neutron-status`: segments uniqueness, port MAC, VLAN ids, HA networks, tags, RBAC target_project) were designed to run before each N+1 step; contract requires all neutron servers stopped (point of no return); agent ↔ server RPC skew of 12 releases is not supported. | Technically possible but unsupported |
| T3 | Ussuri DB → 2026.1 `placement-manage db sync` | Placement | Alembic chain intact (`b4ed3a175331` … `a082b8bb98d0`); the only online migration (Stein) still shipped | — beyond the general skip. | Technically possible but unsupported |
| T4 | Ussuri → 2026.1 Horizon | Horizon | No DB | Settings rewrite (Django 2.2 → 4.2, cache backend, removed settings). | Technically possible but unsupported |
| T5 | Ussuri DB → {Xena…2023.1} code `db sync` (one shot, skipping releases) | Nova | Legacy repos in Xena–2023.1 start at `MIGRATE_INIT_VERSION` 401/066 (≤ Ussuri 407/072) and contain only placeholders after 402/067; then alembic stamp | Skipping V/W (and X–Z when using 2023.1) is outside N+1 policy; Nova online migrations between are still present in 2026.1, but no doc covers a 12-release object-version gap (see §7 Q3). | Technically possible but unsupported |
| T6 | Ussuri DB → {Zed, 2023.1} code `db_sync` | Keystone | Legacy repo starts at `MIGRATE_INIT_VERSION = 72` (≤ Ussuri 073–079), then stamp `27e647c0fad4`; data migrations folded into expand since Yoga | Same policy gap. | Technically possible but unsupported |
| T7 | Ussuri DB → {Xena…2023.1} code `db sync` + `online_data_migrations` | Cinder | Legacy repo starts at 134 (≤ Ussuri 136); the same code ships the `use_quota` online migration | Same policy gap; the online migration's correctness on a DB that never ran Victoria/Wallaby code is unproven. | Technically possible but unsupported |
| T8 | 2023.1 → 2026.1 directly (skipping 2024.1 and 2025.1) | all | Alembic chains intact from the 2023.1 baseline for all services | SLURP covers only consecutive SLURPs; 2023.1→2026.1 skips two. Nova 2026.1 still refuses computes older than Epoxy (I5). | Technically possible but unsupported |
| T9 | Yoga → 2023.1 (skip Zed) | Nova only | `OLDEST_SUPPORTED_SERVICE_VERSION = 'Yoga'` in 2023.1; prelude calls it experimental | Not declared by other services nor by the release team. | Technically possible but unsupported (Nova: experimental) |
| T10 | Ussuri computes kept running while control plane jumps, using `forced_down` to bypass I5 | Nova | `service_get_minimum_version` filters `forced_down == false` | Not a documented procedure; forced-down hosts are excluded from scheduling/evacuation semantics change; RPC compatibility across 12 releases does not exist. | Technically possible but unsupported — high risk |

## 5. Minimal set of releases whose code must execute

"Execute" means running that release's management code (db sync, online data migrations, status checks) against the
database, for example from a disposable container — not deploying the release to serve traffic.

| Service | Minimum code set | Ordered steps (code release in brackets) | Hard constraint that forces it |
|---|---|---|---|
| Nova (main + API DB) | **{one of Xena, Yoga, Zed, 2023.1} + 2026.1** | 1. `api_db sync`, `db sync` [Xena…2023.1] → legacy to 422/087 + alembic stamp. 2. `api_db sync`, `db sync` [2026.1]. 3. `db online_data_migrations` until exit 0 [2026.1]. 4. `nova-status upgrade check` [2026.1]. 5. All computes at 2026.1 before control services start. | I1, I5, I6 |
| Keystone | **{one of Zed, 2023.1} + 2026.1** | 1. `db_sync` [Zed/2023.1] → legacy to 079 + stamp. 2. `db_sync --expand`, `--contract` (or offline `db_sync`) [2026.1]. 3. `keystone-status upgrade check` [2026.1]. | I2, I6 |
| Cinder | **{one of Xena, Yoga, Zed, 2023.1} + 2026.1** | 1. `db sync` [Xena…2023.1]. 2. `db online_data_migrations` until exit 0 [same release] (use_quota). 3. `db sync` [2026.1]. 4. `db online_data_migrations` [2026.1]. 5. `cinder-status upgrade check` [2026.1]. | I3, I4, I6 |
| Glance | **{2026.1}** | `glance-manage db sync` (or expand/migrate/contract) [2026.1]; `glance-status upgrade check` | none (T1) |
| Neutron | **{2026.1}** | `neutron-status upgrade check` [2026.1] first (data checks), then `neutron-db-manage upgrade heads` [2026.1] with all servers stopped | none (T2) |
| Placement | **{2026.1}** | `placement-manage db sync`, `db online_data_migrations`, `placement-status upgrade check` [2026.1] | none (T3) |
| Horizon | **{2026.1}** | settings regeneration | none |

**Union for the whole deployment: {2023.1, 2026.1}** (Zed works equally for the DB steps; 2023.1 is preferred because it
is a SLURP release, has Python 3.10 in its classifiers for Nova/Cinder, and is the first release with the bug 2080556
NUMA fix). This is the theoretical floor of code execution. It is **not** an operating path: it is
**Technically possible but unsupported** and **Not validated**.

## 6. Options, gated (openstack-operational-decisions / openstack-change-review)

| Option | Releases deployed | Code-only executions | Support status | Gate results (change-review) |
|---|---|---|---|---|
| O1 Follow the supported path | V, W, X, Y, Z, 2023.1, 2024.1, 2025.1, 2026.1 (9 upgrades) | — | Officially supported (every edge) | Evidence: pass (upstream path). Recovery: per-step DB backups, credible. Cost: 9 windows; V–X are EOL (tags only), Y/Z/2023.1/2024.1 unmaintained; Kolla images for Ussuri–Yoga reported unavailable from Docker Hub (brief, to verify) → images must be built. Blast radius: bounded per step. |
| O2 Supported from 2023.1 onward, compress pre-SLURP | DB-only "pass" with 2023.1 code (or deploy only 2023.1), then 2024.1, 2025.1, 2026.1 deployed | Nova/Keystone/Cinder DB conversion + Cinder online migration with 2023.1 code | U→2023.1 leg **Technically possible but unsupported**; the rest Officially supported | Evidence: **fail/unknown** until a lab run on a production DB copy proves the U→2023.1 code path (object compatibility, `*-status` results). Recovery: credible only if a pre-change DB dump + Ussuri images are kept and the restore is rehearsed. Verdict: not ready until lab-validated. |
| O3 Floor: execute 2023.1 DB code, then deploy 2026.1 directly | 2026.1 only | 2023.1 DB code for Nova/Keystone/Cinder | Technically possible but unsupported (T5–T8) | Evidence: fail (nothing upstream tests U→2026.1; RabbitMQ/MariaDB cannot jump that far in one hop per Kolla doc). Blast radius: whole cloud in one stop-the-world event (I5). Recovery: restore-only (contract migrations, Neutron contract, Keystone contract are points of no return). Verdict: not ready; should only be considered as a rebuild-with-data-migration variant, decided by the accountable owner. |
| O4 Stay on Ussuri | — | — | — | Risk of staying: EOL since 2024-02-20, no security fixes, growing distance (all later options get harder). Not a long-term option. |

This agent provides the compatibility assessment only; choosing between O1–O3 belongs to the accountable owner after
the lab evidence exists.

## 7. Must-pass-through points (explicit statements and code facts)

| Point | Statement type | Source |
|---|---|---|
| Nova: DB must be converted to alembic by Xena–2023.1 code before any 2023.2+ code runs | Code fact (no explicit "you must" sentence; the note says "no end-user impact") | `nova@2023.2-eol:releasenotes/notes/remove-sqlalchemy-migrate-907c200314884d81.yaml`, `nova@origin/unmaintained/2023.1:nova/db/migration.py` |
| Nova: "ensure all required steps from the previous upgrade have been completed, such as data migrations" | Explicit doc | `nova@origin/stable/2026.1:doc/source/admin/upgrades.rst` lines 27-30 |
| Nova: control services refuse computes older than N-1 (N-2 after 2023.1) | Explicit note + code | `nova@wallaby-eol:releasenotes/notes/prevent-starting-services-with-old-compute-fc80b4ff58a2aaea.yaml`; `nova@origin/stable/2026.1:doc/source/admin/upgrades.rst` lines 52-64 |
| Nova 2024.2 / 2025.2: "you can't do rolling-upgrade from 2023.2 [2024.2], you first need to upgrade to 2024.1 [2025.1]" | Explicit | Dalmatian and Flamingo preludes |
| Keystone: DB must be stamped by Zed/2023.1 code before 2023.2+ | Code fact | `keystone@2023.2-eol:releasenotes/notes/remove-sqlalchemy-migrate-a4fa47685c7e28c6.yaml` |
| Cinder: "you won't be able to apply N+1's schema migrations before completing N's online data migrations" | Explicit doc | `cinder@origin/stable/2026.1:doc/source/admin/upgrades.rst` |
| Cinder 2024.1: `use_quota` must be populated (Xena–2023.2 code) | Explicit migration docstring | `cinder@origin/unmaintained/2024.1:cinder/db/migrations/versions/9ab1b092a404_make_use_quota_non_nullable.py` |
| Glance: pre-Ocata DBs must pass through Wallaby or earlier | Explicit (not applicable to Ussuri) | `glance@xena-eol:releasenotes/notes/drop-support-for-sqlalchemy-migrate-4bcbe7b200697586.yaml` |
| Neutron: migrate off Linux Bridge before 2025.1 | Explicit | `neutron@origin/stable/2025.1:releasenotes/notes/remove-linuxbridge-driver-d0df60e5cf8ab3bc.yaml` |
| Kolla-Ansible: RabbitMQ cannot jump two versions; intermediate RabbitMQ needed for SLURP | Explicit doc | `kolla-ansible@origin/stable/2026.1:doc/source/user/operating-kolla.rst` "SLURP extra preparations" |

## Open questions / what I could not verify

1. **Object-version compatibility (Nova, Cinder)**: serialized versioned objects stored by Ussuri code and read by
   2023.1/2026.1 code. Establish by restoring a production DB copy, running the §5 sequence in containers, then
   `nova-status`/`cinder-status` and instance/volume reads with 2026.1 code.
2. Whether 2023.1 code's legacy migrations (Nova 408–422, Cinder 137–145, Keystone 074–079) behave identically on a
   DB that skipped Victoria/Wallaby runtime (only placeholders are expected for Nova; Cinder 140/141/145 and Keystone
   079 are real migrations). The database specialist owns this.
3. Runtime for code-only execution: which interpreter/container to use for 2023.1 code (Kolla 2023.1 images use
   Ubuntu 22.04/Python 3.10; their availability is not verified — the brief reports Docker Hub `kolla/*` pulls failing
   for Ussuri…Yoga, 2023.1 not checked).
4. Per-service RBAC overrides of the oslo.policy 4.4.0 defaults (Keystone, Cinder, Placement) and the real users,
   tokens and automation that depend on legacy roles — needs a policy test against real accounts.
5. Whether the deployment uses Linux Bridge, Cinder v2 clients, custom JSON policies, sha512_crypt hashes, DB-backed
   Horizon sessions, or QXL video — inventory facts not available to this agent.
6. RabbitMQ and MariaDB hop sequence (3.8 → 4.2; 10.3 → 11.4) — infra/Kolla agents' scope; any compressed OpenStack
   path still needs these hops.
