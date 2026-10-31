# 07 — Red team Stage 5d review: EXP-SVC-02 (operations on Ussuri-created resources under 2026.1)

| Field | Value |
|---|---|
| Author | Agent 7 — Independent Red Team Reviewer |
| Model | Fable 5.1 (claude-fable-5-1). Note: the lab agent for this run (Agent 5b) is also Fable; separate contexts, no shared reasoning. I apply the same method as in Stages 5–5c. |
| Date | 2026-10-31 |
| Status | `DOCUMENTED-UNVERIFIED` for every statement about code (read with `git show`); judgements on evidence are judgements, not re-executions. Nothing run; no file other than this one modified. Bound by the pre-registered criteria (`07-red-team-initial-assessment.md` §4, "Service accepts the DB", "Old objects deserialise") and my Stage 5c conditions (RT-N-30). |
| Inputs read | `experiments/EXP-SVC-02-operations-on-old-resources.md`; `evidence/EXP-SVC-02/strict-r2/` (`results.tsv`, `harness.txt`, `roles-before.txt`, `service-user-roles.txt`, `cinder-service-token-lines.txt`, `service-log-errors.txt`, `vol1-attachment-row-before.txt`, `baseline-manifests.txt`, `rpc-cap.txt`); `strict-r1/` (`INTERRUPTED.txt`, the 409 and `keystonemiddleware` lines) as the source of the failure under investigation only; `lab/ussuri-db-lab/svc/40-exp-svc-02.sh` (strict guard); `git log`/`git diff` of `44846e0`, `3ba36d8`, `1d72dc5`; `cinder@origin/stable/2026.1:cinder/volume/api.py:908-910,2657`, `cinder/exception.py:1112`; `kolla-ansible@origin/stable/2026.1:ansible/roles/cinder/templates/cinder.conf.j2:133`, `ansible/roles/cinder/defaults/main.yml:330-333`; `kolla-ansible` tags. |

Evidence vocabulary: **Confirmed**, **Refuted**, **Unverifiable here**.

---

## 0. Verdict in one paragraph

The cause given for the `strict-r1` failures is **sound and confirmed in source**: Cinder 2026.1 deletes an attachment that Nova owns only when the caller's token carries a role in `[keystone_authtoken] service_token_roles` (`cinder/volume/api.py:908-910`, default `service`), otherwise it raises `ConflictNovaUsingAttachment` (`api.py:2657`, HTTP 409); the migrated Keystone had roles `admin reader member` only (`roles-before.txt`), so Nova's service token was valid but not a *service* token (the `keystonemiddleware` warning in `strict-r1`). The two deviations **reproduce the end state Kolla-Ansible 2026.1 deploys** (`keystone-manage bootstrap` → roles `manager`/`service`, measured in KD-01 C-2; `cinder_ks_user_roles` grants `service`, `cinder.conf.j2:133` sets `service_token_roles_required = true`) and the second one makes the test stricter, not easier: **legitimate, not moved goalposts**. The "lab artefact" label, however, is too comfortable: the missing role is **a procedure dependency** — 2026.1 Cinder requires Keystone state that no Ussuri database contains and that only the deployment tool's registration step creates — so it becomes a mandatory, ordered runbook step with a gate (section 4). `strict-r2`'s 22 OK / 0 FAIL is supported by the evidence, the scope line is honest (Tier A, fake driver, control path only), and `LAB-VALIDATED` is accepted within that scope after two corrections: the Kolla version cited ("20.6.0 (2026.1)") is wrong — 2026.1 is 22.x (`22.2.0` is the latest tag; 20.x is 2025.1) — and the harness-provenance point in section 3. The versioning rule is satisfied in substance by `3ba36d8` (tree clean at run time, content recoverable), with a process note.

---

## 1. Is the cause sound?

