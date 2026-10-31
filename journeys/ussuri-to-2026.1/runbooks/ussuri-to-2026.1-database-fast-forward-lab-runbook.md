# Runbook (lab): offline database fast-forward Ussuri → 2026.1, then one 2026.1 deployment (proposal P2)

> [!CAUTION]
> **Technically possible but unsupported. Lab-verified only, on a container lab with synthetic data. Not for production use.**
> Upstream OpenStack and Kolla-Ansible neither document nor test an upgrade from Ussuri to 2026.1 without the
> intermediate releases. Every step below carries its own status. The steps marked `LAB-VALIDATED` were run once, by
> an AI lab agent, on a single-host Docker lab with about 4,100 rows of synthetic data, PyPI code instead of Kolla
> images, a standalone MariaDB instead of Galera, fake hypervisors and no data plane. The steps marked
> `PROPOSED-UNVERIFIED` or `DOCUMENTED-UNVERIFIED` have **never been run anywhere**. Nothing here is
> `PRODUCTION-VALIDATED`. Do not run this on a platform whose data you cannot afford to lose.

| Metadata | |
|---|---|
| Status of this page | **Draft — not yet validated.** Page status = weakest step = `PROPOSED-UNVERIFIED` ([rules](../../../docs/validation-status.md)). Outside this repository: *lab-verified* steps exist; the runbook as a whole is **not** lab-verified |
| Author | Agent 8b — Documentation and Community Engineer (Fable 5.1), 2026-10-31, from the records listed under "Author notes". Written with the skill `openstack-runbook-authoring` |
| Owner | OzarLand owner (accountable); the architect (Agent 1) owns the plan |
| Last validation | none (no non-author has executed this page) |
| Review by | before any Tier B rehearsal |
| Evidence class of the procedure | Technically possible but unsupported (S2c with the Cinder-only 2023.2 step of [DR-004](../decision-records/DR-004-cinder-2023.2-step.md)) |
| Executable by | Platform team with OpenStack database and Kolla-Ansible expertise, in a lab. Every destructive step needs the approver named on it |
| Templates | [`docs/templates/runbook-step.md`](../../../docs/templates/runbook-step.md); OzarLand runbook template |

Status tags: `[LAB-VALIDATED: VAL-001]` means the step was executed in the lab and matched its expected result, with the
record cited. `[LAB-VALIDATED: EXP-…]` cites an experiment record whose validation id the architect has not assigned
yet. `[DOCUMENTED-UNVERIFIED: source]` means read in upstream code or documentation, never run. `[PROPOSED-UNVERIFIED]`
means an idea written here, never run. **Execution mode:** `Automated` (a script runs it), `Manual` (an operator runs
it), `Approval point` (stop; the named role approves before continuing).

---

## 1. Purpose and scope

**Purpose.** Bring the databases of a Kolla-Ansible Ussuri control plane to the 2026.1 schema and data state offline,
by running the migration code of 2023.1, Cinder 2023.2, 2024.1, 2025.1 and 2026.1 **without deploying or operating any
intermediate release**, then deploy a 2026.1 control plane once on the result and re-adopt the compute hosts.

**Covers:** the P2 sequence of [`architecture.md`](../architecture.md) §2: pre-checks, fencing, backups, the hops
H1 → H1b → H2 → H3 → H4 (+ H4r), the MariaDB engine line, the 2026.1 deployment with the mandatory KD-M1..KD-M10 steps,
the Nova gate (DR-003 state d), per-host re-adoption, post-upgrade validation, recovery and stop conditions.

**Does NOT cover:**

- the supported staircase (P1), a parallel cloud (P3) or the hybrid (P4);
- any service other than Keystone, Glance, Placement, Nova, Neutron (core, no sub-projects) and Cinder: Heat, Octavia,
  Barbican, Designate, Magnum, Ironic, Manila, Masakari and Neutron sub-projects are outside every table of this
  journey (Red Team RT-N-13). A platform with any of them stops at §4 step 0.4;
- ML2/OVN (OVN NB/SB databases are not in MariaDB), data-plane operations, live migration;
- rollback after the point of no return (§10): there is none; it is a recovery project.

## 2. Context (why it is built this way)

- A direct jump is **incompatible**: 2026.1 Nova, Keystone and Cinder have no path for a pre-Alembic database; they
  attempt the initial schema, fail on `Table already exists` and leave an empty `alembic_version` table behind
  ([EXP-DB-N1](../experiments/EXP-DB-N1-direct-2026.1.md), `FAILED` as predicted; pre-check PC-V3).
- 2023.1 is the common **bridge** for Nova (Xena–2023.1), Cinder (Xena–2023.1) and Keystone (Zed–2023.1)
  ([DR-002](../decision-records/DR-002-keystone-bridge-window-disagreement.md)).
- Released cinder 22.3.0 (2023.1) leaves soft-deleted volumes and snapshots with `use_quota` NULL; 2024.1's
  `9ab1b092a404` then fails, **on the supported path too**. Hence the Cinder-only 23.5.0 step H1b and the hard gate
  PC-C1 ([DR-004](../decision-records/DR-004-cinder-2023.2-step.md),
  [troubleshooting](../troubleshooting/cinder-use-quota-null-blocks-2024.1-db-sync.md)).
- Nova 2026.1 accepts no compute older than Epoxy, and the compute RPC cap is a second gate. Forced-down rows are
  excluded from both queries; with every Ussuri `nova-compute` row forced-down the control plane starts **without** the
  workaround flag ([DR-003](../decision-records/DR-003-nova-service-version-gate.md), state (d),
  [EXP-SVC-01](../experiments/EXP-SVC-01-2026.1-services-on-h4r.md)).
- The 2026.1 API **cannot** modify an Ussuri service row (`PUT /os-services/<id>` → HTTP 500 `ServiceTooOld`, both
  directions). Forced-down must therefore be set through the **Ussuri** API before the pre-bridge backup (PC-N5).
- Kolla-Ansible `deploy` changes data on purpose (admin password, endpoints, roles, cell mappings) and takes the
  `create_cell` branch when the cell name does not match ([EXP-KD-01](../experiments/EXP-KD-01-kolla-deploy-time-on-h4r.md),
  Red Team Stage 5c KD-M1..M5).
