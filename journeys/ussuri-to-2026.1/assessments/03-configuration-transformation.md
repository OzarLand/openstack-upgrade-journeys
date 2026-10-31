# Kolla-Ansible configuration transformation strategy, Ussuri (10.x) to 2026.1 (22.x)

| Field | Value |
|---|---|
| Author | Agent 3, Kolla-Ansible Specialist (OzarLand multi-agent team, Stage 1) |
| Model | Claude Opus (claude-opus-5-5) |
| Date | 2026-10-31 |
| Status | Draft, Stage 1. Derived from source; no transformation was executed. Every row is DOCUMENTED-UNVERIFIED (from release notes or code) or PROPOSED-UNVERIFIED (my proposal). |
| Skills applied | `openstack-kolla-ansible-operations` (configuration.md: layout, precedence, overrides, `kolla-mergepwd`, secrets), `openstack-automation-review` (what a tool may decide), `openstack-change-review` |
| Inputs read | `kolla-ansible@<ref>:etc/kolla/globals.yml`, `etc/kolla/passwords.yml`, `ansible/inventory/multinode`, `ansible/group_vars/all*`, every release note added per series from Victoria to 2026.1 (upgrade, deprecations, prelude, critical sections), kolla release notes for the same series, `kolla_ansible/cmd/mergepwd.py`. Refs as in `03-kolla-ansible-assessment.md` section 1. |

Secrets rule (skill rule 11): this document names keys only. A transformation tool must never print, log or diff
secret values; it works on decrypted copies in a private temporary directory and re-encrypts (KA-CFG-03/04).

## 1. Principles

1. **Two ways to use the table.** (a) Standard path: apply the rows of each hop just before that hop, with that
   hop's Kolla-Ansible and sample files; the "Hop" column says when. (b) Rebuild path: apply all rows at once to
   produce a 2026.1 configuration from the Ussuri one. Same rows, different timing.
2. **Start from the target release's samples, carry the operator's intent.** For each hop, take the new
   `globals.yml`, inventory and `passwords.yml` samples from the installed Kolla-Ansible
   (`<venv>/share/kolla-ansible/etc_examples/kolla/` and `.../ansible/inventory/`) and re-apply the operator's
   values; do not edit the old files forward blindly (upstream operating guide; KA-CFG-04).
3. **Never decide what is a judgement.** A tool may rename, delete obsolete keys and flag; it must not choose a
   network backend, drop a service, change a storage layout or accept data loss (automation-review: execution vs
   judgement).
4. **Unknown variables are silent.** Ansible ignores variables nobody reads; a removed variable left in
   `globals.yml` produces no error and no effect. The tool must report every key in the operator's files that the
   target release does not read.
5. **Per-host values do not belong in `globals.yml`** (extra-vars precedence beats `host_vars`, KA-CFG-01): moving
   values such as `kolla_base_distro` per host (needed during Rocky 9/10 migrations) goes into inventory variables.
6. **Everything in git, one commit per hop**, reviewed with `diff -r` against the sample; the generated files are
   checked with `kolla-ansible genconfig` + `validate-config` (available from 2023.1) before a run.

## 2. Inventory transformations

