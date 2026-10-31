# Kolla-Ansible 22.x deploying a 2026.1 control plane on pre-existing, migrated databases

| Field | Value |
|---|---|
| Author | Agent 3, Kolla-Ansible Specialist (OzarLand multi-agent team) |
| Model | Claude Opus (claude-opus-5-5) |
| Date | 2026-10-31 |
| Status | Draft. **Source reading only; nothing was executed.** Every statement about behaviour is `DOCUMENTED-UNVERIFIED` (read in code); every step of section 5 is `PROPOSED-UNVERIFIED`. |
| Skills applied | `openstack-kolla-ansible-operations` (deploy vs upgrade, `--limit` caveats KA-CMD-07/08, MariaDB restore and `mariadb-recovery` KA-OPS-14), `openstack-change-review` (gates, point of no return), `openstack-automation-review` (what Kolla decides silently) |
| Inputs read | `architecture.md` §2 P2 and §4; `DR-003` (incl. Agent 4 response); `DR-004`; `validation/VAL-001-exp-db-01-strict-r2.yaml`; `07-red-team-stage3-review.md`; `07-red-team-stage5-results-review.md`; `lab/quick-lab-extension/ussuri-release-profile.patch` (head); my `03-*` Stage 1 files. |
| Code refs (DR-004 rule: released tags) | `kolla-ansible@22.2.0` (a3badc932, 2026-09-01; `stable/2026.1` head is 30 commits later, see §6); `kolla@22.2.0`; `kolla-ansible@ussuri-eol` for the Ussuri layout; `nova@33.0.2`, `keystone@29.1.0`, `glance@32.0.0` (latest 2026.1-series tags in the local clones). Kolla images build service code from `$tarballs_base/openstack/<svc>/<svc>-stable-2026.1.tar.gz` (`kolla@22.2.0:kolla/common/sources.py` line 241–244, `kolla/common/config.py` 381–384), i.e. branch content at build time, not these PyPI tags. |

## 0. Answer in short