| Claim | Result | Evidence |
|---|---|---|
| `strict-r1` detach and resize-with-volume failed with `ConflictNovaUsingAttachment` (409) inside nova-compute's `do_detach_volume`/`_terminate_volume_connections` | **Confirmed** | `strict-r1/results.tsv` fault lines; compute logs quoted in the record |
| cinder-api logged "A valid token was submitted as a service token, but it was not a valid service token" on the same requests | **Confirmed** | `strict-r1` cinder-api lines 19:02:07, 19:02:10 |
| Root cause: no `service` role existed in the migrated Keystone, so Nova's `[service_user]` token had roles `admin, member, reader` and Cinder's `is_service` test failed | **Confirmed in source**: `cinder@origin/stable/2026.1:cinder/volume/api.py:908-910` (`roles = ctxt.service_roles; service_roles = set(CONF.keystone_authtoken.service_token_roles); return bool(roles and service_roles.intersection(roles))`), `:2657` raises `ConflictNovaUsingAttachment` when the volume is attached to a Nova instance and the caller is not a service; `exception.py:1112`. The role set is in `roles-before.txt` (`admin reader member`) | as cited |
| Nothing in the migrated attachment rows is at fault | **Confirmed by the positive test**: the Ussuri-era attachment row of `a-vol1`/`a-vm1` (`vol1-attachment-row-before.txt`, created 11:22 under Ussuri, connector and `connection_info` present) detached and re-attached cleanly in `strict-r2` with 0 service-token warnings (`cinder-service-token-lines.txt` empty) | `results.tsv` rows `volume-detach-of-Ussuri-era-attachment…`, `volume-re-attach…` |
| Fake-driver masking? | **No, for this failure**: the 409 is raised by cinder-api on a control-plane call before any driver code runs; the fake driver only makes the *host-side* detach a no-op, which the scope line states. It does mask whether os-brick could consume the Ussuri-era `connection_info` — correctly listed under "does NOT show". | scope table |
| Alternative causes excluded? | Reasonable: a fresh nova token after the grant carried `service`, and a live detach then succeeded on the `strict-r1` stack; phase 3B's remaining failures are explained (vm in `error` from the earlier resize; same-flavor resize 400; one stale token). I accept the exclusion of (b) driver and (c) data defect. | record §"Cause" |

**Why "lab artefact" understates it.** Ussuri's `keystone-manage bootstrap` created `admin`, `member`, `reader` only; the `service` role and the Nova→Cinder service-token requirement arrived later (Keystone bootstrap adds `manager`/`service` from 2023.2; Cinder's attachment hardening from the CVE-2023-2088 fix). A migrated Ussuri database therefore **always** lacks the state that 2026.1 Cinder requires for detach and for every resize/migration that terminates volume connections. In the Kolla path this state is created by `keystone-manage bootstrap` plus the `service-ks-register` role grants — **if and only if** those tasks run before Nova and Cinder serve traffic. Any deviation from that order (services started from a database-only restore, a partial deploy, a custom tooling path, or `cinder_ks_user_roles` overridden in globals) reproduces `strict-r1` in production. That is a finding about the procedure's ordering, with a user-visible failure (volumes stuck `detaching`, servers in `ERROR` after resize), not a lab accident.

---

## 2. Are the deviations legitimate?

| Deviation | Ruling | Grounds |
|---|---|---|
| D1: `keystone-manage bootstrap` with Kolla's arguments, then `role add --user {nova,cinder,neutron} --project service service` | **Legitimate (reproduces Kolla's deploy end state)**, with two corrections. (a) Cite the right Kolla release: 2026.1 is kolla-ansible **22.x** (`22.2.0`), not "20.6.0" (that is 2025.1). I verified at `origin/stable/2026.1`: `roles/cinder/defaults/main.yml:330-333` grants role `service` to the cinder user in project `service`; KD-01 C-2 measured the bootstrap effect. (b) Kolla grants `service` to **every** service user it registers (glance, placement, cinder, nova, neutron, …), not three; the lab granted three. Sufficient for the operations tested; the record must say the grant set is partial and why. |
| D2: `cinder.conf [keystone_authtoken] service_token_roles_required = true` | **Legitimate and strictly harder**: with `false` (default) an invalid service token is downgraded with a warning; with `true` it is rejected. Kolla sets `true` (`cinder.conf.j2:133`). Matching production's stricter setting cannot move goalposts in the lab's favour. |
| D3: harness changes (remedy phase removed into stack start; detach/re-attach of the Ussuri-era attachment, two resizes with attached volumes including the encrypted one, warning counter; strict guard on uncommitted `lab/` changes) | **Legitimate**: the added operations are exactly my RT-N-30 list (resize-confirm of the `VERIFY_RESIZE` server, stop/start of an Ussuri ACTIVE server, attach/detach, old-user token with application credential, log scan for `IncompatibleObjectVersion`/`ObjectActionError`), plus the Ussuri-era attachment, which is the sharper test. Moving the remedy from a mid-run patch to the stack-start sequence is the right design: it mirrors Kolla's order instead of repairing after the fact. |

