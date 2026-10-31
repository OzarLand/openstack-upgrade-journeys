# EXP-NNN: <short title: what is tested>

<!-- Copy to journeys/<journey>/experiments/EXP-NNN-short-topic.md. Numbers are never reused. Write `unknown` for
     anything you do not know; never invent values. Redact per docs/validation-status.md. Delete these comments. -->

| | |
|---|---|
| **Experiment ID** | EXP-NNN |
| **Journey** | e.g. ussuri-to-2026.1 |
| **Author / executor** | agent:<name> or @handle (say which; they may differ) |
| **Date planned / run** | YYYY-MM-DD / YYYY-MM-DD, or "not run" |
| **Status** | PROPOSED-UNVERIFIED \| DOCUMENTED-UNVERIFIED \| LAB-VALIDATED \| PRODUCTION-VALIDATED \| NEEDS-REVALIDATION \| FAILED |
| **Evidence class of the claim tested** | Officially supported \| Technically possible but unsupported \| Experimentally validated \| Not validated \| Incompatible |
| **Risk** | read-only \| state-changing \| destructive (highest step) |
| **Validation record** | VAL-NNN, once run |

## Hypothesis

One or two sentences, falsifiable. "From state A, doing B results in C." What would refute it.

## Initial state

Exact starting point. OpenStack release and Kolla-Ansible version; container image tags or digests; host OS and kernel;
database and message queue versions; topology in general terms (node counts, roles, no names); network and storage
backends; data loaded (rows, instances, volumes, images, users) and how it was created; how this state is reproducible.

## Prerequisites

What must exist or be true before starting: resources, access, images and where they come from, time, disk, other
experiments that must have passed (link their IDs).

## Expected outcome

What success looks like, stated before running. Concrete, observable.

## Possible failure modes

| Failure mode | How it would show | What it would mean |
|---|---|---|
| | | |

## Baseline preservation

How the initial state is kept so the experiment can be repeated or undone: snapshot of VMs or volumes, backup of the
database (kept in the lab, never committed), copy of configuration (redacted), exact commands and restore check. State
whether the restore was tested. If no baseline can be preserved, say so and why.

## Steps

Use the [runbook step template](runbook-step.md) for each step that is meant to be reused. Number them. Mark each with
its risk and whether it was run.

| # | Step | Risk | Run? |
|---|---|---|---|
| 1 | | read-only | |

## Evidence

Where the redacted outputs are (`journeys/<journey>/evidence/EXP-NNN/`) and what each file shows. Record anything that
was redacted. No dumps, images or archives.

## Database consistency

Checks before and after, with results: schema versions per service, migration status, row counts of key tables,
orphans or duplicates found, results of the services' own checks (for example `nova-status upgrade check` where it
exists in the release). Write `not run` for anything not run.

## Service checks

State of each service and its dependencies after the step: API reachable, service list up, message queue and database
cluster health, logs for errors, versions reported.

## Workload checks

What the user-visible workloads did: instances kept running or not, were reachable, could be created, resized,
migrated, deleted; volumes attached; images bootable; networks and floating IPs. Compare with the baseline. Write what
was not exercised.

## Conclusion

What was learned, in plain words. Was the hypothesis confirmed, partly confirmed, refuted? What remains unknown? What
to do next (new experiment, new decision, new warning in a runbook)?

## Status

Final status and why, with the validation record (VAL-NNN) and the steps not run. A status is never higher than the
evidence above.