- 2026.1 Cinder refuses Nova's attachment deletes unless Nova's service token carries the role `service`, which no
  Ussuri Keystone contains; Kolla creates it at deploy time ([EXP-SVC-02](../experiments/EXP-SVC-02-operations-on-old-resources.md),
  Red Team Stage 5d KD-M6..M10).

## 3. Preconditions and dependencies

| Precondition | Status | Why / evidence |
|---|---|---|
| **Private image mirror** holding every Ussuri image the platform runs, by digest, plus the 2026.1 Kolla images pinned by digest, and the frozen deploy-host toolchains for both | `[PROPOSED-UNVERIFIED]` | Ussuri Kolla tags were observed not anonymously pullable (HTTP 401) in this mission; rollback cannot redeploy without a mirror (gate G2 of [06-recovery](../assessments/06-recovery-and-rollback-plan.md)) |
| **Backups restored once** on a scratch host by a person other than the author, compared and timed: all service databases, `/etc/kolla`, `passwords.yml`, Fernet and credential keys, certificates | `[PROPOSED-UNVERIFIED]` for a Kolla/Galera platform; `[LAB-VALIDATED: EXP-DB-00]` for the lab's logical and physical restore (571 tables identical, dump sha256 equal) | Gate G1. The lab result says nothing about Mariabackup, Galera or production size |
| **Tier B rehearsal**: the whole sequence run on a sanitised copy of the production databases with the Kolla images by digest and a Galera rebuild | **Not done.** `[PROPOSED-UNVERIFIED]` | VAL-001 `missing_evidence_for_next_level`. Without it, no production decision is possible |
| Host OS for the new control plane supported by Kolla-Ansible 22.x (new hosts) | `[DOCUMENTED-UNVERIFIED: kolla-ansible@22.2.0 prechecks]` | No Kolla release supports both the Ussuri and the 2026.1 host OS |
| Every enabled service is in the scope of §1 | `[PROPOSED-UNVERIFIED]` | RT-N-13 |
| Auto-evacuation (Masakari, custom automation) disabled for the window | `[PROPOSED-UNVERIFIED]` | DR-003 condition 3 |
| Decision rights: a named approver and a named person who can stop, both reachable | `[PROPOSED-UNVERIFIED]` | Gate G8 |
| Evidence to preserve before starting: `services` table rows, `openstack` inventory snapshot, `virsh` dumps per host, schema dump, pre-check outputs | `[LAB-VALIDATED: EXP-DB-00]` for the lab's capture (`nova-services-table.tsv`, `schema-versions.tsv`, inventory) | Needed by every comparison and by rollback |

## 4. Procedure

Each table row is one step. "Expected output" quotes only what was observed in the lab; when nothing was observed it
says so.

### Phase 0 — Scope and inventory (read-only)

| # | Step | Mode | Status | Expected output | Success criterion | If different / stop |
|---|---|---|---|---|---|---|
| 0.1 | Read the banner and §1. Confirm the platform is Kolla-Ansible Ussuri with the six services only | Manual | `[PROPOSED-UNVERIFIED]` | not observed (desk step) | Service list ⊆ {keystone, glance, placement, nova, neutron core, cinder}; ML2/OVS | **STOP**: any other service or OVN → out of scope |
| 0.2 | Record versions: Kolla-Ansible, image digests, MariaDB version, `migrate_version`/`alembic_version` rows, Keystone version row (078 or 079, RT-N-04) | Manual | `[LAB-VALIDATED: EXP-DB-00]` (lab values: keystone 17.0.1, nova 21.2.4, neutron 16.4.2, cinder 16.4.2, glance 20.2.0, placement 3.0.1, MariaDB 10.3.39) | `evidence/EXP-DB-00/schema-versions.tsv` | Every value recorded, none `unknown` | Any `unknown` stays `unknown`; escalate |
| 0.3 | Inventory of compute hosts: hostname, storage type (shared / local disk), instance count at libvirt vs Nova | Manual | `[PROPOSED-UNVERIFIED]` | not observed | libvirt count = Nova count per host | Mismatch → reconcile before any change |
| 0.4 | **Approval point:** owner accepts an unsupported procedure, the lab-only evidence and the downtime class | Approval point (Platform owner + Change authority) | `[PROPOSED-UNVERIFIED]` | written acceptance | Recorded | No acceptance → do not continue |

### Phase 1 — Pre-checks on the Ussuri databases (read-only, before the window)

Source: [`fast-forward-checks.md`](../experiments/fast-forward-checks.md) §1 and §4. Every failed check is a named stop
condition `SC-PC-<id>`; the fix is a separate reviewed change on Ussuri through supported tooling, **never SQL** (SC-HAND).
The lab ran these through `ff/12-prechecks.sh`; in VAL-001 all 37 passed on baseline v4.

