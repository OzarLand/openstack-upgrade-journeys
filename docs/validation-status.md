# Validation status

How this repository says how well a procedure, an experiment or a claim has been tested, and how those words relate to
the ones used in the other OzarLand repositories. It applies the
[knowledge lifecycle](https://github.com/OzarLand/ozarland/blob/main/docs/knowledge-lifecycle.md) and the
[knowledge validation policy](https://github.com/OzarLand/openstack-operator-skills/blob/main/docs/knowledge-validation-policy.md)
of `openstack-operator-skills` to multi-release upgrade work, and adds one status, `FAILED`.

Status of this page: written 2026-10-31 by an AI agent (Stage 1). It is a proposal for the owner to confirm, not a
decided policy.

## Principles

- **Execution, not reading.** A status above `DOCUMENTED-UNVERIFIED` means the procedure was executed and the observed
  result matched the expected result. Reading documentation, release notes, source code, a migration script or an
  AI-generated explanation is not validation, however careful.
- **Per claim, not per page.** Each step or claim carries its own status. A runbook is never "validated" as a whole
  while one of its steps is not. Its page status is that of its weakest step.
- **A test validates what it tested.** A lab run of one release hop on one topology validates that, for the steps
  actually run. It says nothing about another hop, another topology, a larger database or production load.
- **No fabricated evidence.** No invented dates, versions, outputs or results. A missing value is `unknown`.
- **Lab and production stay distinct.** Both are real evidence; they answer different questions.
- **A failure is a result.** It is recorded, kept visible and warned about, not deleted.

## The six statuses

| Status | Meaning | Minimum evidence to hold it |
|---|---|---|
| `PROPOSED-UNVERIFIED` | An idea, hypothesis or adaptation written in this repository. Not executed anywhere. | A clear statement of what is proposed and what test would check it. |
| `DOCUMENTED-UNVERIFIED` | Comes from upstream documentation, release notes, source code or a reliable report. No successful execution is recorded. | The source, as `repo@ref:path` or a link. |
| `LAB-VALIDATED` | Executed on a lab and verified: the observed result matched the expected result. | A validation record (`VAL-NNN.yaml`) and evidence: exact versions, topology, date, who ran it, steps run and not run, redacted outputs. |
| `PRODUCTION-VALIDATED` | Executed and verified on a real platform by a human operator other than the author. | A validation record with a sanitised production report: versions, topology in general terms, what was run, what was seen, date or period, the operator's handle. |
| `NEEDS-REVALIDATION` | Was `LAB-` or `PRODUCTION-VALIDATED`, but something that matters changed. The old evidence is kept and marked stale. | The old record plus the reason it may no longer hold. |
| `FAILED` | Executed and did not behave as written: an error, data inconsistency, a service that did not recover, or a hypothesis refuted. | A validation record with the result and evidence of the failure. |

A *representative lab* runs real OpenStack services at the versions the claim is about, with the same deployment
method, and enough nodes and data to exercise the behaviour. Nested virtualisation, small databases and the absence of
real workloads or of production hardware are recorded as limitations, never hidden. The lab of this mission has no
hardware virtualisation (`unknown` effect on compute-side behaviour, to be recorded per experiment).

### Evidence class is a different question

Every claim also carries the mission's evidence class: *Officially supported*, *Technically possible but unsupported*,
*Experimentally validated*, *Not validated*, *Incompatible*. The class says what upstream and the lab tell us about
possibility; the status says how well a procedure was exercised. They constrain each other:

| Evidence class | Needed status |
|---|---|
| Officially supported | Any. "Supported" is about upstream's position, not about whether anyone here ran it. |
| Technically possible but unsupported | Any, but the page says "unsupported" next to the step. |
| Experimentally validated | `LAB-VALIDATED` or `PRODUCTION-VALIDATED` only, with a validation record. |
| Not validated | `PROPOSED-UNVERIFIED`, `DOCUMENTED-UNVERIFIED`, or `FAILED`. |
| Incompatible | Any; it is a finding, ideally with the upstream source, or `FAILED` with an experiment. |

## Mapping to the other OzarLand vocabularies

| Here | OzarLand page status ([knowledge lifecycle](https://github.com/OzarLand/ozarland/blob/main/docs/knowledge-lifecycle.md#page-statuses)) | `openstack-operator-skills` status ([policy](https://github.com/OzarLand/openstack-operator-skills/blob/main/docs/knowledge-validation-policy.md#2-statuses)) |
|---|---|---|
| `PROPOSED-UNVERIFIED` | `draft` | `PROPOSED-UNVERIFIED` |
| `DOCUMENTED-UNVERIFIED` | `draft` | `DOCUMENTED-UNVERIFIED` |
| `LAB-VALIDATED` | `lab-verified` (not "validated") | `LAB-VALIDATED` |
| `PRODUCTION-VALIDATED` | `validated` | `PRODUCTION-VALIDATED` |
| `NEEDS-REVALIDATION` | `experimental` | `NEEDS-REVALIDATION` |
| `FAILED` | None. A failed procedure is not published as a runbook. A page that records the failure is an `experience-report` (no status field) or stays `experimental` with a visible failure banner. | None. The item is not imported as a procedure; the failure is carried as a warning in `limitations`, as the policy asks for failed lab runs. |

Rules for the mapping:

- Outside this repository, use OzarLand's words: an item here is *lab-verified*, never *validated*, until a human
  operator confirms it.
- The first five statuses are the skills repository's statuses exactly, so a validation record here can be copied into
  its `validation/inventory.yaml` without translation (see [templates](templates/validation-record.yaml)).
- **`FAILED` is the one status with no equivalent.** It is kept here because a refuted hypothesis is the main output of
  an investigation like this one. Adding it to the shared vocabularies, or choosing another mapping, is an owner
  decision (see the repository assessment, "Gaps").
- A runbook page is `lab-verified` only if **every** step is `LAB-VALIDATED` or better, was run by someone other than
  the page's author (a lab agent counts, as in OzarLand; the executor is named), and the page says which steps were not
  run. It is `validated` only if a human operator other than the author confirmed it on a real platform, recorded in
  its `confirmed_by`.

## Evidence rules

Acceptable evidence for `LAB-VALIDATED` or `PRODUCTION-VALIDATED`:

- the record of an execution: exact versions of OpenStack, Kolla-Ansible, container images (tag or digest), host OS,
  database and message queue; topology; date; who ran it; the command sequence; the steps **not** run;
- sanitised command output, service checks, row counts, schema versions, timings;
- for upgrade steps, the **data checks before and after** (see the experiment template: baseline preservation, database
  consistency, service checks, workload checks);
- a pull request or issue that holds the above.

Not acceptable as evidence of validity:

- documentation, release notes or source code read but not executed;
- the existence of a procedure in another repository, OzarLand's included;
- an AI-generated explanation or plan, however plausible;
- a green CI run: it shows that files are well formed, never that a procedure works;
- "it always worked for us", without a recorded execution.

Never in evidence: credentials, tokens, real hostnames or addresses, customer or person names, database dumps,
unredacted logs.

## Who may change a status

| Change | Who | Condition |
|---|---|---|
| Add an item as `PROPOSED-UNVERIFIED` or `DOCUMENTED-UNVERIFIED` | Anyone, including agents | A source, or a statement of what is proposed. |
| To `LAB-VALIDATED` or `FAILED` | A reviewer or maintainer, in a pull request that contains the validation record and evidence | The reviewer is not the author of the procedure; the executor is named; steps not run are listed. |
| To `PRODUCTION-VALIDATED` | A maintainer | A human operator other than the author provided a production report. An agent never confirms a page it wrote and cannot be the production operator. |
| To `NEEDS-REVALIDATION` | Anyone may request; a maintainer sets it | A reason from the next section. |

The agent that ran an experiment is recorded as `executed_by`. Whether a human independently checked it is recorded
separately (`independent_human_check`): it strengthens the evidence without changing the status.

## When a status must go back to `NEEDS-REVALIDATION`

- The procedure text changes in a way that affects what is executed.
- The claim is extended to another release, Kolla-Ansible version, container image build, host OS, database or
  message-queue version, or topology that the evidence did not cover. For multi-release upgrade work this is the most
  common case: a result is valid for the exact version pair it was run on.
- Upstream changes the behaviour (release notes, new patch release, a backport, changed defaults), or the artefacts the
  procedure depends on change or disappear (for example an image tag that is no longer pullable).
- Someone reports a failure.

## Recording a validation

One validation record per execution, in `journeys/<journey>/validation/VAL-NNN.yaml`, from
[`templates/validation-record.yaml`](templates/validation-record.yaml). It points to the experiment that produced it
(`EXP-NNN`) and to the evidence directory. Statuses in prose use the same tag as the skills repository, next to the
step: `[LAB-VALIDATED: VAL-007]`, `[DOCUMENTED-UNVERIFIED: see compatibility-matrix.md#...]`.

## Templates

| Template | Use it for |
|---|---|
| [`templates/experiment-record.md`](templates/experiment-record.md) | Planning and reporting one experiment (`EXP-NNN`) |
| [`templates/decision-record.md`](templates/decision-record.md) | One decision with alternatives, evidence, risks and dissent (`DR-NNN`) |
| [`templates/validation-record.yaml`](templates/validation-record.yaml) | The structured result of one validation (`VAL-NNN`) |
| [`templates/runbook-step.md`](templates/runbook-step.md) | One step of a runbook, with status tag, expected output, success criteria and execution mode |
