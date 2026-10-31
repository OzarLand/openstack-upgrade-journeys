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
- **Status:** Agent 4 has not yet reviewed this answer. It is asked to confirm or maintain its objection at the
  Stage 5 review.

## Evidence still required

EXP-SVC-01 states (a), (b) and (c), with the conductor log lines that show the RPC version selected in each state.