| # | Step | Mode | Status | Expected output | Success criterion | If different / stop |
|---|---|---|---|---|---|---|
| 1.1 | PC-V1 legacy versions inside the bridge window; PC-V2 Alembic heads of glance/placement/neutron | Automated | `[LAB-VALIDATED: VAL-001]` | `strict-r2/prechecks.txt`: all PC-* pass | nova ≥ 401, nova_api ≥ 66, keystone ≥ 72, cinder ≥ 134 | STOP SC-PC-V1/V2 |
| 1.2 | **PC-V3** no `alembic_version` table in nova, nova_cell0, nova_api, keystone, cinder | Automated | `[LAB-VALIDATED: VAL-001]`; the failure it detects: `[FAILED: EXP-DB-N1]` | empty | empty | **STOP before the bridge**: newer code already touched the DB; restore from the last backup before the touch |
| 1.3 | PC-O1 Ussuri online data migrations complete (nova per cell incl. cell0, placement, cinder), run with **Ussuri** tools | Automated | `[LAB-VALIDATED: VAL-001]` (`pc-o1/`) | exit 0 each | exit 0 | STOP; finish them on Ussuri |
| 1.4 | PC-G1 Glance `db check` (a) and `image_locations` backend query (b); PC-G2 no leftover triggers | Automated | `[LAB-VALIDATED: VAL-001]` for (a) and (b) on the lab dataset | (a) exit 0, (b) 0 | both | **STOP SC-GLANCE**; no SQL fix |
| 1.5 | PC-N1 no in-flight Nova work; PC-N2 cell mappings readable; PC-N3 no build requests; PC-N4 `compute_id` residue predicted | Automated | `[LAB-VALIDATED: VAL-001]` | PC-N4 lab: 1 instance host NULL in cell1, 3 in cell0 (residue N-R1) | N1 = 0, N3 = 0; N4 recorded | STOP on N1/N3 |
| 1.6 | **PC-N5** every `nova-compute` row of a fenced host has `forced_down=1` before the final pre-bridge backup (checked again at 3.3) | Manual | `[PROPOSED-UNVERIFIED]` as a named check (RT-N-27, not yet in `fast-forward-checks.md`); the row state itself `[LAB-VALIDATED: EXP-DB-00]` | lab: 3 rows `forced_down=1`, version 51 (`nova-services-table.tsv`) | all fenced hosts `forced_down=1` | **STOP**: no 2026.1 repair path exists (EXP-SVC-01 finding 1) |
| 1.7 | PC-C1p prediction (deleted volumes/snapshots that H1 will leave NULL); PC-C2 Cinder transitional states; PC-C3 declared-transformation predictions; **PC-C4** no non-deleted volume without `service_uuid` | Automated | `[LAB-VALIDATED: VAL-001]`; PC-C4 failure observed on baseline v1 (`cinder-status` "Service UUIDs" FAILURE, EXP-DB-01 R1c C9) | lab v4: C1p 3 volumes, 2 snapshots; C4 empty | C2 no transitional state; C4 empty | STOP; remedy through the Ussuri API with the volume owner (delete never-scheduled `error` volumes), or an owner-recorded acceptance |
| 1.8 | PC-K1 no duplicate trusts; PC-K2 hashers recorded | Automated | `[LAB-VALIDATED: VAL-001]` | lab: only bcrypt | K1 empty | STOP on K1 |
| 1.9 | PC-Q1..Q6 Neutron duplicates and legacy tables (Q5 duplicate segments, Q6 HA networks with **our own** query) | Automated | `[LAB-VALIDATED: VAL-001]`; the Q5 failure observed on baseline v1 (`[FAILED]` EXP-DB-01 R1, SC-PC-Q5) | lab v4: all empty / 0 | all empty / 0 | STOP; remedy through the API (re-model the network), escalate to the architect if not remediable; blocking for **every** path |
| 1.10 | PC-E1 `@@GLOBAL.sql_mode` recorded; PC-E2 table sizes recorded | Automated | `[LAB-VALIDATED: VAL-001]` | strict mode | recorded | — |
| 1.11 | **KD-M7** no pre-existing role named `service` or `manager` with another meaning in the Ussuri Keystone | Manual | `[PROPOSED-UNVERIFIED]` (Red Team Stage 5d) | lab roles before bootstrap: `admin reader member` (`roles-before.txt`) | `openstack role list` shows neither name | Rename or decide before the window: bootstrap would adopt it and its assignments would become service-token roles |
| 1.12 | Config parity CP-* of the one-shot containers: production rendered `<svc>.conf` + override limited to connection keys and an unreachable `transport_url`; dump the effective CP values; `pip freeze` for Neutron sub-projects | Automated | `[LAB-VALIDATED: VAL-001]` (`config-parity.txt`: `quota_backups=7`, `quota_backup_gigabytes=2500`, no sub-projects) | only override keys differ | diff = override keys only | **STOP SC-CP** |

### Phase 2 — Controlled degradation and fencing (state-changing)

| # | Step | Mode | Status | Expected output | Success criterion | If different / stop |
|---|---|---|---|---|---|---|
| 2.1 | **Approval point:** window opens; announce; block state-changing API calls (HAProxy or policy); pause user automation and periodic cleanups | Approval point (Change authority) | `[PROPOSED-UNVERIFIED]` (06-recovery P2) | not observed | writes rejected, reads work | Bus unstable or duplicate instances → stop |
| 2.2 | Capture every `services` row (`id, host, binary, version, disabled, disabled_reason, forced_down, updated_at`) | Manual | `[LAB-VALIDATED: EXP-DB-00]` (`pre-forced-down/nova-services-rows.tsv`) | 3 `nova-compute` rows at 51, `forced_down=0` | all rows captured | — |
| 2.3 | **Fence** every compute, network and storage host: stop `nova_compute`, Neutron agents, `cinder_volume`, `cinder_backup`; keep `nova_libvirt` and `openvswitch_vswitchd` running so instances stay up. Verify per host: `docker ps`, and `rabbitmqctl list_consumers` empty | Manual | `[LAB-VALIDATED: EXP-DB-00]` for **fake** compute and agent containers only (`fence-proof.txt`); real hosts, libvirt and OVS `[PROPOSED-UNVERIFIED]` | lab: `fenced-containers.txt` all exited | no Ussuri RPC/HTTP client left (RT-B-02) | STOP until proven; never start 2026.1 services before this holds |
| 2.4 | **Forced-down through the Ussuri API**, per host, after its fencing evidence: `openstack compute service set --down <host> nova-compute` (microversion ≥ 2.11; the lab used 2.53). Never by SQL. Never delete service or compute-node rows | Manual | `[LAB-VALIDATED: EXP-DB-00]` (`forced-down-api-output.txt`, rows `forced_down=1`) | ``` host=ufj-compute1 forced_down=True ``` (shape; lab values) | every fenced row `forced_down=1` | A row not forced-down now has **no repair path after the bridge** (SVC-01 finding 1). STOP |
| 2.5 | ⚠️ Stop all Ussuri API and control services (no old clients) | Manual | `[LAB-VALIDATED: EXP-SVC-01]` for the lab containers (`no-old-clients.txt`) | all `ufj-*` containers exited | nothing writes to the databases | — |

### Phase 3 — Final consistent backup (restore point RP-0)