**Not a goalpost move** because: the frozen question ("do operations on pre-existing resources succeed through 2026.1 on H4r?") is unchanged; the Keystone additions are not edits to migrated data but the documented deploy-time side effects of the target tool, measured independently (KD-01) before being adopted; and the `strict-r1` failure is kept, labelled, and explained rather than deleted.

---

## 3. Over-claims, scope, evidence, harness provenance

| Point | Ruling |
|---|---|
| Status `LAB-VALIDATED`, 22 OK / 0 FAIL / 6 INFO | **Accepted within the scope line**. `results.tsv` matches; `service-log-errors.txt` shows 0 HTTP 500 / 0 ERROR / 0 object-version errors across 14 logs; `rpc-cap.txt` 6.5 (state (c)/(d) end state, as RT-N-30 required); baseline manifests verified before and after; H4r source never written. |
| Dataset tier "Tier A" | **Correct** (RT-B-11 applied). |
| Scope / "does NOT show" | **Honest and complete**: fake driver makes resize/attach/snapshot host-side no-ops; `connection_info` never consumed by os-brick; encrypted volume = control path only; no Galera, Kolla images, agents other than fake, data plane, broker migration. Add explicitly: "the application-credential token used a **new** credential of a pre-existing user (the pre-existing secrets were not retained by the baseline)" in the scope table, not only in `results.tsv`. |
| "quota enforcement … on Ussuri-created resources" | Supported (bob 5/5 → 403; alice 495 GiB → 413, 1 GiB accepted). |
| Database consistency "not re-checked by a comparator" | Acceptable for an operations experiment; **non-blocking improvement**: run the `same` comparator on the tables the operations do not touch (keystone except `token`/`revocation_event`/`role`/`implied_role`, glance, placement `traits`, neutron `networks`/`subnets`) to show that serving traffic did not rewrite untouched rows (lazy object upgrades, Stage 3 §2.2 point 2). |
| Kolla version citation "kolla-ansible 20.6.0 wheel (2026.1)" | **Refuted — correct to 22.2.0 / 22.x.** KD-01 used 22.2.0 (sha256 recorded); SVC-02 must cite the same artefact or explain the difference. The role defaults are identical at `origin/stable/2026.1`, so the conclusion does not change. |
| Harness provenance: `3ba36d8` is the architect's periodic WIP commit (19:30:43), not a deliberate freeze by the lab agent; `strict-r2` ran 19:37–19:43; `harness.txt` records commit, empty "files changed", script sha256, image id; the script's strict guard refuses uncommitted `lab/` changes; the record commit `1d72dc5` came after the run | **Satisfies the versioning rule in substance.** The rule's purpose (my Stage 5 §6, RT-B-06) is that the exact harness that produced a result is recoverable and unchanged between run and record. Both hold: the tree was clean at run time against a commit that exists, and `git diff 44846e0..3ba36d8 -- lab/` shows the last harness edits (`10-stack.sh`, `40-exp-svc-02.sh`) landed in that commit, before the run. Who pressed "commit" is immaterial to reproducibility. **Process note (non-blocking):** a WIP commit a minute after another WIP commit is an accident of timing; the lab agent should commit its own harness with a message naming the run it is frozen for, so that the freeze is intentional and the message says what changed. |
| "The `strict-r1` run is interrupted, not a result" | **Correct handling**: kept in evidence with `INTERRUPTED.txt`, used only as the failure source. It must stay; it is the only evidence that the dependency of section 1 bites. |

---

## 4. What becomes mandatory in the runbook

Owner: Agent 3 (Kolla text and config), Agent 6 (runbook, gates), Agent 4 (checks). Numbering continues Stage 5c's KD-M series.

