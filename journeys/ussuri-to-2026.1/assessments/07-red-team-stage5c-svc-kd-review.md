# 07 — Red team Stage 5c review: EXP-SVC-01 (services on H4r) and EXP-KD-01 (Kolla deploy-time commands)

| Field | Value |
|---|---|
| Author | Agent 7 — Independent Red Team Reviewer |
| Model | Fable 5.1 (claude-fable-5-1) |
| Date | 2026-10-31 |
| Status | `DOCUMENTED-UNVERIFIED` for every statement about code (read with `git show`); judgements on evidence are judgements, not re-executions. Nothing run; no file other than this one modified. Bound by `07-red-team-initial-assessment.md` §4, `07-red-team-stage3-review.md` (RT-B-01/02, V13–V16) and `07-red-team-stage5-results-review.md`. |
| Inputs read | `experiments/EXP-SVC-01-2026.1-services-on-h4r.md`, `evidence/EXP-SVC-01/strict-r1/` (all states, `harness.txt`, `run.log`, `d/f2/f2-report.txt`), `probe-d1-rpc/`, `no-old-clients.txt`; `experiments/EXP-KD-01-kolla-deploy-time-on-h4r.md`, `evidence/EXP-KD-01/strict-r1/` (`c1`, `c2/state-diffs.txt`, `c34/cell-mappings-*.tsv`, `harness.txt`); `architecture.md` §2 P2/§4; `DR-003` incl. Agent 4's response; `assessments/03-kolla-deploy-on-migrated-databases.md` §6; `lab/ussuri-db-lab/svc/20-exp-svc-01.sh` (`sqlforce`); `evidence/commit-sha-mapping.md`; `nova@origin/stable/2026.1:nova/compute/rpcapi.py`, `nova/compute/manager.py` (`_ComputeV5Proxy`). Dry runs (`dry-*`) were not used as evidence, as labelled. |

Evidence vocabulary as before: **Confirmed**, **Refuted**, **Unverifiable here**.

---

## 0. Verdict in one paragraph

Both records are substantively honest and the evidence supports what they claim for the states and commands they tested. The refutation of my Stage 3 prediction for state (a) is **sound for the six operations tested, and my prediction was wrong in its mechanism**: the 2026.1 compute manager still serves a `_ComputeV5Proxy` (target 5.13), so a 5.11-capped control plane talks to a 2026.1 compute without error for the basic lifecycle operations; what the cap still breaks is narrower (section 1). That changes DR-003's *grounds*, not its *decision*: the sequence stays mandatory because state (a) leaves `nova-status` in Failure (Kolla's upgrade check aborts on it), because the proxy is explicitly marked for removal and so release-dependent, and because the experiment found a stronger reason than mine — **the 2026.1 API cannot force-down or clear an Ussuri row at all** (`ServiceTooOld`, HTTP 500), so a host missed before the bridge has no repair path except re-registering it. The SQL `UPDATE` used to build states (a) and (b) on a clone is acceptable **as lab state construction**, with conditions (section 2). Two labelling defects must be corrected before either record may carry `LAB-VALIDATED`: both say "Dataset tier: the Tier-B lab dataset", which is wrong by the mission's own definition (Tier B = production copy; baseline v4 is Tier A, synthetic), and EXP-SVC-01's title and status line claim "serve every pre-existing resource" while only read-back plus Nova lifecycle operations on *new* servers were exercised (no Cinder data-path operation, no Neutron agent, no operation on a *pre-existing* server). With those corrections, both records may carry `LAB-VALIDATED` within their scope lines (section 3). The KD-01 findings turn two of Agent 3's predictions into facts and require four mandatory steps in the deploy runbook (section 4).

---

## 1. State (a): is the refutation sound, and what does it change for DR-003?

### 1.1 What the evidence shows

