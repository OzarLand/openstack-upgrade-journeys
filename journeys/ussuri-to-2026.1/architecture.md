# Migration architecture — Ussuri → 2026.1 (Stage 2 proposals)

| Metadata | |
|---|---|
| Author | Agent 1 — OpenStack Upgrade Architect (Opus) |
| Date | 2026-10-31 |
| Status | `PROPOSED-UNVERIFIED`. Stage 2 proposals; Red Team review (Stage 3) pending; no experiment run yet. |
| Inputs | `assessments/02-*` (compatibility), `03-*` (Kolla-Ansible), `04-*` (database and messaging), `06-*` (operations), `07-red-team-initial-assessment.md`, `compatibility-matrix.md`, `dependency-graph.md`, DR-001, DR-002 |
| Skills applied | `openstack-operational-decisions` (options, gates, trade-offs), `openstack-change-review` (points of no return, decision rights), `openstack-maintenance-planning` (compute waves), `openstack-kolla-ansible-operations` (Galera and Kolla mechanics) |

> [!WARNING]
> No part of this page is a supported or validated procedure. These are proposals that experiments must confirm or
> reject. The independent Red Team will challenge them before any experiment runs.

## 1. What the independent investigations established

All findings below come from reading upstream source and documentation, so they are `DOCUMENTED-UNVERIFIED`. The
architect re-checked items 2, 3 and 4 in the source.

| # | Finding | Classification | Source |
|---|---|---|---|
| 1 | Upstream's only supported route is U→V→W→X→Y→Z→2023.1→2024.1→2025.1→2026.1: 9 upgrades. Steps are N→N+1 before 2023.1, and SLURP steps after. | Officially supported (per hop) | 02, 03 |
| 2 | Nova, Keystone and Cinder 2023.2+ cannot read a legacy (sqlalchemy-migrate) database. Their code that moves a legacy database onto Alembic exists only in **Xena–2023.1 (Nova, Cinder)** and **Zed–2023.1 (Keystone)**. | Incompatible (direct jump) | 02, 04, 07, DR-002 |
| 3 | Some data migrations live in service code and are deleted later. Cinder 2024.1 `9ab1b092a404` makes `use_quota` NOT NULL and relies on the earlier release's online migrations having run. | Incompatible if skipped | 04, 07; architect-checked |
| 4 | Nova 2026.1 refuses to start if any compute service is older than Epoxy (`OLDEST_SUPPORTED_SERVICE_VERSION = 'Epoxy'`). Ussuri computes are version 51. | Incompatible (mixed versions) | 06, 07; architect-checked |
| 5 | Glance, Placement and Neutron still carry their full Alembic chains in 2026.1. Jumping them directly is technically possible but unsupported. | Possible, unsupported | 02, 04 |
| 6 | No Kolla-Ansible release supports both the Ussuri host OS (Ubuntu 18.04 / CentOS 8) and the 2026.1 host OS (Ubuntu 24.04 / Rocky 10). Every host changes OS at least once, or three times on the staircase. | Forced | 03, 06 |
| 7 | Kolla-Ansible 22.x `upgrade` against Ussuri breaks part-way. Python/Ansible, OS checks, MariaDB 10.3→11.4 and the RabbitMQ version check fail first. The Nova check fails only after other services were already migrated. | Incompatible | 03 |
| 8 | RabbitMQ holds no state worth preserving once every service is stopped and queues are drained. A fresh 2026.1 broker is acceptable. | Possible, unsupported as a "path" | 04 |
| 9 | Kolla Ussuri images are no longer anonymously pullable (HTTP 401 from Docker Hub, observed here). Rollback to Ussuri requires a private mirror made **before** the change. | Observed in this environment | DR-001, 03 |
| 10 | Policy (RBAC) defaults change: `enforce_scope` and `enforce_new_defaults` are on by default from oslo.policy 4.4 (2024.2). JSON policy files are unsupported in 2026.1. Keystone 2026.1 rejects `sha512_crypt` password hashes. | Behaviour change | 02 |
| 11 | Nova 2026.1 needs libvirt ≥ 8.0 and QEMU ≥ 6.2. Ussuri-created instances have no recorded machine type. | Workload risk | 06, 07 |

**Consequence.** The answer to the central question cannot be "one direct jump". Intermediate code must run,
because of findings 2 and 3. The question becomes whether that code can run **only against the databases**, offline,
instead of being deployed and operated. The proposals below differ in exactly that respect.

## 2. Proposals

### P1 — Supported staircase (reference)

Nine `kolla-ansible upgrade` runs, each preceded by `install-deps` and configuration changes and followed by online
data migrations:

- U → V → W → X → Y → Z → 2023.1, one release at a time;
- then 2023.1 → 2024.1 → 2025.1 → 2026.1 as SLURP hops.

The host OS moves 18.04 → 20.04 (Victoria), 20.04 → 22.04 (Yoga/Zed) and 22.04 → 24.04 (2024.1). There are two
RabbitMQ and quorum-queue preparations, and MariaDB moves stepwise with Kolla.

