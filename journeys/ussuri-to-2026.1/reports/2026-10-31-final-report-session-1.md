# Final report, session 1 — Ussuri → 2026.1

| Metadata | |
|---|---|
| Author | Agent 8b — Documentation and Community Engineer (Fable 5.1), from the records of the journey |
| Date | 2026-10-31 |
| Period | Mission start to the Red Team Stage 5d review and the first (draft) runbook |
| Branch | `claude/epic-pascal-2kqc98` |
| Supersedes | nothing; extends [progress report 01](2026-10-31-progress-report-01.md) |

## 1. The central question, answered as far as the evidence goes

**Can a Kolla-Ansible Ussuri cloud reach OpenStack 2026.1 without deploying every intermediate release?**

- **A single direct jump: no.** Incompatible. 2026.1 Nova, Keystone and Cinder have no path for a pre-Alembic
  database; they attempt the initial schema and stop on `Table already exists` (EXP-DB-N1, `FAILED` as predicted).
- **Intermediate code, yes; intermediate deployments, not shown to be needed.** The databases of the six core services
  can be walked offline through 2023.1 → Cinder 2023.2 → 2024.1 → 2025.1 → 2026.1 code with zero undeclared schema or
  data differences and an idempotent second pass (VAL-001, `LAB-VALIDATED`). 2026.1 services then start on the result
  without the Nova workaround flag, read back every pre-existing resource (EXP-SVC-01) and operate on them: tokens,
  credentials, stop/start, resize with attached volumes, Ussuri-era attachment detach and re-attach, snapshots, quota
  enforcement, port and server creation on an old network (EXP-SVC-02, 22/22). Kolla's deploy-time database commands
  are no-ops on the migrated database except the declared Keystone bootstrap changes (EXP-KD-01).
- **What that answer is worth.** All of it on one Docker host, synthetic data (~4,100 rows), PyPI code instead of Kolla
  images, a standalone MariaDB instead of Galera, fake hypervisors, no data plane, no Kolla-Ansible run, no rollback
  rehearsal, no production copy. The procedure is **technically possible but unsupported**; nothing is
  production-validated; and the only path upstream supports remains the nine-hop staircase (P1).

The safest practical path with the fewest intermediate deployments is therefore still a hypothesis with lab support,
P2, and it stands or falls with the deferred work in §6. No recommendation is issued (mission rule: the architect does
not validate its own architecture; the owner decides).

## 2. Validation status by claim

| Claim | Status | Evidence | Scope and limits |
|---|---|---|---|
| Direct jump Ussuri → 2026.1 is incompatible | **Lab-verified negative** (`FAILED` as predicted) | EXP-DB-N1 | Nova, Keystone, Cinder run; Glance, Placement, Neutron not run |
| Lab baseline is restorable; Ussuri forced-down through the Ussuri API | `LAB-VALIDATED` | EXP-DB-00 (v1–v4) | Fake computes; 6 coverage items not covered, 5 partial |
| Offline fast-forward of all six databases, E1 engine line, idempotency | `LAB-VALIDATED` | **VAL-001** (EXP-DB-01 strict-r2, harness `2f3e48a`; re-derived `derive-h4r`) | Tier A, PyPI code, no Galera, 673 s run; not extrapolable |
| Cinder-only 2023.2 step H1b + gate PC-C1 avoid the `use_quota` failure | `LAB-VALIDATED` | VAL-001; DR-004; troubleshooting page | The failure itself hits the **supported** 2023.1 → 2024.1 path too |
| 2026.1 control plane starts on the result in DR-003 state (d), no flag, `nova-status` Success; F2 read-back 0 undeclared; compute adoption; cap 6.5 after re-adoption | `LAB-VALIDATED` (VAL id pending) | EXP-SVC-01 strict-r1 | Fake driver; lab driver for node identity; states (a)/(b) lab-constructed by SQL on a clone |
| Red Team prediction "an RPC operation fails under the 5.11 cap" | **Refuted** for 6 basic operations | EXP-SVC-01 state (a) | `_ComputeV5Proxy` marked for removal upstream; cross-cell resize not tested |
| Operations on Ussuri-created resources through 2026.1 | `LAB-VALIDATED` (VAL id pending) | EXP-SVC-02 strict-r2 (22 OK, 0 FAIL) | Control path only; fake driver; needs Kolla's Keystone `service` role (KD-M6) |
| Kolla deploy-time commands are no-ops and idempotent on the migrated DB; `keystone-manage bootstrap` side effects; cell-name trap | `LAB-VALIDATED` (VAL id pending) | EXP-KD-01 strict-r1 | Commands typed by hand from kolla-ansible 22.2.0 reading; **Kolla-Ansible itself never run** |
| Kolla-Ansible `deploy` on new hosts with the migrated databases (routes M1/M2, KD-M1..M10 as Kolla executes them) | `DOCUMENTED-UNVERIFIED` / `PROPOSED-UNVERIFIED` | 03-kolla-deploy, Stage 5c/5d | No Kolla lab exists in this environment |
| Galera rebuild, Mariabackup restore at production size, host OS reinstall, real computes with libvirt, instance restart, RabbitMQ broker migration | `PROPOSED-UNVERIFIED` | architecture P2, 06-recovery | Unsupported and still theoretical |
| Rollback from RP-0 (EXP-RB-01) | `PROPOSED-UNVERIFIED` (deferred) | 06-recovery | Never run; the runbook's recovery table is unverified |
| Equality with the staircase (EXP-DB-02), minimal path (EXP-DB-03), Cinder skip (N2), engine line E2 | not run | — | Theoretical |
| Tier B (sanitised production copy) | not run | VAL-001 `missing_evidence_for_next_level` | Prerequisite for any production decision |
| Anything `PRODUCTION-VALIDATED` | **0** | — | — |

