# Compatibility matrix: Ussuri → 2026.1

| Field | Value |
|---|---|
| Author | Agent 2 — OpenStack Release Compatibility Expert (Stage 1, independent investigation) |
| Model | Opus (claude-opus-5-5) |
| Date | 2026-10-31 |
| Status | `DOCUMENTED-UNVERIFIED` — everything here comes from reading upstream source trees; nothing was executed. |
| Inputs read | `assessments/00-mission-brief.md`; OzarLand skills `openstack-change-review` (SKILL.md, `references/upgrade-readiness.md`) and `openstack-operational-decisions` (SKILL.md); upstream git trees in `/home/user/src/{nova,keystone,glance,neutron,placement,cinder,horizon,oslo.db,requirements,releases,kolla,kolla-ansible}`; sdists of `oslo.policy` 4.3.0, 4.4.0, 4.5.1, 4.6.0, 5.0.0 and `oslo.messaging` 17.3.2 from PyPI (release notes only). Other files in `assessments/` were deliberately not read. |
| Companion files | `dependency-graph.md` (Mermaid graphs), `assessments/02-unsupported-transitions.md` (transition verdicts and minimal code sets) |

Evidence vocabulary follows the mission brief: **Officially supported**, **Technically possible but unsupported**,
**Experimentally validated** (not used: nothing was run), **Not validated**, **Incompatible**. Citations use
`repo@ref:path`. "Release notes" means `releasenotes/notes/*.yaml`; a note is attributed to the first series ref
whose tree contains it (so notes backported to older branches appear under the oldest branch that carries them; this is
flagged where it matters).

## 1. Refs used per series

| Series | Name | Ref used (all repos unless noted) | Lifecycle status per `releases@origin/master:data/series_status.yaml` |
|---|---|---|---|
| 2020.1 | Ussuri | `ussuri-eol` | End of life (2024-02-20) |
| 2020.2 | Victoria | `victoria-eol` | End of life (2025-12-19) |
| 2021.1 | Wallaby | `wallaby-eol` | End of life (2025-12-19) |
| 2021.2 | Xena | `xena-eol` | End of life (2025-12-19) |
| 2022.1 | Yoga | `origin/unmaintained/yoga` (kolla, kolla-ansible: `yoga-eol`) | Unmaintained |
| 2022.2 | Zed | `origin/unmaintained/zed` (kolla, kolla-ansible: `zed-eol`) | Unmaintained |
| 2023.1 | Antelope (SLURP) | `origin/unmaintained/2023.1` (kolla, kolla-ansible: `2023.1-eol`) | Unmaintained |
| 2023.2 | Bobcat | `2023.2-eol` | End of life (2025-04-30) |
| 2024.1 | Caracal (SLURP) | `origin/unmaintained/2024.1` | Unmaintained |
| 2024.2 | Dalmatian | `2024.2-eol` | End of life (2026-04-29) |
| 2025.1 | Epoxy (SLURP) | `origin/stable/2025.1` | Listed `maintained`, next phase `unmaintained` dated 2026-10-02; several repos already carry `origin/unmaintained/2025.1` too. Treat as transitioning (unverified which is authoritative today). |
| 2025.2 | Flamingo | `origin/stable/2025.2` | Maintained (EOL planned 2027-04-28) |
| 2026.1 | Gazpacho (SLURP) | `origin/stable/2026.1` | Maintained (unmaintained planned 2027-10-27) |

Note: the codename of 2026.1 is **Gazpacho** (`releases@origin/master:data/series_status.yaml`), 2026.2 is Hibiscus
(released 2026-09-30) and 2027.1 Indri (in development, SLURP).

## 2. Release policy facts (all services)