| # | When | Step | Gate / verification |
|---|---|---|---|
| KD-M6 | Post-bootstrap, **before** any Nova, Cinder or Neutron container serves traffic | Keystone registration must have run to completion: roles `manager` and `service` exist (created by 2026.1 `keystone-manage bootstrap`, KD-01 C-2); **every** registered service user (nova, cinder, neutron, glance, placement, and every other enabled service) holds role `service` in project `service` (Kolla `*_ks_user_roles`). Who creates it: **Kolla-Ansible's keystone bootstrap and `service-ks-register` tasks**, in `deploy`; nobody creates it on Ussuri. If the deploy order is customised or the services are started by other means, the operator creates them with the 2026.1 admin before starting Nova/Cinder | `openstack role list` contains `service`; `openstack role assignment list --role service --project service` lists every service user; recorded in the evidence. **STOP** if any is missing |
| KD-M7 | Pre-deploy (Ussuri side, read-only) | Check that no pre-existing role named `service` or `manager` with another meaning exists in the Ussuri Keystone (bootstrap would adopt it, and its existing assignments would silently become service-token roles) | `openstack role list` on Ussuri shows neither name; otherwise rename/decide before the window |
| KD-M8 | Config parity (Agent 3) | `cinder.conf [keystone_authtoken] service_token_roles_required = true` and `[keystone_authtoken] service_token_roles = service` (Kolla defaults); Nova `[service_user] send_service_user_token = true` with the nova user's credentials; the same for Neutron and Glance where Kolla sets it | rendered-config diff against Kolla templates at the pinned tag |
| KD-M9 | Post-deploy acceptance, before user traffic | One detach of a pre-existing attachment and one resize-confirm of a server with an attached volume, on a canary tenant; cinder-api log shows **zero** "not a valid service token" lines | the two operations succeed; log count 0. **STOP** on a 409 `ConflictNovaUsingAttachment` |
| KD-M10 | Runbook text | State the failure signature explicitly (volume stuck `detaching`, server `ERROR` after resize, 409 `ConflictNovaUsingAttachment`, `keystonemiddleware` warning) and the remedy (grant `service`, restart the token-holding services so cached service tokens are refreshed — `strict-r1` showed a worker holding a pre-grant token) | — |

---

## 5. Issues

| ID | Type | Finding | Action | Owner |
|---|---|---|---|---|
| RT-B-13 | Blocking for the record's citations (not for the result) | Kolla release cited as 20.6.0 for 2026.1; 2026.1 is 22.x (KD-01 used 22.2.0) | Correct the citation; state which artefact the role defaults were read from | Agent 5b |
| RT-N-31 | Non-blocking | "Lab artefact" wording understates a procedure dependency (section 1) | Reword: "deploy-time Keystone state required by 2026.1 Cinder; created by Kolla's registration tasks; ordering gate KD-M6" | Agent 5b, Agent 6 |
| RT-N-32 | Non-blocking | Only three service users were granted `service`; Kolla grants all | State the partial set in the deviations; grant all in later runs (EXP-SVC-03 or K-01) | Agent 5b |
| RT-N-33 | Non-blocking | Harness freeze made by a WIP commit of the architect | Lab agent commits its own harness with a run-naming message before each strict run; the guard already enforces cleanliness | Agent 5b, Architect |
| RT-N-34 | Non-blocking | No comparator check of untouched tables during service traffic | Add a `same` comparison on untouched tables to EXP-SVC-02's next run or to EXP-SVC-03 | Agent 5b, Agent 4 |
| RT-N-35 | Non-blocking | Application-credential token used a new credential (pre-existing secrets not retained) | Move the statement into the scope table; for Tier B, test a pre-existing credential whose secret the owner holds | Agent 5b |

## 6. What I keep, sharpen or withdraw

- **Keep** the Stage 5c acceptance of EXP-SVC-01 and the DR-003 sequence; SVC-02 ran in its end state (6.5 cap, all hosts re-adopted) and exercised the operations RT-N-30 asked for.
- **Sharpen** RT-B-02 / KD-M series: "every Ussuri client stopped" and "Kolla registration complete" are both **ordering** gates around the first start of 2026.1 Nova/Cinder; SVC-02 supplies the failure signature for the second.
- **Withdraw** nothing.

## 7. Open questions / what I could not verify

- Whether Kolla-Ansible 22.2.0's `deploy` order guarantees `service-ks-register` for cinder/nova/neutron **before** their containers start serving (Agent 3's K-01 or a read of the role task order at the pinned tag); if not, KD-M6 must be an explicit wait.
- Whether os-brick on a real compute consumes the Ussuri-era `connection_info` (needs libvirt; stays `Not validated`).
- Whether any Ussuri-era deployment customised a role named `service` (KD-M7 exists for that reason).
- The exact Kolla artefact the lab read role defaults from (RT-B-13).

Decision support only. Nothing here was executed; statements about code are `DOCUMENTED-UNVERIFIED` from source reading; the status I accept is a judgement against the pre-registered criteria within the record's scope line. The runbook steps named above require the accountable owner's approval under the change process.
