# 05 - Laboratory feasibility and Ussuri baseline

| Metadata | |
|---|---|
| Author | Agent 5 - Laboratory and Automation Engineer |
| Model | Sonnet |
| Date | 2026-10-31 |
| Status | Stage 1 feasibility and Phase 2 baseline: **built, captured, restore proven**. Baseline coverage partly complete (see section 6). No later-release code was run |
| Inputs read | `assessments/00-mission-brief.md`; `experiments/baseline-coverage-checklist.md` (with the Agent 4 review), `experiments/declared-differences.md` and `experiments/fast-forward-checks.md` (only the DR-003, ODM and PC rows); OzarLand `openstack-quick-lab` (README, CONTRIBUTING, `variants/openstack-cloud/*`); skills `openstack-automation-review` and `openstack-kolla-ansible-operations`; upstream `kolla`, `kolla-ansible`, `requirements`, `nova`, `neutron`, `cinder`, `keystone` at `ussuri-eol` |
| Evidence | `evidence/lab-baseline/` (all files named below); scripts in `lab/ussuri-db-lab/`; quick-lab patch in `lab/quick-lab-extension/` |

Status vocabulary: **Experimentally validated** only for what the evidence files show. Everything about a real Kolla-Ansible Ussuri
deployment is `PROPOSED-UNVERIFIED` or `Not validated`.

## 1. Summary

1. A real Kolla-Ansible Ussuri lab **cannot be built in this environment**. Four independent blockers, each shown by a command (section 3).
2. A **container Ussuri control plane** was built instead from the upstream Ussuri releases on PyPI under the `ussuri-eol` upper constraints:
   Keystone, Glance, Placement, Nova (API, conductor, scheduler, three fake computes), Neutron, Cinder (API, scheduler, volume), on MariaDB 10.3,
   RabbitMQ 3.8 and memcached. The real Ussuri `db sync` commands created the real Ussuri schemas (573 tables, 542 in the OpenStack databases).
3. Representative resources were created **only through the Ussuri APIs** (about 60 coverage actions, 3 recorded failures at first attempt, 6 items "not covered").
4. The baseline is **captured twice** per DR-003 (computes stopped but not forced down; then forced down through the API), each with logical dumps, exact row counts,
   `CHECKSUM TABLE` of every table, an API inventory and cold volume tarballs.
5. **Restore is proven**: logical restore and tarball restore into fresh MariaDB containers give identical row counts (571 tables, excluding the two InnoDB statistics tables), identical `CHECKSUM TABLE` for
   542 OpenStack tables and an identical sha256 of the OpenStack-only dump. A full lab restore from the tarballs (22 s) passes the inventory and functional checks with 0 differences.

Baseline status: **LAB-VALIDATED as a Ussuri-schema, API-populated, restorable baseline of a fenced platform**; **NEEDS-REVALIDATION** for the items listed in section 6 as not covered or partial, and
it remains `Not validated` for anything that depends on Kolla-Ansible, libvirt, an OVS/OVN data plane, real storage backends or Galera/HAProxy.

## 2. Environment and versions (`evidence/lab-baseline/versions.txt`, `pip-freeze-ussuri-py38.txt`)

