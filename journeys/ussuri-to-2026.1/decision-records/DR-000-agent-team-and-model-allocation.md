# DR-000 — Agent team and model allocation

| Field | Value |
|---|---|
| Decision ID | DR-000 |
| Date | 2026-10-31 |
| Responsible agent | Agent 1 — OpenStack Upgrade Architect |
| Status | Decided (organizational; no technical validation applies) |

## Context

The mission requires a multi-agent team with independent responsibilities, and the strongest available reasoning
models for architecture, database migration, compatibility analysis and independent review.

The orchestration capability used here is the Claude Code `Agent` tool. Inspected on 2026-10-31, it accepts four
models: `fable`, `opus`, `sonnet` and `haiku`. The environment lists them as the Claude 5 family: Fable 5.1, Opus 5.5,
Sonnet 5.5 and Haiku 5.5. The architect runs as the main session on Opus 5.5 (confirmed through the session API:
`session_context.model` and `last_served_model` both `claude-opus-5-5`).

What is known about the models, and what is not:

- **Opus:** the strongest reasoning model whose behaviour the architect knows from direct experience. It is used for
  long, source-heavy analysis.
- **Sonnet:** strong at coding and execution, and faster and cheaper than Opus.
- **Haiku:** fast and economical. Suited to inventories and repetitive extraction.
- **Fable 5.1:** newest model in the family. Nothing about its relative reasoning strength was available in this
  environment. It is listed first in the family.

## Alternatives considered

1. **Opus for every critical role, including the Red Team.** Strong, but the Red Team would share the architect's
   model, so it would also share its blind spots.
2. **Fable for the Red Team, Opus for the other critical roles (chosen).** Model diversity gives the Red Team real
   independence from the architect.
3. **Sonnet for the specialists, to save cost.** Rejected for the database and compatibility roles: the mission
   forbids lightweight models for critical decisions, and these two roles carry the data-integrity decisions.

## Decision

| Agent | Role | Model assigned | Rationale |
|---|---|---|---|
| 1 | OpenStack Upgrade Architect | Opus 5.5 (main session) | Highest known reasoning. Coordinates and owns the final architecture. |
| 2 | Release Compatibility Expert | Opus | Long, source-heavy release analysis across 13 series. |
| 3 | Kolla-Ansible Specialist | Opus | Reasoning plus code reading across 13 Kolla-Ansible series. |
| 4 | Database and Messaging Specialist | Opus | Data-integrity critical; must critique schema transformations. |
| 5 | Laboratory and Automation Engineer | Sonnet | Strong coding and execution; builds and runs the lab. |
| 6 | Operations and Reliability Expert | Sonnet | High reasoning, guided by the OzarLand skills. Its conclusions are re-checked by the Red Team. |
| 7 | Independent Red Team Reviewer | Fable | Independent of the architect's model. Starts without reading the other agents' work. |
| 8 | Documentation and Community Engineer | Sonnet | Documentation and repository structure. |
| — | Inventory assistant | Haiku | Factual inventory of the repositories. No decisions. |

## Risks and limitations

- Fable's capabilities were not measured here. If its Red Team findings turn out shallow or wrong, the Red Team role
  is re-run on Opus with a fresh context, and the switch is recorded in this file.
- Agent 6 runs on Sonnet although the role needs high reasoning. Its operational conclusions are cross-checked by the
  Red Team (Fable) and the architect (Opus).
- All agents come from one model family. Real independence also depends on separate contexts and on the rule that
  the Red Team reads no other agent's output before its initial assessment.

## Record of actual runs

Updated as stages complete.

| Stage | Agent | Model | Deliverables |
|---|---|---|---|
| 1 | 2, 3, 4 | opus | see `assessments/02-*`, `03-*`, `04-*` |
| 1 | 5, 6, 8 | sonnet | see `assessments/05-*`, `06-*`, `08-*` |
| 1 | 7 | fable | `assessments/07-red-team-initial-assessment.md` |
| 1 | inventory | haiku | `assessments/01-repository-inventory.md` |
| 2 | 1 (architect) | opus | `architecture.md` |
| 3 | 7 | fable | `assessments/07-red-team-stage3-review.md` |
| 4 | 5 | sonnet | `experiments/EXP-DB-*`, `evidence/`, `lab/ussuri-db-lab/ff/` |
| 5 | 4 | opus | `experiments/EXP-DB-01-root-cause-analysis.md`, amendments to `declared-differences.md` |
| 5 | 7 | fable | `assessments/07-red-team-stage5-results-review.md` (interrupted once by a usage limit and resumed in the same context) |

Notes:
- The inventory assistant (Haiku) made one call to create a remote session, which its task did not need. The call was
  denied and not retried.
- Fable's Red Team work found issues that the other agents and the architect had missed. The two most important were
  the second Nova gate (RPC cap) and the comparator-integrity problem. No switch to Opus was needed.