Outside this repository these results are called *lab-verified*, never *validated*.

## 3. Experiments and their statuses

| ID | Status | Note |
|---|---|---|
| EXP-DB-00 | `LAB-VALIDATED` (restorability) | Baselines v1–v4; v3 withdrawn as Cinder evidence |
| EXP-DB-N1 | `FAILED` (expected negative) | Leaves an empty `alembic_version`: pre-check PC-V3 |
| EXP-DB-R0 | `LAB-VALIDATED` (calibration) | Amendments A1–A6; Red Team added A7 |
| EXP-DB-01 R1 family | `FAILED` | SC-PC-Q5, SC-DIFF, SC-CMD at H2 (Cinder); comparator integrity issue RT-B-06 disclosed and reconstructed |
| EXP-DB-01 strict R2 | `LAB-VALIDATED` | **VAL-001**; re-derived strictly as `derive-h4r` (33 PASS) |
| EXP-SVC-01 | `LAB-VALIDATED` (b, c, d, F2, C-5); state (a) prediction `REFUTED` | Corrections RT-B-11/12 applied |
| EXP-KD-01 | `LAB-VALIDATED` (C-1..C-4) | Correction RT-B-11 applied |
| EXP-SVC-02 strict-r1 | interrupted, not a result | Source of the `service`-role finding |
| EXP-SVC-02 strict-r2 | `LAB-VALIDATED` | 22 OK; corrections RT-B-13, RT-N-32 appended |
| EXP-RB-01, EXP-DB-02, EXP-DB-03, EXP-DB-N2, E2, K-01..K-08 | not run | §6 |

## 4. Strategy comparison outcome (P1–P4)

| Proposal | Outcome after session 1 |
|---|---|
| **P1 supported staircase** | Reference and the only supported path: 9 upgrades, 8 intermediate deployments, 3 host OS changes per host. Not experimented here. The `use_quota` finding shows that even P1 hits a data-dependent failure at 2023.1 → 2024.1 for clouds with old deleted volumes. |
| **P2 offline fast-forward + one 2026.1 deployment** | The hypothesis survived every experiment it was given (EXP-DB-01, SVC-01, SVC-02, KD-01) within the lab scope, with two additions to the plan (H1b/PC-C1; KD-M1..M10) and one re-weighting (DR-003 grounds). Not shown: Kolla run, Galera, real computes, rollback, Tier B, equality with the staircase. **Lab-verified at the database and service level only; unsupported; not ready for a production decision.** |
| **P3 parallel cloud** | Not experimented. Remains the fallback; identity and IDs change. |
| **P4 hybrid** | Not experimented. Highest complexity; nothing in this session supports or refutes it. |

The architect's provisional position stays "none": the working hypothesis is P2, and the comparison matrix of
`architecture.md` §3 is unchanged except that P2's "feasibility: hypothesis to test" now reads "lab-verified, narrow
scope" for the database and service layers.

## 5. Disagreements and their resolution

