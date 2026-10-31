# DR-002 — Keystone legacy-to-Alembic bridge window (disagreement between Agents 2 and 4)

| Field | Value |
|---|---|
| Decision ID | DR-002 |
| Date | 2026-10-31 |
| Responsible agent | Agent 1 — Architect (arbitration) |
| Status | Resolved from source reading. The claim is `DOCUMENTED-UNVERIFIED`; the experiment EXP-DB-01 will test it. |

## Context

Agent 4 (`assessments/04-database-migration-dependency-graph.md`) placed the Keystone bridge window at **Yoga to
2023.1**. Agent 2 (`assessments/02-unsupported-transitions.md`) placed it at **Zed or 2023.1**. Both agree that the
bridge was removed in 2023.2 (keystone commit `8c9462f6f`).

## Evidence

The architect checked which branches contain the function that moves a legacy sqlalchemy-migrate database onto the
Alembic history (`_init_alembic_on_legacy_database` in `keystone/common/sql/upgrades.py`):

| Ref | Function present |
|---|---|
| `xena-eol` | no |
| `origin/unmaintained/yoga` | no |
| `origin/unmaintained/zed` | **yes** |
| `origin/unmaintained/2023.1` | **yes** |
| `2023.2-eol` | no |

## Decision

The Keystone bridge window is **Zed to 2023.1**; Agent 2's reading stands. The windows of the three services that need
a bridge are then:

- Nova: Xena to 2023.1;
- Cinder: Xena to 2023.1;
- Keystone: Zed to 2023.1.

The common bridge releases are therefore **Zed and 2023.1**. 2023.1 is chosen as the bridge for the experiments,
because it is also the start of the SLURP chain to 2026.1.

## Dissent kept visible

Agent 4's deliverable keeps its original text. A correction note points here, so the history of the reasoning stays
readable.