| # | Step | Mode | Status | Expected output | Success criterion | If different / stop |
|---|---|---|---|---|---|---|
| 3.1 | Full backup of every service database with the flags of 2.4 inside; copy off-host; `/etc/kolla`, keys, certificates; `MANIFEST.sha256` | Manual | `[LAB-VALIDATED: EXP-DB-00]` for the lab's logical dump + datadir tarball (restore proven, 22 s); Mariabackup/Galera `[DOCUMENTED-UNVERIFIED: openstack-kolla-ansible-operations KA-OPS-12/14]` | lab dump sha256 recorded, manifest verifies | backup verifies and is off-host | STOP: backup incomplete |
| 3.2 | T0 snapshot for the comparator: schema dump, row counts, per-row fingerprints, predictions of the declared transformations | Automated | `[LAB-VALIDATED: VAL-001]` (`strict-r2/T0/`) | T0 predictions recorded | present | — |
| 3.3 | Re-check PC-N5 and PC-V3 on the backup copy | Automated | `[LAB-VALIDATED: VAL-001]` for PC-V3; PC-N5 `[PROPOSED-UNVERIFIED]` | — | pass | STOP |
| 3.4 | **Approval point:** RP-0 exists and verifies. The next command is the point of no return for the production copy of the database (Strategy B) — or none, if the walk runs on a clone (Strategy D, recommended) | Approval point (Change authority + Platform owner, in person) | `[PROPOSED-UNVERIFIED]` | — | approval recorded | — |

### Phase 4 — Fast-forward hops on one node (destructive on the copy)

Executed in the lab by `ff/50-run-s2c.sh` (harness `2f3e48a`, strict mode, verdict `ff/55-verdict.sh`: 33 PASS). The
production equivalent must use the **rehearsed image digests**, not PyPI. Each hop runs, in this order, one-shot
containers of that release with the Phase 1.12 configuration: `keystone-manage db_sync`; `nova-manage api_db sync`;
`nova-manage db sync --local_cell` (cell0, then each cell); `cinder-manage db sync`; `cinder-manage db
online_data_migrations` (until 0); `nova-manage db online_data_migrations` (per cell, cell0 included, until 0);
`glance-manage db sync`; `placement-manage db sync`; `neutron-db-manage upgrade heads`; `placement-manage db
online_data_migrations`. No `alembic stamp`, no edit of bookkeeping tables or rows at any time (SC-HAND).

**Checks after every hop** (C1–C10, `ff/40-checks.sh`): C1 every command exit 0 and every ODM loop ends at 0
(SC-CMD); C2 versions equal the fresh reference; C3 `migrate_version` state as declared; C4 schema vs a fresh
same-server reference, **0 undeclared** (SC-DIFF); C5/C6 row counts and fingerprints vs T0, 0 undeclared, plus the N-3
reconciliation; C7 ODM summaries saved; C8 engine checks (SC-ENGINE); C9 `*-status upgrade check`, no FAILURE; C10
durations recorded. The declared set is frozen in [`declared-differences.md`](../experiments/declared-differences.md)
(Amendments 1 and 2).

| # | Step | Mode | Status | Expected output (lab, ~4,100 rows; not extrapolable) | Success criterion | If different / stop |
|---|---|---|---|---|---|---|
| 4.1 | Engine 10.3 → 10.5 → 10.6: clean shutdown (`innodb_fast_shutdown=0`), start the newer major, `mariadb-upgrade`, `mariadb-check --all-databases --check-upgrade`, clean restart, scan the error log since the restart | Automated | `[LAB-VALIDATED: VAL-001]` (library images 10.3.39 → 10.5.29 → 10.6.28) | exit 0, 0, 0 `[ERROR]` after restart. `Incorrect definition of table mysql.event` **before** `mariadb-upgrade` is recorded, not SC-ENGINE (RT-N-15) | all three | **STOP SC-ENGINE** |
| 4.2 | **H1** — 2023.1 for all services (bridge) | Automated | `[LAB-VALIDATED: VAL-001]` (36 s of commands) | Cinder ODM migrates the non-deleted rows only (lab 7 volumes, 1 snapshot); Keystone `migrate_version` 078 → 079 (V-K1); C4 declared A1 141 + S-1 + S-3.4, 0 undeclared | C1–C9 pass | STOP on any SC-* |
| 4.3 | **H1b** — Cinder only, cinder 23.5.0 (2023.2): `db sync` + ODM until 0 | Automated | `[LAB-VALIDATED: VAL-001]` (5 s); the step is itself *technically possible but unsupported* | lab: 3 deleted volumes + 2 deleted snapshots migrated; 30 Cinder schema lines declared; other databases identical to H1 | C1–C9 pass | STOP. Cinder's point of no return is **before H1b** (`89aa6f9639f9` drops `migrate_version`) |
| 4.4 | **Gate PC-C1**: `SELECT COUNT(*) FROM cinder.volumes WHERE use_quota IS NULL;` and the same for `snapshots`, **no `deleted` filter** | Automated | `[LAB-VALIDATED: VAL-001]`; the failure it prevents `[FAILED: EXP-DB-01 R1o]` (`DataError 1265` at H2) | `0` and `0` | 0 / 0 | **STOP SC-PC-C1.** Never fix by SQL; never purge as a fix. See [troubleshooting](../troubleshooting/cinder-use-quota-null-blocks-2024.1-db-sync.md) |
| 4.5 | Engine 10.6 → 10.11, as 4.1 | Automated | `[LAB-VALIDATED: VAL-001]` (10.11.19) | clean | as 4.1 | STOP SC-ENGINE |
| 4.6 | **H2** — 2024.1 all services | Automated | `[LAB-VALIDATED: VAL-001]` (33 s) | `migrate_version` dropped for nova, nova_cell0, nova_api, cinder (R-1); Nova `populate_instance_compute_id` migrates all but the host-NULL residue N-R1 (exit 0); transient A7 enum difference declared at H2 only; R-5 quota classes +2 | C1–C9 pass | STOP |
| 4.7 | **H3** — 2025.1 all services | Automated | `[LAB-VALIDATED: VAL-001]` (41 s) | A7 converges; 0 undeclared | pass | STOP |
| 4.8 | Engine 10.11 → 11.4, as 4.1 | Automated | `[LAB-VALIDATED: VAL-001]` (11.4.13) | clean | as 4.1 | STOP SC-ENGINE |
| 4.9 | **H4** — 2026.1 all services | Automated | `[LAB-VALIDATED: VAL-001]` (40 s) | heads: nova_api `cdeec0c85668`, nova cells `2903cd72dc14`, keystone `742c857f1dfb`+`c88cdce8f248`, cinder `9c74c1c6971f`, glance `2024_1_contract01`, placement `a082b8bb98d0`, neutron `5c85685d616d`+`b1bca967e19d`; C5/C6 104 declared, 0 undeclared | pass; `neutron-status` exit 1 is acceptable only for the OVN-connect warning | STOP |
| 4.10 | **H4r** — second 2026.1 pass (idempotency) | Automated | `[LAB-VALIDATED: VAL-001]` (40 s) | `H4r == H4`, 0 differences, no exclusions | 0 differences | **STOP SC-IDEMP** |
| 4.11 | Targeted value checks (16 asserts: `use_quota` NOT NULL, R-5 7/2500, `compute_id` mismatches 0, V-Q6/7/8/9, V-K1 079, `shadow_migrate_version` 0 rows) and the Nova archive check (A3) on a disposable copy | Automated | `[LAB-VALIDATED: VAL-001]` | 16 ASSERT-PASS | all pass | STOP |
| 4.12 | Dump the 2026.1-head databases (per service, never the `mysql` schema); record checksums | Manual | `[LAB-VALIDATED: EXP-SVC-01]` for the lab's datadir copy (`derive-h4r-datadir-mariadb11.4.tgz`) | sha256 recorded | present | — |

