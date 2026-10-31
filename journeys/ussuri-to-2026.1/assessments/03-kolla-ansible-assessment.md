# Kolla-Ansible and Kolla compatibility assessment, Ussuri (10.x) to 2026.1 (22.x)

| Field | Value |
|---|---|
| Author | Agent 3, Kolla-Ansible Specialist (OzarLand multi-agent team, Stage 1, independent investigation) |
| Model | Claude Opus (claude-opus-5-5) |
| Date | 2026-10-31 |
| Status | Draft, Stage 1. Source reading only; nothing in this file was executed against an OpenStack deployment. |
| Skills applied | `openstack-kolla-ansible-operations` (SKILL.md and all `references/`), `openstack-automation-review`, `openstack-change-review` (incl. `references/upgrade-readiness.md`) |
| Inputs read | `00-mission-brief.md`; kolla-ansible and kolla at the 13 refs listed in section 1 (support matrix, prechecks, group_vars, inventories, roles `rabbitmq`, `mariadb`, `nova`, `nova-cell`, `keystone`, `glance`, `neutron`, `placement`, `cinder`, CLI, `setup.cfg`, `requirements*`, every release note added per series, `operating-kolla.rst`, `rabbitmq.rst`, `rocky-linux-9.rst`); kolla `kolla/common/config.py`, `kolla/template/repos.yaml`, `docker/*/extend_start.sh`, `.zuul.d/`; nova `stable/2026.1` (`nova/objects/service.py`, `nova/cmd/status.py`, `nova/db/migration.py`); OzarLand `kolla-ansible-deployment-patterns/version-notes/*` (2025.1→2026.1 lab report); `openstack-quick-lab/variants/openstack-cloud/*`; PyPI JSON metadata (ansible, ansible-base, ansible-core, kolla-ansible, kolla); Docker Hub registry API (anonymous); `git ls-remote` of the GitHub mirror of `ansible-collection-kolla`. |

Citation format: `kolla-ansible@<ref>:<path>`, `kolla@<ref>:<path>`. Refs are the ones in section 1. Release notes
are cited by file name under `releasenotes/notes/`. Evidence classes follow the mission brief.

## 0. Answer in short

1. **Forced Kolla-Ansible hops (supported path):** Ussuri → Victoria → Wallaby → Xena → Yoga → Zed → 2023.1 →
   2024.1 → 2025.1 → 2026.1: **nine `kolla-ansible upgrade` runs**, eight intermediate releases deployed.
   Before 2023.1 there is no skip-level upgrade in Kolla-Ansible (every release is N→N+1); from 2023.1 the
   Kolla-Ansible operating guide documents skip-level (SLURP) upgrades with extra RabbitMQ preparation.
   (Officially supported per hop; DOCUMENTED-UNVERIFIED as a chain.)
2. **Host OS transitions are forced inside the chain**, because no Kolla-Ansible release supports both the Ussuri
   host OS and the 2026.1 host OS. Ubuntu: 18.04 → 20.04 (in Victoria), 20.04 → 22.04 (in Yoga or right after the
   Zed container upgrade), 22.04 → 24.04 (in 2024.1, or 2024.2 if that release were deployed). CentOS: CentOS 8 →
   CentOS Stream 8 (Ussuri-eol/Victoria/Wallaby) → Rocky Linux 9 (reprovision, in Yoga) → Rocky Linux 10
   (reprovision, in 2025.1). Section 3.
3. **No code path in Kolla-Ansible 22.x accepts a Ussuri deployment.** There is no generic "previous release" check,
   but four independent gates would stop or damage a direct `kolla-ansible upgrade` (sections 5 and 6): the deploy
   host and target Python/Ansible requirements, the inventory and host OS checks, `rabbitmq-version-check`
   (3.8 → 4.2 is not an allowed path), and `nova-status upgrade check` run with the 2026.1 Nova image
   (`OLDEST_SUPPORTED_SERVICE_VERSION = 'Epoxy'`). Classification: **Incompatible**.
4. **Image availability is the hardest practical blocker** for every intermediate hop: Ussuri–Wallaby defaults
   pull from Docker Hub `kolla/*`, which answers 401 to anonymous manifest requests from here (observed), and
   2026.1 prechecks refuse quay.io `openstack.kolla` images unless `--use-test-images` is passed. Section 4.

## 1. Refs examined

| Series | kolla-ansible ref | Last release on that line (PyPI) | kolla ref | Last kolla release (PyPI) |
|---|---|---|---|---|
| Ussuri | `ussuri-eol` (8a94fe9eb, 2022-12-06) | 10.4.0 (2021-11-23) | `ussuri-eol` (9107c5f9e) | 10.4.0 |
| Victoria | `victoria-eol` (0ea41464e) | 11.4.0 | `victoria-eol` | 11.3.0 |
| Wallaby | `wallaby-eol` (909041878) | 12.8.0 | `wallaby-eol` | 12.7.0 |
| Xena | `xena-eol` (1eb757fd8) | 13.9.0 | `xena-eol` | 13.10.0 |
| Yoga | `yoga-eol` (4349d96e8) | 14.11.0 | `yoga-eol` | 14.12.0 |
| Zed | `zed-eol` (b1527cd96) | 15.6.0 | `zed-eol` | 15.6.0 |
| 2023.1 | `2023.1-eol` (4891a21dc) | 16.7.0 | `2023.1-eol` | 16.6.0 |
| 2023.2 | `2023.2-eol` (94ecb2efd) | 17.9.0 | `2023.2-eol` | 17.9.0 |
| 2024.1 | `origin/unmaintained/2024.1` (a8be33be8, tag `2024.1-eom`) | 18.8.0 | `origin/unmaintained/2024.1` | 18.8.0 |
| 2024.2 | `2024.2-eol` (e3f40c8cb) | 19.8.0 | `2024.2-eol` | 19.8.0 |
| 2025.1 | `origin/stable/2025.1` (7222f0fb4) | 20.6.0 | `origin/stable/2025.1` | 20.6.0 |
| 2025.2 | `origin/stable/2025.2` (aef4e3a32) | 21.3.0 | `origin/stable/2025.2` | 21.3.0 |
| 2026.1 | `origin/stable/2026.1` (ee8a3f52a) | 22.2.0 | `origin/stable/2026.1` | 22.2.0 |