| Item | Value |
|---|---|
| Host OS / kernel | Ubuntu 24.04.5 LTS / 6.18.44-fc-v185 (no `/dev/kvm`, no `/lib/modules`) |
| Host Python / Docker | 3.13.18 / 29.9.2 (client and server) |
| Resources | 4 vCPU, 15 GB RAM |
| MariaDB | `mariadb:10.3` = 10.3.39 (Ubuntu 20.04 build from MariaDB's repo). Kolla Ussuri used the MariaDB 10.3 repo (`kolla@ussuri-eol:kolla/template/repos.yaml:56,68,78`); exact patch level of any original image: unknown. Deviation: official Docker image, single node, no Galera |
| RabbitMQ | `rabbitmq:3.8-management` = 3.8.34 on Erlang/OTP 24. Kolla Ussuri: CentOS `rabbitmq-server-3.8.*` with `erlang-23.*` (`kolla@ussuri-eol:docker/rabbitmq/Dockerfile.j2`); Ubuntu: unpinned cloudsmith package. Deviation: Erlang 24, single node, no `ha-all` policy |
| memcached | 1.5.22 |
| Application runtime | `python:3.8-buster` build stage, `python:3.8-slim-buster` runtime; Python 3.8.17 (Ussuri supports 3.6-3.8) |
| Packages | keystone 17.0.1, glance 20.2.0, openstack-placement 3.0.1, nova 21.2.4, neutron 16.4.2 (neutron-lib 2.3.0), cinder 16.4.2, python-openstackclient 5.2.0, osc-placement 2.0.0, oslo.db 8.1.1, SQLAlchemy 1.3.16, sqlalchemy-migrate 0.13.0, alembic 1.4.2, eventlet 0.26.1, PyMySQL 0.9.3, gunicorn 20.0.4 (194 packages; `pip check` clean). Constraints: `requirements@ussuri-eol` (5095bcd0), file kept as `lab/ussuri-db-lab/image/upper-constraints-ussuri-eol.txt`. Horizon not installed |
| Image build / bring-up | build 162 s; `up` 175 s (infra 10, config 2, keystone 11, catalogue 88, db syncs 39, services 11); `populate` about 17 min (the 1500 token revocations take about 8 min) (`up-timings.txt`, `dbsync-timings.txt`) |

Schema markers at T0 (`schema-versions.tsv`): keystone `keystone`=109 plus `keystone_expand`/`keystone_data_migrate`/`keystone_contract`=078; glance `ussuri_contract01`; placement `b5c396305c25`; nova_api 072; nova and nova_cell0 407; neutron two alembic heads (`5c85685d616d`, `d8bdf05313f4`); cinder 136. `@@GLOBAL.sql_mode` = `STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION`; services use oslo.db's session default `TRADITIONAL` (not measured through a live session in this run: stated from the oslo.db option default).

## 3. Track K - what a real Kolla-Ansible Ussuri lab needs, and why it cannot run here

### 3.1 Requirements (source: `kolla-ansible@ussuri-eol`)

| Need | Value | Source |
|---|---|---|
| Kolla-Ansible | 10.x (latest tag 10.4.0) | `git tag` of `kolla-ansible` |
| Ansible | **2.8 to 2.9 only** (package `ansible`, not `ansible-core`) | `ansible/roles/prechecks/vars/main.yml` (`ansible_version_min: '2.8'`, `max: '2.9'`); `doc/source/user/quickstart.rst` |
| Host OS | CentOS 8, Debian 10, RHEL 8, **Ubuntu 18.04** (all end of life) | `doc/source/user/support-matrix.rst`; `prechecks/vars/main.yml` `host_os_distributions` |
| Host Python | 3.6 on Ubuntu 18.04 (`python-requires >=3.6`) | `setup.cfg` |
| Images | `kolla/<distro>-<install_type>-<service>:ussuri` on Docker Hub (`docker_namespace: kolla`, `openstack_release: ussuri`); distro `ubuntu` or `centos` (tag suffix `-centos8s` on Stream) | `ansible/group_vars/all.yml:117,530-533`; roles' `*_image` variables |
| No such features in 10.x | `kolla-ansible install-deps`, `kolla_container_engine`, ProxySQL, `--use-test-images`, `docker_http_proxy` variables | absent in `tools/kolla-ansible`, `ansible/group_vars/all.yml`, `ansible/roles/baremetal/defaults/main.yml` |

### 3.2 Why it cannot run here (`probe-registry.txt`, `probe-kolla-images.txt`, `probe-kolla-build-network.txt`)

| Blocker | Evidence |
|---|---|
| No OpenStack cloud account for quick-lab's `create.sh` | mission brief; the variant needs `clouds.yaml` |
| Kolla Ussuri images not pullable | `kolla/ubuntu-source-keystone:ussuri` (and `ubuntu-binary-`, `centos-source-`, `centos-binary-`, `base`, `mariadb`, `rabbitmq`, tags `ussuri` and `10.4.0`): token request 200, **manifest request 401 UNAUTHORIZED**; `docker pull` -> "pull access denied". Hub API shows the tag `status: inactive`, last pushed 2022-12-31 |
| quay.io and the Kolla source/RPM hosts blocked | `quay.io`, `tarballs.opendev.org`, `opendev.org`, `trunk.rdoproject.org`, `mirror.centos.org`, `vault.centos.org`, `ubuntu-cloud.archive.canonical.com`, `dlm.mariadb.com`, `dl.cloudsmith.io`: HTTP 000 through the proxy. Ubuntu archive and PyPI reachable |
| No KVM, no kernel modules | `/dev/kvm` and `/lib/modules` absent; `modprobe`/`lsmod` not installed. No OVS datapath, no nested VMs |

### 3.3 Local rebuild probe with `kolla-build` 10.4.0 (`kolla-build-probe-summary.txt`, logs in `lab/ussuri-db-lab/kolla-probe/`)

Time-boxed to about 30 minutes, `ubuntu:18.04`, `install_type=source`, sources from GitHub git at `ussuri-eol`:

1. `pip install kolla==10.4.0` without constraints fails (`jinja2.contextfilter` removed in Jinja2 3.1): **install with the `ussuri-eol` constraints**.
2. `kolla-build base` (published templates) fails at step 21/33, `apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80` ("keyserver receive failed: No data" through the proxy). **FAILED**.
3. With a template override that removes the custom `sources.list`, apt preferences and key import, **`base` built** (`ufj/ubuntu-source-base:ussuri-probe`, 308 MB). This image is **not** the Kolla Ussuri base: no Ubuntu Cloud Archive (qemu/libvirt/OVS), none of the MariaDB, RabbitMQ, Docker, Grafana or Elastic repositories.
4. `openstack-base`: the git clone of `requirements@ussuri-eol` works from a container with `--network host`; the next step (`pip install -c upper-constraints virtualenv` inside the build) fails: the build container cannot reach the proxy (a host loopback address) and would also need the proxy CA inside the image. The only shortcut is to disable TLS verification, which was **not** done. Stopped there.

Conclusion: a faithful Kolla Ussuri image set cannot be rebuilt here. **Not validated**: whether the same build would succeed on a host with direct Internet access and a reachable Ubuntu Cloud Archive (Ussuri pocket for bionic; whether it still exists: unknown).

### 3.4 Extension of openstack-quick-lab (patch, `PROPOSED-UNVERIFIED`)

`lab/quick-lab-extension/ussuri-release-profile.patch` (253 lines; `git apply --check` passes on the pristine `openstack-quick-lab` at `f7abc066`; not pushed). It adds a **release profile** mechanism: empty `RELEASE_PROFILE` keeps today's 2026.1 behaviour byte for byte in intent (`ANSIBLE_PIP_SPEC` defaults to `ansible-core==$ANSIBLE_CORE_VERSION`, `PIP_EXTRA` to `docker dbus-python`); `RELEASE_PROFILE=ussuri` loads `profiles/ussuri.env`. What in `remote-deploy.sh`/`create.sh`/`deploy.sh` assumed 2026.1, and what the patch does:

| 2026.1 assumption | Ussuri reality | Patch |
|---|---|---|
| `ansible-core==2.20.10` | `ansible` 2.9.x | `ANSIBLE_PIP_SPEC="ansible>=2.9,<2.10"` |
| `kolla-ansible==22.2.0` | 10.4.0 | `KOLLA_ANSIBLE_VERSION` in the profile |
| `kolla-ansible install-deps` | command does not exist | `HAS_INSTALL_DEPS=no` |
| `kolla_container_engine`, `enable_proxysql` in `globals.yml` | unknown variables | `HAS_CONTAINER_ENGINE_VAR`, `HAS_PROXYSQL` |
| `prechecks --use-test-images` | option does not exist | `HAS_USE_TEST_IMAGES=no` |
| `docker_http_proxy` etc. in `globals.yml` | do not exist in 10.x | systemd drop-in for Docker (`HAS_DOCKER_PROXY_VARS=no`) |
| `timedatectl show`, `networkctl reload` | systemd 237 on Ubuntu 18.04 has neither | `OLD_SYSTEMD=yes` fallbacks |
| `/etc/apt/sources.list.d/ubuntu.sources` (deb822) | `/etc/apt/sources.list` | `APT_SOURCES_FORMAT=list` |
| image regex `ubuntu.*24\.04` | `ubuntu.*18\.04` (a cloud may no longer offer it) | `HOST_IMAGE_REGEX` |
| images from quay.io, tag `2026.1` | none pullable | `REQUIRE_DOCKER_REGISTRY=yes`, `IMAGE_SOURCE=build` -> `profiles/ussuri-build-images.sh` (kolla-build 10.4.0 under the constraints into a local `registry:2`) |
| `docker` SDK without bound | Ansible 2.9 modules | `PIP_EXTRA="docker<5"` |

Per the `openstack-automation-review` skill: the patch is scoped to one variant, keeps the default path unchanged, adds no destructive action, and every new branch is explicit and named; but it was **never run** (no cloud), so safeguards (idempotency of the new `images` step, stop conditions when the build fails) are untested. Per `openstack-kolla-ansible-operations`: a real Ussuri deployment would also need `kolla-ansible bootstrap-servers` to install `docker-ce` from Docker's bionic repository (`ansible/roles/baremetal/defaults/main.yml`: `docker_apt_url`), whose availability today is unknown.

## 4. Track D - the container control plane

### 4.1 Topology and differences from Kolla Ussuri (`lab/ussuri-db-lab/README.md` has the diagram)

One image `ufj-ussuri-py38:1`, containers on the `ufj-net` network, every object prefixed `ufj-`: `ufj-mariadb`, `ufj-rabbitmq`, `ufj-memcached`, `ufj-keystone` (gunicorn), `ufj-glance`, `ufj-placement` (gunicorn), `ufj-nova-api/conductor/scheduler`,
`ufj-compute1/2/3` (fake), `ufj-neutron`, `ufj-fake-agent1/2/3`, `ufj-cinder-api/scheduler/volume`, `ufj-static` (HTTP file server for image locations), `ufj-client`. Volumes: `ufj-mariadb-data`, `ufj-rabbitmq-data`, `ufj-glance-images`, `ufj-keystone-keys` (Fernet and credential keys).

| Kolla-Ansible Ussuri | This lab |
|---|---|
| Kolla images, Python 3.6, Apache mod_wsgi | one Python 3.8 image from wheels, gunicorn |
| Galera cluster behind HAProxy/keepalived | one MariaDB node |
| RabbitMQ cluster with HA policy | one node |
| libvirt/KVM computes, OVS agents, L3/DHCP/metadata agents | `nova.virt.fake.FakeDriver` (subclass `ufj_fake.UfjFakeDriver` adds a 2-cell NUMA topology and PCPU inventory), ML2 mechanism driver `fake_agent` (a test driver shipped in the neutron wheel) with fake agents that send the real `report_state` and `update_device_up` RPCs; **no L3/DHCP/metadata agents, no datapath** |
| LVM/Ceph backend | `cinder.tests.fake_driver.FakeLoggingVolumeDriver`, two backends (`fake`, `fake2`); no cinder-backup |
| Fernet in `/etc/keystone` | Fernet in a Docker volume, `keystone-manage fernet_setup/credential_setup` |

The fake agent reads the list of its bound ports from the neutron database (read-only SELECT) because there is no datapath to learn it from; it is a lab device, not production behaviour.

### 4.2 What worked

* All real Ussuri schema commands succeeded: `keystone-manage db_sync` + `bootstrap`, `glance-manage db_sync`, `placement-manage db sync`, `nova-manage api_db sync`/`cell_v2 map_cell0`/`create_cell`/`db sync`, `neutron-db-manage upgrade heads`, `cinder-manage db sync` (timings in `dbsync-timings.txt`: nova db sync 12.9 s, neutron 5.2 s, others under 4 s).
* The three fake computes register (`nova.services` version 51), the scheduler places servers on them, ports bind (`vif_type=ovs`) and reach ACTIVE via the fake agents, Placement holds allocations for every live instance (`coverage-counts-T0-corrections.tsv`: no live instance without allocation).
* `nova-manage db archive_deleted_rows` archived the force-deleted instances (`nova-archive-deleted-rows.txt`), populating the shadow tables. Ussuri `nova-manage`, `placement-manage` and `cinder-manage db online_data_migrations` exit 0 and `glance-manage db check` reports "up to date", `nova-status upgrade check` succeeds (`odm-T0.txt`).

### 4.3 What failed or deviated (kept on purpose)

| Failure | Cause / consequence |
|---|---|
| `kolla/*` images, quay.io, Kolla rebuild | section 3 |
| Docker Hub **HTTP 429** on anonymous `python:3.8-slim-buster` pull during a rebuild | retried; `05-build-image.sh` now pulls with back-off |
| TLS-intercepting proxy: `pip` inside `docker build` failed certificate verification | the proxy CA is copied into the build context for the build only (`LAB_CA_BUNDLE`); verification was never disabled |
| MariaDB `--init-connect` with spaces broke the image entrypoint | option dropped |
| `[fernet_receipts] key_repository` default broke `keystone-manage bootstrap` | set explicitly |
| Keystone/placement factory parsed gunicorn's command line | wrapper modules in `wsgi/` |
| python-openstackclient 5.2: no `server create --tag`, no trust/user lookup for non-admin users | `tools/tag_server.py`, REST helpers in `tools/coverage_rest.py` |
| Volume **create from image** ends in `error` with the fake driver (Cinder `GlanceMetadataExists` on retry) | the volume `a-boot` is kept in the baseline as an `error` row; a blank bootable volume backs the boot-from-volume server |
| Pinned-CPU server `a-pinned` ends in **ERROR** (`ValueError` in `conductor.schedule_and_build_instances`, recorded in `nova_cell0.instance_faults`) | the lab driver/PCPU inventory does not satisfy the Ussuri request; the flavor `ufj.pinned` exists, the NUMA flavor server `a-numa` is ACTIVE. Cause not investigated further |
| Server tags, cinder group quota key `consistencygroups`, Glance multi-location, force-delete of soft-deleted servers failed on the first attempts | tool bugs, fixed in the scripts (recorded in the transcript; the final `coverage-actions.tsv` is from the last run). Two steps of that run were completed by hand afterwards (force-delete of three soft-deleted servers after the helper fix, archive, ODM runs: `61-odm.sh`) because the populate script aborted on `nova-manage archive` exit code 1 (rows archived) |
| `nova-manage db online_data_migrations`: `fill_virtual_interface_list` reports **9 needed, 0 completed**, exit 0, on every run | **the "0 remaining" summary for this ODM is not achieved**; cause not investigated (fake-driver instances have no virtual-interface list entries to fill). Record for PC-O1 |
| The coverage log initially recorded client output containing application-credential and EC2 secrets | scrubbed; the script now keeps only identifiers. Lab-generated, never valid outside the lab |
| A first `70-capture` row-count comparison failed on `mysql.innodb_table_stats`/`innodb_index_stats` | engine statistics rewritten by the server; excluded from the row-count comparison and reported (`restore-test.txt`) |

## 5. Baseline capture, DR-003 end state and recovery

Procedure (`scripts/72-capture-both.sh`): (A) `nova.services` table (id, host, binary, version, disabled, disabled_reason, forced_down, updated_at, deleted) and the *running* API inventory; stop `ufj-compute1/2/3` and `ufj-fake-agent1/2/3` and record the proof; API inventory of the fenced platform; stop the other services; dumps, counts, checksums, cold tarballs of `ufj-mariadb-data`, `ufj-keystone-keys`, `ufj-glance-images` -> `backups/baseline-20261031T114211Z-pre-forced-down`.
Then **`openstack compute service set --down <host> nova-compute` through the Ussuri API** (compute microversion 2.53 >= 2.11; `forced-down-api-output.txt`; no SQL) for the three computes. Then capture (B) -> `backups/baseline-20261031T114357Z-final` (`backups/latest`).

| Fact | Value |
|---|---|
| Fake compute host names | `ufj-compute1`, `ufj-compute2`, `ufj-compute3` (container name = nova host name) - EXP-SVC-01 may start a 2026.1 fake compute under one of them |
| `compute_driver` | shared `nova.conf`: `fake.FakeDriver`; compute containers add `nova-compute.conf`: `ufj_fake.UfjFakeDriver` (`fake-compute-config.txt`). Other settings that matter: `vif_plugging_is_fatal=false`, `reclaim_instance_interval=3600`, `NUMATopologyFilter` enabled, `resume_guests_state_on_host_boot=false` |
| Services table, final (`nova-services-table.tsv`) | conductor, scheduler, `nova-osapi_compute`/`nova-metadata` rows (host `0.0.0.0`), and 3 `nova-compute` rows, all `version=51`, `disabled=0`, `disabled_reason=NULL`; the 3 computes `forced_down=1`; pre-forced-down table has `forced_down=0` (`pre-forced-down/nova-services-table.tsv`); running table before the stop: `pre-forced-down/nova-services-running.tsv` |
| Proof of stop | `fence-proof.txt`: all six containers `status=exited running=false`, 0 running |
| Inventories | `pre-forced-down/inventory-running.json` (computes up), `pre-forced-down/inventory-fenced.json`, `inventory-fenced.json` = `inventory.json` (final). Note: in the first inventory taken after the stop, nova still reports the computes `up` for up to 60 s (heartbeat window); the forced-down state is visible in the final one |
| Two starting states | A: `backups/latest-pre-forced-down` (computes stopped, not forced down); B: `backups/latest` (forced down) |
| Database facts | 573 tables; counts in `rowcounts.tsv`; per-table checksums in `table-checksums.tsv`; sha256 of the OpenStack-only dump in `openstack-databases.sql.sha256`; schema-only dump `schema-only.sql.gz`; row counts per checklist item `coverage-counts-T0.tsv` (+ `-corrections.tsv`) |

Recovery tests (`restore-test.txt`, `verify-after-restore-into-lab.txt`):

| Test | Result |
|---|---|
| Logical restore (`all-databases.sql.gz` into empty `mariadb:10.3`, 10 s) | **PASS**: row counts identical (571 tables), `CHECKSUM TABLE` identical (542), dump sha256 identical (`cec9cd76...`); `mysql.*` grant/stat tables differ, reported |
| Physical restore (tarball into a new volume, 5 s) | **PASS**: same, and the `mysql.*` system tables are identical too |
| Full lab restore from tarballs (`./ufj.sh restore --yes`, 22 s; computes stay stopped) then API inventory compare | **PASS**: 0 differences; logins, image checksums (3), 11/11 servers same status, a write test, 3 compute rows present |
| Same compare on the live lab before the destructive restore | PASS (0 differences) |

Caveats: the verify step *writes* (a temporary network is created and deleted), so a lab used for verification is no longer byte-equal to the backup; **experiments must start from a restored copy, never from the preserved `backups/` directory**. The backups contain password hashes, Fernet keys and the lab passwords: they are git-ignored and must stay local (55 MB).

## 6. Coverage of `baseline-coverage-checklist.md` (RT-B-04) and the Agent 4 additions

Actions log: `coverage-actions.tsv`. T0 counts: `coverage-counts-T0.tsv`. Legend: C covered, P partial, N not covered.

| Item | State | Note |
|---|---|---|
| Cinder volumes available / in-use / deleted | C | 4 / 3 (plus 1 `error`) / 1 soft-deleted |
| Snapshot | C | 2 |
| `temporary='True'` admin metadata (non-deleted and deleted) | **N** | only created internally by backup/migration data paths; no backup service and no data path with the fake driver |
| `migration_status LIKE 'target:%'` | **N** | a migrate request to `fake2` was issued (`volume-migrate-attempt`); count is 0 |
| `quota_usages` rows | C | 13; `groups` usage present |
| Consistency-group quota rows (`quota_usages`/`reservations` for `consistencygroups`) | **P** | `groups` rows exist (1 quota row, 1 usage row); `consistencygroups` is not an accepted quota key in the v3 API and the usage/reservation rows for it are 0 even though a consistency group was created |
| Non-default `quota_backups` | C | `quota_backups=7`, `quota_backup_gigabytes=2500` in `cinder.conf` (`fake-compute-config.txt`); `default` quota classes listed in the counts file |
| Encryption volume type + attached volume with `connection_info` | C | 1 encrypted type, 1 encrypted volume, attachments with `connection_info` 3 |
| Nova ACTIVE / SHUTOFF / soft-deleted | C | 7 active, 1 stopped, 1 resized (VERIFY_RESIZE), 1 `soft-delete` |
| ERROR-without-host | C | in `nova_cell0` (`a-huge`, `a-pinned`); `nova.instances` ERROR-without-host count is 0 (cell0 holds them) |
| Deleted + archived (shadow tables) | C | 2 rows in `shadow_instances`, 2 in `shadow_block_device_mapping` |
| Deleted instance (live table) whose compute node row is gone | **N** | needs a compute service deletable through the API; a fourth fake compute received live instances and was removed from the design |
| Live instance on a host whose compute node is later deleted | C | `a-on-compute3` on `ufj-compute3` |
| NUMA flavor without `cpu_policy=dedicated` + instance | C | `ufj.numa`, `a-numa` ACTIVE with `numa_topology` |
| Pinned flavor + instance | **P** | flavor exists; the instance is in ERROR |
| Volume-backed BDMs | C | 3 `source_type=volume` |
| One resized + one migrated instance | C | `migrations`: resize confirmed 1, migration finished 1; `migration_context` 1 (the migrated instance is left in VERIFY_RESIZE) |
| `request_specs` with hints and server group | C | 12 request specs, 2 instance groups |
| `instance_actions` | C | 17 |
| Quotas in the API DB | C | 8 rows |
| Quotas in the legacy cell DB | **N (by design)** | the Ussuri API writes the API DB; `nova.quotas` has 0 rows; the Ussuri ODMs report 0 needed (`odm-T0.txt`) |
| At least two fake computes | C | 3 |
| `pci_devices` row with NULL uuid | **N** | the fake driver reports no PCI devices |
| `console_auth_tokens` | C | 1 |
| `cell_mappings` URLs as stored | C | recorded with passwords masked; lab names `ufj-mariadb`; `cell0` transport URL is `none:///` |
| Service rows incl. stopped computes | C | section 5. A row "for a compute that no longer exists": **N** (see above) |
| Keystone trusts (one with `expires_at` NULL, one with a value) | C | 3 (2 NULL, 1 dated). The duplicate pair is for negative copies only |
| Application credentials; with access rules | C | 4, 1 access rule |
| EC2 and TOTP credentials, credential key repository preserved | C | 1 + 1; `ufj-keystone-keys` volume is in the tarballs |
| Revocation events | C | 1501 rows |
| Federated mapping; identity provider; protocol; service provider | C | 1 each |
| Project tags | C | 3 |
| Password hasher per user | **P** | all 9 users `$2b$` (bcrypt). `sha512_crypt` cannot be produced: Ussuri only offers `bcrypt`, `scrypt`, `pbkdf2_sha512` (`keystone@ussuri-eol:keystone/conf/identity.py:111-114`); scrypt/pbkdf2 users were not created |
| `migrate_version`, all rows | C | `keystone`=109, `keystone_expand`/`data_migrate`/`contract`=078 |
| Neutron multi-segment network | C | 1 (two VLAN segments) |
| Segment range with NULL `physical_network` | C | `vxlan/NULL` ranges (default 1-1000 and 2000-2100). A duplicate range is for negative copies |
| Non-empty `quotas` | C | 5 rows |
| Ports with binding profiles and `extra_dhcp_opts`; `trusted` profile and empty profile | C | 2 profiles (1 `trusted`), 2 `extradhcpopts`, 20 ports with empty profile |
| HA router / `ha_router_networks` | **N** | no L3 agents (`min_l3_agents_per_router`) |
| RBAC in network, qos, security group, subnetpool, address scope tables | C | 3 / 1 / 1 / 2 / 1 |
| Tags incl. mixed case and non-ASCII | C | `ÉTÉ`, `tâg-ünï`, `Mixed-Case`, ... |
| Port-forwarding rule | C | 1 |
| DHCP ports | **N** | no DHCP agent |
| `portbindingports` and legacy plugin tables | C (counts) | `portbindingports` 0 |
| Glance multi-location image | C | 1 image with 2 locations |
| `image_locations.meta_data` without `"backend":` | C | 5 of 5 locations (all), counted |
| Glance tasks (with result) | C | 1 import task, success, with result |
| Images with properties, members (shared), community, hidden | **P** | properties 8, community 1, hidden 1, shared images 2; `image_members` rows are **0** (the sharing done in `populate.sh` did not create a member row; not investigated) |
| Placement nested provider, custom trait | C | `ufj-compute1-nested`, `CUSTOM_UFJ_LAB` |
| Allocations for every fake instance | C | verified (corrections file) |
| Consumer with no `consumer_types` row | C | the table does not exist in Ussuri (0): all 12 consumers qualify; one manual non-instance consumer created at microversion 1.28 |
| Every consumer has project and user | C | 0 incomplete |
| `@@GLOBAL.sql_mode` Ussuri; later engine images | C / out of scope | Ussuri recorded; the later engines are for the experiments |
| Ussuri ODM summaries "0 remaining" | **P** | all 0 except nova `fill_virtual_interface_list` (9 needed, 0 completed) |
| libvirt blobs, PCI/SR-IOV, OVN, real Ceph/LVM `connection_info` | **N** | Tier B only |

## 7. Automation review of my own scripts (skill `openstack-automation-review`, applied by me; a second reader has not reviewed them)

* **Scope and blast radius**: everything acts on containers/volumes named `ufj-*`; `99-destroy.sh` and `85-restore-into-lab.sh` need `--yes`, list what they will remove first, and `destroy` never touches `backups/` or `.secrets/` unless explicitly asked. No script touches anything outside the Docker host.
* **Preview/confirm**: destroy prints the targets and refuses without `--yes`; restore verifies `MANIFEST.sha256` before touching volumes.
* **Idempotency**: infra, config, db syncs (guarded `create_cell`), services and most `populate` steps ("show or create") can be re-run; `70-capture` is not idempotent (it stops services) and says so. `populate` was re-run several times during development; some objects (extra floating IPs, duplicate coverage lines) accumulated on early runs, the baseline comes from a clean run.
* **Failure/interruption**: scripts use `set -euo pipefail`; two real failures of that style are in section 4.3 (a command that exits 1 on success killed the populate script; fixed with `|| true` and a separate `61-odm.sh`). `70-capture` leaves the lab stopped if it dies midway (documented in the README; restart with `./ufj.sh restore` or `docker start`).
* **Concurrency**: no lock; one script at a time (stated).
* **Secrets**: generated at run time into git-ignored `.secrets/` and `.run/`; `backups/` is git-ignored and sensitive; the evidence directory was scanned for every generated secret value (0 hits). The proxy CA file is a build-time input only.
* **Owner/maintainability**: single author; the dependency on `cinder.tests.*` and `neutron.tests.*` modules (test drivers shipped in the wheels) is a fragility, and the fake agent reads the neutron DB: both are lab-only devices.
* **Verdict**: safe for a disposable, local lab; not for anything else.

## 8. Open questions / what I could not verify

1. A real Kolla-Ansible Ussuri run, with any image source, on Ubuntu 18.04 or CentOS 8: not possible here. Whether Docker's bionic repository, the Ussuri Ubuntu Cloud Archive pocket and `cloud-images.ubuntu.com/bionic` are still usable: unknown.
2. Exact MariaDB and RabbitMQ patch levels of the original Kolla Ussuri images: unknown; the lab uses 10.3.39 / 3.8.34 (Erlang 24).
3. Why nova's `fill_virtual_interface_list` finds 9 rows and completes none, why `a-pinned` fails with `ValueError`, why no `image_members` row was created, and why `consistencygroups` usage rows are not produced: not investigated.
4. The session `sql_mode` of the tools was not measured through a live connection.
5. Whether the nova API-database `quotas` rows and the Glance task result will behave the same under a Galera cluster: not covered.
6. Image-build reproducibility from a clean cache was demonstrated twice (162 s, then cached); a bit-for-bit identical image is not claimed (base images float).
7. Rebuild/restore instructions assume Docker Hub anonymous pulls of `python`, `mariadb`, `rabbitmq`, `memcached` (rate-limited once, HTTP 429).