- **For:** every hop is supported upstream and tested in CI. Rollback is per hop.
- **Against:** 8 intermediate deployments, 9 maintenance campaigns and 3 OS changes per host. It needs every
  intermediate image (availability not established), and months of calendar time.

### P2 — Offline database fast-forward, then deploy 2026.1 once (Strategies B + D)

```mermaid
flowchart TB
    subgraph prep["Weeks before"]
      m["Mirror Ussuri images<br/>to a private registry"] --> b["Backups restored once<br/>on a scratch host"]
      b --> r["Rehearse the fast-forward<br/>on a copy of production DBs"]
    end
    subgraph w0["Window 1: control plane"]
      s0["Ussuri: finish online data<br/>migrations, pre-checks"] --> stop["Stop all API and<br/>control services"]
      stop --> bk["Final backup<br/>+ datadir copies"]
      bk --> ff["DB fast-forward on one node, wsrep off:<br/>2023.1 → 2024.1 → 2025.1 → 2026.1<br/>(db sync + online migrations per hop)"]
      ff --> chk["Checks per hop:<br/>versions, schema diff vs reference,<br/>row counts and fingerprints"]
      chk --> dep["Deploy 2026.1 control plane<br/>(Kolla-Ansible 22.x, new OS hosts)<br/>fresh RabbitMQ"]
    end
    subgraph waves["Compute waves"]
      cw["Per compute host: reinstall Ubuntu 24.04 or replace,<br/>deploy 2026.1 nova-compute and agents,<br/>bring its instances back (method depends on storage)"]
    end
    prep --> w0 --> waves
    ff -. "stop condition" .-> rb["Rollback: restore Ussuri DB,<br/>restart Ussuri control plane<br/>from mirrored images"]
```

Database code sequence (variant S2c of `assessments/04-database-migration-strategy.md`):

1. Ussuri, with the platform running: finish online data migrations.
2. 2023.1: the bridge for Nova, Keystone and Cinder, plus 2023.1 online data migrations.
3. 2024.1, then 2025.1, then 2026.1: SLURP hops, each with `db sync` and online data migrations.

MariaDB follows 10.3 → 10.6 → 10.11 → 11.4 on one node with wsrep off, and Galera is rebuilt afterwards.

Compute transition. While the control plane is migrated and redeployed, Ussuri computes and their instances keep
running, but they are unmanaged: no API operation can act on them. Every compute host then needs a new OS anyway
(finding 6). Per host, by storage type:

- **Shared storage (Ceph RBD, boot-from-volume):** move instances to a host already on 2026.1. Live migration is
  impossible across this gap (finding 4), so the candidate is an operator-controlled restart on another host. The
  exact Nova mechanism (evacuate from a fenced, forced-down Ussuri service, or rebuild of the compute record) is open
  and needs an experiment. Instance UUIDs, ports and volumes are preserved by design.
- **Local ephemeral disks:** either reinstall the host in place while preserving `/var/lib/nova/instances` and the
  hostname, then let 2026.1 nova-compute adopt the instances and hard-reboot them; or cold-copy the disks. Each
  instance is down for its host's reinstall.

The Nova service-version gate (finding 4) can be crossed in two ways, and this is an open decision for the Red Team:

- `[workarounds]disable_compute_service_check_for_ffu` until all computes report 2026.1;
- marking Ussuri compute services forced-down.

Agent 4 objects to forced-down because it changes real state; Agent 6 accepts fencing plus forced-down as part of an
evacuation flow. The disagreement is kept open and goes to the Red Team (see section 5).

- **For:**
  - Identity and every resource ID are preserved: same databases, same Keystone and Fernet keys.
  - Only one Kolla-Ansible deployment, plus one host OS change per host.
  - No intermediate service is ever operated.
  - The old control plane stays bootable until the point of no return.
- **Against:**
  - Unsupported upstream.
  - Nova object blobs are never re-saved by intermediate services (Agent 4, risk 1).
  - The control plane is offline for the whole window.
  - Compute waves need spare capacity or per-host downtime.
  - The PyPI-built migration code must be replaced in production by exactly the image digests that were rehearsed.

### P3 — Parallel 2026.1 cloud with API-level resource migration (Strategy C, fallback)

Deploy a clean 2026.1 cloud and recreate projects, users, networks, security groups, images, flavors and quotas
through the APIs. Move workloads by exporting disks or volumes and importing them. Preservable identifiers are image
IDs, MACs, fixed IPs and floating IPs. Instance, volume, network, port, project and user UUIDs change (Agent 6,
`06-workload-preservation-strategy.md`).

- **For:** no unsupported database operation at all. The old cloud is untouched until the last workload has moved.
- **Against:**
  - Identifiers change, which breaks tenants' automation, billing and integrations.
  - Downtime per instance equals copy time.
  - Full duplicate capacity is needed.
  - Users must re-authenticate unless a Keystone migration is added. That addition makes it P4.

### P4 — Hybrid: fast-forward the identity and image layers, rebuild the rest (Strategy D)

