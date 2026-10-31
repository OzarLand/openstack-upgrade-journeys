# 04 — Messaging compatibility: RabbitMQ and Memcached (Ussuri → 2026.1)

| Metadata | |
|---|---|
| Author | Agent 4 — Database and Messaging Specialist (Stage 1, independent investigation) |
| Model | Opus (claude-opus-5-5) |
| Date | 2026-10-31 |
| Status | Source analysis only; all procedures `PROPOSED-UNVERIFIED` |
| Inputs read | `00-mission-brief.md`; `kolla@<series>:docker/rabbitmq/**`, `kolla@<series>:docker/base/apt_preferences.ubuntu`, `kolla@<series>:kolla/template/repos.yaml`; `kolla-ansible@<series>:ansible/roles/rabbitmq/**`, `ansible/group_vars/all*.yml`, `ansible/rabbitmq-*.yml`, `doc/source/reference/message-queues/rabbitmq.rst`, release notes; `requirements@<series>:upper-constraints.txt`; OzarLand `openstack-incident-analysis/references/control-plane-recovery.md` (IA-CP-05/06), `openstack-kolla-ansible-operations/references/host-and-database-operations.md` (KA-OPS-26), `kolla-ansible-deployment-patterns/version-notes/*2025.1*2026.1*`. |

## 1. Conclusion

- RabbitMQ in Kolla goes from **3.8 / Erlang 23 (Ussuri)** to **4.2 / Erlang 27 (2026.1)**. An in-place upgrade
  would have to step through at least 3.8 → 3.9 → 3.10 → 3.11 → 3.12 → 3.13 → 4.x. Kolla-Ansible 2026.1
  enforces "minor + 1" or an explicit `rabbitmq_allowed_upgrades` jump (only `3.13 → 4.0/4.1/4.2` and
  `4.0 → 4.1/4.2`). It refuses anything else in `rabbitmq-version-check`.
- OpenStack keeps **no durable business state** in RabbitMQ. In a full-stop upgrade the broker can be
  **replaced by a fresh 2026.1 RabbitMQ cluster**, which avoids the stepwise broker upgrade and the
  classic-mirrored → quorum/durable queue migration entirely. What is lost: in-flight RPC (none if every service is
  stopped and drained), undelivered notifications (which matters only for notification consumers), and broker
  definitions, which Kolla-Ansible re-creates from `passwords.yml`. Status: **Technically possible but
  unsupported** as an upgrade method. Rebuilding RabbitMQ from scratch is part of Kolla-Ansible's documented RabbitMQ password
  rotation ("stop all, rebuild RabbitMQ, deploy"; OzarLand KA-OPS-24/26, `DOCUMENTED-UNVERIFIED`). Not validated
  for this journey.
- Memcached is a cache. A fresh, empty Memcached is acceptable. Flush or replace it after the upgrade.

## 2. RabbitMQ and Erlang per Kolla series (from source)

| Series | RabbitMQ pin | Erlang pin | Evidence |
|---|---|---|---|
| Ussuri | 3.8.* | 23.* | `kolla@ussuri-eol:docker/rabbitmq/Dockerfile.j2` (rpm), `docker/base/apt_preferences.ubuntu` (`rabbitmq-server 3.8.*`, `erlang* 1:23.*`) |
| Victoria | 3.8.* | 23.* | same files at `victoria-eol` |
| Wallaby | 3.9.* | 25.* | `wallaby-eol` |
| Xena | 3.9.* | 25.* (rpm) | `xena-eol` |
| Yoga | 3.9.* | 25.2.* (rpm) | `yoga-eol` |
| Zed | 3.10.* | 25.* | `zed-eol` |
| 2023.1 | 3.11.* default; extra images `rabbitmq-3-12` (Erlang 26), `rabbitmq-3-13` (Erlang 26.2) | 25.* | `kolla@2023.1-eol:docker/rabbitmq/{rabbitmq,rabbitmq-3-12,rabbitmq-3-13}/apt_preferences_rabbitmq.ubuntu` |
| 2023.2 | 3.12.* | 26.* | `2023.2-eol` |
| 2024.1 | 3.13.* default; extra `rabbitmq-4-1` (Erlang 27) | 26.2.* | `origin/unmaintained/2024.1` |
| 2024.2 | 3.13.* default; extra `rabbitmq-4-1` | 26.2.* | `2024.2-eol` |
| 2025.1 | 4.0.* default; extra `rabbitmq-4-1` | 26.2.* / 27.* | `origin/stable/2025.1` |
| 2025.2 | 4.1.* | 27.* | `origin/stable/2025.2:docker/rabbitmq/Dockerfile.j2` |
| 2026.1 | 4.2.* | 27.* | `origin/stable/2026.1:docker/rabbitmq/Dockerfile.j2` |