Observed: the eol tags sit after the last PyPI release on several lines (e.g. `git describe` gives
`ussuri-em-46-g8a94fe9eb`). Installing from PyPI and installing from the eol tag are not the same code; the plan
must pin one and record which.

## 2. Per-series compatibility table

"Host OS (matrix)" is `doc/source/user/support-matrix.rst`; "Host OS (precheck)" is `host_os_distributions` in
`ansible/roles/prechecks/vars/main.yml`, which is what `kolla-ansible prechecks` actually enforces. The Ansible range is
`ansible_version_min/max` (same file) and, up to 2024.1, `ANSIBLE_VERSION_MIN/MAX` in `tools/kolla-ansible`; from
2024.2 the bash CLI was replaced by a Python CLI and the check lives in `prechecks/tasks/package_checks.yml`.
Controller Python minimum for the Ansible line is from PyPI `requires_python` (observed 2026-10-31).

| Series (KA) | Host OS (matrix) | Host OS (precheck accepts) | Ansible on deploy host | Deploy-host Python | Default images (registry / name / tag) | Image base | RabbitMQ / MariaDB in images | Notable upgrade checks and changes |
|---|---|---|---|---|---|---|---|---|
| Ussuri (10.x) | CentOS 8, Debian 10, RHEL 8, Ubuntu 18.04 | CentOS 8, Debian buster, RHEL 8, Ubuntu bionic | Ansible 2.8–2.9 | KA classifiers 3.6–3.7; Ansible 2.9 accepts ≥2.7 | Docker Hub `kolla/<distro>-<binary\|source>-<svc>:ussuri` (`docker_registry` empty, `docker_namespace: kolla`, `kolla_install_type: binary`); CentOS Stream suffix `-centos8s` at eol | Ubuntu 18.04, CentOS 8 | 3.8 / 10.3 | none release-aware; MariaDB `upgrade.yml` = deploy + `mysql_upgrade` |
| Victoria (11.x) | CentOS 8, Debian 10, RHEL 8, Ubuntu 20.04 | adds Ubuntu **bionic + focal** | Ansible 2.9 only | 3.6–3.8 | same scheme, `:victoria` | **Ubuntu 20.04** | 3.8 / 10.3 | `ubuntu-focal` note: upgrade containers to Victoria first, then hosts to 20.04; common services become their own play and need inventory groups `common`, `cron`, `fluentd`, `kolla-logs`, `kolla-toolbox` (`separate-common-play`); `mariadb-server` image replaces `mariadb` |
| Wallaby (12.x) | CentOS Stream 8, Debian 11, RHEL 8 (deprecated), Ubuntu 20.04 | CentOS 8, Debian buster/bullseye, RHEL 8, Ubuntu focal | Ansible 2.9–2.10 | 3.6–3.8 | same, `:wallaby` | Ubuntu 20.04, CentOS Stream 8 | 3.9 at eol tag / 10.3 (Ubuntu) | Docker ≥ 18.09, docker SDK ≥ 3.4.1; chrony disabled by default, prechecks fail if the chrony container still runs; Prometheus v2; ELK 7; critical LP#1941706 (VMs killed on `nova_libvirt` stop) fixed in 12.2.0 |
| Xena (13.x) | CentOS Stream 8, Debian 11, RHEL 8, Rocky 8, Ubuntu 20.04 | CentOS 8, Debian bullseye, RHEL 8, Rocky 8, Ubuntu focal | Ansible 2.10–2.11 (ansible 3–4) | 2.11 accepts ≥2.7 | **quay.io `openstack.kolla/<distro>-<type>-<svc>:xena`**, default type **source** | Ubuntu 20.04 | 3.9 / 10.5 | `haproxy` group → `loadbalancer` (`drop-group-haproxy`, checked by `inventory_checks.yml`); chrony role removed; `docker_registry_insecure` default false; Prometheus v1 removed |
| Yoga (14.x) | CentOS Stream 8, Debian 11, openEuler, RHEL 8, Rocky 8/9, Ubuntu 20.04/22.04 | adds CentOS/RHEL/Rocky 9, Ubuntu **focal + jammy** | ansible-core 2.11–2.12 (ansible 4–5) | 2.12 needs ≥3.8 | quay.io, `:yoga`; binary images deprecated (kolla `yoga-prelude`) | Ubuntu 20.04, Rocky 9 | 3.9 / 10.6 | CentOS Stream 8 dropped after Yoga: `rocky-linux-9.rst` (reprovision, rolling); `ironic-pxe`/`ironic-ipxe` → `ironic-tftp`/`ironic-http`; first `requirements.yml` (ansible-collection-kolla) |
| Zed (15.x) | CentOS Stream 9, Debian 11, openEuler, Rocky 9, Ubuntu 22.04 | CentOS 9, Debian bullseye, Rocky 9, Ubuntu **focal + jammy** | ansible-core 2.12–2.13 | ≥3.8 | **quay.io `openstack.kolla/<svc>:zed-<distro>-<version>`**; binary images removed; `kolla_container_engine` appears (docker only) | **Ubuntu 22.04**, Rocky 9 | 3.10 / 10.6 | Elasticsearch/Kibana → OpenSearch (data volume moved, groups renamed, `add-opensearch`); Monasca/Kafka/Storm/Zookeeper dropped; Keystone admin port gone; `update_keystone_service_user_passwords` |
| 2023.1 (16.x) SLURP | CentOS Stream 9, Debian 11/12, openEuler, Rocky 9, Ubuntu 22.04 | CentOS 9, Debian bullseye/bookworm, Rocky 9, Ubuntu jammy | ansible-core 2.13–2.14 (ansible 6–7) | 2.14 needs ≥3.9 | quay.io, `2023.1-<distro>-<ver>` | Ubuntu 22.04 | **3.11 default, 3.12/3.13 images shipped** / 10.6 | **`rabbitmq-version-check` introduced** (downgrade guard); RabbitMQ rolling upgrade; `rabbitmq-upgrade <ver>` command; quorum-queue option (`om_enable_rabbitmq_quorum_queues` default false); containers get systemd units |
| 2023.2 (17.x) | as 2023.1 | as 2023.1 | ansible-core 2.14–2.15 | ≥3.9 | quay.io (Docker Hub publish jobs still defined) | Ubuntu 22.04 | 3.12 / 10.11 | **Podman** option (`kolla_container_engine: podman`); `kolla_docker` module renamed `kolla_container`; quorum queues default **true**; Prometheus basic auth (`prometheus_password`) |
| 2024.1 (18.x) SLURP | CentOS Stream 9, Debian 11/12, openEuler, Rocky 9, Ubuntu 22.04/24.04 | adds Ubuntu **jammy + noble** | ansible-core 2.15–2.16 | ≥3.10 for 2.16 | quay.io, `2024.1-ubuntu-jammy` default; Noble images optional | Ubuntu 22.04 (24.04 optional) | 3.13 / 10.11 | SLURP from 2023.1 needs RabbitMQ 3.12 first and the durable/quorum queue procedure (`rabbitmq.rst`); version check allows ±1 minor or 3.13→4.0/4.1; Horizon `custom_local_settings` → `_9999-custom-settings.py`; Murano, Sahara, Senlin, Solum, Vitrage, Freezer dropped |
| 2024.2 (19.x) | CentOS Stream 9, Debian 12, Rocky 9, Ubuntu 22.04/24.04 | CentOS 9, Debian bookworm, Rocky 9, Ubuntu jammy/noble | ansible-core 2.16–2.17 | KA `python_requires >=3.10` | quay.io only; `2024.2-ubuntu-noble` default | **Ubuntu 24.04** | 3.13 / 10.11 | Python CLI (`mariadb_backup` → `mariadb-backup`); `enable_proxysql: yes` default; Python 3.8/3.9 dropped; openEuler dropped |
| 2025.1 (20.x) SLURP | CentOS Stream 9/10, Debian 12, Rocky 9/10, Ubuntu 24.04 | CentOS 9/10, Debian bookworm, Rocky 9/10, Ubuntu **noble only** | ansible-core 2.17–2.18 | ≥3.10 / 2.18 ≥3.11 | quay.io, Rocky default still 9 | Ubuntu 24.04, Rocky 9 (10 buildable) | 4.0 (4.1 image) / 10.11 | Ubuntu 22.04 removed; `om_enable_rabbitmq_high_availability` removed (quorum queues mandatory); Linux Bridge removed; Swift removed; Prometheus v3; `migrate-valkey`, `migrate-container-engine` commands; `rocky-linux-10.rst` |
| 2025.2 (21.x) | CentOS Stream 10, Debian 12, Rocky 10, Ubuntu 24.04 | CentOS 10, Debian bookworm, Rocky 10, Ubuntu noble | ansible-core 2.18–2.19 | KA `>=3.11` | quay.io | Ubuntu 24.04, Rocky 10 | 4.1 / 11.4 | ProxySQL mandatory with MariaDB (clustercheck removed); Neutron uWSGI + new groups; Horizon 8080 behind HAProxy; Redis → Valkey |
| 2026.1 (22.x) SLURP | CentOS Stream 10, Debian 13, Rocky 10, Ubuntu 24.04 | CentOS 10, Debian bookworm/trixie, Rocky 10, Ubuntu noble | ansible-core 2.19–2.20 (`ansible-core>=2.19,!=2.19.0,<2.21`) | KA `>=3.11`; ansible-core 2.20 needs ≥3.12 | quay.io `openstack.kolla/<svc>:2026.1-<distro>-<ver>`; **prechecks refuse quay.io/openstack.kolla unless `--use-test-images`** | Ubuntu 24.04, Rocky 10, Debian 13 | 4.2 / 11.4 | `rabbitmq_allowed_upgrades` (3.13→4.0/4.1/4.2, 4.0→4.1/4.2); `kolla-toolbox`→`kolla_toolbox`, `kolla-logs`→`kolla_logs` groups; Cinder volume moved to `cinder` group; nova-libvirt version and start-script checks; Zun, Kuryr, InfluxDB, Telegraf dropped |