Fast-forward only Keystone (bridge 2023.1) and Glance (alembic, direct). Keystone IDs, credentials and images are
preserved. Neutron, Nova and Cinder resources are recreated in a parallel 2026.1 cloud as in P3. This avoids the
riskiest database (Nova object blobs) at the cost of changing compute, network and volume IDs. It also isolates
P2's biggest unknown.

## 3. Comparison matrix (before experiments)

| Criterion | P1 staircase | P2 DB fast-forward | P3 parallel cloud | P4 hybrid |
|---|---|---|---|---|
| Technical feasibility | Supported per hop | Unsupported. Hypothesis to test (EXP-DB-*) | Supported building blocks | Partly unsupported (Keystone bridge) |
| Data preservation | Full (by design) | Full **if** experiments prove it | Partial (IDs change) | Identity and images full, rest partial |
| Workload continuity | Rolling per hop. Host OS changes force instance moves 3 times | Instances keep running while unmanaged. One move or restart per instance | One cutover per instance (copy time) | As P3 |
| Downtime (control plane) | Short per hop, ×9 | One long window (hours, scales with DB size; measured in the experiments) | None for the old cloud | Keystone window only |
| Complexity | High (9 campaigns) | High, concentrated in one rehearsed window | High (tooling for resource recreation) | Highest (both kinds) |
| Automation | Kolla-Ansible per hop | Kolla-Ansible once + fast-forward scripts (new) | Custom migration tooling | Both |
| Recovery | Per hop: DB restore + previous images | Before the point of no return: restore + Ussuri images. After it: forward only | Old cloud untouched | Old cloud untouched for compute; Keystone restore |
| Operational risk | Fatigue, many windows, image availability for 8 releases | Concentrated, untested combination | Tenant-visible changes | Two systems at once |
| Supportability | Upstream-supported path | Unsupported; must be owned locally | Supported pieces | Mixed |

## 4. Experiments required before any recommendation

They run on the container lab of DR-001, always on copies of the preserved Ussuri baseline. Each one gets an
experiment record in `experiments/`.

| ID | Hypothesis | Pass criteria (aligned with the Red Team's pre-registered criteria) |
|---|---|---|
| EXP-DB-00 | The baseline is complete and restorable. | Restore into a fresh MariaDB gives identical row counts and dump checksum. |
| EXP-DB-01 (main, S2c) | U → 2023.1 → 2024.1 → 2025.1 → 2026.1 migrates every database with no manual edits. | Every command exits 0. Online migrations reach 0. Schema diff against a fresh reference = only declared differences. Row counts and fingerprints match except declared transformations. All `*-status upgrade check` with no FAILURE except the predicted Nova compute check. |
| EXP-DB-02 (reference, S2b) | The full DB staircase U→V→W→X→Y→Z→2023.1→…→2026.1 gives the **same** final data as EXP-DB-01. | Normalised final dumps of 01 and 02 are identical except declared differences. This is the differential test of "skipping is equivalent". |
| EXP-DB-03 (minimal, S2a) | U → 2023.1 → 2026.1 gives the same final data as EXP-DB-01. | As for 02. |
| EXP-DB-N1 (negative) | 2026.1 code refuses a Ussuri database for Nova, Keystone and Cinder. | The predicted error is recorded verbatim. The run is expected to be FAILED, which confirms finding 2. |
| EXP-DB-N2 (negative) | Skipping the Cinder online migrations at the bridge breaks or silently alters `use_quota` at 2024.1. | Observed behaviour under oslo.db's sql_mode is recorded. |
| EXP-SVC-01 | 2026.1 services start on the fast-forwarded databases and serve every pre-existing resource. | `show` of every server, port, volume, image, project and user equals the T0 inventory; zero 500 errors. A 2026.1 fake nova-compute can then take over a baseline host name, and `nova-status upgrade check` passes. |
| EXP-SVC-02 | Pre-existing resources stay operable after the migration. | Resize (fake), volume attach and detach, snapshot, a token for an old user, and a new port on an old network. |

Out of scope for this lab, and listed so that nobody claims them:

- Kolla-Ansible playbooks and configuration transformation;
- host OS upgrade;
- the data plane (QEMU, OVS);
- live behaviour of instances;
- Galera rebuild;
- the RabbitMQ engine upgrade.

These need the quick-lab Kolla Ussuri variant (DR-001, alternative 1).

## 5. Open decisions for the Red Team review (Stage 3)

1. Nova service-version gate: `disable_compute_service_check_for_ffu`, forced-down, or another mechanism?
2. Bridge release: 2023.1 (the SLURP start), or Zed? Both are inside all windows (DR-002).
3. Should the engine path be stepwise or dump/restore? This lab can test both on MariaDB library images; production
   behaviour under Galera cannot be tested here.
4. Is a container lab with upstream PyPI code and the fake virt driver enough to move P2's database claim to
   `LAB-VALIDATED`, given that Kolla images are not used?
5. P4 as a risk-reduction fallback: worth keeping?

## 6. Provisional position of the architect

None. The architect does not validate its own architecture (mission rule). The working hypothesis is that P2 is the
most promising way to avoid deploying intermediate releases, and that it stands or falls with EXP-DB-01, 02 and
EXP-SVC-01. P1 remains the reference and the only supported path.