### Phase 5 — Engine path to the target cluster

| # | Step | Mode | Status | Expected output | Success criterion | If different / stop |
|---|---|---|---|---|---|---|
| 5.1 | Engine line **E1** (stepwise 10.3 → 10.5 → 10.6 → 10.11 → 11.4 on one node) | Automated | `[LAB-VALIDATED: VAL-001]`, standalone library images, **no Galera, wsrep not applicable** | as 4.1/4.5/4.8 | — | — |
| 5.2 | Engine line **E2** (dump on the old engine, restore on 11.4) as an alternative | — | `[PROPOSED-UNVERIFIED]` (not run) | — | — | Do not use without a rehearsal |
| 5.3 | **Galera rebuild**: Kolla bootstraps an empty Galera (route M1: `deploy` limited to the infrastructure tags), then the dumps of 4.12 are restored through the first node **before any service bootstrap**; or route M2 (physical datadir + `kolla-ansible mariadb-recovery`) | Manual | `[PROPOSED-UNVERIFIED]` (03-kolla-deploy §2.2; exact `--tags` set unknown) | not observed | all nodes `Synced`; checksums equal 4.12 | STOP: any service created an empty schema first (restore then needs `DROP DATABASE`: a new decision) |

### Phase 6 — 2026.1 deployment with Kolla-Ansible 22.x (mandatory KD-M1..KD-M10)

Kolla-Ansible itself was **never run** in this journey. EXP-KD-01 ran, by hand from the 2026.1 PyPI image, the
commands Agent 3 read in `kolla-ansible@22.2.0`; whether Kolla issues exactly those commands stays
`DOCUMENTED-UNVERIFIED` until a Kolla lab (K-01). Use `deploy`, not `upgrade`, on new hosts.

| # | Step | Mode | Status | Expected output | Success criterion | If different / stop |
|---|---|---|---|---|---|---|
| 6.1 | Configuration transformed from the Ussuri-rendered files; the 13 lab config changes of `svc/config-changes.txt` (RabbitMQ quorum queues, memcache backend, `[service_user]`, `[upgrade_levels] compute = auto`, service token settings, …) are the minimum known set | Manual | `[LAB-VALIDATED: EXP-SVC-01/02]` for the lab's hand-rendered files; Kolla templates `[DOCUMENTED-UNVERIFIED: kolla-ansible@22.2.0]` | — | rendered-config diff reviewed | — |
| 6.2 | **KD-M1** record `nova-manage cell_v2 list_cells --verbose`; set `nova_cell_name` to the **stored** cell name (lab `cell1`; Kolla Ussuri default was `''`: read it, do not assume) | Manual | `[LAB-VALIDATED: EXP-KD-01 C-3]` (`extract_cell('')` → None, `extract_cell('cell1')` → the cell) | cell uuid returned for the stored name | `extract_cell(<name>)` of the pinned wheel returns the stored uuid | STOP: Kolla would take the `create_cell` branch |
| 6.3 | **KD-M2** `nova-manage cell_v2 update_cell --cell_uuid <uuid> --transport-url … --database_connection …` to the new broker and database | Manual | `[DOCUMENTED-UNVERIFIED: nova@33.0.2 manage.py]`; the trap it avoids `[LAB-VALIDATED: EXP-KD-01 C-4 (iii)]` (second unnamed mapping on the same database) | `list_cells` shows the new hosts, cell count unchanged | cell count unchanged | STOP |
| 6.4 | **KD-M4** `keystone_admin_password` in `passwords.yml` equals the Ussuri admin password; `passwords.yml` key-diffed against the Ussuri one; declare the expected bootstrap changes: roles `manager`, `service`; implied chain `admin→manager→member`; endpoint URL rewrite | Manual | `[LAB-VALIDATED: EXP-KD-01 C-2]` (different password → reset, `revocation_event` 1501 → 1, every admin token invalid) | — | key diff clean; declaration written | STOP: a wrong value **is applied** |
| 6.5 | **KD-M8** config parity with Kolla's templates at the pinned tag: `cinder.conf [keystone_authtoken] service_token_roles_required = true`, `service_token_roles = service`; Nova `[service_user] send_service_user_token = true` with the nova user; the same for Neutron and Glance where Kolla sets it | Manual | `[LAB-VALIDATED: EXP-SVC-02]` for the Cinder and Nova settings in the lab; Kolla rendering `[DOCUMENTED-UNVERIFIED: kolla-ansible@origin/stable/2026.1 cinder.conf.j2:133]` | — | rendered diff = Kolla defaults | STOP |
| 6.6 | `bootstrap-servers`, `pull` (private registry), `prechecks` on the new hosts; inventory = new control hosts only, compute group **empty** | Manual | `[PROPOSED-UNVERIFIED]` | not observed | `prechecks` failed=0 | STOP |
| 6.7 | Route M1 infrastructure deploy + restore (Phase 5.3); record checksums (snapshot S5) | Manual | `[PROPOSED-UNVERIFIED]` | not observed | checksums = 4.12 | STOP |
| 6.8 | ⚠️ `kolla-ansible deploy` (control plane). Record every bootstrap container's output | Manual | `[PROPOSED-UNVERIFIED]` (Kolla never run here); the database effect of its commands `[LAB-VALIDATED: EXP-KD-01 C-1]` (11 commands, two passes, 0 differences) | not observed | `failed=0`; no `TooOldComputeService` in nova logs (state (d), 7.1) | STOP: a `TooOldComputeService` refusal proves a row was not forced-down (free verification); do **not** set the workaround flag without a separate decision |
| 6.9 | **KD-M3** `SELECT id, uuid, name FROM nova_api.cell_mappings;` | Automated | `[LAB-VALIDATED: EXP-KD-01 C-4]` for the duplicate it detects | exactly cell0 + the one named cell | 2 rows, no `name IS NULL` | **STOP**: remove the unnamed row with `delete_cell` before any instance is scheduled |
| 6.10 | Post-deploy database diff against S5: only the declared bootstrap changes (6.4) allowed | Automated | `[LAB-VALIDATED: EXP-KD-01 C-1/C-2]` for the command effects | role 3 → 5, implied_role 2 → 3, endpoints updated in place; nothing else | diff = declared set | STOP SC-DIFF |
| 6.11 | **KD-M6** Keystone registration complete **before** any Nova, Cinder or Neutron container serves traffic: roles `manager` and `service` exist; **every** registered service user holds `service` in project `service` | Manual | `[LAB-VALIDATED: EXP-SVC-02]` for three users (nova, cinder, neutron: `service-user-roles.txt`); Kolla grants it to **all** (RT-N-32); Kolla's task order `[DOCUMENTED-UNVERIFIED]` (open question, Stage 5d §7) | `openstack role list` contains `service`; assignment list shows every service user | all present | **STOP** if any is missing; create them with the 2026.1 admin before starting Nova/Cinder |
| 6.12 | Explicit `nova-manage db online_data_migrations` (API and each cell), `cinder-manage db online_data_migrations` (Kolla `deploy` runs neither); `nova-status upgrade check`, `cinder-status`, `placement-status`, `glance-status`, `keystone-status`, `neutron-status` | Manual | `[LAB-VALIDATED: EXP-SVC-01 d1]` (`status-tools-1-started.txt`) | nova-status "Older than N-1 computes" **Success**; exit 1 only for the `hw_machine_type` Warning; cinder/placement/glance/keystone 0; neutron 1 for the OVN warning only | no FAILURE | STOP on any FAILURE |
| 6.13 | **KD-M5** second `deploy` (or `reconfigure`) → comparator `same` = 0 database changes | Manual | `[PROPOSED-UNVERIFIED]` for the Kolla run; the idempotency of the commands `[LAB-VALIDATED: EXP-KD-01 C-1]` | 0 differences | 0 | STOP |