| # | Change | Hop | Automatable | Evidence |
|---|---|---|---|---|
| I1 | Add groups `common`, `cron`, `fluentd`, `kolla-logs`, `kolla-toolbox` (children of `common`) | → Victoria | Yes | `kolla-ansible@victoria-eol:releasenotes/notes/separate-common-play-09a1aa1ac7d0797a.yaml`; `ansible/inventory/multinode` lines 48, 271–281 |
| I2 | `masakari-monitors` → `masakari-hostmonitor`, `masakari-instancemonitor` | → Wallaby | Yes | multinode at victoria-eol vs wallaby-eol |
| I3 | Add `hacluster`, `hacluster-remote` (only meaningful with Masakari host monitor) | → Wallaby | Yes (add from sample) | multinode at wallaby-eol; Zed `change-value-of-enable-hacluster` |
| I4 | **`haproxy` → `loadbalancer`** (precheck fails otherwise) | → Xena | Yes | `drop-group-haproxy-6119957627811873.yaml`; `prechecks/tasks/inventory_checks.yml` |
| I5 | Remove `chrony`, `chrony-server` | → Xena (after `chrony-cleanup` in Wallaby) | Yes, after the service decision C3 | `remove-chrony-role-90f164df8090f916.yaml` |
| I6 | `ironic-pxe` → `ironic-tftp`, `ironic-ipxe` → `ironic-http` | → Yoga | Yes | `ironic-rename-61f8b1d0cb34a36f.yaml` |
| I7 | `elasticsearch` → `opensearch`, `kibana` → `opensearch-dashboards`; remove `elasticsearch-curator` | → Zed | Yes (with C5) | `add-opensearch-53ef174195acce45.yaml` |
| I8 | Remove groups of dropped services (Monasca, Kafka, Storm, Zookeeper (Zed); Panko, Rally, Tempest (Xena); Karbor, Qinling, Searchlight (Wallaby); Congress, MongoDB, Hyper-V (Victoria); Skydive (2023.1); Freezer, Murano, Sahara, Senlin, Solum, Vitrage, `outward-rabbitmq`, `prometheus-haproxy-exporter` (2024.1); Swift (2025.1); Venus, `ironic-inspector` (2025.2); Zun, Kuryr, InfluxDB, Telegraf (2026.1)) | the hop that drops them | Removal of the group: yes. Removal of the **service**: no (C1) | release notes named in the assessment section 2 |
| I9 | Add `letsencrypt*` (2023.2), `skyline*` (2023.1), `valkey`, `nova-metadata` (2025.1), `ovn-sb-db-relay` (2025.1), `octavia-driver-agent`, `prometheus-libvirt-exporter`, `prometheus-openstack-network-exporter`, `prometheus-valkey-exporter` | hop that introduces them | Yes (copy from sample) | sample inventories |
| I10 | Add `neutron-rpc-server`, `neutron-periodic-worker`, `neutron-ovn-maintenance-worker`, `neutron-ovn-agent`, `neutron-ovn-vpn-agent` | → 2025.2 / 2026.1 | Yes | `neutron-uwsgi-5ac29b1403c02554.yaml` |
| I11 | Cinder: `cinder-volume`/`cinder-backup` default to group `cinder` (controllers) instead of `storage`; new `cinder-volume-lvm`, `cinder-volume-multiple`, `cinder-backup-lvm`, `cinder-backup-multiple` | → 2026.1 | **Partly**: mapping hosts that hold an LVM VG to `cinder-volume-lvm` needs the operator's layout | `move-cinder-volume-b4ee8e4378ea6828.yaml` |
| I12 | `kolla-toolbox` → `kolla_toolbox`, `kolla-logs` → `kolla_logs` (also in overrides and `--tags`) | → 2026.1 | Yes | `rename-kolla-toolbox-role-31e3b6c34519f68c.yaml`, `kolla-logs-rename-13892296d83a41f5.yaml` |
| I13 | Host OS reprovision: per-host `kolla_base_distro` / `kolla_base_distro_version` in `host_vars` during mixed-OS windows | Yoga (Rocky 9), 2025.1 (Rocky 10), 2024.1 (Ubuntu Noble with Jammy or Noble images) | Template yes, timing no | `kolla-ansible@yoga-eol:doc/source/user/rocky-linux-9.rst` |

## 3. `globals.yml` transformations

Default changes that alter behaviour are listed even when no key must change, because an operator who did not set
the key inherits the new default.