| Claim | Result | Evidence |
|---|---|---|
| Without the flag, with two unforced version-51 rows, api/conductor/scheduler refuse to start with `TooOldComputeService` (min 51, oldest supported 68) | **Confirmed** | `strict-r1/a/refusal-lines.txt`, `containers-no-flag.txt`; `services-rows-1-unforced.tsv` shows rows 8 and 10 at 51, `forced_down=0` |
| With the flag, the cap is 5.11 (`Automatically selected compute RPC version 5.11 from minimum service version 51`) in nova-api and nova-conductor; `nova-status` "Older than N-1 computes" Failure | **Confirmed** | `a/rpc-cap-3-*.txt`, `a/status-tools-3-flag-restarted.txt` |
| Under the 5.11 cap, server create on the 2026.1 compute and stop/start/reboot --hard/pause/unpause all succeed | **Confirmed** | `a/op-3.txt` (ACTIVE, then five `-> OK`); the "1 err-line" counted by my grep is the heading "compute log (errors since …):" with nothing under it |
| Cause: `_ComputeV5Proxy` in the 2026.1 compute manager | **Confirmed** in source: `nova@origin/stable/2026.1:nova/compute/manager.py:12347-12349`, `target = messaging.Target(version='5.13')`; the manager registers both the 6.x endpoint and this proxy, so a 5.x-capped client's casts/calls are dispatched normally |
| State (d): no cap cached while min service version is 0; `nova-status` Success; cap 6.5 only after compute1 re-registers (72) and is cleared through the API | **Confirmed**, with one caveat: in the strict run the "no cap cached" claim rests on the *absence* of a log line (the cap is computed lazily); the positive DEBUG line "Not caching compute RPC version_cap, because min service_version is 0" exists only in the supplementary `probe-d1-rpc/`, run after the strict run with the same configuration. The record says so; the status table must cite the probe explicitly for that sub-claim. |
| States (b), (c): cap 6.5 from 72, `nova-status` Success, adoption of compute2/3 under their baseline hostnames (`compute_id` file = existing `compute_nodes.uuid`, no duplicate rows), forced-down cleared through the API once the row is at 72 | **Confirmed** | `b/`, `c/` adoption and rpc-cap files, `services-rows-*.tsv` |

### 1.2 Is the refutation sound? Yes, for what was tested; here is what it does not cover

1. **Fake-driver masking.** The RPC dispatch (`oslo.messaging` target/version negotiation, manager endpoint selection) happens before any driver call, so the fake driver cannot mask an RPC version rejection. It does mask everything *after* dispatch (power state, migration, volume attach), which is irrelevant to the RPC-cap question and was never claimed. The refutation of "an RPC-bearing operation fails under 5.11" is therefore sound for the operations tested.
2. **My Stage 3 V15 wording was wrong in one half.** "Methods either raise `MigrationError('Compute too old')` or fall back to 5.x payloads that a 6.x server rejects": the first half stands, the second is refuted — the 6.x server *also* runs the V5 proxy, so 5.x payloads are accepted. I withdraw that half.
3. **What still breaks or degrades at 5.11** (`nova@origin/stable/2026.1:nova/compute/rpcapi.py`): (a) the cross-cell snapshot-based resize family raises `MigrationError`/`MigrationPreCheckError('Compute too old')` when the required 5.x minor is above the cap (`confirm_snapshot_based_resize_at_source`:723, `finish_snapshot_based_resize_at_dest`:833, `finish_revert_snapshot_based_resize_at_source`:872, `prep_snapshot_based_resize_at_source`:1173, `prep_snapshot_based_resize_at_dest`:1134, `revert_snapshot_based_resize_at_dest`:1374) — whether 5.11 is below each method's minimum is **Unverifiable here** without reading each `version=` argument; the record should list them; (b) `prepare_for_alt_rpcserver`:590 falls back from the `compute-alt` topic to the plain topic below 6.5, which loses the graceful-shutdown ordering for revert-resize storage checks (`check_instance_shared_storage`:673) — a semantic regression, not an error; (c) everything added to the 6.x line only (RPC 6.1–6.5 payload fields) is sent in 5.x shape: the proxy translates, with whatever defaults it fills in. None of the six tested operations touches (a)–(c), so the record must not generalise "state (a) does not break operations" beyond "the six basic lifecycle operations on a newly created server".
4. **The proxy is a courtesy, not a contract.** The class comment says "Remove this proxy class in the X release"; it survived to 2026.1, which shows only that upstream has not got round to it. A later release can remove it without notice. A procedure must not depend on it.

### 1.3 Consequence for DR-003

The **decision stands unchanged; its grounds are re-weighted**:

- Gate 1 (start-up refusal without the flag) and gate 2 (the 5.11 cap, `nova-status` Failure) are **both confirmed in the lab** exactly as described in Stage 3 and DR-003.
- Gate 2 is **less dangerous than I predicted** for basic operations in 2026.1 (V5 proxy), and **exactly as dangerous as predicted** for the operational gate: Kolla-Ansible's upgrade/deploy flow runs `nova-status upgrade check` and stops on Failure, and the Failure persists until the last unforced old row is gone *and* the services restart (cache `LAST_VERSION`).
- The experiment adds a **stronger argument for Agent 4's condition 1 than mine**: the 2026.1 API returns HTTP 500 `ServiceTooOld` for `PUT /os-services/<id>` on a version-51 row in **both** directions (`a/api-up-attempt-2.txt`, `-3.txt`). So forced-down **must** be set with the Ussuri API, before the final pre-bridge backup; afterwards the only path for a missed host is to bring a 2026.1 `nova-compute` up under its hostname (row goes to 72) or to accept the flag plus a degraded state. DR-003 "Evidence still required" is now satisfied for states (a)–(d) within the fake-driver scope; the deleted-row refusal path stays "not demonstrable" as recorded.
- Agent 4's sharpening (no flag at all; a refusal is a free verification) is **confirmed by state (a)**: the refusal fired on exactly the two un-forced rows. The flag stays a documented fallback.