Sources for the table, by column: `kolla-ansible@<ref>:doc/source/user/support-matrix.rst`;
`kolla-ansible@<ref>:ansible/roles/prechecks/vars/main.yml`; `kolla-ansible@<ref>:tools/kolla-ansible`
(lines 58–63 Ussuri–Xena, 71–76 Yoga, 10–11 Zed–2024.1); `kolla-ansible@<ref>:requirements.txt` and `setup.cfg`;
`kolla-ansible@<ref>:ansible/group_vars/all.yml` (2025.2+: `ansible/group_vars/all/*.yml`) for `docker_registry`,
`docker_namespace`, `kolla_install_type`, `openstack_tag`, `kolla_base_distro_version_default_map`;
`kolla-ansible@<ref>:ansible/roles/nova/defaults/main.yml` (`nova_api_image`) for the name scheme;
`kolla@<ref>:kolla/common/config.py` (`DEFAULT_BASE_TAGS`/`DISTRO_RELEASE`); `kolla@<ref>:docker/rabbitmq/` and
`kolla@<ref>:kolla/template/repos.yaml` for RabbitMQ and MariaDB versions; release notes named in the cell.
Deploy-host Python: PyPI `requires_python` of ansible 2.9.27 (`>=2.7`), ansible-base 2.10.17 (`>=2.7`), ansible-core
2.11.12 (`>=2.7`), 2.12/2.13 (`>=3.8`), 2.14/2.15 (`>=3.9`), 2.16/2.17 (`>=3.10`), 2.18/2.19 (`>=3.11`), 2.20.0
(`>=3.12`), kolla-ansible 17–18 (`>=3.8`), 19–20 (`>=3.10`), 21–22 (`>=3.11`).