The `*-eol` refs show each branch's **last** state. An image built earlier in a branch's life may carry a different
patch level. The exact versions in the running Ussuri images must be read on the platform
(`docker exec rabbitmq rabbitmqctl version`; `rabbitmqctl status` for Erlang).

OzarLand lab observation (not this mission's lab): a 2025.1 → 2026.1 Kolla-Ansible upgrade took RabbitMQ 4.0.9 →
4.2.9 (`kolla-ansible-deployment-patterns/version-notes/upgrade-report-2025.1-to-2026.1-all-in-one-lab.md`).

## 3. Kolla-Ansible handling, per series

| Topic | Evidence | Meaning for this journey |
|---|---|---|
| Ussuri upgrade = full stop of RabbitMQ | `kolla-ansible@ussuri-eol:ansible/roles/rabbitmq/tasks/upgrade.yml` ("full stop upgrade … necessary when moving between major releases") | The Ussuri tooling already assumes a broker outage on upgrade |
| Ussuri default policy `ha-all` (classic mirrored, pattern `.*`) | `kolla-ansible@ussuri-eol:ansible/roles/rabbitmq/templates/definitions.json.j2` | The existing broker holds classic mirrored queues; mirroring is removed in RabbitMQ 4.0 |
| `remove-ha-all-policy.yml` (Victoria →) | `kolla-ansible@victoria-eol:ansible/roles/rabbitmq/tasks/` | Removes the policy during upgrade |
| `om_enable_rabbitmq_high_availability` (Wallaby → 2024.2, removed by 2025.1) | `ansible/group_vars/all.yml` / `all/common.yml` per ref; note `remove-om_enable_rabbitmq_high_availability-*.yaml` | — |
| `om_enable_rabbitmq_quorum_queues`: `false` (2023.1), `true` (2023.2, 2024.1, 2024.2), variable gone in 2025.1+ (quorum is the only mode) | same files | Queue type change across the path |
| Stream fanout `om_enable_rabbitmq_stream_fanout: true` (2025.1 →) | `kolla-ansible@origin/stable/2026.1:ansible/group_vars/all/common.yml` | Fanout queues become streams |
| Durable queues default from Epoxy, "following procedure is required to be carried out before any upgrade to Epoxy": `genconfig`, stop services, (reconfigure rabbitmq), `kolla-ansible rabbitmq-reset-state`, `deploy` | `kolla-ansible@origin/stable/2026.1:doc/source/reference/message-queues/rabbitmq.rst` ("High Availability") | On a sequential path this is a mandatory broker reset anyway |
| `rabbitmq-version-check` (2023.1 →): allows same, minor+1, or `rabbitmq_allowed_upgrades` | `.../rabbitmq/tasks/version-check.yml`; defaults `3.13: [4.0, 4.1, 4.2]`, `4.0: [4.1, 4.2]` | 3.8 → 4.2 is refused; the check runs only `when: container_facts.containers[rabbitmq] is defined` |
| `enable_feature_flag all` on upgrade (2023.1 →) | `.../rabbitmq/tasks/feature-flags.yml`; note `rabbitmq-enable-all-feature-flags-at-once-*.yaml` | Feature flags are enabled after each step |
| `kolla-ansible rabbitmq-upgrade <version>` (`ansible/rabbitmq-upgrade.yml`, image `rabbitmq-<x-y>`, commit `03c7e8496`, 2024) | `kolla-ansible@{2023.1-eol … origin/stable/2026.1}:ansible/rabbitmq-upgrade.yml` | Supports intermediate broker images within one Kolla release |
| `rabbitmq-reset-state` = `stop_app`, `force_reset || reset`, `start_app`, `await_online_nodes` | `kolla-ansible@origin/stable/2026.1:ansible/roles/rabbitmq/tasks/reset-state.yml` (TODO: `force_reset` unsupported with Khepri) | OzarLand IA-CP-05: on a 2026.1 lab with Khepri this **failed** (`DOCUMENTED-UNVERIFIED`, one lab run) |
| `rabbitmq_password` / cookie rotation = stop all, `docker rm rabbitmq`, `docker volume rm rabbitmq`, `deploy` | OzarLand KA-OPS-26 (`DOCUMENTED-UNVERIFIED`) | Kolla's own practice already treats the broker volume as disposable |

oslo.messaging client side: Ussuri u-c `oslo.messaging===12.1.6`, `kombu===4.6.8`, `amqp===2.5.2`; 2026.1
`oslo.messaging===17.3.2`, `kombu===5.6.2`, `amqp===5.3.1` (`requirements@<ref>:upper-constraints.txt`). Old clients
never talk to the new broker in a full-stop upgrade, because all services are stopped. In a sequential path, every hop runs
matched client/broker versions.

## 4. Stepwise broker upgrade (if the broker were kept)

The constraints come from two sources, and only the first was checked here:

1. Kolla-Ansible's checks (verified in code, above): minor + 1, or 3.13 → 4.x, or 4.0 → 4.x.
2. RabbitMQ's own rules (from knowledge, **not verifiable here**: rabbitmq.com is not reachable from this environment).
   Upgrades go one minor series at a time, with all stable feature flags enabled before the next series. Some
   versions require feature flags introduced in 3.8/3.11 to be enabled before 3.11/3.12 will start. 4.0 removes
   classic queue mirroring and transient non-exclusive queues are deprecated. 4.2 makes Khepri the metadata store
   (OzarLand labs observed "RabbitMQ 4.2.9 with Khepri"). Each step also needs a matching Erlang (23 → 25 → 26 → 27).

So an in-place broker path from Ussuri needs at least seven broker versions (3.8, 3.9, 3.10, 3.11, 3.12, 3.13, 4.x),
several Erlang changes, and a queue-type migration. On a sequential deployment path these come "for free" with each
Kolla release. In a database fast-forward there is no running intermediate Kolla release to provide them.

## 5. Does RabbitMQ hold data that must survive?

| State in the broker | Owner | Survives a fresh broker? | Assessment |
|---|---|---|---|
| vhost `/`, users, permissions, policies | Kolla-Ansible `definitions.json` from `passwords.yml` | Re-created by `deploy` | Nothing to preserve. Export definitions only for audit (`rabbitmqctl export_definitions`) |
| RPC queues/exchanges (`compute.*`, `conductor`, `scheduler`, `q-*`, reply queues, fanouts) | oslo.messaging, re-declared at service start | Re-declared by 2026.1 services as quorum/stream | Nothing to preserve |
| In-flight RPC messages | services | Lost | Acceptable **only if** every service is stopped first and no long operation (live migration, resize, volume attach/migrate, image upload) is in flight. Stopping mid-operation leaves instances/volumes in transitional states, and that is a DB-level clean-up problem |
| Notification queues (`notifications.*`, `versioned_notifications.*`) | consumers: Ceilometer, Designate sink, Searchlight, external billing/CMDB | Lost | **Decide per consumer.** Drain or accept the loss; record queue depths before stopping |
| Murano `outward_rabbitmq` (Ussuri option) | Murano agents | separate broker | Check whether it is enabled; Murano is outside this assessment |
| Erlang cookie, cluster membership, Mnesia/Khepri | broker | Fresh cluster forms with the new cookie | No OpenStack data |

**Argument.** For a full-stop upgrade, preserving the RabbitMQ data directory gives no OpenStack data-integrity
benefit. It forces the stepwise broker path, the mirrored → quorum/durable/stream migration and a
`rabbitmq-reset-state` that a 2026.1 lab reported failing with Khepri (IA-CP-05). A fresh broker is the safer
choice, provided that:

1. every OpenStack service (including `nova_compute`, Neutron agents, `cinder_volume`/`backup`) is stopped first,
   after the queues have drained. Read-only check: `rabbitmqctl list_queues name messages consumers` shows
   `messages = 0` on RPC queues;
2. notification consumers have drained their queues, or their owners accept the loss in writing;
3. the old RabbitMQ volume is kept (stopped, renamed, not deleted) until the new platform is accepted. It is
   useless for rollback to 2026.1 but necessary for rollback to Ussuri, together with the Ussuri images;
4. after the fresh deploy, quorum-queue/stream membership is checked on all nodes
   (`rabbitmqctl list_queues name type members`). OzarLand found rejoined nodes missing from replicas (IA-CP-05, KA-OPS-10).

## 6. Proposed broker procedure for a full-stop journey (`PROPOSED-UNVERIFIED`)

1. *Read-only*: `rabbitmqctl cluster_status`, `list_queues name messages consumers`, `export_definitions <file>`
   (the file contains password hashes; keep it in the secured backup set).
2. *State-changing*: stop all OpenStack services (Kolla-Ansible: `kolla-ansible stop --yes-i-really-really-mean-it`
   with the tags agreed in the runbook); confirm queues stop changing.
3. *State-changing*: stop RabbitMQ on all nodes; rename/keep the `rabbitmq` volume (do not delete).
4. *State-changing*: deploy 2026.1 RabbitMQ on empty volumes (Kolla-Ansible 2026.1 `deploy`/`upgrade` with no
   existing container: `version-check.yml` is skipped when the container does not exist). Remove any leftover
   `ha-all` policy (fresh definitions do not contain it).
5. *Read-only*: `rabbitmq-diagnostics check_running`, `cluster_status`, `list_feature_flags`, after services start
   `list_queues name type members consumers`.
6. *State-changing*: flush Memcached (section 7).

Undo: before step 4, restart the old containers on the kept volumes. After the services have started on 2026.1, the
undo is the full Ussuri rollback (`04-recovery-consistency-requirements.md`).

## 7. Memcached

- Kolla installs the distribution `memcached` package unpinned in both Ussuri and 2026.1
  (`kolla@{ussuri-eol,origin/stable/2026.1}:docker/memcached/Dockerfile.j2`). There is no volume, so the state lives in RAM only.
- Contents: Keystone token-validation and oslo.cache entries, Horizon sessions (if configured), Nova/Neutron
  oslo.cache entries. Fernet keys are **not** in Memcached (Kolla volume `keystone_fernet_tokens`,
  `kolla-ansible@ussuri-eol:ansible/roles/keystone/defaults/main.yml`).
- A fresh Memcached loses only cache entries. Users of Horizon log in again. Entries written by Ussuri-era code must
  not be read by 2026.1 code, so start 2026.1 with an empty cache (restart or `flush_all`; OzarLand KA-OPS-26 does
  the same after a broker rebuild). Status: **Technically possible**; Not validated.

## 8. Classification

| Claim | Status |
|---|---|
| Kolla-Ansible stepwise broker upgrade within allowed paths, one Kolla release at a time | **Officially supported** |
| Broker 3.8 → 4.2 in one step keeping data | **Incompatible** (Kolla-Ansible check refuses; RabbitMQ rules, unverified here, require steps) |
| Fresh 2026.1 broker in a full-stop upgrade, old volume kept for rollback | **Technically possible but unsupported** as an upgrade method; Not validated |
| `rabbitmq-reset-state` on 4.2 + Khepri | Reported **failed** on an OzarLand lab (`DOCUMENTED-UNVERIFIED`) |
| Fresh Memcached | **Technically possible**; Not validated |

## 9. Open questions / what I could not verify

- RabbitMQ upstream upgrade and feature-flag rules: rabbitmq.com not reachable. They need checking from the official
  docs or by experiment (Docker Hub `rabbitmq:<ver>` library images).
- Whether a fresh 4.2 cluster deployed by Kolla-Ansible 2026.1 uses Khepri by default: unknown here; OzarLand labs
  report Khepri on 4.2.9.
- Which notification consumers exist in the real deployment and whether their queues can be drained.
- Docker Hub anonymous pull **rate limit** was hit during this investigation (`toomanyrequests` on manifest checks).
  The lab must budget its pulls or use authenticated pulls.