| # | Fact | Source | Classification |
|---|---|---|---|
| P1 | Upgrades are supported between adjacent releases (N → N+1). | `releases@origin/master:doc/source/index.rst` lines 94-109 ("in addition to between adjacent major releases") | Officially supported |
| P2 | SLURP releases: 2023.1, 2024.1, 2025.1, 2026.1 (and 2027.1). Upgrades are also supported between consecutive SLURP releases (N → N+2). | `releases@origin/master:data/series_status.yaml` (`slurp: yes`), `releases@origin/master:doc/source/index.rst` ("upgrade paths starting with the 2023.1 Antelope release") | Officially supported |
| P3 | No SLURP marking exists for any series before 2023.1. Ussuri…Zed therefore only have N → N+1 upgrade support. | same file: no `slurp` key on zed/yoga/…/ussuri | Officially supported (N+1 only) |
| P4 | Nova 2023.1: compute services may be rolling-upgraded from **Yoga** "as an experimental feature" (first SLURP). | `nova@origin/unmaintained/2023.1:releasenotes/notes/antelope-prelude-4a99907b00e739f8.yaml`; `nova@origin/unmaintained/2023.1:nova/objects/service.py` `OLDEST_SUPPORTED_SERVICE_VERSION = 'Yoga'` | Technically possible, declared experimental by Nova only. Not a cross-project promise. |
| P5 | Nova 2024.1 can be reached from 2023.1 skipping 2023.2; 2025.1 from 2024.1; 2026.1 from 2025.1. Non-SLURP 2024.2 / 2025.2 can only be reached from the preceding SLURP. | Nova preludes: `nova@origin/unmaintained/2024.1:releasenotes/notes/caracal-prelude-63fac6e27509930d.yaml`, `nova@2024.2-eol:releasenotes/notes/dalmatian-prelude-35a774ecc9e56004.yaml`, `nova@origin/stable/2025.1:releasenotes/notes/epoxy-prelude-f164cc03b742cfc5.yaml`, `nova@origin/stable/2025.2:releasenotes/notes/flamingo-prelude-22a2782315ce0808.yaml`, `nova@origin/stable/2026.1:releasenotes/notes/gazpacho-prelude-1c2b533501ce2afd.yaml` | Officially supported |
| P6 | Kolla-Ansible documents SLURP skip-level upgrades from 2023.1, with an extra RabbitMQ preparation ("RabbitMQ … does not support jumping two versions in one upgrade"). | `kolla-ansible@2023.1-eol:doc/source/user/operating-kolla.rst` lines 190-198 (same text through `origin/stable/2026.1`) | Officially supported (deployment-tool level; details are the Kolla agent's scope) |
| P7 | No project document found that supports skipping more than one release before 2023.1, or more than one SLURP hop after it. | absence in `doc/source` of all seven projects at `origin/stable/2026.1` (grep for SLURP / skip-level found only `nova:doc/source/contributor/ptl-guide.rst`) | A Ussuri → 2026.1 direct jump is **not supported** by any project. |

## 3. Cross-cutting runtime matrix (per release)

Python ranges come from `setup.cfg` (`python_requires` and classifiers) up to 2025.2 and from `pyproject.toml`
(`requires-python`, classifiers) in 2026.1, read from Nova unless a service differs. Library versions are the pins in
`requirements@<ref>:upper-constraints.txt`. Kolla base OS is the image base in `kolla@<ref>:kolla/common/config.py`;
MariaDB/RabbitMQ are the package-repo pins in `kolla@<ref>` (`docker/base/Dockerfile.j2` or
`kolla/template/repos.yaml`, `docker/rabbitmq/Dockerfile.j2`) and are only indicative of image content.

| Release | Nova ver. | python_requires / classifiers (Nova) | Deviations by service | SQLAlchemy u-c | sqlalchemy-migrate u-c | alembic | oslo.db | oslo.messaging | oslo.policy | Django (Horizon) | Kolla image OS (Ubuntu default) → Python | MariaDB repo / RabbitMQ in Kolla |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Ussuri | 21.x | >=3.6 / 3.6, 3.7 | — | 1.3.16 | 0.13.0 | 1.4.2 | 8.1.1 | 12.1.6 | 3.1.2 | 2.2.12 | Ubuntu 18.04 / CentOS 8 → py3.6 | 10.3 / 3.8.* |
| Victoria | 22.x | >=3.6 / 3.6–3.8 | keystone 3.6–3.7 | 1.3.19 | 0.13.0 | 1.4.2 | 8.4.1 | 12.5.2 | 3.5.0 | 2.2.15 | Ubuntu 20.04 / CentOS 8 → py3.8/3.6 | unknown / unknown |
| Wallaby | 23.x | >=3.6 / 3.6–3.8 | keystone 3.6–3.7 | 1.3.23 | 0.13.0 | 1.5.7 | 8.5.2 | 12.7.3 | 3.7.1 | 2.2.19 | Ubuntu 20.04 / CentOS Stream 8 | unknown |
| Xena | 24.x | >=3.6 / 3.6–3.8 | keystone 3.6–3.7 | **1.4.23** | 0.13.0 | 1.7.1 | 11.0.0 | 12.9.4 | 3.8.3 | 2.2.24 | Ubuntu 20.04 / CentOS Stream 8 → py3.8/3.6 | 10.5 / 3.9.* |
| Yoga | 25.x | >=3.6 / 3.6–3.9 | keystone 3.6–3.7 | 1.4.31 | 0.13.0 | 1.7.6 | 11.2.0 | 12.13.3 | 3.11.0 | 3.2.12 | Ubuntu 20.04 / CentOS Stream 8–9 / Rocky 9 | unknown |
| Zed | 26.x | **>=3.8** / 3.8–3.9 | keystone, glance, neutron, placement 3.8–3.9 | 1.4.40 | 0.13.0 | 1.8.1 | 12.1.2 | 14.0.3 | 4.0.0 | 3.2.15 | Ubuntu 22.04 → py3.10 (outside classifiers) | 10.6 / unknown |
| 2023.1 | 27.x | >=3.8 / 3.8–3.10 | keystone/glance/neutron/placement 3.8–3.9 | 1.4.41 | 0.13.0 | 1.8.1 | 12.3.3 | 14.2.5 | 4.1.1 | 3.2.16 | Ubuntu 22.04 → py3.10 | 10.6 / unknown |
| 2023.2 | 28.x | >=3.8 / 3.8–3.10 | keystone etc. 3.8–3.9 | 1.4.41 | 0.13.0 (pinned but no service uses it) | 1.9.4 | 14.1.1 | 14.4.2 | 4.2.1 | 3.2.18 | Ubuntu 22.04 | unknown |
| 2024.1 | 29.x | >=3.8 / 3.8–3.11 | horizon 3.8–3.9 | 1.4.51 | 0.13.0 | 1.9.4 | 15.0.0 | 14.7.2 | 4.3.0 | 4.2.10 | Ubuntu 22.04 and 24.04 | 10.11 / unknown |
| 2024.2 | 30.x | >=3.8 / 3.8–3.11 | cinder, horizon >=3.9 | **2.0.32** | removed | 1.13.2 | 16.0.0 | 14.9.3 | **4.4.0** | 4.2.15 | Ubuntu 24.04 → py3.12 | 10.11 / unknown |
| 2025.1 | 31.x | >=3.9 / 3.9–3.12 | glance, cinder 3.9–3.11 | 2.0.38 | — | 1.14.1 | 17.2.2 | 16.1.2 | 4.5.1 | 4.2.19 | Ubuntu 24.04, Rocky/CentOS 9–10 | 10.11 / unknown |
| 2025.2 | 32.x | >=3.10 / 3.10–3.12 | horizon >=3.9 | 2.0.42 | — | 1.16.4 | 17.4.0 | 17.1.1 | 4.6.0 | 4.2.23 | Ubuntu 24.04, Rocky/CentOS 10 | 11.4 / unknown |
| 2026.1 | 33.x | >=3.10 (pyproject) / 3.10–3.12 (keystone, glance, neutron, cinder add 3.13) | horizon setup.cfg >=3.9 | 2.0.46 | — | 1.18.4 | 18.0.0 | 17.3.2 | **5.0.0** | 4.2.28 | Ubuntu 24.04 → py3.12; Debian 13 → py3.13; Rocky 10 | 11.4 (repos.yaml) / 4.2.* |

Sources: `<svc>@<ref>:setup.cfg`, `<svc>@origin/stable/2026.1:pyproject.toml`,
`requirements@<ref>:upper-constraints.txt`, `releases@origin/master:deliverables/<series>/<deliverable>.yaml`,
`kolla@<ref>:kolla/common/config.py`. "unknown" = not looked up (outside this agent's focus).

Key consequences (classification in brackets):

- **SQLAlchemy 1.x → 2.0 happens at 2024.2.** sqlalchemy-migrate does not support SQLAlchemy 2.x
  (`oslo.db@2023.2-eol:releasenotes/notes/remove-sqlalchemy-migrate-f69c805004e6bac1.yaml`). Any code that still
  contains sqlalchemy-migrate legacy migrations (Nova/Cinder Xena–2023.1, Keystone Zed–2023.1, Keystone Yoga legacy
  only) must run with its own SQLAlchemy 1.4 pins, never with 2026.1 libraries. [Incompatible to mix]
- **Python gap.** 2026.1 needs Python ≥3.10; Ussuri code was built for 3.6–3.7 (Ussuri Kolla images: Python 3.6).
  Old migration code from Xena–2023.1 is declared for Python 3.6–3.10 depending on release; running it on the host's
  or 2026.1's Python 3.12/3.13 is outside every declared range. [Not validated]
- **oslo.policy 4.4.0 (2024.2 pin)** flips `enforce_scope` and `enforce_new_defaults` to `True` library-wide;
  **oslo.policy 5.0.0 (2026.1 pin)** removes JSON policy file support entirely
  (`oslo.policy-4.4.0.tar.gz:releasenotes/notes/enforce_scope_new_defaults-aaf134e5409ae7f2.yaml`,
  `oslo_policy-5.0.0.tar.gz:releasenotes/notes/remove-json-format-support-e6a32981dff45139.yaml`; 5.0.0 is the
  2026.1 pin in `requirements@origin/stable/2026.1:upper-constraints.txt`). [Incompatible: any remaining
  `policy.json` override on 2026.1]
- **oslo.db 2024.1 removed legacy option aliases** (`[DEFAULT] sql_connection`, `[DATABASE] sql_connection`,
  `[sql] connection`, …) (`oslo.db@origin/unmaintained/2024.1:releasenotes/notes/remove-deprecated-opts-1d095911e82fee3b.yaml`).
  [Incompatible if a Ussuri config still uses them; Kolla templates normally use `[database] connection` — unverified
  for this deployment's overrides]

## 4. Per-service matrices

Column meanings:

- **Upgrade-from (official)**: per P1–P5. "N-1" means only the immediately previous release.
- **DB framework**: what `*-manage db sync` uses in that release.
- **Min. source schema**: the oldest database schema the release's own migration code can upgrade (from the
  `INIT_VERSION`/`MIGRATE_INIT_VERSION` constants and the presence or absence of legacy repositories).
- **Mandatory steps**: steps the release's docs/notes/code make a precondition, especially for the *next* upgrade.

### 4.1 Nova (and Nova API DB)

| Release | Upgrade-from (official) | DB framework | Min. source schema (main / api) | Oldest compute tolerated by control services | Mandatory steps / blocking checks | Key removals relevant to a Ussuri deployment | Status |
|---|---|---|---|---|---|---|---|
| Ussuri (source) | Train | sqlalchemy-migrate; main 216_havana…**407**, api 001…**072** | — | Train (`OLDEST_SUPPORTED_SERVICE_VERSION='Train'`) | — | — | starting point |
| Victoria | Ussuri | sqlalchemy-migrate (…412 / …077) | 216 / 001 | Ussuri | Policy file default changes to `policy.yaml` (`nova@victoria-eol:releasenotes/notes/bug-1875418-default-policy-file-change-22bd4cc6e27e0091.yaml`); `[service_user]` config "required" (note `service-user-token-421d067c16257782.yaml`, present on `victoria-eol` as a later backport, CVE bug 2004555); libvirt ≥5.0 / QEMU ≥4.0 | XenAPI driver, RetryFilter, Aggregate{Core,RAM,Disk}Filter, `[vnc]/[spice] keymap`, hooks removed | Officially supported (U→V) |
| Wallaby | Victoria | sqlalchemy-migrate; **compacted to 402_train** (`nova@origin/stable/2026.1` commit `5c9c81e0f9` "db: Compact Train database migrations") | **401 / 066** (`nova@wallaby-eol:nova/db/sqlalchemy/migration.py` `INIT_VERSION`) | Victoria | Services refuse to start if any compute older than N-1 exists (`nova@wallaby-eol:releasenotes/notes/prevent-starting-services-with-old-compute-fc80b4ff58a2aaea.yaml`); libvirt ≥6.0 / QEMU ≥4.2 | custom scheduler drivers, `[scheduler] scheduler_driver`, libvirt xen/uml | Officially supported (V→W) |
| Xena | Wallaby | **alembic introduced**; legacy repo moved to `nova/db/{main,api}/legacy_migrations` (402…422 / 067…087), applied automatically then alembic stamped `8f2f1571d55b` / `d67eeaabee36` (`nova@xena-eol:releasenotes/notes/switch-to-alembic-ed5c64f62b6c91a3.yaml`, `nova@xena-eol:nova/db/migration.py`) | 401 / 066 | Wallaby | Placement microversion ≥1.36 required | `[database] use_db_reconnect`, `use_tpool`, old scheduler option aliases, two workarounds | Officially supported (W→X) |
| Yoga | Xena | alembic + legacy | 401 / 066 | Xena | — | vnc legacy opts, bandwidth notification field | Officially supported (X→Y) |
| Zed | Yoga | alembic + legacy | 401 / 066 | Yoga | `nova-status upgrade check` now fails on too-old computes (`too-old-compute-check-code-7dbcde45cfd23394.yaml`); Python ≥3.8 | PowerVM driver | Officially supported (Y→Z) |
| 2023.1 (SLURP) | Zed; Yoga experimental (P4) | alembic + legacy (last release that can convert a sqlalchemy-migrate DB) | 401 / 066 (`nova@origin/unmaintained/2023.1:nova/db/migration.py` `MIGRATE_INIT_VERSION`) | Yoga (N-2) | `enforce_scope`/`enforce_new_defaults` default True (`enable-enforce-scope-and-new-defaults-14db8c75b263b599.yaml`); computes persist `compute_id` file in `state_path`; fix for pre-Victoria NUMA instances (bug 2080556) first present here | — | Officially supported (Z→2023.1) |
| 2023.2 | 2023.1 | **alembic only**; legacy migrations removed (commit `fd39e4b4be` "db: Remove legacy migrations", 2023-02-01; `nova@2023.2-eol:releasenotes/notes/remove-sqlalchemy-migrate-907c200314884d81.yaml`); `migrate_version` table dropped by `1b91788ec3a6` | **DB must already be under alembic control** (stamped by Xena–2023.1). `db_sync` simply runs `alembic upgrade` (`nova@2023.2-eol:nova/db/migration.py`). | 2023.1 | New online migration `populate_instance_compute_id` | AvailabilityZoneFilter; libvirt ≥7.0 / QEMU ≥5.2 | Officially supported (2023.1→2023.2) |
| 2024.1 (SLURP) | 2023.2; 2023.1 (SLURP) | alembic | alembic `8f2f1571d55b` / `d67eeaabee36` | 2023.1 | — | Hyper-V driver, RDP console, `[api] use_forwarded_for` | Officially supported |
| 2024.2 | 2024.1 | alembic | idem | 2024.1 | — | — | Officially supported |
| 2025.1 (SLURP) | 2024.2; 2024.1 | alembic | idem | 2024.1 | libvirt ≥8.0 / QEMU ≥6.2; QXL/SPICE unusable on Ubuntu 24.04 (`make-virtio-the-default-spice-video-model-fff5189fa637d4bd.yaml`) | Python 3.8 | Officially supported |
| 2025.2 | 2025.1 | alembic | idem | 2025.1 | Service-to-service APIs default to `service` role (`add-policy-service-role-eaa391e30431a9d6.yaml`); nova-api under eventlet removed | old `[DEFAULT]` aliases of `[api]` options | Officially supported |
| 2026.1 (SLURP) | 2025.2; 2025.1 | alembic | idem | **2025.1** (`nova@origin/stable/2026.1:nova/objects/service.py`) | Native threading default for api/scheduler/metadata; `graceful_shutdown_timeout` 180 s; WSGI scripts removed | `/os-volumes_boot` (≥2.103) | Officially supported from 2025.1/2025.2 only |

Nova online data migrations retained in 2026.1 code (`nova@origin/stable/2026.1:nova/cmd/manage.py`
`online_migrations`): Pike/Queens/Rocky/Stein/Victoria/2023.2 entries are all still present; none was removed between
Ussuri and 2026.1. Nova `nova-status upgrade check` checks present at 2026.1: Cells v2, Placement API, Cinder API, policy
JSON, Older than N-1 computes, `hw_machine_type` unset, Service User Token configuration
(`nova@origin/stable/2026.1:nova/cmd/status.py`). The minimum-version gate ignores service rows with `deleted != 0` or
`forced_down = true` (`nova@origin/stable/2026.1:nova/db/main/api.py:service_get_minimum_version`).

### 4.2 Keystone

| Release | Upgrade-from | DB framework | Min. source schema | Mandatory steps | Key removals / changes | Status |
|---|---|---|---|---|---|---|
| Ussuri (source) | Train | sqlalchemy-migrate, three repos (expand/data_migration/contract, 001…**079**) + pre-Newton `migrate_repo` (067…109) | — | `db_sync --expand/--migrate/--contract` | — | Note: `079_*_update_local_id_limit` exists only on `ussuri-eol` after the last 17.x tag (commit `97a63ca8d`, 2021-05-20): a Ussuri DB may be at 078 or 079. |
| Victoria–Xena | N-1 | idem | idem | idem | JSON policy default → YAML (Wallaby) | Officially supported |
| Yoga | Xena | sqlalchemy-migrate only; Newton…Ussuri migrations squashed into `073_*_initial_migration` (commits `c80b183aa`…`3e2b01d5f` "sql: Squash … migrations"), legacy `migrate_repo` removed (`503421d3d`) | **72** (`keystone@origin/unmaintained/yoga:keystone/common/sql/upgrades.py` `INITIAL_VERSION = 72`); a Ussuri DB (≥073) qualifies | `--migrate` still used | legacy pre-Newton migrations removed (`remove-legacy-migrations-647f60019c8dd9e8.yaml`) | Officially supported |
| Zed | Yoga | **alembic introduced** (`27e647c0fad4`); legacy applied then stamped (`keystone@origin/unmaintained/zed:keystone/common/sql/upgrades.py:_init_alembic_on_legacy_database`) | 72 | `--migrate` becomes a no-op; data migrations are in expand (`switch-to-alembic-1fa5248f0ce824ae.yaml`) | Python ≥3.8 | Officially supported |
| 2023.1 | Zed | alembic + legacy (last converter) | 72 (`MIGRATE_INIT_VERSION = 72`) | — | — | Officially supported |
| 2023.2 | 2023.1 | **alembic only** (commit `8c9462f6f` "db: Remove legacy migrations", 2023-02-28; `remove-sqlalchemy-migrate-a4fa47685c7e28c6.yaml`) | DB must be alembic-stamped (Zed or 2023.1 code) | — | LDAP TLS needs `tls_cacertfile`/`tls_cacertdir` | Officially supported |
| 2024.1 (SLURP) | 2023.2; 2023.1 | alembic | alembic | — | `[memcache]` legacy opts, eventlet opts; catalog `$(public_bind_host)s` interpolation no longer substituted; custom policy referencing `%(trust.*)s` / JSON body fields must be rewritten (bug 2148398 note, backported here) | Officially supported |
| 2025.1 (SLURP) | 2024.2; 2024.1 | alembic | alembic | `passlib` dropped; templated catalog driver removed; `sha512_crypt` hashes last supported | EC2-derived tokens banned by default (`[auth] ban_ec2credential_tokens`) | Officially supported |
| 2025.2 | 2025.1 | alembic | alembic | WSGI scripts removed | Python 3.9 | Officially supported |
| 2026.1 (SLURP) | 2025.2; 2025.1 | alembic | alembic | Supported hashers: scrypt, bcrypt, bcrypt_sha256, pbkdf2_sha512 only (`keystone@origin/stable/2026.1:keystone/common/password_hashing.py`) | — | Officially supported from 2025.1/2025.2 only |

### 4.3 Glance

| Release | Upgrade-from | DB framework | Min. source schema | Mandatory steps | Key removals | Status |
|---|---|---|---|---|---|---|
| Ussuri (source) | Train | alembic since Ocata; heads `ussuri_expand01` / `ussuri_contract01` | — | — | — | — |
| Victoria | Ussuri | alembic | `liberty` (full chain) | cinder store multi-backend location rewrite (lazy) | glance-registry and `data_api` options, `enable_v2_api` | Officially supported |
| Wallaby | Victoria | alembic | full chain | JSON policy → YAML | `admin_role`, `owner_is_tenant` | Officially supported |
| Xena | Wallaby | alembic; sqlalchemy-migrate *support* removed ("to upgrade from a pre-Ocata release to Xena or later, you must upgrade to Wallaby or earlier first", `glance@xena-eol:releasenotes/notes/drop-support-for-sqlalchemy-migrate-4bcbe7b200697586.yaml`) | Ocata-era alembic | not relevant to Ussuri (already alembic) | — | Officially supported |
| Yoga–Zed | N-1 | alembic | full chain | — | `secure_proxy_ssl_header`, cache prefetcher periodic job | Officially supported |
| 2023.1 | Zed | alembic | full chain | `enforce_scope`/`enforce_new_defaults` default True; `enforce_secure_rbac` removed | — | Officially supported |
| 2024.1–2026.1 | SLURP rules | alembic; 2026.1 still ships every migration from `liberty_initial` to `2024_1_*` (`glance@origin/stable/2026.1:glance/db/sqlalchemy/alembic_migrations/versions/`) | full chain | `glance-manage db load_metadefs` for metadef updates (optional) | `location_strategy` (2024.2), Windows (2025.1), WSGI script (2026.1), image/disk_format safety check on by default (2025.1) | Officially supported along N+1 / SLURP edges |

Glance rolling upgrades are documented as "not supported" for production
(`glance@origin/stable/2026.1:doc/source/admin/rollingupgrades.rst` lines 20-27): plan Glance with an API outage.

### 4.4 Neutron (ML2/OVS — Kolla default)

| Release | Upgrade-from | DB framework | Min. source schema | Mandatory steps / checks | Key removals / driver status | Status |
|---|---|---|---|---|---|---|
| Ussuri (source) | Train | alembic since Kilo, expand/contract branches | — | — | — | — |
| Victoria | Ussuri | alembic | `kilo` (all milestones kept: `neutron@origin/stable/2026.1:neutron/db/migration/__init__.py` `NEUTRON_MILESTONES` LIBERTY…2025_2) | VLAN id constraint 1–4094 (check added later) | `firewall_driver` not used by server | Officially supported |
| Wallaby | Victoria | alembic | idem | JSON policy → YAML; restart server after address-group migration | — | Officially supported |
| Xena | Wallaby | alembic | idem | server before agents (RPC 1.9 for SR-IOV) | XenAPI options | Officially supported |
| Yoga | Xena | alembic | idem | NetworkSegments unique constraint — check with `neutron-status` (`add-networksegments-uniq-constraint-89e52b42ca2f7ec2.yaml`) | `allow_overlapping_ips` deprecated | Officially supported |
| Zed | Yoga | alembic | idem | — | **Linux Bridge agent marked experimental** (needs `[experimental] linuxbridge=True`); `allow_overlapping_ips` removed | Officially supported |
| 2023.1 | Zed | alembic | idem | new RBAC defaults available (not default) | `keepalived_use_no_track` | Officially supported |
| 2023.2 | 2023.1 | alembic | idem | `enforce_scope`/`enforce_new_defaults` default True (`enable-enforce-scope-and-new-defaults-1f82a9eb71125f5d.yaml`); default SG rules created during migration | neutron-debug | Officially supported |
| 2024.1 (SLURP) | 2023.2; 2023.1 | alembic | idem | ML2/OVS IGMP flood defaults changed; `api_workers` ≥1 | `[agent] veth_mtu`, `[DEFAULT] ovs_integration_bridge`, `segment_mtu`, designate admin opts | Officially supported |
| 2024.2 | 2024.1 | alembic | idem | — | Windows support | Officially supported |
| 2025.1 (SLURP) | 2024.2; 2024.1 | alembic | idem | ≤50 tags per resource (check added); uWSGI `start-time=%t` mandatory | **Linux Bridge ML2 driver removed** ("migrate to a different driver before upgrade", `neutron@origin/stable/2025.1:releasenotes/notes/remove-linuxbridge-driver-d0df60e5cf8ab3bc.yaml`); PostgreSQL dropped; dibbler IPv6 PD removed; OVN migration tool for TripleO removed | Officially supported |
| 2025.2 | 2025.1 | alembic | idem | eventlet `neutron-server` removed: `neutron-api` (WSGI) + `neutron-rpc-server` + `neutron-periodic-workers` (`neutron@origin/stable/2025.2` commit `378453e93d`; `setup.cfg` console scripts) | — | Officially supported |
| 2026.1 (SLURP) | 2025.2; 2025.1 | alembic | idem | Refuses to start if `[ml2_type_vlan] network_vlan_ranges` no longer covers an allocated VLAN; new check for RBAC policies with invalid `target_project` | `neutron-api` script removed (module `neutron.wsgi.api`), `ovn_emit_need_to_frag` | Officially supported from 2025.1/2025.2 only |

OVN / Linux Bridge implications: ML2/OVS survives the whole journey. A Ussuri deployment on Linux Bridge has no
upstream code path past 2024.2 and must migrate driver before 2025.1 code runs [Incompatible past 2024.2]. ML2/OVN is
supported throughout; the in-tree OVS→OVN migration tooling for TripleO was removed in 2025.1 (the generic tooling was
not examined) [Not validated]. `neutron-status upgrade check` at 2026.1 lists 14 checks
(`neutron@origin/stable/2026.1:neutron/cmd/upgrade_checks/checks.py`), several of which inspect existing data (port
MAC sanity, NetworkSegments uniqueness, port binding profile, extra DHCP options, duplicated HA networks, tag limit,
RBAC target_project).

### 4.5 Placement

| Release | Upgrade-from | DB framework | Min. source schema | Mandatory steps | Key removals | Status |
|---|---|---|---|---|---|---|
| Ussuri (source) | Train | alembic (`b4ed3a175331_initial`, blockers `b5c396305c25_block_on_null_consumer`, `611cd6dffd7b_block_on_null_root_provider_id`) | — | — | — | — |
| Wallaby | Victoria | alembic | `b4ed3a175331` | JSON policy → YAML | `[placement]/policy_file`, legacy `placement` policy | Officially supported |
| Xena | Wallaby | alembic (`422ece571366_add_consumer_types_table`) | idem | — | — | Officially supported |
| 2023.1 | Zed | alembic | idem | policies project-scoped; `reshaper:reshape` → service role | — | Officially supported |
| 2026.1 | 2025.2; 2025.1 | alembic (adds `a082b8bb98d0`) | idem | — | `placement-api` WSGI script | Officially supported from 2025.1/2025.2 only |

The only online data migration (`rp_obj.set_root_provider_ids`, Stein) is still in 2026.1
(`placement@origin/stable/2026.1:placement/cmd/manage.py`). The Stein blocker migrations are already satisfied by a
working Ussuri database.

### 4.6 Cinder (LVM and generic)

| Release | Upgrade-from | DB framework | Min. source schema | Mandatory steps | Key removals | Status |
|---|---|---|---|---|---|---|
| Ussuri (source) | Train | sqlalchemy-migrate 123…**136** | — | Ussuri's own online migrations (untyped volumes/snapshots) are a precondition of 136, so a running Ussuri DB has completed them | — | — |
| Victoria | Ussuri | sqlalchemy-migrate …140 | `123_cinder_init` chain (exact init constant not read) | — | `cinder-manage shell`, `rbd_keyring_conf`, VxFlexOS `sio*` options | Officially supported |
| Wallaby | Victoria | sqlalchemy-migrate …141 | idem | LVM ≥2.02.107 | TSM backup driver, NestedQuotaDriver | Officially supported |
| Xena | Wallaby | **alembic introduced** (`921e1a36b076`); migrations compacted to Train (`b29bb44e9`), legacy `135_cinder_init`…145 applied then stamped (`cinder@xena-eol:cinder/db/migration.py`) | **134** (`MIGRATE_INIT_VERSION = 134`); Ussuri DB at 136 qualifies | New online migrations `volume_use_quota` / `snapshot_use_quota`; Nova must send service tokens, else detach fails (bug 2004555) | **Block Storage API v2 removed**, `enable_v2_api`/`enable_v3_api`, `db_driver` | Officially supported |
| Yoga–2023.1 | N-1 | alembic + legacy (2023.1 last converter) | 134 | `use_quota` online migrations still shipped | QNAP unsupported; IET target removed (2023.1) | Officially supported |
| 2023.2 | 2023.1 | **alembic only** (commit `e9dccb93b` "db: Remove legacy migrations", 2023-02-17; `remove-sqlalchemy-migrate-c62b541fd5f4ab10.yaml`) | alembic-stamped DB | `use_quota` online migrations still shipped (**last release**) | — | Officially supported |
| 2024.1 (SLURP) | 2023.2; 2023.1 | alembic `9ab1b092a404_make_use_quota_non_nullable` ("the online migrations from the previous release must already have been run", file docstring) | alembic + **`use_quota` populated** | new online migration `remove_temporary_admin_metadata` | Dell SC/VNX/XtremIO and Windows drivers unsupported | Officially supported |
| 2024.2–2025.2 | SLURP rules | alembic | idem | — | Quobyte unsupported, GlusterFS backup deprecated | Officially supported |
| 2026.1 (SLURP) | 2025.2; 2025.1 | alembic (8 revisions) | idem | `remove_temporary_admin_metadata` still shipped | Windows drivers removed, `cinder-wsgi` script removed | Officially supported from 2025.1/2025.2 only |

General Cinder rule: "Before upgrading N to N+1, you need to run this tool [online_data_migrations] … you won't be able
to apply N+1's schema migrations before completing N's online data migrations"
(`cinder@origin/stable/2026.1:doc/source/admin/upgrades.rst` lines 69-73 and 274-288). LVM driver: no removal found
between Ussuri and 2026.1 (only the LVM ≥2.02.107 requirement and the IET target removal) [Not validated beyond release
notes].

### 4.7 Horizon

| Release | Upgrade-from | Python / Django | Key changes | Status |
|---|---|---|---|---|
| Ussuri | — | 3.6–3.7 / Django 2.2 | — | — |
| Wallaby | Victoria | 3.6–3.8 / 2.2 | `POLICY_FILES` move to YAML; `django.wsgi` removed; Nova extensions blacklist removed | Officially supported |
| Yoga | Xena | 3.6–3.9 / **3.2** | Django 2.2 dropped; legacy launch-instance form removed; default role `member` | Officially supported |
| 2024.1 | 2023.2/2023.1 | 3.8–3.9 / **4.2** | Django 3.2 dropped; cache backend `PyMemcacheCache` | Officially supported |
| 2026.1 | 2025.2/2025.1 | >=3.9 (setup.cfg) / 4.2.28 | EC2 credential downloads removed (2025.2) | Officially supported |

Horizon has no schema of its own (unless DB-backed sessions are configured — unknown for this deployment).

## 5. RBAC and policy timeline (affects every service)

| Release | Change | Source |
|---|---|---|
| Victoria/Wallaby | `[oslo_policy] policy_file` default `policy.json` → `policy.yaml` in all services; JSON deprecated | Nova Victoria note; Keystone/Glance/Neutron/Placement/Cinder Wallaby notes `deprecate-json-formatted-policy-file-*` |
| 2023.1 | Nova and Glance default `enforce_scope=True`, `enforce_new_defaults=True` | `nova@origin/unmaintained/2023.1:…/enable-enforce-scope-and-new-defaults-14db8c75b263b599.yaml`, `glance@origin/unmaintained/2023.1:…/enable-enforce-scope-and-new-defaults-ef543183e6c2eabb.yaml` |
| 2023.2 | Neutron defaults to new RBAC | `neutron@2023.2-eol:…/enable-enforce-scope-and-new-defaults-1f82a9eb71125f5d.yaml` |
| 2024.2 | oslo.policy 4.4.0: defaults True library-wide (services that do not override follow) | `oslo.policy-4.4.0.tar.gz:releasenotes/notes/enforce_scope_new_defaults-aaf134e5409ae7f2.yaml` |
| 2025.1/2025.2 | `service` role required for service-to-service APIs (Nova, Glance, Neutron for Octavia) | Nova `add-policy-service-role-eaa391e30431a9d6.yaml`, Glance `service-api-default-eae660940ed97010.yaml` |
| 2026.1 | JSON policy files unsupported (oslo.policy 5.0.0) | `oslo_policy-5.0.0.tar.gz:releasenotes/notes/remove-json-format-support-e6a32981dff45139.yaml` |

Which services still override the oslo.policy defaults back to False in 2024.2–2026.1 (Cinder, Keystone, Placement)
was **not verified** (a full-tree grep was too slow on the partial clones).

## 6. Ussuri functionality that blocks or changes the journey (summary)

| Item | Affected if the Ussuri deployment… | Becomes a problem at | Classification |
|---|---|---|---|
| `policy.json` overrides (any service) | has custom JSON policy files | deprecated Wallaby; unusable at 2026.1 (oslo.policy 5.0.0) | Incompatible on 2026.1 unless converted |
| Legacy RBAC (admin-or-owner, system scope tokens) | relies on old defaults / system-scoped tokens | Nova, Glance 2023.1; Neutron 2023.2; library-wide 2024.2 | Officially supported change; needs testing against real users |
| Cinder v2 API endpoints | catalog / clients use `volumev2` | Xena | Incompatible from Xena |
| Neutron Linux Bridge | uses LB instead of OVS | experimental Zed; removed 2025.1 | Incompatible from 2025.1 |
| Nova XenAPI, PowerVM, Hyper-V, libvirt xen/uml | non-KVM hypervisor | V / Z / 2024.1 / W | Incompatible |
| Nova custom scheduler driver, Aggregate*Filter, RetryFilter, AvailabilityZoneFilter | listed in `enabled_filters` | V (filters), W (driver), 2023.2 (AZ filter) | Incompatible (service start/config errors) |
| Nova `[service_user]` / service token | not configured | Victoria-era backport; Cinder detach fails without it from Xena | Officially required |
| QXL/SPICE video model | instances use QXL | 2025.1 on Ubuntu 24.04 hypervisor images | Incompatible on that OS |
| Instances created pre-Victoria with NUMA topology but unpinned | flavors with `hw:mem_page_size`/`hw:numa_nodes` | cannot start on Victoria…Zed computes; fixed from 2023.1 (bug 2080556) | Incompatible on V–Z computes |
| Keystone `sha512_crypt` password hashes | users created when that was the default | unsupported in 2026.1 hashers list | Incompatible: password rotation |
| Keystone templated catalog driver | `[catalog] driver = templated` | 2025.1 | Incompatible |
| oslo.db `sql_connection` aliases | old option names in overrides | 2024.1 | Incompatible |
| Glance `owner_is_tenant`, `admin_role`, registry | set in config | Victoria / Wallaby | silently ignored / removed |
| WSGI scripts (`nova-api-wsgi`, `keystone-wsgi-*`, `glance-wsgi-api`, `neutron-api`, `cinder-wsgi`, `placement-api`) | deployment tool references scripts | 2025.2 (Keystone) / 2026.1 (others) | Incompatible for old tooling (Kolla 22.x handles this — not verified here) |
| Python 3.6 runtime | Ussuri images | Zed requires ≥3.8, 2025.2 requires ≥3.10 | Incompatible to reuse old interpreter |

## Open questions / what I could not verify

1. Whether each service other than Nova/Glance/Neutron overrides `enforce_scope`/`enforce_new_defaults` back to False
   in 2024.2–2026.1 (would need targeted reads of `<svc>/common/policy.py`-style files per release).
2. The exact `nova-status`/`neutron-status` result *level* (warning vs failure) of each check at 2026.1 for a database
   that has never seen intermediate releases — reading is not executing; a 2026.1 `*-status upgrade check` against a
   restored copy of the production DB would establish it.
3. Whether persisted versioned objects in the Nova DB (e.g. `instance_extra.numa_topology`, `request_specs`) written by
   Ussuri code can still be loaded by 2026.1 code without intermediate rewrites. No document guarantees compatibility
   across more than the supported window. Establish by loading a copy of the DB with 2026.1 code and exercising
   instance operations.
4. MariaDB and RabbitMQ versions for Victoria–Yoga and RabbitMQ for 2023.1–2025.2 were not looked up (Kolla agent's
   scope).
5. The authoritative lifecycle state of 2025.1 on 2026-10-31 (file says "maintained" with a 2026-10-02 transition date;
   branches `unmaintained/2025.1` exist for nova, neutron, cinder, placement, oslo.db).
6. Whether Kolla Ussuri images were built from the `stable/ussuri` tip (Keystone at 079) or from a 17.x tag (078); both
   are fine for every later converter, but the DB specialist should confirm the actual `migrate_version` rows.
7. Release-note attribution is by first branch containing the file; notes backported to older branches (e.g. Nova
   `service-user-token`, Keystone bug 2148398) appear under older series than the release that introduced them.