What the table means for the deploy host (Technically derived, Not validated): no single Python serves the chain.
Ansible 2.9 (Ussuri, Victoria) on Python 3.12 is unknown and doubtful; ansible-core 2.14+ cannot run on Ubuntu
20.04's Python 3.8; ansible-core 2.18+ and kolla-ansible 21+ cannot run on Ubuntu 22.04's Python 3.10. The deploy
host therefore changes too: one virtual environment (or container) per hop, with a Python that both ends support.
Target-host Python minimums of each ansible-core line were **not** checked (only controller requirements were);
see Open questions.

## 3. Host OS transitions and overlaps

### 3.1 Overlap matrix (precheck-accepted)

| Host OS | Ussuri | Vic | Wal | Xena | Yoga | Zed | 23.1 | 23.2 | 24.1 | 24.2 | 25.1 | 25.2 | 26.1 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Ubuntu 18.04 | M P | P | | | | | | | | | | | |
| Ubuntu 20.04 | | M P | M P | M P | M P | P | | | | | | | |
| Ubuntu 22.04 | | | | | M P | M P | M P | M P | M P | M P | | | |
| Ubuntu 24.04 | | | | | | | | | M P | M P | M P | M P | M P |
| CentOS Linux 8 | M P | M P | P | P | P | | | | | | | | |
| CentOS Stream 8 | (suffix at eol) | P (`-centos8s`) | M | M | M (untested) | | | | | | | | |
| Rocky 8 | | | | M P | M P | | | | | | | | |
| Rocky 9 / CS9 | | | | | M P | M P | M P | M P | M P | M P | M P | | |
| Rocky 10 / CS10 | | | | | | | | | | | M P | M P | M P |
| Debian 10 | M P | M P | P | | | | | | | | | | |
| Debian 11 | | | M P | M P | M P | M P | M P | M P | M P | | | | |
| Debian 12 | | | | | | | M P | M P | M P | M P | M P | M P | P |
| Debian 13 | | | | | | | | | | | | | M P |

M = support matrix, P = precheck. CentOS 8 vs Stream 8 is decided by `openstack_tag_suffix` and, from 2026.1 at
least, a Stream check in `host_os_checks.yml`; the CentOS rows are indicative only.

### 3.2 Forced transitions (documented)

| Distribution | Transition | Where it can happen | Upstream guidance | Status |
|---|---|---|---|---|
| Ubuntu | 18.04 → 20.04 | Victoria only (Ussuri does not accept focal; Wallaby does not accept bionic) | "Ubuntu users upgrading from Ussuri should first upgrade OpenStack containers to Victoria, which uses the Ubuntu Focal 20.04 base container image. Hosts should then be upgraded to Ubuntu Focal 20.04." (`kolla-ansible@victoria-eol:releasenotes/notes/ubuntu-focal-bdc157d4505f9a0c.yaml`) | Officially supported, DOCUMENTED-UNVERIFIED |
| Ubuntu | 20.04 → 22.04 | Yoga (jammy hosts with focal images) or Zed (focal hosts with jammy images; Zed precheck still accepts focal) | Two documents disagree on the order: `kolla-ansible@yoga-eol:doc/source/user/operating-kolla.rst` lines 79–86 says upgrade containers to Zed first; `kolla-ansible@zed-eol:doc/source/user/operating-kolla.rst` lines 88–93 says upgrade hosts in Yoga then go to Zed. Both are accepted by the prechecks. | Officially supported, order is a human decision |
| Ubuntu | 22.04 → 24.04 | 2024.1 or 2024.2 (both accept jammy and noble); must be done before 2025.1 | 2024.1 support matrix: Noble hosts can use Jammy (default) or Noble images; release note `ubuntu-noble`; **no migration guide found** in 2024.1/2024.2 docs | Officially supported host OS, procedure not documented upstream |
| CentOS | CentOS 8 → CentOS Stream 8 | Victoria (both), already prepared by Ussuri-eol `-centos8s` suffix | `kolla-ansible@wallaby-eol:releasenotes/notes/centos-stream-686441cc4c0e47d7.yaml` | Officially supported |
| CentOS | Stream 8 → Rocky 9 (or CS9) | Yoga | `kolla-ansible@yoga-eol:doc/source/user/rocky-linux-9.rst`: remove host from service, reprovision, redeploy, per-host `kolla_base_distro`; MariaDB instability observed mid-migration, `mariadb_recovery` suggested | Officially supported, reprovision (not in-place) |
| Rocky | 9 → 10 | 2025.1 | `kolla-ansible@origin/stable/2025.1:doc/source/user/rocky-linux-10.rst`, note `rocky-10-epoxy`, `add-valkey` (`migrate-valkey` "one use case is migrating a Rocky Linux 9 based 2025.1 deployment to Rocky Linux 10") | Officially supported |
| Debian | 10 → 11 → 12 (→ 13 optional) | 11 in Wallaby (both), 12 in 2023.1–2024.1 (both), 13 only in 2026.1 | prechecks/matrix only | precheck-accepted; no guide read |

