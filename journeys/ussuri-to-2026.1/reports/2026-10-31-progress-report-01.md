# Consolidated progress report 01 — Ussuri → 2026.1

| Metadata | |
|---|---|
| Author | Agent 1 — OpenStack Upgrade Architect (Opus) |
| Date | 2026-10-31 |
| Period | Mission start to the first lab-validated result |
| Branch | `claude/epic-pascal-2kqc98` |

## 1. Completed work

| Stage | Work | Where |
|---|---|---|
| Phase 1 — repository assessment | Inventory of the three OzarLand repositories. This repository was scaffolded on OzarLand conventions: README, CONTRIBUTING, validation statuses and templates. | `assessments/01-*`, `08-*`, root files, `docs/` |
| Agents and models | Eight roles plus an inventory assistant. Model allocation recorded with its limits. | DR-000 |
| Phase 2 — laboratory | Quick-lab cannot run here: no cloud account, no Kolla Ussuri images, no KVM. A container control plane was built from upstream Ussuri code instead, with a baseline populated through the APIs, captured fenced and forced-down, and with restore proven. A quick-lab Ussuri profile patch is drafted. | DR-001, `lab/`, `assessments/05-*`, EXP-DB-00 |
| Stage 1 — independent investigations | Release compatibility, Kolla-Ansible, database and messaging, operations, initial Red Team assessment. | `assessments/02-07`, `compatibility-matrix.md`, `dependency-graph.md` |
| Stage 2 — architecture | Proposals P1–P4, comparison matrix, experiment plan. | `architecture.md` |
| Stage 3 — Red Team review | Five blocking issues found and resolved before experiments started. Nova gate mechanism decided. | `07-red-team-stage3-review.md`, DR-003 |
| Stage 4 — experiments | EXP-DB-00, N1, R0 and EXP-DB-01 (failed, root-caused, then a strict re-run passed). | `experiments/`, `evidence/` |
| Stage 5 — independent validation | Red Team review of the results. The evidence-integrity issue was resolved. Amendments 1 and 2 were accepted. | `07-red-team-stage5-results-review.md` |

## 2. Important findings

1. **A single direct jump is incompatible.** This was shown in the lab (EXP-DB-N1, FAILED as predicted). Nova,
   Keystone and Cinder 2026.1 have no code path for a legacy (pre-Alembic) database. They try to create the schema
   from scratch, stop on `Table already exists`, and leave an empty `alembic_version` table behind. That leftover
   table becomes a pre-check item (PC-V3).
2. **Intermediate code must run; intermediate deployments need not.** Only Xena–2023.1 code (Nova, Cinder) and
   Zed–2023.1 code (Keystone) can move a legacy database onto Alembic. 2023.1 is the common bridge (DR-002).
3. **Released code differs from branch heads.** The last 2023.1 Cinder release (22.3.0) skips soft-deleted rows in
   the `use_quota` online data migration. The fix exists only on the branch and in cinder 23.5.0 (2023.2). Without it,
   the 2024.1 migration fails, **on the supported path too**. Fix adopted: a Cinder-only 23.5.0 step plus a hard gate
   (DR-004). Process lesson: every claim is now checked at the installed release tag.
4. **The database fast-forward works in the lab, within a narrow scope** (VAL-001, `LAB-VALIDATED`, technically
   possible but unsupported). The path is: Ussuri, then 2023.1 for all services, then Cinder 23.5.0, then 2024.1,
   2025.1 and 2026.1. MariaDB is upgraded stepwise from 10.3 to 11.4. The run ended with 0 undeclared schema or data
   differences at every hop, and a second 2026.1 pass changed nothing.
5. **Data patterns that are valid in Ussuri break later migrations on any path.** Two examples:
   - two VLAN segments on the same physical network (Neutron Yoga migration `e981acd076d3`);
   - error volumes without a service, which make `cinder-status` fail.
   Both are now pre-checks, with remedies through the API.