| # | Key / behaviour | Hop | Action | Automatable | Evidence |
|---|---|---|---|---|---|
| G1 | `openstack_release`, `openstack_tag`, `*_tag` pinned to a series | every hop | Remove or set to the hop's release; a pinned old tag makes `upgrade` redeploy old images | Yes (flag pinned per-service tags for review) | `operating-kolla.rst` "Version of deployed images" |
| G2 | `kolla_install_type` (Ussuri default `binary`) | Xena changes default to `source`; Yoga deprecates binary; **Zed removes binary** | Human decision on **when** to switch binary→source (Xena, Yoga or forced at Zed); then delete the key | Flag only | `default-type-source-3fefd8baa3ca46ba.yaml`, kolla `yoga-prelude`, `zed-prelude` |
| G3 | `docker_registry`, `docker_namespace` (Ussuri: Docker Hub `kolla`) | Xena default becomes quay.io / `openstack.kolla`; 2026.1 prechecks reject quay `openstack.kolla` without `--use-test-images` | Point both at the operator's registry for every hop; keep the namespace consistent with how images were mirrored | Yes once the registry exists | `switch-images-to-quay-d4640afca6862eee.yaml`, `prechecks/tasks/registry_checks.yml` |
| G4 | `docker_registry_insecure` (Ussuri default "yes if docker_registry else no") | Xena default `false` | Set explicitly; reaches Docker only via `bootstrap-servers` or a manual `daemon.json` change | Yes (value), No (applying it: Docker restart risk) | `bug-1940547-771f6affb3547748.yaml`; KA-CMD-14 |
| G5 | `kolla_base_distro` (default `centos` in Ussuri, `rocky` from Zed) | Zed | Set explicitly (`ubuntu`, `rocky`, `debian`) so the default change never applies by accident | Yes | group_vars |
| G6 | `enable_chrony` (Ussuri default yes) | Wallaby default no, prechecks fail if container runs; Xena removes | Decision C3, run `kolla-ansible chrony-cleanup` in Wallaby, host NTP | Flag | `deprecate-chrony-077a8686e79a919e.yaml` |
| G7 | `enable_host_ntp` | removed Xena | delete | Yes | `drop-enable_host_ntp` |
| G8 | `docker_disable_default_iptables_rules` / `docker_disable_default_network` | Wallaby default yes | Review host firewall assumptions; applied by `bootstrap-servers` | Flag | `disable-docker-iptables-bridge-493feb35cba4c405.yaml` |
| G9 | `octavia_auto_configure` | Victoria default yes | Ussuri Octavia users set `no` | Yes if Octavia enabled | `automatic-deploy-of-octavia-efe94f4db86d9106.yaml` |
| G10 | `haproxy_http_keep_alive_timeout`, `haproxy_service_template` | Victoria/Xena | Re-check if customised | Flag | `bug-1892622`, `haproxy-default-template-upgrade` |
| G11 | `kolla_internal_address` | deprecated Victoria | replace with `kolla_internal_vip_address` | Yes | `remove-kolla_internal_address-variable` |
| G12 | `prometheus_use_v1`, Prometheus v1→v2 (Wallaby), target names (Xena), v2→v3 (2025.1), basic auth (2023.2) | several | Decide whether old metrics are kept; dashboards/alerts rework | Flag | `add-prometheus-v2`, `prometheus-target-names`, `upgrade-prometheus-to-v3`, `expose-prometheus-on-external-api` |
| G13 | `enable_elasticsearch`, `enable_kibana`, `elasticsearch_curator_*` → `enable_opensearch*`, `opensearch_*` retention | Zed | Rename; backup ES data first (volume moved automatically) | Mostly | `add-opensearch`, `opensearch-log-retention` |
| G14 | `enable_monasca` and Monasca/Kafka/Storm/Zookeeper keys | Zed removes | Decision C1; `monasca_cleanup` existed in Zed, removed 2023.2 | Flag | `drop_monasca_kafka_storm_zookeeper`, `drop-monasca-final` |
| G15 | `storage_interface` → `swift_storage_interface` | removed Zed | rename (if Swift kept until 2025.1) | Yes | `remove-deprecated-storage_interface` |
| G16 | `keystone_token_provider`, `keystone_admin_port`, `keystone_admin_url`, `admin_protocol` | Zed | delete; check external users of port 35357 and of admin endpoints | Delete yes, consumers no | `drop-keystone-token-provider-variable`, `keystone-admin-port-gone` |
| G17 | `ironic_dnsmasq_dhcp_range` + `ironic_dnsmasq_default_gateway` → `ironic_dnsmasq_dhcp_ranges` list; `enable_ironic_ipxe` → `ironic_dnsmasq_serve_ipxe`; inspector variables renamed (2025.2) | Yoga–2025.2 | transform | Yes | `ironic-inspector-multiple-ranges`, `remove-deprecated-enable_ironic_ipxe`, `drop-ironic-inspector` |
| G18 | `om_enable_rabbitmq_high_availability` (Wallaby–2024.2) → quorum queues (`om_enable_rabbitmq_quorum_queues` default true from 2023.2; option removed 2025.1) | 2023.2–2025.1 | Run the documented durable/quorum queue procedure (genconfig, stop services, reconfigure rabbitmq, `rabbitmq-reset-state`, deploy) before the SLURP to 2024.1 and in any case before 2025.1 | **No**: procedure with a service outage | `kolla-ansible@origin/unmaintained/2024.1:doc/source/reference/message-queues/rabbitmq.rst`; `remove-om_enable_rabbitmq_high_availability` |
| G19 | `rabbitmq_image` override to `rabbitmq-3-12` (2023.1) before the SLURP to 2024.1; `rabbitmq_allowed_upgrades` | 2023.1, 2026.1 | Set temporarily, then remove | Yes, but run is a change | 2024.1 `rabbitmq.rst` "SLURP"/"RabbitMQ versions"; 2026.1 `rabbitmq.rst` "Upgrading RabbitMQ" |
| G20 | `enable_proxysql` (default yes from 2024.2; mandatory with MariaDB from 2025.2), `enable_mariadb_clustercheck` | 2024.2 / 2025.2 | Decide when to move to ProxySQL; new passwords `proxysql_admin_password`, `proxysql_stats_password`, `mariadb_monitor_password` | Flag | `switch-to-proxysql`, `drop-clustercheck-and-haproxy-support-for-mariadb` |
| G21 | `enable_redis` → `enable_valkey` (set `enable_redis: "no"`, `enable_valkey: "yes"` before the upgrade) | → 2025.2/2026.1 (`migrate-valkey` in 2025.1) | transform | Yes | `replace-redis-with-valkey` |
| G22 | `neutron_plugin_agent: linuxbridge` | experimental Zed, **removed 2025.1** | Migration to ML2/OVS or OVN | **No**: network architecture change | `linuxbridge-is-experimental-in-neutron`, `remove-neutron-linuxbridge` |
| G23 | `ceph_*_keyring` variables | changed 2023.2, removed 2025.1 (derived from `ceph_*_user`) | Align keyring file names with users | Partly | `multiple-ceph-backends`, `enhance-ceph-multiple-clusters-integration` |
| G24 | `distro_python_version` | default "3" 2024.2, removed 2026.1 | delete | Yes | `standarize-python-version-paths`, `remove-distro-python-version` |
| G25 | `lightbits_JWT` → `lightbits_jwt`; `neutron_legacy_iptables`, `bifrost_enable_ironic_inspector` removed | 2025.2/2026.1 | rename/delete | Yes | notes `lightbits-jwt`, `drop-legacy-iptables`, `drop-ironic-inspector` |
| G26 | `letsencrypt_cert_server` → `letsencrypt_external_cert_server` | 2025.1 | rename | Yes | `bug-2076331` |
| G27 | `kolla_container_engine` (new in Zed, `docker`) | Zed+ | Set `docker` explicitly | Yes | group_vars |
| G28 | Behaviour defaults without a key to change: `designate_enable_notifications_sink` no (2024.1); `enable_ironic_neutron_agent` no (2025.1); `nova_enable_external_metadata` off (Yoga); Nova legacy endpoint off (Zed); Keystone admin endpoint not created (Zed); `kolla_haproxy_ssl_settings` hardened (2024.2); `innodb_log_file_size` 2 GB (2025.1); Horizon on 8080 behind HAProxy (2025.2); `neutron_agents_wrappers` on (2025.2); `om_rabbitmq_qos_prefetch_count` 50 (2026.1); `ha_vrrp_health_check_interval` unset (2026.1); RabbitMQ message TTL 10 min and queue expiry 1 h (2023.1) | various | Review each; set old value explicitly only with a reason | Flag | notes named in the cell |
| G29 | Removed integrations in `globals.yml`: Hyper-V, XenAPI, MongoDB, `nova_msi_url` (Victoria), VMware drivers (2025.2), HNAS, `om_rpc_*` (qdrouterd, Zed) | various | Decision C1 | Flag | `remove-hyperv`, `remove-xenapi`, `drop-vmware-support`, kolla `drop-qdrouterd` |