Ubuntu summary: three host OS upgrades, at Victoria, Yoga/Zed, and 2024.1. The deploy host follows its own path
(section 2).

## 4. Container engine, image naming, registries, image availability

### 4.1 Engine

- Docker only up to 2023.1. Podman support appears in 2023.2 (`kolla_container_engine: podman`,
  `kolla-ansible@2023.2-eol:releasenotes/notes/feature-podman-support-c4fa7c367b4ceac4.yaml`); the Ansible module is
  renamed `kolla_container` (`rename-kolla-docker`). A Docker→Podman migration command `migrate-container-engine`
  exists from 2025.1 (`kolla-ansible@origin/stable/2025.1:setup.cfg`). Containers get systemd units
  `kolla-<name>-container.service` from 2023.1 (`add-systemd-container-control`).
- Docker minimum 18.09 and docker SDK 3.4.1 from Wallaby onward (prechecks vars). Docker's own settings
  (registries, proxy, insecure registries) reach the daemon only through `bootstrap-servers`, which can restart
  Docker and every container (`openstack-kolla-ansible-operations`, commands-and-changes.md KA-CMD-14 and the 2025.1→2026.1
  lab report). Wallaby disabled Docker iptables/bridge by default (`disable-docker-iptables-bridge`), a change applied
  only by `bootstrap-servers`.
- Recommendation: stay on Docker through the chain; an engine change is a separate change (do not stack it).

### 4.2 Image name scheme

| Series | Default image reference | Evidence |
|---|---|---|
| Ussuri–Wallaby | `[docker.io/]kolla/<distro>-<binary\|source>-<service>:<release>` (CentOS Stream: `<release>-centos8s`) | `kolla-ansible@ussuri-eol:ansible/roles/nova/defaults/main.yml` (`nova_api_image`), `ansible/group_vars/all.yml` (`docker_namespace: "kolla"`, `docker_registry:` empty) |
| Xena–Yoga | `quay.io/openstack.kolla/<distro>-<source\|binary>-<service>:<release>`; default type source | `switch-images-to-quay-d4640afca6862eee.yaml`, `default-type-source-3fefd8baa3ca46ba.yaml` |
| Zed–2026.1 | `quay.io/openstack.kolla/<service>:<release>-<distro>-<distro_version>` (e.g. `nova-api:2026.1-ubuntu-noble`) | `kolla@zed-eol:releasenotes/notes/new-naming-scheme-45a5669053c9328d.yaml`; `kolla-ansible@zed-eol:ansible/group_vars/all.yml` `openstack_tag` |
| 2024.2–2026.1 | adds `docker_image_name_prefix`; 2025.2+ `docker_image_url` | group_vars |

Image renames that matter for a mirror list: `mariadb` → `mariadb-server` (Victoria/Wallaby), `prometheus-v2-server`
→ `prometheus-server` (2025.1), `ironic-pxe` → `ironic-tftp`, `ironic-ipxe` → `ironic-http` (Yoga), Elasticsearch,
Kibana → OpenSearch, OpenSearch Dashboards (Zed), `redis` → `valkey` (2025.2), `rabbitmq-3-12`/`-3-13`/`-4-x`
side images for SLURP preparation (2023.1+).

### 4.3 Where images were published (kolla CI)

| Series | Publish jobs in kolla `.zuul.d/` at the ref | Note |
|---|---|---|
| Ussuri–Xena | `kolla-publish-<distro>-<type>-{dockerhub,quay}`; Docker Hub namespace `kolla`, quay namespace `openstack.kolla` | `kolla@ussuri-eol:.zuul.d/ubuntu.yaml` lines 50–67 |
| Yoga | none at the eol tag: "Drop publishing and periodic jobs" (3b1c87c92, 2024-02-07) | images published earlier remain only if the registries kept them |
| Zed, 2023.1, 2023.2 | `kolla-publish-<distro>-{dockerhub,quay}`; Zed and 2023.1 later stopped publishing ("CI: Stop publishing since Zed is unmaintained", "CI: Drop upgrade and publish jobs for 2023.1") | `kolla@zed-eol`, `kolla@2023.1-eol` `.zuul.d/` history |
| 2024.1 | none at branch tip ("Cleanup zuul jobs", ee46746c6, 2026-06-26) | |
| 2024.2–2026.1 | quay.io only (`kolla-publish-*-quay`) | `kolla@origin/stable/2026.1:tests/playbooks/publish.yml` |

### 4.4 Availability (observed from this environment, 2026-10-31)

- Docker Hub: an anonymous token for `repository:kolla/ubuntu-binary-nova-api:pull` was **issued** (HTTP 200), but
  manifest requests answered **401 UNAUTHORIZED** for `kolla/ubuntu-binary-nova-api:ussuri`,
  `kolla/ubuntu-source-nova-api:yoga`, `kolla/nova-api:2023.1-ubuntu-jammy`, `kolla/ubuntu-binary-mariadb-server:ussuri`.
  Hub tag metadata for `ussuri`: `status: inactive`, `last_pushed: 2022-12-31`. (Observed. The brief reported a 401 on
  the token itself; here the token was issued and the manifest refused. Same practical result: not pullable
  anonymously from here.)
- quay.io: blocked by this environment's proxy; availability of `quay.io/openstack.kolla/*` tags for Ussuri–2024.1 is
  **unknown**.
