# DR-NNN: <the decision, as a short statement or question>

<!-- Copy to journeys/<journey>/decision-records/DR-NNN-short-topic.md. Numbers are never reused. One decision per
     record. A decision is not evidence: it says what we chose and why, and what would change our mind. Delete comments. -->

| | |
|---|---|
| **Decision ID** | DR-NNN |
| **Journey** | e.g. ussuri-to-2026.1 |
| **Date** | YYYY-MM-DD |
| **Responsible agent / person** | agent:<name> or @handle (the one who proposes and answers for it) |
| **Reviewed by** | someone other than the proposer, or "not yet" |
| **Validation status** | PROPOSED-UNVERIFIED \| DOCUMENTED-UNVERIFIED \| LAB-VALIDATED \| PRODUCTION-VALIDATED \| NEEDS-REVALIDATION \| FAILED |
| **State** | proposed \| accepted \| superseded by DR-NNN \| rejected |

## Context

What forces this decision: the question, the constraints (data safety, supportability, time, lab limits), what is known
and unknown. Link the assessments and experiments it rests on.

## Alternatives considered

| # | Alternative | One-line description |
|---|---|---|
| A | | |
| B | | |

Include "do nothing" and the unsupported option if they are real candidates.

## Evidence

For each alternative: what we know, with its evidence class (*Officially supported*, *Technically possible but
unsupported*, *Experimentally validated*, *Not validated*, *Incompatible*) and its source (`repo@ref:path`, link,
`EXP-NNN` / `VAL-NNN`). Reading is not validation: say which pieces were only read.

## Risks

Per alternative: what can go wrong, how likely (or `unknown`), what is lost, whether it is reversible, and the point of
no return if there is one.

## Arguments for and against

| Alternative | For | Against |
|---|---|---|
| A | | |
| B | | |

## Decision

What was decided, in one paragraph, and the conditions under which it holds. What would make us revisit it (exit
conditions: a failed experiment, a new upstream release, new evidence).

## Responsible agent

Who owns the decision and its follow-up. Who must approve it before anything state-changing relies on it.

## Validation status

The status of the decision's key claims and what test would raise it. A decision based on unverified claims is itself
labelled unverified.

## Dissent

Disagreements, from other agents or from operators, with their reasons. Dissent is kept, not deleted; add to it when
someone disagrees later. Write "none recorded" only if that is true.