| Disagreement | Parties | Resolution |
|---|---|---|
| Keystone bridge window (Yoga–2023.1 vs Zed–2023.1) | Agent 2 vs Agent 4 | Resolved from source for Agent 2; 2023.1 common bridge (DR-002) |
| Forced-down to pass the Nova gate changes real state | Agent 4 vs Red Team ruling | Agent 4 withdrew with four conditions and sharpened the mechanism (no flag, state d); adopted (DR-003); state (d) lab-verified |
| Red Team Stage 3 V6 (read at the branch head) | Red Team vs Agent 4 lab reproduction | Red Team accepted the correction; rule "verify at the installed tag" (DR-004) |
| Red Team prediction: RPC operations fail under the 5.11 cap (V15 second half) | Red Team vs EXP-SVC-01 | Refuted for six operations; Red Team withdrew that half, kept DR-003 on stronger grounds (no 2026.1 repair path for old rows) |
| Cause of the Cinder H2 failure ("code covers deleted rows" vs `read_deleted='no'`) | Agent 5 record vs Agent 4 / Red Team | Record corrected; frozen V-C1 text was wrong (RT-B-08) |
| Baseline v3 (`cinder-manage db purge`) as a remedy | Agent 5 vs Red Team | Ruled a goalpost move; withdrawn; baseline v4 and H1b instead |
| Comparator edited after the run, five undeclared items not recorded (RT-B-06) | Red Team vs Agent 5 | Disclosed, reconstructed, harness versioned; strict runs refuse a dirty tree; closed |
| "Tier-B" label on synthetic data; SVC-01 title over-claim (RT-B-11/12) | Red Team vs Agent 5 | Corrections appended to both records |
| Kolla version cited as 20.6.0 for 2026.1 (RT-B-13); "lab artefact" wording (RT-N-31) | Red Team vs Agent 5b | 22.2.0 correction appended to EXP-SVC-02; the missing `service` role is a procedure dependency with an ordering gate (KD-M6) |
| Red Team independence after the model change | — | The Red Team (Fable) and the lab agent 5b (Fable) now share a model; separate contexts, no shared reasoning. Recorded in DR-000 as reduced independence |

## 6. Deferred work

1. **EXP-RB-01** rollback rehearsal from RP-0, including clearing `forced_down` through the Ussuri API after the Ussuri
   computes are back. The runbook's recovery section is unverified until then.
2. **EXP-DB-02 / EXP-DB-03** (differential with the staircase; minimal path), **N2** (Cinder skip / non-strict
   `sql_mode`), **engine line E2** (dump and restore) and the bridge code on 11.4.
3. **The real Kolla-Ansible lab** (K-01..K-08: `deploy` on migrated databases, routes M1/M2, compute re-adoption with
   libvirt, cell-name negatives, second `deploy`): needs a cloud account or a KVM host and a registry mirror. Postponed
   by the owner.
4. **Tier B**: a sanitised production copy with Kolla images by digest and a Galera rebuild. Prerequisite for any
   production decision.
5. **Skills improvement**: create `openstack-upgrade-engineering`, or extend `openstack-change-review` (upgrade
   readiness) and `openstack-kolla-ansible-operations`. First candidate content: "verify at the installed tag",
   migration bridge windows, data pre-checks, the two Nova gates, the Keystone `service`-role dependency.
6. **The quick-lab Ussuri profile** (`lab/quick-lab-extension/ussuri-release-profile.patch`, drafted, not run) as the
   base of the Kolla lab and a later contribution to openstack-quick-lab.
7. Follow-ups from the Red Team: PC-N5 in `fast-forward-checks.md` §4 (RT-N-27); DR-003/P2 wording (RT-N-26); the
   eleven config changes into `03-configuration-transformation.md` (RT-N-29); grant `service` to every service user and
   add a comparator check on untouched tables in EXP-SVC-03 (RT-N-32/34); a pre-existing application credential in
   Tier B (RT-N-35); validation ids for EXP-SVC-01/02 and EXP-KD-01.

## 7. Decisions taken by the owner

- Branch history rewritten without AI or session trailers; sign-off in the owner's name (`evidence/commit-sha-mapping.md`).
- The Cinder `use_quota` issue is documented in this repository, not reported upstream for now.
- The real Kolla-Ansible lab (cloud account or KVM host) is postponed.
- The Sonnet lab agent (Agent 5) was stopped for budget reasons; Fable agents took over the lab (Agent 5b) and the
  documentation (Agent 8b). Recorded in DR-000 with the reduced Red Team independence.

Still open for the owner: adding `FAILED` to the shared OzarLand status vocabularies; the relation of this repository
to the planned `openstack-upgrade-playbooks`; the skills decision above; access to a cloud account or KVM host.

## 8. Deliverables of this session

`runbooks/ussuri-to-2026.1-database-fast-forward-lab-runbook.md` (draft, every step tagged; page status
`PROPOSED-UNVERIFIED` because unverified steps exist), this report, and the updates to `HANDOFF.md`, `README.md`,
DR-000 and EXP-SVC-02.