## 4. `passwords.yml` transformations

Mechanics: `kolla-mergepwd --old <ussuri copy> --new <new sample after kolla-genpwd> --final <merged>` keeps every
existing value and adds new keys; `--clean` (2026.1, `kolla_ansible/cmd/mergepwd.py`) drops keys absent from the new
sample. `kolla-mergepwd` exists already in Ussuri (`setup.cfg` console_scripts). Run it at **every** hop
(PROPOSED-UNVERIFIED; KA-CFG-04 is DOCUMENTED-UNVERIFIED).

| # | Keys | Hop | Action |
|---|---|---|---|
| P1 | New keys between Ussuri and 2026.1 sample (observed by diffing the samples): `ceph_rgw_keystone_password`, `haproxy_ssh_key`, `keystone_federation_openid_crypto_password`, `mariadb_monitor_password`, `neutron_ssh_key`, `octavia_amp_ssh_key`, `octavia_client_ca_password`, `octavia_persistence_database_password`, `opensearch_dashboards_password`, `prometheus_bcrypt_salt`, `prometheus_grafana_password`, `prometheus_haproxy_password`, `prometheus_password`, `prometheus_skyline_password`, `proxysql_admin_password`, `proxysql_stats_password`, `skyline_database_password`, `skyline_keystone_password`, `skyline_secret_key`, `valkey_master_password` | as introduced | Generate with `kolla-genpwd` on the new sample, merge. Automatable |
| P2 | Keys dropped (present in Ussuri sample, absent in 2026.1): Congress, Freezer, `ironic_inspector_*`, Karbor, `kibana_password`, Kuryr, Monasca, Murano, `nsxv3_api_password`, `outward_rabbitmq_*`, Panko, `qdrouterd_password`, Qinling, Rally, Sahara, Searchlight, Senlin, Solum, Swift (`swift_hash_path_*`, `swift_keystone_password`), Vitrage, VMware, `xenserver_password`, Zun | after the service is gone | Keep until the service, its Keystone user and database are removed (C1); then `--clean`. **Never** drop `swift_hash_path_*` while Swift data exists |
| P3 | Rotated or re-meant keys: `prometheus_password` (basic auth, 2023.2); Keystone service user passwords now pushed to Keystone on reconfigure (`update_keystone_service_user_passwords`, Zed) | Zed+ | Verify no accidental change between files: a changed service password is applied to Keystone at the next run (KA-CFG-04, Zed note) |
| P4 | Values that must survive a rebuild path unchanged: `database_password`, every `*_database_password`, every `*_keystone_password`, `rabbitmq_password`/`rabbitmq_cluster_cookie` (cookie may change on an empty cluster), `memcache_secret_key`, `keystone_admin_password`, Octavia CA and keys, `metadata_secret`, Ceph keys | rebuild | Carry over; verify with a key-name diff only |

