# DR-003 — Crossing Nova's service-version gate after a database fast-forward

| Field | Value |
|---|---|
| Decision ID | DR-003 |
| Date | 2026-10-31 |
| Responsible agent | Agent 1 — Architect, adopting the Red Team ruling (Agent 7, Stage 3, ruling 1) |
| Validation status | `PROPOSED-UNVERIFIED`. Experiment EXP-SVC-01 must test it, states (a), (b) and (c). |

## Context

Nova 2026.1 sets `OLDEST_SUPPORTED_SERVICE_VERSION = 'Epoxy'` (`nova@origin/stable/2026.1:nova/objects/service.py`).
After the fast-forward, the database still contains Ussuri `nova-compute` service rows at version 51. The Red Team
showed in source that this is **two** gates:

1. **Start-up:** `nova/service.py` and `wsgi_app.py` refuse to start. Only this gate reads
   `[workarounds]disable_compute_service_check_for_ffu`.
2. **Compute RPC cap:** derived from the same minimum-service-version query. It maps version 51 to RPC `5.11` and is
   cached in `LAST_VERSION` for the life of the process. 2026.1 computes serve RPC 6.x, so a control plane started
   with the workaround while non-forced-down Ussuri rows exist cannot drive 2026.1 computes.

## Alternatives

| Option | For | Against |
|---|---|---|
| A. Workaround flag only (Agent 4's preference) | Changes no database state | Does not cross gate 2. Fails as soon as an RPC-bearing operation runs. |
| B. Delete old service and compute-node rows | Clears both gates | Destroys state. Breaks node adoption when the host returns under the same name (`_ensure_existing_node_identity`) and orphans instances. Rejected. |
| C. Fence, then forced-down, then start with the workaround as a time-boxed safeguard, re-adopt each host, clear forced-down, remove the workaround and restart control services (chosen) | Forced-down excludes rows from both queries without deleting them. It records a state that fencing has already made true. | The rows change state. Automation (auto-evacuation) could act on forced-down hosts, so it must be disabled for the window. Local-disk hosts must never be evacuated. |

## Decision

Option C, in the sequence written in `architecture.md` §2 P2.

## Dissent

Agent 4 (database and messaging) argued in Stage 1 against using forced-down to pass the gate, because it changes real
state (`assessments/04-database-migration-strategy.md` §2, risk 2).

- **Answer:** forced-down is applied only after fencing has been verified, so it asserts a true fact rather than
  bypassing a check. Deleting rows, which Agent 4 rightly objected to, remains forbidden.
- **Status:** resolved. Agent 4 withdrew its objection with four conditions and proposed running without the
  workaround flag (see its response below). The architect adopted both on 2026-10-31: the conditions are in
  `architecture.md` §2 P2, and the flag is now a fallback rather than a default. EXP-SVC-01 gains state (d).

## Evidence still required

EXP-SVC-01 states (a), (b) and (c), with the conductor log lines that show the RPC version selected in each state.

## Agent 4 response (2026-10-31)

Agent 4 — Database and Messaging Specialist (Opus). Status of this response: source reading only (`PROPOSED-UNVERIFIED`).

**I accept Option C and withdraw my objection, with four conditions.** My objection (strategy §2, risk 2) was against using
`forced_down` *to get past a check*. The Red Team showed that the flag alone does not cross gate 2 (V15). I had
not identified that. Under Option C, `forced_down` is set only after fencing has been verified, so it records a true
state instead of hiding one. Deleting rows stays forbidden, which was the core of my concern.

**A sharpening that makes the workaround flag unnecessary (please test it in EXP-SVC-01).** With every Ussuri
`nova-compute` row forced-down, both gates see **no** compute service:

- `service_get_minimum_version` excludes forced-down rows (`nova@origin/stable/2026.1:nova/db/main/api.py:427-436`);
  `get_minimum_version_all_cells` returns `0` when no row qualifies (`nova/objects/service.py`, end of the function).
- `raise_if_old_compute()` returns early when the minimum is 0 ("no compute in the system",
  `nova/utils.py:1035-1083`), so API, conductor and scheduler start **without** `disable_compute_service_check_for_ffu`,
  and `nova-status` "Older than N-1 computes" returns SUCCESS (it calls the same function).
- `_determine_version_cap()` does **not cache** when the minimum is 0 and uses the current RPC version
  (`nova/compute/rpcapi.py:530-538`). `LAST_VERSION` is first cached when a re-registered 2026.1 compute has had its
  forced-down flag cleared, at version 72 → RPC 6.x. Note that clearing `forced_down` on a host that is still Ussuri
  would cache 5.11 again. The per-host order "start 2026.1 compute, verify, then clear" is therefore mandatory.

Recommendation: **do not set the flag at all.** If a 2026.1 control-plane service then refuses to start with
`TooOldComputeService`, that refusal proves some old row was not forced-down. It is a free verification, and the flag would hide it.
Keep the flag only as a documented fallback that needs a separate decision. This also removes the Kolla-Ansible `nova-status`
abort without skipping any check.

**Conditions**

1. Forced-down is applied **through the Nova API** (`openstack compute service set --down <host> nova-compute`,
   microversion ≥ 2.11), never by SQL. Since the 2026.1 API cannot be used before the gate is crossed, apply it with the
   **Ussuri** API after fencing and **before** the final pre-bridge backup. The backup then contains the flags. The
   Ussuri rollback runbook (EXP-RB-01) must clear them per host after the Ussuri computes are back.
2. The pre-change state of every `services` row (`id, host, binary, version, disabled, disabled_reason, forced_down,
   updated_at`) is captured in the run record. Per host, the evidence that it is fenced (`nova_compute` container
   stopped and not restarting; Neutron/Cinder agents stopped) is captured **before** its row is forced down.
3. Auto-evacuation (Masakari, custom automation) is disabled for the window. Hosts with local-disk instances are never
   evacuated while forced down. Any host not re-adopted in the window stays forced down **and** disabled, with a reason.
4. `forced_down` is cleared per host only after the 2026.1 compute has re-registered (version 72), adopted its node
   (`_ensure_existing_node_identity`) and passed the per-host check. After the last host, restart API, conductor and
   scheduler once and verify the conductor log shows a 6.x compute RPC version.

EXP-SVC-01 should add a state **(d)**: all Ussuri rows forced-down, flag **not** set → services start, `nova-status` 0,
no RPC cap cached; then one host re-registered and cleared → cap 6.x.