- Kolla-Ansible 2026.1 prechecks refuse quay.io `openstack.kolla` images: "meant only for testing purposes … use
  --use-test-images" (`kolla-ansible@origin/stable/2026.1:ansible/roles/prechecks/tasks/registry_checks.yml`; the OzarLand
  quick-lab passes `--use-test-images`, `remote-deploy.sh` line 105). Production is expected to run its own registry.
- Rebuilding old images with kolla is **Not validated** and likely needs patches: source images fetch
  `$tarballs_base/openstack/nova/nova-stable-ussuri.tar.gz` (`kolla@ussuri-eol:kolla/common/config.py` line 627–630),
  a branch tarball whose branch no longer exists; Ussuri–Zed RabbitMQ/Erlang repositories include `packagecloud.io`,
  which kolla itself says was shut down on 2024-08-18 (`kolla@2023.1-eol:releasenotes/notes/rabbitmq-erlang-migrate-from-packagecloud-59d7e9e0a10e1da0.yaml`);
  Ubuntu binary images depend on Ubuntu Cloud Archive pockets for bionic/focal (availability not checked).
- `kolla-ansible install-deps` for Yoga–2023.2 and 2024.2 points at branches that no longer exist on the GitHub
  mirror of `ansible-collection-kolla` (`requirements.yml`: `unmaintained/yoga`, `unmaintained/zed`,
  `unmaintained/2023.1`, `stable/2023.2`, `stable/2024.2`); `git ls-remote` shows only the `*-eol`/`*-eom` tags for
  those series (Observed). The plan must pin the collection to tags (the automation-review rule on renamed
  branches applies exactly here).

## 5. What `kolla-ansible upgrade` does (2026.1), and the gates

Mechanics (from `kolla-ansible@origin/stable/2026.1`):

- CLI: `upgrade` runs `site.yml` with `kolla_action=upgrade` and `kolla_serial` forced
  (`kolla_ansible/cli/commands.py`, class `Upgrade`; OzarLand lab KA-CMD-09 observed the override for `reconfigure`).
  It does **not** run prechecks (the `prechecks` role only applies to `kolla_action_precheck`, `ansible/site.yml`).
  There is no task that compares the running release or image tags with an allowed "previous release".
  `openstack_previous_release_name` existed up to 2024.2 and was used only for Ironic `pin_release_version`
  (`improve-ironic-pin-release-version` note, 2025.1).
- MariaDB: `SET GLOBAL wsrep_sst_method='rsync'` via `docker exec mariadb mariadb -uroot …`, rolling `deploy.yml`, back
  to `mariabackup`, then `post-upgrade.yml` runs `mariadb-upgrade` in a one-shot container (`KOLLA_UPGRADE`), and the
  `mariadb_clustercheck` container is removed (`roles/mariadb/tasks/upgrade.yml`, `post-upgrade.yml`,
  `kolla@origin/stable/2026.1:docker/mariadb-server/extend_start.sh`). No MariaDB version check.
- RabbitMQ: `rabbitmq-version-check` compares `rabbitmqctl --version` of the running container with the new image;
  passes only for +1 minor, an explicit `rabbitmq_allowed_upgrades` path, or same version
  (`roles/rabbitmq/tasks/version-check.yml`, defaults lines 130–139). 3.8 → 4.2 fails with "Invalid upgrade path
  detected!". Since 2023.1 the check exists; since 2024.1 it refuses skip-release jumps.
- Keystone: `db_sync --expand`, `--migrate` (first keystone host), `--contract` (last host)
  (`roles/keystone/tasks/upgrade.yml`, `kolla@origin/stable/2026.1:docker/keystone/keystone/extend_start.sh`).
- Glance: `glance_enable_rolling_upgrade: false` by default → legacy path (`db_sync`); rolling path uses
  `glance-manage db expand/migrate/contract` (`roles/glance/tasks/*upgrade.yml`, `group_vars/all/glance.yml`).
- Neutron: `neutron_enable_rolling_upgrade: "yes"`: expand, restart, check pending contract scripts, stop all
  `neutron-server` if contract needed, contract (`roles/neutron/tasks/rolling_upgrade.yml`); `neutron_plugin_agent_check.yml`
  refuses ML2/OVS↔OVN mismatches.