6. **Nova 2026.1 accepts no compute older than Epoxy, and its RPC cap is a second gate.** Decision: fence the old
   computes, mark them forced-down through the Ussuri API, start 2026.1 without the workaround flag, then re-adopt each
   host under the same name (DR-003; still to be tested in EXP-SVC-01).
7. **The Ussuri Kolla images are no longer anonymously pullable** (HTTP 401, observed here). Rollback depends on a
   private mirror taken before the change.
8. **Operations.** No Kolla-Ansible release supports both the Ussuri and the 2026.1 host OS, so every host changes OS.
   The supported staircase P1 means 9 upgrades and 3 OS changes per host.

## 3. Experiments executed

| ID | Status | Note |
|---|---|---|
| EXP-DB-00 | LAB-VALIDATED (restorability) | Baselines v1–v4, coverage gaps listed |
| EXP-DB-N1 | FAILED (as predicted) | Confirms finding 1 |
| EXP-DB-R0 | LAB-VALIDATED (calibration, after correction) | Produced amendments A1–A6; the Red Team added A7 |
| EXP-DB-01 R1 | FAILED | Stop conditions: Neutron segments, Cinder `use_quota`, `cinder-status`. Comparator integrity issue (RT-B-06) disclosed and reconstructed |
| EXP-DB-01 strict R2 | LAB-VALIDATED | VAL-001; harness `2f3e48a` |

## 4. Current blockers

- No cloud account or KVM, so there is no Kolla-Ansible lab: Kolla playbooks, configuration transformation, host OS
  and the data plane cannot be tested here.
- No production dataset (Tier B), which is a prerequisite for any production decision.
- Docker Hub rate limits. Images come through a mirror, with digests recorded.

## 5. Technical disagreements, all recorded

- **Keystone bridge window** (Agent 2 vs Agent 4). Resolved from source in favour of Agent 2 (DR-002).
- **Forced-down to pass the Nova gate** (Agent 4 objected). Resolved by the Red Team's ruling. Agent 4 withdrew its
  objection with four conditions and sharpened the mechanism (DR-003).
- **Red Team Stage 3 verification V6** (read at the branch head) was corrected by Agent 4's lab reproduction; the Red
  Team accepted the correction.

## 6. Decisions required from the owner

1. **Commit attribution.** This session adds `Co-Authored-By:` and `Claude-Session:` lines, but the OzarLand rules
   (`ozarland/docs/agents.md`, the skills `CLAUDE.md`) say commit messages stay plain. Keep, or rewrite the branch
   history?
2. Whether to report the Cinder 2023.1 → 2024.1 `use_quota` issue upstream or to the OzarLand community (no action
   taken).
3. Whether to add `FAILED` to the shared OzarLand status vocabularies.
4. Access to a cloud account (or a KVM host) and a registry mirror for the Kolla-Ansible Ussuri lab.

## 7. Next actions (proposed order)

1. **EXP-SVC-01 and EXP-SVC-02.** Start 2026.1 services on the H4r database from VAL-001: Nova gate states (a)–(d),
   then read back every pre-existing resource and operate on it.
2. **EXP-RB-01.** Rollback rehearsal from the pre-bridge dump.
3. **EXP-DB-N2, EXP-DB-02 and EXP-DB-03.** Cinder skip, full staircase differential, minimal path. Also the E2 engine
   line (dump and restore) and the bridge code on 11.4.
4. Agent 6 and Agent 3: update the operational and Kolla plans with DR-003 and DR-004, then define the Kolla-Ansible
   2026.1 deployment step on top of migrated databases.
5. Red Team Stage 5 review of each new result. No runbook is written until the service-level and rollback experiments
   have results (mission rule).
6. Skills: assess whether `openstack-upgrade-engineering` is warranted, or whether `openstack-change-review` (upgrade
   readiness) and `openstack-kolla-ansible-operations` should be extended. The first candidate content is the
   "verify at the installed tag" rule, migration bridge windows, and data pre-checks.