### Phase 7 — Nova gate state (d) and per-host re-adoption

| # | Step | Mode | Status | Expected output | Success criterion | If different / stop |
|---|---|---|---|---|---|---|
| 7.1 | 2026.1 control plane started **without** `[workarounds] disable_compute_service_check_for_ffu`; `[upgrade_levels] compute = auto` present | Manual | `[LAB-VALIDATED: EXP-SVC-01 d1]` (`flag-absent.txt`); the refusal with un-forced rows `[LAB-VALIDATED: EXP-SVC-01 a]` (`TooOldComputeService … minimum compute service level … 51 … oldest supported … 68`) | no cap cached: DEBUG `Not caching compute RPC version_cap, because min service_version is 0` (`probe-d1-rpc/`) | services up, no cap | A refusal = a row missed; see 2.4; STOP |
| 7.2 | **F2 read-back** of every pre-existing resource through the 2026.1 APIs (`tools/f2_readback.py`): counts per collection, authentication of old users, credential decryption, image checksums | Automated | `[LAB-VALIDATED: EXP-SVC-01 d1]` (`d/f2/f2-report.txt`) | 36 collections equal; **1 declared difference** (port `binding:profile.trusted` moved to `porttrusted` by `5bcb7b31ec7d`); 0 undeclared; 0 HTTP 5xx | 0 undeclared, 0 5xx | STOP |
| 7.3 | Per compute host: reinstall the OS (or replace) **keeping the same short hostname** and the preserved `nova_compute` volume / instance storage; deploy 2026.1 `nova-compute` and agents on it | Manual | `[PROPOSED-UNVERIFIED]` (real host, libvirt, OS reinstall never run) | not observed | host up | STOP; never "retry from scratch" without restoring the volume (node identity) |
| 7.4 | Verify adoption: service row version 72 with a fresh `updated_at`; `/var/lib/nova/compute_id` equals the existing `compute_nodes.uuid`; one `compute_nodes` row; Placement provider reused. Kolla's own "compute registered" wait is satisfied by the **old** forced-down rows and proves nothing | Manual | `[LAB-VALIDATED: EXP-SVC-01 d2/c]` with the lab driver `ufj_fake2026.py` (node identity path real, hypervisor fake) | `adoption-compute1.txt`: `compute_id` = `ffb37850-…`, no duplicate row, `forced_down` still 1 | all four | STOP: none or several `compute_nodes` rows → `_ensure_existing_node_identity` refuses |
| 7.5 | Clear forced-down **through the 2026.1 API** only now (row is at 72): `openstack compute service set --up <host> nova-compute`. Clearing it on a host still at Ussuri would cache RPC 5.11 | Manual | `[LAB-VALIDATED: EXP-SVC-01 d2/c]` | success; on a version-51 row the same call returns HTTP 500 `ServiceTooOld` | `forced_down=0`, version 72 | STOP on 500 |
| 7.6 | Bring the host's instances back (hard reboot regenerates the libvirt XML; method depends on storage) | Manual | `[PROPOSED-UNVERIFIED]` (fake driver: no instance data exists) | not observed | instances ACTIVE, reachable | Instance fails to start → do not retry destructively; read the libvirt log; escalate |
| 7.7 | After the **last** host: restart nova-api, nova-conductor and nova-scheduler once; a host not re-adopted stays forced-down **and** disabled with a reason | Manual | `[LAB-VALIDATED: EXP-SVC-01 d2]` | `Automatically selected compute RPC version 6.5 from minimum service version 72` (nova-api, nova-conductor) | 6.x in the logs; nova-status Success | STOP: 5.11 means an un-forced old row remains |