Required text change in DR-003/architecture P2: replace "cannot drive 2026.1 computes" (my Stage 3 wording, now refuted) with "runs with a 5.11 cap that `nova-status` reports as Failure, that degrades cross-cell resize and the `compute-alt` topic, and that depends on a proxy class upstream has marked for removal".

---

## 2. The `UPDATE nova.services SET forced_down=…` deviation

**Acceptable as lab state construction, with conditions.** Grounds: the API refused (recorded, both directions); the update touches the one column the Ussuri API force-down call changes (`forced_down`), is restricted to `binary='nova-compute' AND version<72`, is executed on a disposable clone, is logged in `run.log` with before/after rows (`services-rows-*.tsv`), and is declared in the record before the results. It constructs the *same* row state the Ussuri API would have produced (`services-rows-0-pre-start.tsv` of stack d shows the API-produced state from baseline v4 for comparison). It is **not** an SC-HAND violation of the migration procedure, because it is not part of the procedure: it manufactures the negative state (a) that the procedure forbids.

Conditions: (1) the record must say in its status line that states (a) and (b) are "lab-constructed by SQL on a clone", which it does in the deviations list but not in the status table; (2) the production runbook must carry the inverse lesson explicitly: **there is no 2026.1 API path to repair a row that was not forced-down before the bridge**; the pre-bridge check "every `nova-compute` row of a fenced host has `forced_down=1`" is therefore a hard gate (add as PC-N5 to `fast-forward-checks.md`); (3) no further SQL on `services` in any experiment that carries a status, including EXP-SVC-02.

---

## 3. Over-claiming, scope lines, sufficiency for `LAB-VALIDATED`

### 3.1 EXP-SVC-01

| Point | Ruling |
|---|---|
| "Dataset tier: the Tier-B lab dataset of the Ussuri baseline v4" | **Refuted — must be corrected.** The mission's vocabulary (my criterion B.3, architecture §4 "Production prerequisite") defines Tier B as a sanitised copy of the production databases. Baseline v4 is Tier A (synthetic, through Ussuri APIs). The word "Tier-B" here would let a reader believe the production-copy prerequisite is met. Same defect in EXP-KD-01. |
| Title and status line: "serve every pre-existing resource" | **Over-claim.** What was shown: read-back (list/show) of every pre-existing resource with 0 undeclared differences and 0 HTTP 5xx; auth for two users; EC2/TOTP decrypt; image checksums; a write test; six lifecycle operations on **newly created** servers; compute adoption. Not shown: any operation on a pre-existing server (resize confirm of the `VERIFY_RESIVE` server, stop/start of an Ussuri-created ACTIVE server), any Cinder data-path call (attach/snapshot — `cinder-volume` runs but no operation was issued), any Neutron port binding (no agents). Those are EXP-SVC-02's job; the SVC-01 title must say "start on … and read back every pre-existing resource". |
| `LAB-VALIDATED` for (b), (c), (d), F2, C-5 | **Accepted within the scope line**, after the two corrections above and the probe citation (section 1.1). The scope line and "does NOT show" list are otherwise complete and honest, including the lab driver (`ufj_fake2026.py`) and the eleven configuration changes. |
| State (a) "REFUTED" | **Accepted**, reworded as in section 1.2 point 3: "refuted for server create, stop, start, reboot, pause, unpause on a newly created server; cross-cell resize paths and the `compute-alt` fallback not tested". |
| Evidence sufficiency | Sufficient: harness commit and script hash recorded (`harness.txt`, clean tree), live `run.log`, per-state row dumps, RPC log lines, status-tool outputs, F2 report with the one declared difference and its migration cause (`5bcb7b31ec7d`), `no-old-clients.txt` proving RT-B-02's precondition (Ussuri containers stopped). The history rewrite did not change file hashes (`commit-sha-mapping.md`); the SVC record cites the harness SHA as it stood, which is acceptable since the mapping file exists. |
| Findings 2 and 5 (cap exists only with `[upgrade_levels] compute = auto`; eleven config changes incl. RabbitMQ 4.4 quorum queues, `oslo_cache.memcache_pool` gone, `AvailabilityZoneFilter` gone, `[service_user]` needed) | **Important and correctly flagged.** Finding 2 means a deployment *without* `compute = auto` has no second gate at all — Kolla templates `auto`, so production has it; the record should say which applies to the target. Finding 5 belongs in Agent 3's configuration-transformation deliverable as mandatory items. |