- **Use `deploy`, not `upgrade`,** on new hosts. `upgrade` assumes running old containers (`mariadb` upgrade execs into a
  running `mariadb` container; Keystone's upgrade path never runs Fernet setup or `keystone-manage bootstrap`).
- `deploy` re-runs schema syncs on every service (idempotent only if the 2026.1 heads are already reached: VAL-001's
  second pass is the evidence for the commands it ran), **does not run `nova-status`**, and **does not run Nova or Cinder
  online data migrations** (only Placement's). Correction to Red Team V18 and to my Stage 1 text: the Nova bootstrap
  containers in `deploy` use `KOLLA_UPGRADE`, not `KOLLA_BOOTSTRAP`.
- `deploy` **does change data** on purpose: admin password/enable flag and Keystone endpoint URLs
  (`keystone-manage bootstrap`), service users' passwords (`update_keystone_service_user_passwords: true`),
  catalog endpoints, roles and implied roles, cell mappings (transport URL, database URL), DB users' passwords, Glance
  metadef namespaces (additions), Heat domain if missing.
- MariaDB: Kolla decides "existing cluster" **only** by whether the `mariadb` Docker volume already exists. Two adoption
  routes: logical restore into a freshly bootstrapped Galera (recommended), or physical datadir in a pre-created volume
  followed by `kolla-ansible mariadb-recovery`.
- Nova: two silent traps: (1) the default cell is found **by name** (`nova_cell_name: ''`); a mismatch makes Kolla run
  `create_cell`, which either silently does nothing or creates a **second cell mapping on the same database**;
  (2) the "compute registered" wait passes on the **old** forced-down Ussuri rows, so it proves nothing about the new
  compute.

## 1. What each role does against an existing database (`kolla_action=deploy`)

Common to every OpenStack role below: `mysql_db` (create if absent; no change if present) and `mysql_user` with
`password` + `append_privs: yes` (sets the password to `passwords.yml`'s value if different; adds privileges, removes
none), both skipped with `use_preconfigured_databases` (`kolla-ansible@22.2.0:ansible/roles/<svc>/tasks/bootstrap.yml`).
Then a one-shot bootstrap container, then `service-ks-register`.

| Role | Bootstrap command run by `deploy` (image side: `kolla@22.2.0:docker/<svc>/.../extend_start.sh`) | Idempotent on a 2026.1-head DB? | Data it changes | Aborts on a status check? |
|---|---|---|---|---|
| keystone | `KOLLA_BOOTSTRAP` → `keystone-manage db_sync` (no `--expand/--migrate/--contract`: all three) | Expected yes (head) | none by itself | no |
| keystone (Fernet) | `fernet_setup` **only when no `keystone_fernet` container runs on any keystone host** (`roles/keystone/tasks/bootstrap_service.yml`) | new keys on new hosts | all existing tokens invalid (acceptable) | fails if some hosts need Fernet bootstrap and `--limit` excludes others |
| keystone (bootstrap) | `kolla_keystone_bootstrap` → `keystone-manage bootstrap` per region (`roles/keystone/tasks/register.yml`; `kolla@22.2.0:docker/keystone/keystone/keystone_bootstrap.sh`) | yes, reports "changed" unless 9 "skipping" lines | **resets the admin password** if it does not authenticate with `keystone_admin_password`, **re-enables** a disabled admin, **updates** `keystone` public/internal endpoint URLs if different, ensures roles `reader`/`member`/`manager`/`admin`/`service` and implied roles, **deletes the admin→member implied role** (pre-2023.2 leftover), creates the region if absent (`keystone@29.1.0:keystone/cmd/bootstrap.py` lines 195–260, 319+). Admin-interface endpoints are not touched (no admin URL passed) | no |
| all services | `service-ks-register` (`roles/service-ks-register/tasks/main.yml`): `openstack.cloud.catalog_service`, `endpoint`, `project`, `identity_user` with `update_password: always` when `update_keystone_service_user_passwords` (default `true`, `group_vars/all/keystone.yml:19`), `identity_role`, `role_assignment` | yes | service users' passwords set to `passwords.yml`; endpoint URLs updated to the new values (module behaviour, collection version not checked); entries with `state: absent` deleted | no |
| glance | toggles `log_bin_trust_function_creators` 1→0; `KOLLA_BOOTSTRAP` → `glance-manage db_sync` + `db_load_metadefs` (legacy path, `glance_enable_rolling_upgrade: false`) | yes for schema; `db_load_metadefs` without `--merge` **skips existing namespaces** (`glance@32.0.0:glance/db/sqlalchemy/metadata.py` 299–301) | new metadef namespaces added | no |
| placement | `KOLLA_BOOTSTRAP` → `placement-manage db sync` + `db online_data_migrations` | expected yes | ODM only if anything left | no |
| nova (API) | `nova_api_bootstrap` with **`KOLLA_UPGRADE`** → `nova-manage api_db sync` + `db sync --local_cell` (cell0, from nova-api's `[database]`) (`roles/nova/tasks/bootstrap_service.yml`, `templates/nova.conf.j2` 93–101) | expected yes | none | **no `nova-status` in deploy** (`KOLLA_UPGRADE_CHECK` exists only in `roles/nova/tasks/upgrade.yml`) |
| nova (cell0) | `map_cell0` → prints "Cell0 is already setup", not changed; `list_cells`; **`update_cell --cell_uuid 0000… --database_connection <computed> --transport-url none:/`** if the stored cell0 DB URL string differs from the computed one (`roles/nova/tasks/map_cell0.yml`) | yes | cell0 mapping DB URL rewritten if address, port, user, password or `?ssl_ca` suffix differ | no |
| nova-cell (cell DB) | `nova_cell_bootstrap` with `KOLLA_UPGRADE` → `nova-manage db sync --local_cell` on the first conductor (`roles/nova-cell/tasks/bootstrap_service.yml`) | expected yes | none | no |
| nova-cell (`create_cells.yml`) | `list_cells --verbose` → filter `extract_cell(nova_cell_name)` (`kolla-ansible@22.2.0:kolla_ansible/nova_filters.py`) matches the **name** (empty name = default cell). Found and transport URL or DB URL differ → `update_cell --cell_uuid <uuid>` (uses the conductor's own `transport_url` and `[database]`). Not found → `create_cell` | update: yes | **cell mapping `transport_url`/`database_connection` rewritten** (expected when RabbitMQ hosts change). If not found by name: `create_cell` returns 2 "already exists" when either string matches an existing cell (tolerated by `failed_when`, nothing updated), else **creates a second mapping to the same database** (`nova@33.0.2:nova/cmd/manage.py` 1191–1214, 760–777) | later `discover_computes` fails "Unable to find settings for the default cell" in the first case |
| nova-cell (computes) | `wait_discover_computes.yml`: polls `openstack compute service list --service nova-compute` until every inventory compute's `ansible_facts.nodename` appears (disabled services included), then `discover_hosts --by-service --cell_uuid` | yes | host mappings only for unmapped hosts | **false positive**: old Ussuri rows with the same host already satisfy the wait |
| nova (online data migrations) | **not run in deploy**: plays "Run Nova API/cell online data migrations" are `kolla_action == 'upgrade'` only (`ansible/nova.yml` ~262–305) | — | — | — |
| neutron | `KOLLA_BOOTSTRAP` → `neutron-db-manage --subproject neutron upgrade head` + each `neutron_bootstrap_services` subproject; `neutron_plugin_agent_check.yml` also runs in deploy (ML2/OVS vs OVN containers/volumes on the host) | expected yes | none; agent rows are reused by host+type when agents start | plugin check only |
| cinder | `KOLLA_BOOTSTRAP` → `cinder-manage db sync` only; **no ODM, no `cinder-status`** anywhere in `kolla-ansible@22.2.0` (answers RT-N-19: Kolla never aborts on `cinder-status`) | expected yes | none | no |
| heat | `heat-manage db_sync`; creates `heat_user_domain` and its admin user only if missing | yes | none if present | no |
| horizon | `manage.py migrate --noinput` only when `horizon_backend_database` | yes | Django tables | no |
| mariadb | see §2.2 | — | `register.yml` creates `root_shard_<id>`, `mariadb_monitor_user` (ProxySQL) and backup users, logging in as `database_user` with `database_password` | fails on "existing but stopped" cluster, or not-Synced cluster |
| rabbitmq | `version-check.yml` gets container facts; on new hosts no `rabbitmq` container exists → **check skipped**; fresh cluster, definitions from templates | n/a | n/a (start empty) | no |

Idempotency evidence: VAL-001 (LAB-VALIDATED, narrow scope) shows that "a second 2026.1 pass changes nothing" for
the commands its harness ran. Commands Kolla adds that VAL-001 may not have exercised: plain `keystone-manage db_sync`,
`glance-manage db_load_metadefs`, `heat-manage db_sync`, Horizon `migrate`, Neutron sub-project heads,
`placement-manage db online_data_migrations` via bootstrap. Experiment C-1 below covers them.

## 2. `deploy` vs `upgrade` on new hosts, and preconditions

### 2.1 Why `deploy`

| Aspect | `upgrade` on fresh hosts | `deploy` on fresh hosts |
|---|---|---|
| MariaDB | `roles/mariadb/tasks/upgrade.yml` starts with `docker exec mariadb mariadb -uroot …` → fails, no container | bootstrap or adopt (§2.2) |
| Keystone | `upgrade.yml`: config, containers, expand/migrate/contract; **no Fernet setup, no `keystone-manage bootstrap`, no `service-ks-register`** → Keystone without Fernet keys | full bootstrap |
| Nova | `nova-status upgrade check` with the 2026.1 image, abort on rc ≥ 2; needs Placement and Cinder APIs (RT-N-05) | no status check; services' own start-up gate applies (DR-003 state d) |
| RabbitMQ | version check skipped (no container) | same |
| Online data migrations | Nova (API + cells), Cinder, Placement run | Placement only |

`upgrade` brings nothing `deploy` lacks here except ODM and `nova-status`; both are better run explicitly (§5) where
their result can be recorded. Classification of the whole procedure: **Technically possible but unsupported**.

### 2.2 Making Kolla adopt the migrated databases

Kolla's decision (`roles/mariadb/tasks/lookup_cluster.yml`): `create_volume mariadb`; if the volume already existed on
any shard host, `mariadb_cluster_exists = true`, no bootstrap; then with >1 node and no port alive → **fail "MariaDB
cluster exists but is stopped. Please start it using kolla-ansible mariadb-recovery"**; if alive, every node must be
`Synced`. Bootstrap (`bootstrap_cluster.yml`, `KOLLA_BOOTSTRAP` → `mariadb-install-db` + root grants from
`database_password`) runs only when no host had the volume.

| Route | How | Pros | Risks / preconditions |
|---|---|---|---|
| **M1 logical (recommended)** | (1) `deploy --tags` limited to the infrastructure plays (loadbalancer/ProxySQL, mariadb) so Kolla bootstraps an empty Galera; (2) restore per-service dumps (`keystone`, `glance`, `nova_api`, `nova`, `nova_cell0`, `neutron`, `cinder`, `placement`, `heat`, …), **never the `mysql` schema**, through the first node; (3) full `deploy` | Kolla owns users, grants, root and ProxySQL users; no UID or Galera-state issues; same engine (11.4) dump → 11.4 | Must happen **before** any service bootstrap, otherwise services create an empty schema first (restore would then need `DROP DATABASE`). Galera needs InnoDB and a primary key on every table (check before). Dump size/time. The exact tag set for step 1 is to be fixed in the lab. |
| M2 physical | Pre-create the `mariadb` volume on every MariaDB host; copy the 11.4 datadir (from the fast-forward host) into the first host's volume, `chown` to the Kolla image's `mysql` UID (Kolla image ≠ library image UID: to verify), others empty; run `kolla-ansible mariadb-recovery -e mariadb_recover_inventory_name=<first>`; then `deploy` | No dump/reload time | The datadir's `mysql.user` is the Ussuri one: `database_password` must be the Ussuri value (P4 of `03-configuration-transformation.md`); library-image vs Kolla-image minor version and config differences; grastate/seqno from a wsrep-off server. The analogous restore on 2026.1 is LAB-VALIDATED (KA-OPS-14) for a Kolla-made mariabackup only |

Other preconditions `deploy` itself checks or needs (`prechecks` must be run explicitly; `deploy` does not run them):
host OS in `host_os_distributions`; inventory groups (`loadbalancer` etc.); own registry (prechecks refuse quay.io
`openstack.kolla` without `--use-test-images`); the Ussuri computes **absent from the inventory** until reinstalled
(`--limit` still gathers facts from all hosts, KA-CMD-07, and `--limit` is "not recommended" by the 2026.1 operating
guide); Ussuri RPC/HTTP clients stopped (RT-B-02).

## 3. Interaction with the Nova gate (DR-003 state d) and compute re-adoption

- **Start-up.** With every Ussuri `nova-compute` row forced-down and no workaround flag, `deploy` starts API,
  scheduler, conductor; nothing in Kolla runs `nova-status` in `deploy`, so Kolla adds no abort. A start-up refusal
  (`TooOldComputeService`) is then the free verification Agent 4 described.
- **`[upgrade_levels] compute = auto`** is templated by Kolla (`roles/nova{,-cell}/templates/nova.conf.j2`); nothing to
  change; state (d) depends on it not being pinned in overrides.
- **Compute re-adoption.** Kolla sets no `host` for libvirt computes (`roles/nova-cell/templates/nova.conf.j2`: only
  ironic/fake set `host`), so `CONF.host` is the OS hostname: the reinstalled host **must keep the same short
  hostname** as in Ussuri (and the same `ansible_facts.nodename` for Kolla's wait). `state_path=/var/lib/nova` is the
  `nova_compute` volume (`nova_instance_datadir_volume`, `group_vars/all/nova.yml:15`). On first start
  `_ensure_existing_node_identity` sees service version 51 < `NODE_IDENTITY_VERSION` and **writes `compute_id` from the
  single `compute_nodes` row of that host**; it refuses if none or several rows exist (`nova@33.0.2:nova/compute/manager.py`
  1651–1697). Corollary: if a 2026.1 compute ever starts, bumps the row's version, and its volume is then lost, it
  refuses to start ("No local node identity found"). Keep the volume; never "retry from scratch" without restoring.
- **Placement** resource providers keep their UUID (= compute node UUID) and allocations, provided the node is adopted.
- **`nova_compute_virt_type`** must equal the Ussuri value (`kvm` default, `qemu` in nested labs); `nova_libvirt` is
  fresh (domain XML lost with the old `libvirtd`/`nova_libvirt_qemu` volumes unless preserved): instances come back by
  start/hard reboot, which regenerates the XML. Local instance disks survive only if the `nova_compute` volume (or
  `/var/lib/nova/instances`) is on preserved storage. The libvirt version check is skipped on a fresh host (no
  container).
- **Order per host (DR-003 condition 4):** deploy 2026.1 on the host → verify the service row shows version 72 and a
  fresh `updated_at` **and** `compute_id` exists (Kolla's own wait cannot show this) → clear forced-down through the
  2026.1 API → after the last host restart API/conductor/scheduler (`kolla-ansible deploy --tags nova` would only
  restart on config change; use a targeted container restart, recorded).

## 4. Other data-touching effects to expect

- Fernet keys new: all tokens invalid. Credential encryption: neither Ussuri nor 2026.1 Kolla configures a credential
  key repository (`git grep credential_setup` empty at both refs); Keystone then uses the **null key**
  (`keystone@29.1.0:keystone/common/fernet_utils.py` 30–33, `credential/providers/fernet/core.py` 74–76), so stored
  credentials should stay readable. Hypothesis, test K-06.
- Leftovers kept: Ussuri admin-interface endpoints, catalog entries and DB users of removed services, old agents of
  hosts not re-adopted.
- `kolla-ansible deploy` re-asserts every value from `passwords.yml`: a wrong value there **is applied** (DB users,
  service users, admin). The merged `passwords.yml` must be key-diffed against the Ussuri one before the first run.

## 5. Proposed sequence (all `PROPOSED-UNVERIFIED`)

1. Fast-forward done and gated per VAL-001 path; PC-V3 and PC-C1 pass; dumps of the 2026.1-head databases taken.
2. Ussuri clients fenced and stopped (RT-B-02); all Ussuri compute rows forced-down via the Ussuri API before the final
   backup (DR-003).
3. Configuration transformed (`03-configuration-transformation.md`), `nova_cell_name` equal to the stored default cell
   name (`''` for a Kolla-built Ussuri), `nova_compute_virt_type` unchanged, `passwords.yml` merged and key-diffed,
   inventory = new control hosts only, compute group empty.
4. `bootstrap-servers`, `pull`, `prechecks` on new hosts (read-only except host preparation).
5. M1: deploy only infrastructure (loadbalancer/ProxySQL, MariaDB) → restore service dumps → record checksums.
6. Read-only predictions: `nova-manage cell_v2 list_cells --verbose` vs computed URLs (predicts `update_cell`).
7. `kolla-ansible deploy` (control plane). Record every bootstrap container's output.
8. Post-deploy DB diff against step 5 snapshot: only the changes listed in §1/§4 allowed.
9. Explicit `nova-manage db online_data_migrations` (API and each cell), `cinder-manage db online_data_migrations`,
   `nova-status upgrade check` (expect 0, or 1 for `hw_machine_type`), `cinder-status`, `placement-status`; record.
10. Per compute: reinstall (same hostname, preserved instance storage), add to inventory, `bootstrap-servers`/`deploy
    --limit <host>` per the add-compute procedure, verify row version 72 + `compute_id`, clear forced-down, start
    instances. After the last host: restart nova control services, verify conductor logs a 6.x compute RPC version.

Point of no return: step 7's first write by a tenant API call to the new control plane (before it, rollback = Ussuri
restore per EXP-RB-01).

## 6. Experiments

Kolla lab (quick-lab Ussuri profile, `lab/quick-lab-extension/ussuri-release-profile.patch`):

| ID | What | Pass |
|---|---|---|
| K-01 | Ussuri Kolla AIO/multinode → baseline → offline fast-forward (VAL-001 path) → new 24.04 hosts, KA 22.2.0, route M1, steps 1–9 | `deploy` failed=0; DB diff before/after deploy = only §1/§4 items; `nova-status` 0; T0 inventory equal |
| K-02 | Route M2 (physical datadir + `mariadb-recovery`) | Galera Synced on all nodes; same DB checksums as K-01 step 5 |
| K-03 | Compute re-adoption with libvirt (nested): same hostname, preserved `nova_compute` volume; `compute_id` written; RP UUID unchanged; instance restarted from its disk | as stated; conductor logs 6.x after last host |
| K-04 | Negative: compute deployed but kept from registering → Kolla wait still passes | demonstrates the false positive |
| K-05 | Negative: cell name mismatch (`nova_cell_name` ≠ stored) with (a) one URL equal, (b) both different | (a) rc 2 tolerated then "Unable to find settings"; (b) second mapping created: recorded, then restored |
| K-06 | EC2 credential created on Ussuri readable after redeploy (null key) | `openstack ec2 credentials show` equals T0 |
| K-07 | Second `deploy` and a `reconfigure`: zero DB change | diff empty |
| K-08 | `upgrade` on fresh hosts (negative) | fails at the MariaDB exec task as predicted |

Testable now in the container lab (no Kolla images):

| ID | What |
|---|---|
| C-1 | Run Kolla's exact deploy-time commands (table §1, from 2026.1 PyPI code) against the VAL-001 final databases twice; schema/row diff (metadefs additions declared) |
| C-2 | `keystone-manage bootstrap` with the lab's admin password, then with a different one, then with changed endpoint URLs: record each change (password reset, endpoint update, implied-role deletion) |
| C-3 | Feed the lab's `nova-manage cell_v2 list_cells --verbose` output to `kolla_ansible.nova_filters.extract_cell` from `kolla-ansible@22.2.0` with `''` and `cell1`; the lab's default cell is named `cell1` (`lab/ussuri-db-lab/scripts/40-dbsync-services.sh`), unlike Kolla's `''`: predicts which branch Kolla would take |
| C-4 | `create_cell` rc 2 path and duplicate-mapping path on a copy |
| C-5 | DR-003 state (d) plus fake-compute adoption under the same hostname: `compute_id` written by `_ensure_existing_node_identity` (fake driver is not ironic, so the code path runs) |

## 7. Open questions / what I could not verify

1. The exact `--tags` set that bootstraps MariaDB (+ ProxySQL/HAProxy) without any service bootstrap in 22.2.0 (M1 step 1).
2. Kolla image `mysql` UID vs the library image used in VAL-001 (M2).
3. `openstack.cloud.endpoint`/`identity_user` behaviour in the collection version `install-deps` pins (`<3` for
   `ansible.posix` etc.; `openstack.cloud` version not checked).
4. The 30 commits on `stable/2026.1` after 22.2.0 include "mariadb: Increase healthcheck start_period to 120s" and
   "Fix container unhealthy checks"; a large restored database may need the former. Pin and record the KA version
   actually used.
5. Whether Kolla images' service code (branch tarball at build time) equals the PyPI tags read here (DR-004 rule; a
   Tier B run must use image digests).
6. ML2/OVN deployments: OVN NB/SB databases are not in MariaDB; a rebuild needs `neutron-ovn-db-sync-util` (not analysed).