### Phase 8 — Post-upgrade validation (canary tenant, before user traffic)

| # | Step | Mode | Status | Expected output | Success criterion | If different / stop |
|---|---|---|---|---|---|---|
| 8.1 | Repeat F2 read-back (7.2) after the deployment and the re-adoption | Automated | `[LAB-VALIDATED: EXP-SVC-01]` | 0 undeclared | 0 undeclared | STOP |
| 8.2 | **SVC-02 canary operations** on pre-existing resources: tokens for old users (password, application credential), EC2/TOTP decryption, stop/start of an Ussuri ACTIVE server, resize-confirm of the Ussuri `VERIFY_RESIZE` server, **detach and re-attach of an Ussuri-era attachment**, attach/detach of an old volume on an old server, resize with an attached (and an encrypted) volume, snapshot, quota refusal (403 / 413), port and server creation on an old network | Manual | `[LAB-VALIDATED: EXP-SVC-02 strict-r2]` (22 OK, 0 FAIL, 6 INFO) with the **fake driver**: resize, attach and snapshot are host-side no-ops; `connection_info` never consumed by os-brick | `results.tsv` 22 OK; quota: `Quota exceeded for instances: Requested 1, but already used 5 of 5`; `VolumeSizeExceedsAvailableQuota` | all OK | STOP on any FAIL; see §9 for the 409 signature |
| 8.3 | **KD-M9** cinder-api log count of `not a valid service token` lines = 0; no HTTP 500, ERROR, `IncompatibleObjectVersion` or `ObjectActionError` in any service log | Automated | `[LAB-VALIDATED: EXP-SVC-02]` (`cinder-service-token-lines.txt` empty; `service-log-errors.txt` 0 across 14 logs) | 0 / 0 | 0 | **STOP on 409 `ConflictNovaUsingAttachment`** |
| 8.4 | End-to-end capability with a **real** hypervisor: create, reach and delete a test VM with a volume and a floating IP | Manual | `[PROPOSED-UNVERIFIED]` (no hypervisor in the lab) | not observed | VM reachable | STOP |
| 8.5 | **Approval point:** reopen user traffic; observation period starts (length: owner's decision) | Approval point (Change authority) | `[PROPOSED-UNVERIFIED]` | — | recorded | — |

## 5. Decision points

| Check (read-only) | If you see | Go to |
|---|---|---|
| PC-V3 on the Ussuri DB | an `alembic_version` table in nova/keystone/cinder databases | STOP; newer code already ran; restore the last backup before the touch (§10) |
| PC-C1 after H1b | any NULL | STOP SC-PC-C1; the H1b ODM did not run to 0; never SQL, never purge |
| nova-api/conductor start-up | `TooOldComputeService` | an Ussuri `nova-compute` row is not forced-down; it has no 2026.1 repair path: bring a 2026.1 compute up under that hostname, or STOP and decide on the flag as a fallback |
| conductor log after 7.7 | `compute RPC version 5.11` | an un-forced old row exists, or a host was cleared while still Ussuri; find the row, re-apply 7.3–7.5 |
| volume detach / resize | 409 `ConflictNovaUsingAttachment`, volume stuck `detaching`, server `ERROR` | §9 signature 2: the `service` role is missing (KD-M6) |
| `cell_mappings` | a row with `name IS NULL` | KD-M3: `delete_cell` before any scheduling |

## 6. Stop and escalate

Stop if: any named stop condition SC-PC-*, SC-GLANCE, SC-CP, SC-CMD, SC-DIFF, SC-IDEMP, SC-HAND, SC-ENGINE fires; any
dependency behaves differently from the rehearsal; monitoring is blind for the new state; recovery (RP-0 restore within
the accepted time) is no longer credible; the decision authority is unreachable. **Time already invested creates no
obligation to continue; resuming after a stop is a new decision.**

Collect before escalating: the run log, `steps.tsv`, the failing command's log, `schema-diff.txt`/`data-diff.txt`, the
engine error log since the last restart, the `services` rows, the pre-check outputs. Escalate to: the Platform owner
and the Change authority (names to fill per organisation).

## 7. Do NOT do without escalation

- Any SQL write to an OpenStack database: no `alembic stamp`, no edit of `migrate_version`, `alembic_version` or data
  rows (SC-HAND). The lab's SQL `UPDATE` of `forced_down` was lab state construction on a disposable clone, never a
  procedure step.
- `cinder-manage db purge` as a fix for PC-C1 (a data-retention decision with its own change record).
- Deleting `services` or `compute_nodes` rows (breaks node adoption, orphans instances).
- Setting `[workarounds] disable_compute_service_check_for_ffu` (a fallback that hides a missed row; separate decision).
- Clearing `forced_down` on a host that still runs Ussuri `nova-compute`.
- Starting any 2026.1 service while an Ussuri RPC or HTTP client is running (RT-B-02).
- Starting Nova, Cinder or Neutron 2026.1 before the Keystone registration (KD-M6) is complete.
- `kolla-ansible upgrade` on the new hosts (no Fernet setup, no bootstrap; fails at the MariaDB exec task).
- Removing Ussuri images, the last restore point or the old hosts before the observation period ends (P7, the real
  point of no return).

## 8. Verification

End to end, not process state: 7.2/8.1 read-back with 0 undeclared differences; 8.2 canary operations on
pre-existing resources; 8.3 zero service-token warnings and zero errors; 8.4 a real VM created, reached and deleted
(**never done in this journey**).

## 9. Troubleshooting

1. **`cinder-manage db sync` fails at 2024.1 with `DataError: (1265, "Data truncated for column 'use_quota' …")`**
   (migration `9ab1b092a404`). Soft-deleted volumes or snapshots still have `use_quota` NULL because released cinder
   2023.1 excludes deleted rows from the online data migration. Avoidance: step H1b with cinder 23.5.0, then gate
   PC-C1. Full page: [`cinder-use-quota-null-blocks-2024.1-db-sync.md`](../troubleshooting/cinder-use-quota-null-blocks-2024.1-db-sync.md).
   `[LAB-VALIDATED: VAL-001]` for the avoidance; the failure `[FAILED: EXP-DB-01 R1o]`.
2. **Service-role 409 signature (EXP-SVC-02 `strict-r1`, KD-M10).** Volume detach fails and the volume stays
   `detaching`; a resize of a server with an attached volume leaves the server in `ERROR`. nova-compute logs
   `cinderclient.exceptions.ClientException: ConflictNovaUsingAttachment: Detach volume from instance … using the
   Compute API (HTTP 409)` inside `do_detach_volume` or `_terminate_volume_connections`. cinder-api logs `WARNING
   keystonemiddleware.auth_token … A valid token was submitted as a service token, but it was not a valid service
   token.` (with `service_token_roles_required = true` the request is rejected with 401 instead). **Cause:** the role
   `service` does not exist in the migrated Keystone, or the nova user does not hold it (`cinder/volume/api.py:908-910`,
   `is_service`). **Remedy:** `keystone-manage bootstrap` (2026.1) creates the role; grant `service` to every service
   user in project `service`; then **restart the token-holding services** so cached service tokens are refreshed (a
   nova-api worker kept a pre-grant token in the lab). Nothing in the migrated attachment rows is at fault: the
   Ussuri-era attachment detached and re-attached cleanly once the role existed. `[LAB-VALIDATED: EXP-SVC-02]`.
3. **`TooOldComputeService` at start-up** → §5. **HTTP 500 `ServiceTooOld` on `compute service set`** → the row is
   still at version 51; only the Ussuri API (before the bridge) or a re-registration (7.3) can change it.
4. **`Table … already exists` with an empty `alembic_version` left behind** → 2026.1 code was run against the legacy
   database (EXP-DB-N1). Restore; PC-V3.
5. **PC-Q5 duplicate segments** (`e981acd076d3` would fail) → remedy through the Ussuri API only; blocking for every
   path, the staircase included.
6. **`cinder-status` FAILURE "Service UUIDs"** at every hop → a volume without `service_uuid` (PC-C4); resolve through
   the API before T0 or record an acceptance.
7. **Neutron under gunicorn returns 500 on the first `GET /v2.0/ports`** (lab wrapper) → all model modules must be
   imported and mappers configured before the WSGI app (SVC-01 finding 8; not a Kolla issue).

## 10. Recovery

| If the procedure fails at | First move | What is restorable | What is lost |
|---|---|---|---|
| Phases 0–3 | Stop; re-enable the API (new decision) | everything | nothing |
| Phase 4 on a **clone** (Strategy D, recommended) | Stop; discard the clone | the Ussuri plane is untouched; unfreeze | nothing |
| Phase 4 on the **production copy** (Strategy B) | Stop; **do not retry on the same database** | RP-0 on a Ussuri control plane rebuilt from mirrored images on hosts the Ussuri images support | everything since RP-0; a half-walked database is a state no release can serve |
| Phase 6–7 before the first tenant write to the new plane | Stop the new plane; switch VIP/DNS back; clear `forced_down` per host through the **Ussuri** API after the Ussuri computes are back (EXP-RB-01 must define this) | RP-0 | nothing, if no shared backend was written |
| After the first tenant write or the first instance start on 2026.1 | Highest-level decision; take a new restore point first | disk data on the backends | control-plane records for the interval: a recovery project, not a rollback |

**Point of no return:** Strategy B: the first migration command on the production database (and, for Cinder, H1b).
Strategy D: the first write by the new plane to production computes or storage. The real one for both: P7, when the
old images, the last restore point and the old hosts are gone.

**Rollback rehearsal EXP-RB-01 is deferred and has never been run.** Every row of this table is
`[PROPOSED-UNVERIFIED]`; the lab's own restore of its baselines is `[LAB-VALIDATED: EXP-DB-00]` and says nothing about
Galera, Mariabackup or a Kolla control plane.

## 11. Known limitations (what the lab evidence does not show)

Synthetic Tier A dataset (~4,100 rows, 11 instances; coverage gaps: HA routers, DHCP ports, PCI devices, temporary
Cinder metadata, deleted instances whose node row is gone); PyPI code, not Kolla images (parity unknown, RT-N-10);
standalone MariaDB, no Galera, no ProxySQL; fake hypervisor (`connection_info` never consumed by os-brick; resize,
attach, snapshot host-side no-ops); fake L2 agents, no ML2/OVN, no data plane; fresh RabbitMQ 4.x (no migration from a
live 3.8 broker); Kolla-Ansible never executed; no host OS reinstall; no real compute; no rollback rehearsal; no Tier B;
no durations that extrapolate; no second operator and no human re-execution. The Nova `_ComputeV5Proxy` that made
state (a) survivable is marked for removal upstream and must not be relied on. Only three service users were granted
`service` in the lab (RT-N-32). The application-credential token used a new credential of an old user (RT-N-35).

## 12. History

| Date | Change | Why | By |
|---|---|---|---|
| 2026-10-31 | First draft from VAL-001, EXP-DB-00/N1/R0/01, EXP-SVC-01/02, EXP-KD-01, DR-000..004, Red Team Stages 3, 5, 5b, 5c, 5d | Mission rule: no runbook before service-level results; SVC-02 and Stage 5d closed that condition (rollback stays deferred and marked) | Agent 8b (Fable) |

Approaches tried that did not work: direct jump (N1); the chain without H1b on a dataset with soft-deleted Cinder rows
(R1o); `cinder-manage db purge` as a remedy (baseline v3, withdrawn); starting 2026.1 services without the `service`
role (SVC-02 `strict-r1`, interrupted).

## Author notes

- **Sources used:** the records cited in each step; nothing was inferred beyond them. Lab values are quoted as
  observed; production values are placeholders.
- **Gaps marked TODO (owners):** PC-N5 text in `fast-forward-checks.md` §4 (Agent 4); Kolla's `service-ks-register`
  ordering guarantee before Nova/Cinder serve traffic (Agent 3, K-01); the exact M1 `--tags` set (Agent 3); the
  EXP-RB-01 rollback steps (Agent 5/6); validation ids for EXP-SVC-01/02 and EXP-KD-01 (architect).
- **Validation plan:** a person who did not write this page executes it on a Tier B rehearsal environment (Kolla
  images by digest, Galera, a real hypervisor), observed but not helped; the page is corrected from their questions.
  Until then: **Draft — not yet validated.**

Decision support only. Nothing in this page authorises a production change; every state-changing step requires the
named approver under the organisation's change process.
