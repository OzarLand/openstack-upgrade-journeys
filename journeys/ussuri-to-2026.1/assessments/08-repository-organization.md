# 08. Repository organization and OzarLand conventions

| | |
|---|---|
| **Author** | Agent 8, documentation and community engineer |
| **Model** | Sonnet 5.5 (assigned) |
| **Date** | 2026-10-31 |
| **Status** | PROPOSED-UNVERIFIED. An organisational proposal for the architect and the owner. It makes no claim about OpenStack behaviour. |
| **Inputs read** | `00-mission-brief.md`; in `/home/user/ozarland/ozarland`: `README.md`, `docs/conventions/*`, `docs/knowledge-lifecycle.md`, `docs/review-policy.md`, `docs/agents.md`, `docs/repositories.md`, `docs/github-conventions.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `tools/check_content.py`, `community/templates/upgrade-playbook.md` (section names); `openstack-quick-lab` (README, CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, `.github/`, `.gitignore`); `openstack-operator-skills` (README top, CONTRIBUTING, SECURITY, CLAUDE.md, `docs/knowledge-validation-policy.md`, `docs/templates/`, `.github/`); `kolla-ansible-deployment-patterns` (CONTRIBUTING, front matter and openings of the two `version-notes/` pages, template list); skill `openstack-runbook-authoring` (SKILL.md, `runbook-template.md`, `validation-and-exercises.md`). Not read: other files of `assessments/`. |

Skill applied: `openstack-runbook-authoring`. It shaped the runbook step template (read-only versus state-changing,
expected result, what to check if it differs, stop and escalation conditions, point of no return), the rule that a
runbook is a draft until a non-author has run it, and the rule that gaps become `TODO` or `unknown`, never plausible
values.

## 1. Summary

- The new repository fits OzarLand with few changes: same identity block, same Apache-2.0 licence and DCO, same
  sensitive-data and risk-warning rules, same issue/PR-template style, same code of conduct pointer.
- The one real design problem is **vocabulary**. This mission uses six validation statuses; OzarLand pages use four;
  the skills repository uses five. Five of the six map one-to-one. `FAILED` has no equivalent anywhere. Proposal in
  section 4.
- The second problem is **tooling**: OzarLand's content checker treats every Markdown file outside a short list of
  directories as a "page" that needs front matter. Journey working documents (assessments, experiments, decisions)
  would all fail it. Options in section 6.
- The third is **where the knowledge ends up**. This repository is an investigation; OzarLand's planned
  `openstack-upgrade-playbooks` is the home for reusable upgrade knowledge. The split is proposed in section 5. The
  relation between the two repositories is an owner decision.

## 2. What the three repositories teach us

### 2.1 `ozarland` (the hub)

| Convention | What it requires | Applied here |
|---|---|---|
| README identity (`readme-identity.md`) | Back-link on line 1; centred header with emoji, bold sentence, badges, anchor links; intro ending "Part of OzarLand: *a shared land for better OpenStack operations.*"; shared closing block with a "you are here" marker; Apache-2.0 and non-affiliation line; no banner (hub only) | Followed in `README.md`. Emoji 🧭 chosen by me; there is no assigned one, the owner may change it. |
| Content metadata (`content-metadata.md`) | YAML front matter on every page; `status` in `draft | lab-verified | validated | experimental`; `confirmed_by` appended by others, never by the author; `authored_by`; provenance line; "Validity and limits" section | Applied to the pages that are procedures (runbooks, rollback, troubleshooting). Working documents use the mission's metadata block instead (section 3). |
| Risk warnings | ⚠️ state-changing, 🛑 destructive, four questions, direct DB edits always destructive, no destructive step hidden in a script | In the runbook-step template, CONTRIBUTING and the PR checklist. |
| Runbook structure | Fixed section order for symptom runbooks | `troubleshooting/` pages follow it. Upgrade steps follow the `playbook` kind (below). |
| Sensitive data | No secrets, hostnames, IPs, names, unredacted logs; RFC 2606/5737 placeholders | In CONTRIBUTING, SECURITY, PR and issue forms, `.gitignore`. Added: database dumps and backups, which matter for upgrade work. |
| Licensing and DCO | Apache-2.0, `git commit -s`, no CLA | Root `LICENSE` is Apache-2.0 (checked: Apache License 2.0 text present). |
| Knowledge lifecycle | A lab check is evidence, not validation; validation needs a second environment and a human operator; validity decays; disagreement is content | Built into `docs/validation-status.md` and the decision-record "dissent" section. |
| Review policy and agents | Agents are identified in each PR (`Author:` line), never review or merge their own PRs, sign off in the owner's name, commit messages stay plain | PR template has the `Author:` line. See gap 8 on commit trailers. |
| GitHub conventions | Shared labels (`kind/*`, `status/*`, `component/*`, `deploy/*`, `risk/*`), squash merge, Discussions centralised in `ozarland` | Issue forms use existing labels only. No new label is required. |
| `check_content.py` | Per-kind required fields and sections; risk markers; sensitive-data scan; links | See gap 2. |

The `playbook` kind is the closest existing kind for upgrade steps. Its required fields are `title, kind, status,
openstack_releases, components, deployment_methods, risk, confirmed_by, upstream_refs, last_verified`, and its
required sections `Upgrade path`, `Prerequisites and pre-checks`, `Procedure`, `Rollback`, `Validity and limits`
(`check_content.py`, `REQUIRED_FIELDS` and `REQUIRED_SECTIONS`). The `experience-report` kind (no `status` field) is
the right container for "we tried X and it failed".

### 2.2 `openstack-quick-lab`

- README style: centred header, factual badges ("tested on one cloud"), an honest status callout (`> [!NOTE] Status:
  early, tested on one cloud`), tables over prose, a "for managers" tip, Mermaid with the shared colours. The same shape
  fits here.
- CONTRIBUTING is short, links to the hub, then states repository-specific rules (what a variant must contain, testing,
  one topic per PR, English, DCO). Our CONTRIBUTING mirrors it.
- SECURITY lists what counts as a security issue for this repository, tells the reader to use GitHub private
  vulnerability reporting, and sends upstream vulnerabilities to the OpenStack VMT. Mirrored, with the issues that matter
  here: unsafe procedure, published dumps and credentials.
- Issue forms: `config.yml` with contact links, a "failed at a step" form with a required redaction checkbox.
  Mirrored by the two forms here.
- Boundary: the quick lab builds a **2026.1** lab only and needs an OpenStack cloud account. It cannot host a Ussuri
  deployment and cannot run from this environment. It is a possible later home for a lab variant, not a dependency.

### 2.3 `openstack-operator-skills`

- `docs/knowledge-validation-policy.md` is the nearest existing policy. Its five statuses, "execution, not reading",
  per-claim validation, "a test validates what it tested", evidence rules, `NEEDS-REVALIDATION` triggers and the
  inventory fields are reused almost verbatim.
- Its mapping table to OzarLand page statuses is the precedent for ours: `LAB-VALIDATED` is *lab-verified* and never
  "validated"; `PRODUCTION-VALIDATED` needs a human operator other than the author; unverified statuses are `draft`;
  `NEEDS-REVALIDATION` is `experimental`.
- Its status tags (`[LAB-VALIDATED: VM-NET-04]`) travel with the text. We use the same tag syntax so a step can be
  imported into a skill later.
- Its `docs/templates/validation-record.yaml` is the base of ours (extra keys added, marked `[skills]` where shared).
- Its CONTRIBUTING has the rule we adopt for the split of knowledge: general knowledge goes first to the OzarLand page
  repository that owns it, and the skill follows.
- Its `CLAUDE.md` says never to add `Co-Authored-By:` or session links to commits or PR descriptions. See gap 8.

### 2.4 `kolla-ansible-deployment-patterns`

- `version-notes/` holds two pages for 2025.1 to 2026.1: a `kind: playbook` page built from release notes
  (`status: draft`, `risk: destructive`, `confirmed_by: []`, `authored_by: agent:ozarland-author`) and a
  `kind: experience-report` page of a lab run (`authored_by: agent:lab-reviewer`, `environment` block with topology,
  network, storage, OS). The first states sources and that it was "followed once on a disposable all-in-one lab"; the
  second opens with a callout "observed on a disposable all-in-one lab, not on production".
- Naming: `<from>-to-<to>.md` for the release-notes page; `upgrade-report-<from>-to-<to>-<topology>.md` for the report.
- Lesson: the labels that stop an over-reading are the callout at the top, the explicit environment block and the
  "Validity and limits" section. Our journey README and templates carry the same three.
- These are single-hop, SLURP-to-SLURP pages. Nothing in the OzarLand repositories yet covers a multi-release journey.

## 3. Proposed structure

The mission's proposed tree is kept and adapted. Directories that already exist from the scaffolding are unchanged.

```text
openstack-upgrade-journeys/
  README.md  CONTRIBUTING.md  SECURITY.md  CODE_OF_CONDUCT.md  LICENSE  .gitignore
  .github/
    pull_request_template.md
    ISSUE_TEMPLATE/  config.yml  experiment-report.yml  unsafe-or-wrong-procedure.yml
  docs/
    validation-status.md
    templates/  experiment-record.md  decision-record.md  validation-record.yaml  runbook-step.md
  journeys/
    ussuri-to-2026.1/
      README.md
      compatibility-matrix.md
      dependency-graph.md
      lessons-learned.md
      assessments/        00-mission-brief.md  0N-<topic>.md ...
      decision-records/   DR-NNN-<topic>.md
      experiments/        EXP-NNN-<topic>.md
      validation/         VAL-NNN.yaml
      evidence/           EXP-NNN/  (redacted text only)
      runbooks/
      rollback/
      troubleshooting/
```

Why each choice:

| Choice | Reason |
|---|---|
| `journeys/<from>-to-<to>/` | More than one journey is likely (other start releases, other tools). Each is self-contained; shared rules sit at the root. |
| Root `docs/` for statuses and templates | They apply to every journey, and `docs/` is already outside the content checker's page scan. |
| Templates in `docs/templates/` | Same location as `openstack-operator-skills`; `templates` and `docs` are both excluded from page checks. (The hub keeps its page templates in `community/templates/`, `kolla-ansible-deployment-patterns` in `templates/`; there is no single rule.) |
| Numbered IDs `EXP-`, `DR-`, `VAL-` | Stable, never reused, citable from statuses (`[LAB-VALIDATED: VAL-007]`) and from other repositories. Same idea as inventory IDs in the skills repository. |
| Separate `validation/` (YAML) from `experiments/` (prose) | The experiment says what and why; the validation record is the structured, copyable result. Matches the skills inventory format and keeps one record per execution, so a rerun adds a record rather than rewriting history. |
| `evidence/EXP-NNN/` | Keeps outputs next to nothing else; easy to review for sensitive data; `.gitignore` blocks dumps, images and archives. |
| `runbooks/`, `rollback/`, `troubleshooting/` | Match OzarLand kinds: `playbook` for steps and rollback, `runbook` for symptoms. Rollback is separate because "what cannot be undone" is the key safety question of a journey. |
| `decision-records/` with a mandatory "dissent" section | Applies the `openstack-operational-decisions` approach and the lifecycle rule that disagreement is content. |
| `assessments/0N-*.md` | The mission's working reports, with the mission metadata block. They are inputs, not procedures. |
| No `tools/` yet | Nothing to automate until content exists. A small consistency checker (IDs unique, statuses legal, tags point to existing records) is the obvious first tool, modelled on `validate_knowledge.py`. Proposed, not written. |

### Which files are "pages" and which are working documents

| Location | Kind | Metadata |
|---|---|---|
| `runbooks/`, `rollback/` | OzarLand `playbook` | OzarLand front matter (`status` per the mapping, `risk`, `confirmed_by: []` until a human operator confirms, `authored_by`, `last_verified`), required sections, provenance line |
| `troubleshooting/` | OzarLand `runbook` or `diagnostic` | Same front matter; runbook structure |
| `lessons-learned.md` | `experience-report` (no status field) | Front matter without `status` |
| `assessments/`, `decision-records/`, `experiments/`, `compatibility-matrix.md`, `dependency-graph.md` | Working documents | The mission's metadata block (author agent and role, model, date, status, inputs read) and a closing "Open questions / what I could not verify" |
| `validation/*.yaml` | Records | The template's fields |

Step-level statuses in runbooks use the tag syntax `[LAB-VALIDATED: VAL-NNN]`. The page `status` is the weakest step's
status mapped as below. Every state-changing step has ⚠️, every destructive one 🛑, from the OzarLand rules.

## 4. Validation statuses and their mapping

Full definitions, evidence rules and who may change a status are in [`docs/validation-status.md`](../../../docs/validation-status.md).

| Here | OzarLand page status | `openstack-operator-skills` | Notes |
|---|---|---|---|
| `PROPOSED-UNVERIFIED` | `draft` | `PROPOSED-UNVERIFIED` | Same words. |
| `DOCUMENTED-UNVERIFIED` | `draft` | `DOCUMENTED-UNVERIFIED` | Same words. A source is required. |
| `LAB-VALIDATED` | `lab-verified` | `LAB-VALIDATED` | OzarLand's rule that the verifier is someone other than the page author is kept; a lab agent counts, as in the hub's lifecycle. |
| `PRODUCTION-VALIDATED` | `validated` | `PRODUCTION-VALIDATED` | Human operator other than the author. No agent can set it. |
| `NEEDS-REVALIDATION` | `experimental` | `NEEDS-REVALIDATION` | Triggers extended for version-pair work: any change of image build, tool or database/queue version. |
| `FAILED` | none | none | Proposal below. |

**The `FAILED` gap.** Neither OzarLand nor the skills repository has a status for "executed and refuted". In the skills
policy, a failed run is reported as a warning in `limitations`; in OzarLand pages it surfaces as `experimental` or in an
experience report. For an investigation whose main output may be "this path does not work", a visible failure state is
needed. Proposal:

1. Keep `FAILED` in this repository as a status of experiments, validation records and steps.
2. Never publish a `FAILED` step as a runbook step. The page records it under "Known failures" and in
   `troubleshooting/`; the page status is at most `experimental`.
3. When knowledge is copied to a skill, the failure goes into `limitations`, and the item is not imported as a
   procedure.
4. Ask the owner whether to add `FAILED` (or "refuted") to the shared vocabularies. Until then this mapping stands.

**Relation to the mission's evidence classes.** The mission's five classes (*Officially supported*, *Technically
possible but unsupported*, *Experimentally validated*, *Not validated*, *Incompatible*) describe possibility; the six
statuses describe how well a procedure was exercised. `Experimentally validated` requires `LAB-VALIDATED` or better;
`Not validated` fits `PROPOSED-`/`DOCUMENTED-UNVERIFIED` or `FAILED`. The table is in `docs/validation-status.md`.

## 5. How knowledge is split across repositories

| Knowledge | Lives first in | Why | Link back |
|---|---|---|---|
| Journey-specific investigation: compatibility matrix, dependency graph, experiments, decisions, evidence, the multi-release runbooks | **this repository** | Specific to a start and target release; mostly unvalidated; evolves quickly | Statuses and IDs |
| How Kolla-Ansible behaves in a given release, a single-hop version note, a single-hop lab upgrade report | `kolla-ansible-deployment-patterns` (`version-notes/`) | That is where OzarLand keeps them today (`docs/repositories.md`); new hops (for example 2025.1 to 2026.1) are already there | Link from here; do not copy |
| A symptom met on one instance, volume or port, with checks and fix | `openstack-vm-runbooks` | Symptom-driven, release-independent runbooks | `troubleshooting/` links to it |
| Reusable, validated upgrade guidance per release pair and deployment method | `openstack-upgrade-playbooks` (planned, priority 2; created when two or more upgrade reports exist, `docs/launch-plan.md`) | Different format and audience from this investigation | Only after validation; this repository keeps the evidence |
| Distilled decision points and checks, with their status | `openstack-operator-skills` (inventory entry citing the OzarLand page and, if useful, a `VAL-NNN`) | The skills follow the pages; they do not originate procedures | Status copied, never raised |
| A lab to rehearse on | `openstack-quick-lab` (2026.1 only today) | Cannot host a Ussuri deployment; a variant for this would be a separate proposal | Mention only |

Rule of thumb, from the skills repository's CONTRIBUTING: general knowledge goes first to the OzarLand page repository
that owns it, and everything else follows; this repository holds what only exists because of this journey.

**Relation to `openstack-upgrade-playbooks`.** The hub says upgrade reports stay in `kolla-ansible-deployment-patterns`
until that repository exists, and that it will be created from two or more real upgrade reports. This repository is
therefore an investigation space upstream of it, not a replacement. Whether this repository later becomes that
repository, feeds it, or stays separate is not decided here. It is an owner decision.

## 6. Gaps and decisions needed

| # | Gap | Proposed handling | Who decides |
|---|---|---|---|
| 1 | No OzarLand page kind for a multi-release "journey" | Use `playbook`, `runbook`, `experience-report` for pages; working documents with the mission metadata block | Architect; owner if a new kind is wanted |
| 2 | `tools/check_content.py` treats every `.md` not under `NON_PAGE_DIRS` (`.github, .claude, templates, tools, docs, community, newcomers`) as a page and fails it without front matter. Assessments, experiments, decision records and the matrix would all fail. | Either (a) CI passes only `runbooks/`, `rollback/`, `troubleshooting/` and `lessons-learned.md` to the checker as explicit file arguments (the checker supports that); or (b) add `assessments`, `experiments`, `decision-records`, `evidence` to `NON_PAGE_DIRS` (the check is by path component; `journeys` stays a page directory). (b) changes a shared tool, which the review policy reserves for the owner. Not tested here: I did not run the checker. | Owner for (b) |
| 3 | `tools/status_blocks.py` generates badges and counts for known repositories only | Badges here are static; counts are written by hand and say 0. Extend the tool or add a small local script when there is something to count. | Owner |
| 4 | Six statuses versus four and five | Section 4 | Architect now; owner for `FAILED` in shared vocabularies |
| 5 | OzarLand `lab-verified` means someone other than the author ran it; the skills repository accepts a lab agent's run with `independent_human_check: false` | Same rule: a named executor other than the page author; `independent_human_check` recorded separately; never described as "validated" | Architect |
| 6 | The shared closing block in every README lists four repositories | Our README adds a fifth row as a proposal (marked by a comment). Adding a repository to the block must be applied in every OzarLand repository in the same round of PRs (`readme-identity.md`) | Owner |
| 7 | Repository name, emoji, GitHub topics, label set and whether Discussions are enabled are not fixed | I assumed `OzarLand/openstack-upgrade-journeys` in links, 🧭 as the emoji, and existing shared labels only. Links to issue forms will not work until the repository exists on GitHub under that name. | Owner |
| 8 | Commit and PR attribution. The hub's `agents.md` says commit messages stay plain and AI use is disclosed in the PR `Author:` line, signed off in the owner's name; the skills `CLAUDE.md` forbids `Co-Authored-By:` and session links. The attribution lines requested for this session's commits differ. | Not resolved here. The PR template carries the `Author:` line. The architect should check the instruction for commits against the owner's rule before committing. | Architect / owner |
| 9 | No `CLAUDE.md` or agent instructions file for this repository, unlike the skills repository | Not created (not requested). Worth adding once the working conventions settle. | Architect |
| 10 | No checker for IDs, tags and cross-references | Propose a small `tools/check_journey.py` (unique IDs, legal statuses, tags resolve to records, no status above its evidence). Not written. | Architect |
| 11 | The stages (1 to 4) in the journey README are an outline I wrote for orientation; only Stage 1 comes from the mission | Marked as a working outline; the architect owns the plan | Architect |
| 12 | The agent table only knows agent 8 and the architect | Other rows left for the architect | Architect |

## 7. What I checked, and what I did not

Checked by reading: the conventions and templates listed under "Inputs read", the root `LICENSE` header (Apache License,
Version 2.0), the scaffolding directories present on 2026-10-31.

Not checked:

- I did not run `check_content.py` on any file of this repository, so I cannot say whether the runbook front matter
  proposed here passes it unchanged. I read its constants and function names only (gap 2).
- I did not verify that the GitHub links to forms and pages resolve; the repository is not yet on GitHub, and GitHub web
  pages are not reachable from this environment.
- I did not verify the release names, Kolla-Ansible version numbers or any OpenStack behaviour. This document makes no
  claim about them; specialists provide that content.
- Badges are static and were not rendered.

## Open questions / what I could not verify

1. Is the repository meant to become, feed, or stay separate from `openstack-upgrade-playbooks`?
2. May the shared checker be changed (gap 2, option b), or must CI pass explicit file lists?
3. Is `FAILED` to be added to the shared vocabularies?
4. Final repository name, emoji and labels (gap 7).
5. Which commit attribution applies (gap 8).
6. Whether the owner wants runbook pages in this repository to carry `confirmed_by` entries for lab runs (the OzarLand
   rule) in addition to the `VAL-NNN` records, or only the records. I assumed both: the record is the evidence, the
   `confirmed_by` entry is the pointer the checker and the page status read.