## 5. Custom configuration overrides in `/etc/kolla/config`

| # | Override | Hop | What changes | Automatable |
|---|---|---|---|---|
| O1 | `neutron/ml2_conf.ini` holding agent sections | Victoria | Agent options must move to `openvswitch_agent.ini` / `linuxbridge_agent.ini` (`remove-ml2-agents-config`) | Partly (section move is mechanical; review values) |
| O2 | `trove/trove-taskmanager.conf`, `trove-conductor.conf` | Wallaby | merge into `trove/trove.conf` | Yes |
| O3 | `fluentd/*` custom input/output/filter | Victoria (td-agent 4 syntax, kolla `td-agent-4`), Zed (OpenSearch output), 2025.2 (fluentd own role, `fluentd-direct`) | Re-write against the new templates | No (review) |
| O4 | `prometheus/*` (prometheus.yml, alert rules, cmd line extras) | Wallaby (v2 `--option` syntax), Xena (target names, cAdvisor metrics), 2024.1 (HAProxy native metrics), 2025.1 (v3) | Re-write; dashboards and alerts | No |
| O5 | `elasticsearch/*`, `kibana/*` | Zed | Port to `opensearch/*`, `opensearch-dashboards/*` | Partly |
| O6 | `haproxy/services.d/*`, custom `haproxy_single_service_listen.cfg.j2` | Xena (template deleted), 2024.2 (TLS hardening), 2025.2/2026.1 (Horizon 8080, glance/neutron TLS proxies gone, uWSGI) | Re-write | No |
| O7 | `horizon/custom_local_settings`, `local_settings` | 2024.1 | Rename to `_9999-custom-settings.py` / `_9998-kolla-settings.py`; `HORIZON_IMAGES_UPLOAD_MODE` default `direct` (2023.2) | Rename yes, content review |
| O8 | `nova/*.conf`, `neutron/*.conf`, `keystone/*.conf`, … INI overrides | every hop | Options removed or renamed upstream between Ussuri and 2026.1; detect with `kolla-ansible validate-config` (2023.1+) per hop, read only new lines (KA-CFG-02 notes pre-existing errors) | Detection yes, fix no |
| O9 | Policy files (`*/policy.json`, `policy.yaml`) | Wallaby onward (oslo.policy JSON deprecation, nova-status "Policy File JSON to YAML Migration"), 2023.x–2024.x (secure RBAC defaults, `enforce_scope`, `enforce_new_defaults`) | Convert JSON → YAML (`oslopolicy-convert-json-to-yaml`), then re-validate every rule against new defaults and personas | Conversion yes, rule decisions no |
| O10 | `ironic/*` (inspector, pxe/ipxe) | Yoga, 2025.2 | Paths moved under `/var/lib/ironic`; inspector removed | No |
| O11 | `galera.cnf` / MariaDB overrides | Xena (10.5), Yoga (10.6), 2023.2 (10.11), 2025.2 (11.4) | Remove options dropped by newer MariaDB; revisit `innodb_log_file_size` | Detection partly |
| O12 | `rabbitmq/*` (definitions, `rabbitmq.conf`, policies such as `ha-all`) | 2023.1 (definitions change → restarts), 2025.1 (no classic mirroring), RabbitMQ 4.x | Remove mirrored-queue policies; follow quorum procedure | No |
| O13 | `redis/*` | 2025.2 | Port to `valkey/*` | Partly |
| O14 | `cron` / logrotate template overrides | 2026.1 (`simplified-cron-templates`) | Re-apply on new templates | No |
| O15 | Global file `config/global.conf`, per-host directories `config/<svc>/<inventory_hostname>/` | rebuild path | Host directories must use **inventory names** (KA-CFG-01: a machine-hostname directory is ignored silently) | Yes (check) |