- Nova: config, then **`nova-status upgrade check` with the new image**; fails the run on rc ∉ {0,1}
  (`roles/nova/tasks/upgrade.yml`); `nova_safety_upgrade: false` (no stop of all services); `api_db sync` +
  `db sync` (`KOLLA_UPGRADE`), reloads, then API and cell **online data migrations** (`ansible/nova.yml` plays "Run
  Nova API/cell online data migrations"); `[upgrade_levels] compute = auto` (`nova.conf.j2`). nova-cell runs a
  libvirt downgrade check and an image-content check (`roles/nova-cell/tasks/version-check.yml`).
- Placement and Cinder: `db sync`, then online data migrations (`KOLLA_OSM`) (`roles/placement/tasks/upgrade.yml`,
  `roles/cinder/tasks/upgrade.yml`).

The upstream 2026.1 Nova code sets `OLDEST_SUPPORTED_SERVICE_VERSION = 'Epoxy'`
(`nova@origin/stable/2026.1:nova/objects/service.py` line 284), and `nova-status upgrade check` returns FAILURE for
computes older than that (`nova/cmd/status.py` `_check_old_computes`). Nova removed its sqlalchemy-migrate (pre-alembic)
migrations in 28.0.0 / 2023.2 (`nova` commit fd39e4b4be); `nova/db/migration.py` on 2026.1 only runs alembic. Both
are Nova facts reported here because Kolla-Ansible relies on them; the Nova specialist owns them.

## 6. Can Kolla-Ansible 22.x be pointed at a Ussuri deployment?

### 6.1 `kolla-ansible upgrade` (22.x) on the Ussuri environment: Incompatible

In the order a run would meet them (Technically derived from code, Not validated):

1. **Deploy host:** kolla-ansible 22.x needs Python ≥ 3.11 and ansible-core 2.19–2.20 (2.20 needs Python ≥ 3.12). A
   Ussuri deploy host (Ubuntu 18.04, Python 3.6) cannot install it. A new deploy host is needed regardless.
2. **Targets:** Ussuri hosts run Ubuntu 18.04 (Python 3.6) or CentOS 8. Whether ansible-core 2.19/2.20 can even gather
   facts on Python 3.6 targets was not checked (Open question); 2026.1 prechecks reject bionic/CentOS 8 outright.
3. **Inventory and variables:** a Ussuri inventory lacks `loadbalancer`, `common`, `cron`, `fluentd`, `kolla_logs`,
   `kolla_toolbox`, `neutron-rpc-server`, `neutron-periodic-worker`, `valkey`, … (section 2 of
   `03-configuration-transformation.md`). Plays index `groups[...]` of missing groups.
4. **First stateful gate, MariaDB:** the upgrade's first MariaDB task runs `mariadb -uroot …` inside the running
   Ussuri `mariadb` container (MariaDB 10.3). Hypothesis: the `mariadb` client name does not exist in 10.3 images
   (introduced in a later MariaDB series, from memory), so the task would fail; if it did not, a rolling restart
   from 10.3 (Galera 3) straight to 11.4 (Galera 4) is outside anything Kolla-Ansible or MariaDB tests. Data-damage
   risk.
5. **RabbitMQ:** `rabbitmq-version-check` fails for 3.8 → 4.2 (explicit gate). Classic mirrored queues
   (`ha-all`-style policies) are gone in RabbitMQ 4.x and the quorum/durable queue migration must be done first.
6. **Nova:** `nova-status upgrade check` with the 2026.1 image against Ussuri databases fails (computes older than
   Epoxy; and the DB is not at an alembic revision the 2026.1 code knows). Kolla-Ansible stops the run there, but
   **after** Keystone, Glance, Placement and Neutron have already been through their 2026.1 upgrade tasks: a half-
   upgraded control plane with no supported way back except restore.
7. **Keystone/Glance/Neutron/Cinder DB migrations** from Ussuri schemas with 2026.1 code: owned by the service
   specialists; Kolla-Ansible adds no protection.

Verdict: there is no code path in 22.x that accepts Ussuri containers or data; there is also no early, clean refusal.
The gates that exist fire late (RabbitMQ, Nova) and can leave partial state.

### 6.2 Ussuri `/etc/kolla` + 2026.1 `deploy` on fresh hosts, databases migrated separately: Technically possible but unsupported

Plausible shape (PROPOSED-UNVERIFIED):

- Fresh Ubuntu 24.04 (or Rocky 10) hosts, new deploy host, 2026.1 Kolla-Ansible, a registry holding 2026.1 images.
- `/etc/kolla` transformed (not reused as is): globals, inventory, `passwords.yml` merged with `kolla-mergepwd`
  keeping every Ussuri secret, overrides rewritten (see `03-configuration-transformation.md`).
- Databases brought to the 2026.1 schema **outside** Kolla-Ansible by running each service's intermediate code for
  its migrations (section 7), then loaded into the new Galera before `deploy`.
- `deploy` then bootstraps on existing databases: Kolla's bootstrap containers run `db sync` and online migrations,
  which are idempotent on an up-to-date schema (from the `extend_start.sh` scripts; not executed); `keystone-manage
  bootstrap` re-asserts the admin user, endpoints are re-registered by `service-ks-register`.

What breaks or needs care (Hypotheses to test in a lab):
- Fernet keys and credential keys: tokens become invalid (acceptable); Keystone's **credential encryption keys**
  must be carried over or encrypted credentials stored in the Keystone database (e.g. EC2 secrets) become
  unreadable. Where Kolla-Ansible keeps them in each release was not checked (Open question 9).
- Hostnames: compute service records, Placement resource providers, Neutron agents and instance `host` fields refer
  to the old hostnames; keeping the same inventory hostnames avoids orphan records.
- Running instances: Ussuri computes cannot coexist with 2026.1 control plane (RPC and service version gates), so
  instances are stopped, computes are reinstalled, and instances are started again on the same host (local disks
  kept) or anywhere (shared Ceph). This is a full data-plane outage per compute, not a rolling upgrade.
- Leftovers in the catalog: Ussuri admin endpoints, `cinderv2`/`volumev2`, Panko/Monasca etc. are not removed by
  Kolla-Ansible (`drop-admin-endpoints` Yoga note).
- RabbitMQ: start empty; nothing to migrate (queues are rebuilt by services).
- Ceph, Octavia amphorae, OVN databases (if ML2/OVN) and Designate pools: outside this assessment.

## 7. Intermediate images needed if intermediate code runs only for database migrations

Assumption (to be confirmed by the service specialists): before 2023.1 every service requires N→N+1 code steps; from
2023.1, SLURP allows 2023.1 → 2024.1 → 2025.1 → 2026.1. Under that assumption the code of these series must run
against the databases: **Victoria, Wallaby, Xena, Yoga, Zed, 2023.1, 2024.1, 2025.1** (then 2026.1 itself).

| Purpose | Kolla image (per series) | Commands Kolla runs in it (`extend_start.sh`) |
|---|---|---|
| Keystone schema | `keystone` | `keystone-manage db_sync --expand/--migrate/--contract` |
| Glance schema | `glance-api` | `glance-manage db_sync` or `db expand/migrate/contract` |
| Neutron schema (+ enabled sub-projects such as VPNaaS, FWaaS until removed) | `neutron-server` | `neutron-db-manage --subproject neutron upgrade [--expand\|--contract]` |
| Nova API + cell schemas and online data | `nova-api` (API DB), `nova-conductor` (cells) | `nova-manage api_db sync`, `nova-manage db sync --local_cell`, `nova-manage db online_data_migrations` |
| Placement | `placement-api` | `placement-manage db sync`, `online_data_migrations` |
| Cinder | `cinder-api` | `cinder-manage db sync`, `online_data_migrations` |
| Heat, Octavia, Designate, Barbican, Manila, … (if enabled) | `<service>-api`/engine image | service `db sync` |
| MariaDB data directory | `mariadb-server` 10.5 (Xena), 10.6 (Yoga), 10.11 (2023.2+), 11.4 (2025.2+) | `mariadb-upgrade`/`mysql_upgrade`; whether 10.3 → 11.4 can be done in one jump, or a dump/restore is preferable, is a MariaDB question (Open question) |

Image naming per series follows section 4.2; for Ussuri–Yoga the binary/source choice matters (the database code is
the same release but packaged differently; any is fine for migrations). Availability: Docker Hub copies are not
pullable anonymously from here; quay.io copies are unknown; rebuilds are not validated. **An image inventory against
the real registry (quay.io from a host that can reach it, or a vendor mirror) is the first gate of any plan.** An
alternative that avoids container images entirely is running each project's tagged source in a per-series Python
virtual environment (PyPI wheels pinned by `requirements` `upper-constraints` of that series); that belongs to the
service specialists and the architect.

## 8. Notes from the OzarLand material

- The 2025.1 → 2026.1 lab report (Kolla-Ansible 20.6.0 → 22.2.0, all-in-one, Ubuntu 24.04, Docker 29) is the only
  executed evidence for the last hop: `upgrade` completed in 24 min, `failed=0`, RabbitMQ 4.0.9 → 4.2.9 allowed, MariaDB
  10.11 → 11.4.13 without incident, everything that broke was before `upgrade` (registry settings, backup check,
  image pruning). [LAB-VALIDATED: KA-ARCH-29, single all-in-one, draft, not multinode] It says nothing about earlier hops.
- The quick-lab deploys 2026.1 with `KOLLA_ANSIBLE_VERSION="22.2.0"`, `ANSIBLE_CORE_VERSION="2.20.10"`, Docker, Ubuntu
  24.04 (`config.example.env` lines 55–56) and passes `--use-test-images` to prechecks when pulling from quay.io.
  It can host a 2026.1 target lab but not the intermediate releases.
- Skill rules that shape the plan: keep the deploy host's Kolla-Ansible pinned to the platform's release (a newer
  Kolla-Ansible `deploy` is an upgrade without upgrade tasks, KA-CMD-02); `--limit` is not recommended for upgrades
  (bug 2054348); `bootstrap-servers` can restart Docker and every container; `kolla-mergepwd` keeps old keys
  (KA-CFG-04); there is no downgrade after schema migrations (KA-ARCH-28).

## 9. Classification summary

| Claim | Class |
|---|---|
| Each N→N+1 hop Ussuri…2023.1 with that release's Kolla-Ansible `upgrade` | Officially supported (per hop), DOCUMENTED-UNVERIFIED |
| SLURP hops 2023.1→2024.1→2025.1→2026.1 with the target release's Kolla-Ansible | Officially supported, DOCUMENTED-UNVERIFIED; last hop has one all-in-one lab run (LAB-VALIDATED, draft) |
| Skipping any release before 2023.1 with Kolla-Ansible | Not supported; no documented path |
| `kolla-ansible upgrade` 22.x directly on Ussuri | Incompatible |
| 2026.1 `deploy` on fresh hosts with separately migrated databases | Technically possible but unsupported; Not validated |
| Host OS upgrades at Victoria, Yoga/Zed, 2024.1 (Ubuntu) | Officially supported host-OS overlaps; procedure only documented for Rocky 9/10 and Focal (order note) |
| Intermediate image availability | Not validated; Docker Hub not pullable here (Observed); quay unknown |

## 10. Open questions / what I could not verify

1. quay.io availability of `openstack.kolla` tags for Ussuri through 2024.1, per image (blocked here). Would be
   established by `skopeo list-tags docker://quay.io/openstack.kolla/<image>` from a host with access.
2. Whether Docker Hub `kolla/*` is pullable with an authenticated (non-anonymous) account.
3. Target-host Python minimum of each ansible-core line (2.16–2.20); only controller requirements were read.
4. Whether Ansible 2.9 (Ussuri/Victoria) runs on Python ≥ 3.10; if not, those hops need a Python 3.8 venv or container.
5. Whether the MariaDB 10.3 image contains a `mariadb` client binary (affects 6.1 item 4); and whether MariaDB/Galera
   tolerate 10.3 → 11.4 in one step.
6. Rebuildability of kolla images for each EOL series (tarball URLs, packagecloud, UCA), i.e. whether a local
   registry can be filled by building.
7. The Ubuntu 22.04 → 24.04 host migration procedure (no upstream guide found in 2024.1/2024.2 docs).
8. Exact list of non-default services in the real Ussuri deployment (Monasca, Freezer, Zun, Swift, Linux Bridge,
   Elasticsearch, chrony, Redis, Octavia, Ironic…): each one adds forced steps.
9. Keystone credential/Fernet key locations per release for the rebuild path (6.2).
10. The precise first failing task of 6.1 was derived from code, not run. A lab run on disposable VMs would settle it.