### 3.2 EXP-KD-01

| Point | Ruling |
|---|---|
| "Tier-B lab dataset" | **Refuted — correct to Tier A** (as above). |
| C-1: eleven Kolla deploy-time commands, two passes, 0 differences each | **Confirmed** (`c1/diff-s0-s1.txt`, `diff-s1-s2.txt`, `steps.tsv`). This closes my Stage 3 V18 requirement (idempotency of every 2026.1 sync under Kolla's bootstrap) for the commands as listed by Agent 3 — not for Kolla's actual invocation, which the scope line says. |
| C-2: `keystone-manage bootstrap` side effects | **Confirmed** (`c2/state-diffs.txt`): roles `manager` and `service` created; implied role `admin→member` replaced by `admin→manager`, `manager→member`; password reset when the supplied password differs (new `password` row, old password 401, `revocation_event` grows); endpoint URLs rewritten when they differ. |
| C-3/C-4: `extract_cell('')` returns None for a cell named `cell1`; `create_cell` exits 2 while either string matches, and creates an unnamed second mapping on the same database when both differ | **Confirmed** (`c34/cell-mappings-3-after-iii.tsv`: id 3, name NULL, same database). |
| `LAB-VALIDATED` | **Accepted within the scope line** after the Tier correction. The scope is narrow and says so (commands typed by hand from Agent 3's table; Kolla-Ansible and Kolla images not run; heat/horizon absent). The record must not be cited as "Kolla deploy validated"; it validates the *database effect of the commands Agent 3 says Kolla runs*. Whether Kolla runs exactly those commands with those arguments remains `DOCUMENTED-UNVERIFIED` (Agent 3's source reading) until K-01. |

---

## 4. What the KD-01 findings make mandatory in the deploy runbook

Two of Agent 3's predicted traps are now facts (C-3/C-4, C-2). In a real migration both the RabbitMQ URL and the database address change (new controllers, new broker), which is exactly case (iii): a silent second cell mapping on the same database, after which `extract_cell('')` returns the duplicate and every later Kolla run addresses the wrong mapping. The following become **mandatory steps** (owner: Agent 3 for the Kolla text, Agent 6 for the runbook, Agent 4 for the checks):

| # | When | Step | Verification |
|---|---|---|---|
| KD-M1 | Pre-deploy, after the fast-forward, before any Kolla run | Record `nova-manage cell_v2 list_cells --verbose` (names, uuids, URL hosts masked); set `nova_cell_name` in Kolla globals to the **stored** cell name (here `cell1`; production: whatever the Ussuri deployment used — Kolla Ussuri's default was `''`, so read it, do not assume) | `extract_cell(<name>)` of the pinned kolla-ansible wheel returns the stored uuid |
| KD-M2 | Pre-deploy | Update the stored cell1 mapping to the new transport URL and database connection with `nova-manage cell_v2 update_cell --cell_uuid <uuid> --transport-url … --database_connection …` (supported tool), so that Kolla's `create_cell` branch is never taken | `list_cells` shows the new hosts; cell count unchanged |
| KD-M3 | Post-deploy gate | `SELECT id, uuid, name FROM nova_api.cell_mappings` = exactly cell0 plus the one named cell; **any mapping with `name IS NULL` or a third row = STOP** and remove it with `delete_cell` before any instance is scheduled (an unnamed duplicate receives scheduling and ODM traffic for the same database twice) | query result in the evidence |
| KD-M4 | Pre-deploy | `keystone_admin_password` in `passwords.yml` **equals** the existing Ussuri admin password (preserved `passwords.yml`, 03-config P4); otherwise bootstrap resets it, invalidates every admin token (`revocation_event` growth) and breaks every service account or automation that still holds the old one. Declare and accept the expected role changes (`manager`, `service` roles; implied-role chain `admin→manager→member`, functionally equivalent for `member` by transitivity) and the endpoint URL rewrite to the new VIP | post-bootstrap diff of `role`, `implied_role`, `endpoint`, `password` = exactly the declared set |
| KD-M5 | Post-deploy | Second `deploy` (or `reconfigure`) must produce **zero** database change (K-07) — C-1 shows the commands are idempotent, which makes this check cheap and decisive | comparator `same` = 0 |

Policy note on KD-M4: a deployment that customised `policy.yaml` around the implied role `admin→member` should verify its policies against the new chain before go-live; this is Agent 3's item.

---

## 5. Issues

| ID | Type | Finding | Action | Owner |
|---|---|---|---|---|
| RT-B-11 | Blocking for the `LAB-VALIDATED` label of both records | "Tier-B" used for the synthetic v4 dataset in EXP-SVC-01 and EXP-KD-01 | Correct to "Tier A (synthetic, Ussuri APIs)" in both records; grep every record for "Tier-B"/"Tier B" and keep the term for production copies only | Agent 5, Agent 8 (convention) |
| RT-B-12 | Blocking for the SVC-01 label | Title/status "serve every pre-existing resource" exceeds the evidence (read-back + new-server operations) | Retitle "start on the fast-forwarded databases and read back every pre-existing resource"; move operations on pre-existing resources to EXP-SVC-02 as already planned | Agent 5 |
| RT-N-25 | Non-blocking | State (d) "no cap cached" positive evidence is only in `probe-d1-rpc/` | Cite the probe in the status table; run the strict re-run at DEBUG for `nova.compute.rpcapi` | Agent 5 |
| RT-N-26 | Non-blocking | DR-003/P2 text still carries my refuted wording ("cannot drive 2026.1 computes") | Replace per section 1.3; list the 5.11-capped failure/degradation paths of section 1.2 point 3 | Architect |
| RT-N-27 | Non-blocking | PC-N5 missing: "every fenced host's `nova-compute` row has `forced_down=1` before the final pre-bridge backup" (no 2026.1 repair path) | Add to `fast-forward-checks.md` §4 | Agent 4 |
| RT-N-28 | Non-blocking | KD-M1…M5 not yet in the Kolla deploy text or the runbook | Write them; KD-M3 and KD-M5 as named stop conditions | Agent 3, Agent 6 |
| RT-N-29 | Non-blocking | SVC-01 finding 5 (eleven config changes for 2026.1 on Ussuri-rendered files) is lab knowledge that production needs | Fold into `03-configuration-transformation.md` as mandatory transformations with sources | Agent 3 |
| RT-N-30 | Non-blocking | EXP-SVC-02 must test under the **6.5** cap only (state (c) end state) and must include: resize-confirm of the Ussuri-created `VERIFY_RESIZE` server, stop/start of an Ussuri-created ACTIVE server, a volume attach/detach with the fake backend, a token for a pre-existing user with pre-existing application credential, and a log scan for `IncompatibleObjectVersion`/`ObjectActionError` (Stage 3 §6) | Design before run | Agent 5 |

## 6. What I withdraw, keep or sharpen

- **Withdraw** the second half of Stage 3 V15 ("5.x payloads that a 6.x server rejects"): the 2026.1 compute manager serves a V5 proxy. The RPC cap is real; its consequence in 2026.1 is `nova-status` Failure plus the narrower breakage of section 1.2, not a general inability to operate.
- **Keep** ruling 1 of Stage 3 and DR-003 Option C; the grounds are now (i) gate 1 confirmed, (ii) `nova-status` Failure confirmed, (iii) no 2026.1 API repair path for old rows (new, stronger than my original argument), (iv) proxy removal risk.
- **Sharpen** RT-B-02: `no-old-clients.txt` is the right kind of evidence for "every Ussuri client stopped"; the production version of it is per host (`docker ps`, `rabbitmqctl list_consumers` empty), as written.

## 7. Open questions / what I could not verify

- The exact 5.x minor each cross-cell resize RPC method requires (whether 5.11 is below it); the record or Agent 4 should list them from `rpcapi.py`.
- What `_ComputeV5Proxy` fills in for 6.x-only parameters when translating 5.x calls (reading the proxy body was out of this review's budget).
- Whether Kolla-Ansible 22.2.0 passes exactly the arguments Agent 3's table lists to `keystone-manage bootstrap` and `nova-manage cell_v2` (needs K-01 or a read of the role tasks at the pinned tag).
- Whether Kolla Ussuri's default `nova_cell_name` was `''` in the target deployment (production must read `list_cells`, not assume).

Decision support only. Nothing here was executed; statements about code are `DOCUMENTED-UNVERIFIED` from source reading; the statuses I accept are judgements against the pre-registered criteria within the records' scope lines. State-changing runbook steps named above (`update_cell`, `delete_cell`, password alignment) require the accountable owner's approval under the change process.