## 6. Decisions a tool must hand to a human

| # | Decision | Why it is a judgement |
|---|---|---|
| C1 | Fate of each dropped service (Monasca, Freezer, Murano, Sahara, Senlin, Solum, Vitrage, Swift, Zun, Kuryr, Karbor, Qinling, Searchlight, Panko, Congress, InfluxDB/Telegraf, Venus, ironic-inspector, VMware/Hyper-V/XenAPI drivers): migrate users and data elsewhere, export, or delete; Kolla-Ansible has no single-service removal command (OzarLand 2025.1→2026.1 notes) | Tenant data and API consumers |
| C2 | Linux Bridge → ML2/OVS or OVN, and when (must be done before 2025.1) | Data-plane architecture, outage |
| C3 | NTP: chrony container → host NTP (Wallaby) | Host configuration ownership |
| C4 | binary → source images (between Xena and Zed) | Changes every container's filesystem layout |
| C5 | Logging data: keep Elasticsearch indices (migrated to OpenSearch at Zed) or start empty | Retention/compliance |
| C6 | Metrics history: Prometheus v1→v2 and v2→v3 | Retention |
| C7 | Host OS reprovision vs in-place release upgrade, and order (Yoga vs Zed for Jammy; 2024.1 for Noble) | Outage and recovery plan |
| C8 | ProxySQL adoption timing; HAProxy/Horizon port changes seen by firewalls and monitoring | External consumers |
| C9 | RBAC/policy changes and custom policies | Who keeps which permission |
| C10 | Cinder volume service placement (`cinder-volume-lvm` vs controllers) | Where the data lives |

## 7. Shape of a transformation tool (PROPOSED-UNVERIFIED)

Reviewed against `openstack-automation-review`:

- **Input:** Ussuri `/etc/kolla` (decrypted copy in a private temp dir), inventory, target hop.
- **Output:** a proposed `/etc/kolla` and inventory for the hop, a **report** (renamed, deleted, flagged, unknown
  keys, decisions C1–C10 still open), never applied automatically; the operator commits it.
- **Safeguards:** dry run by default (report only); refuses to proceed while any C-decision for the hop is open;
  idempotent (re-running on its own output changes nothing); secrets never in logs or diffs (key names only);
  pinned data per hop taken from the Kolla-Ansible source at the eol tag of that series, not from moving branches
  (`unmaintained/*` branches have been deleted, assessment section 4.4).
- **Verification:** `kolla-ansible genconfig` + `validate-config` + `prechecks` with that hop's Kolla-Ansible
  (read-only or files-only), and a key-name diff of `passwords.yml` showing only additions.
- **Owner and limits:** owned by the platform team; a tool that only one person can explain is control debt.

## 8. Open questions / what I could not verify

1. The real Ussuri `globals.yml`, inventory and overrides (none available here); the table is the superset.
2. Option-level removals inside service config files (O8) were not enumerated; they belong to each service
   specialist and to `validate-config` runs per hop.
3. Where Kolla-Ansible stores Keystone credential keys per release (needed by the rebuild path).
4. Whether `kolla-genpwd` in old releases runs on the Python chosen for each hop's deploy-host venv.
5. Release notes were collected by file-name difference between consecutive branches; notes backported to older
   branches are attributed to the oldest branch that has them, so a few items may belong one series later than
   listed (e.g. OpenSearch appears in Yoga for Rocky only, default in Zed).
