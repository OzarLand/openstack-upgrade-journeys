# Handoff — how to resume this journey

Last updated: 2026-10-31 (end of session 1), by Agent 8b (documentation, Fable). Previous update 16:35 UTC by the
architect (Agent 1). Read this first if you are a new session or a new contributor picking the work up.

## Where the work stands

| Item | State |
|---|---|
| Question | Can a Kolla-Ansible Ussuri cloud reach 2026.1 without deploying every intermediate release? |
| Direct jump | **Incompatible**: EXP-DB-N1 failed, as predicted. |
| Database fast-forward | **`LAB-VALIDATED`** in a narrow scope (VAL-001). Path: Ussuri → 2023.1 (all services) → Cinder 23.5.0 (2023.2) → 2024.1 → 2025.1 → 2026.1; MariaDB 10.3 → 11.4 stepwise. Technically possible but unsupported. Re-derived strictly at 15:26 UTC (`evidence/EXP-DB-01/derive-h4r/`). |
| EXP-SVC-01 (2026.1 services on the migrated database) | **`LAB-VALIDATED`** for states (b), (c), (d), the F2 read-back and compute adoption; the Red Team prediction for state (a) is refuted for six basic operations. Red Team Stage 5c accepted it after the Tier-A and title corrections. |
| EXP-KD-01 (Kolla deploy-time commands on H4r) | **`LAB-VALIDATED`** for the commands run by hand (C-1..C-4). Kolla-Ansible itself never run. Mandatory steps KD-M1..KD-M5 (Stage 5c). |
| EXP-SVC-02 (operations on Ussuri-created resources) | **`LAB-VALIDATED`**, `strict-r2`, 22/22 OK (Agent 5b, Fable). The `strict-r1` failures were the missing Keystone `service` role that Kolla creates at deploy time: a procedure dependency, now KD-M6..KD-M10 (Stage 5d). Corrections RT-B-13 and RT-N-32 appended to the record. |
| Runbook | **Draft** `runbooks/ussuri-to-2026.1-database-fast-forward-lab-runbook.md`: every step tagged; page status `PROPOSED-UNVERIFIED` because Kolla, Galera, host OS, real computes and rollback were never run. |
| Final report | `reports/2026-10-31-final-report-session-1.md` |
| Next experiments | EXP-RB-01 (rollback rehearsal; the runbook's recovery section is unverified until then), EXP-DB-02/03, N2, engine E2, EXP-SVC-03 (RT-N-32/34/35), then the Kolla lab K-01..K-08 and Tier B. Red Team review of each. |
| Not testable in this environment | Kolla-Ansible itself, Galera, host OS, data plane, real VMs, production data. The owner deferred the real lab ("plus tard"). |
| Agents | The Sonnet lab agent (Agent 5) was stopped for budget reasons. **The lab now runs on Fable agents** (Agent 5b), as do documentation (Agent 8b) and the Red Team (Agent 7): same model, separate contexts, reduced independence recorded in DR-000. |

Read, in this order:

1. `README.md`
2. `reports/2026-10-31-final-report-session-1.md`, then `reports/2026-10-31-progress-report-01.md`
3. `architecture.md` (§2 P2 and §4)
4. `decision-records/DR-000` to `DR-004`
5. `experiments/declared-differences.md`, frozen with Amendments 1 and 2
6. `experiments/fast-forward-checks.md`
7. The Red Team reviews in `assessments/07-*` (Stage 5d defines KD-M6..KD-M10)
8. `runbooks/ussuri-to-2026.1-database-fast-forward-lab-runbook.md`

Next steps for the next session, in order: (1) assign VAL ids to EXP-SVC-01, EXP-KD-01 and EXP-SVC-02; (2) add PC-N5 to
`fast-forward-checks.md` §4 and the RT-N-26 wording to DR-003 and `architecture.md`; (3) EXP-RB-01; (4) the remaining
Red Team follow-ups (RT-N-29, RT-N-32..35); (5) the skills decision.

## Rules in force (do not relax them)

- **Every result runs on a copy.** Never touch the baselines under `lab/ussuri-db-lab/backups*/`. Each holds a
  `MANIFEST.sha256`: verify it before and after each run, from inside the baseline directory.
- **Commit the harness under `lab/` before every strict run** and record the SHA in the experiment record. Never edit
  the harness between a run and its record. Any stop condition makes the run `FAILED`, recorded with its live outputs.
- **The declared-differences list is frozen.** It changes only by a versioned amendment that the Red Team accepts.
- **Check migration code at the installed release tags, never at branch heads** (lesson of DR-004).
- **Commits:** plain messages and `git commit -s`. Author and sign-off are the owner's (Soufian Zaouam, GitHub
  noreply address, set in the repository config). No AI or session trailers. The branch history was rewritten on
  2026-10-31; old SHAs map to new ones in `evidence/commit-sha-mapping.md`.
- **No secrets in git.** `.secrets/`, `.run/` and `backups*/` are git-ignored.

## How to restart the lab (Docker host)

```bash
# If the Docker daemon is down (container restart):
dockerd > /tmp/dockerd.log 2>&1 &
cd lab/ussuri-db-lab
cat README.md            # ufj.sh subcommands: build, up, populate, capture, restore, verify, ff ..., destroy
(cd backups-v4/latest && sha256sum -c MANIFEST.sha256)
```

- **Migrated 2026.1 database:** volume `ufj-ff-derive-h4r-data`, with a durable copy in
  `backups-ff/derive-h4r-datadir-mariadb11.4.tgz` (git-ignored; sha256 beside it). Every SVC/KD run clones it
  (`svc/10-stack.sh clone`); the source is never written.
- **2026.1 runtime:** `lab/ussuri-db-lab/svc/` (`10-stack.sh up` renders, starts Keystone, runs the Kolla-equivalent
  `keystone-manage bootstrap` and the `service` role grants, then the other services; `20-exp-svc-01.sh`,
  `30-exp-kd-01.sh`, `40-exp-svc-02.sh`). Strict labels refuse to run with uncommitted `lab/` changes; the lab agent
  commits its own harness with a run-naming message before each strict run (RT-N-33).
- **Container stopped at Ussuri:** the `ufj-*` Ussuri control plane must stay stopped while 2026.1 services run. This
  is the no-old-clients precondition.

Machine-local files under `lab/ussuri-db-lab/{.secrets,.run,backups*}` are lost if the container is reclaimed. They
can be rebuilt with `./ufj.sh all` and the documented baseline derivation (EXP-DB-00 v1 → v4). The resulting
checksums will differ, so a rebuild needs a new baseline record.

## Decisions the owner already took

- History rewritten without AI trailers; sign-off in the owner's name.
- The Cinder `use_quota` bug is documented in this repository
  (`troubleshooting/cinder-use-quota-null-blocks-2024.1-db-sync.md`), not reported upstream for now.
- The real Kolla-Ansible lab (cloud account or KVM host) is postponed.
- The Sonnet lab agent was stopped for budget reasons; Fable agents took over the lab and the documentation (DR-000).

## Open decisions

- Whether to add `FAILED` to the shared OzarLand status vocabularies.
- The relation of this repository to the planned `openstack-upgrade-playbooks`.
- Skills: whether to create `openstack-upgrade-engineering`, or to extend `openstack-change-review` and
  `openstack-kolla-ansible-operations`.

## Agent roles and models

See `decision-records/DR-000-agent-team-and-model-allocation.md`.
