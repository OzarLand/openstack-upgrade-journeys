# Contributing

This repository follows the OzarLand community rules: the
[code of conduct](https://github.com/OzarLand/ozarland/blob/main/CODE_OF_CONDUCT.md), the
[review and merge policy](https://github.com/OzarLand/ozarland/blob/main/docs/review-policy.md), the
[knowledge lifecycle](https://github.com/OzarLand/ozarland/blob/main/docs/knowledge-lifecycle.md) and the
[content conventions](https://github.com/OzarLand/ozarland/tree/main/docs/conventions). What is specific to this
repository is below.

The most useful contribution is **evidence**. A short report that you ran one step and what you saw is worth more than
a long page nobody ran.

## Ground rules

1. **English only.**
2. **One topic per pull request**: one experiment, one decision record, one runbook, one correction.
3. **Sign off every commit** (`git commit -s`), as in every OzarLand repository
   ([Developer Certificate of Origin](https://developercertificate.org/)). Web commits are signed off automatically.
4. **Never raise a status without evidence.** Reading documentation, release notes or source code is not validation
   ([validation status](docs/validation-status.md)). Write `unknown` when you do not know.
5. **No sensitive data** (see the last section).
6. **Say what you did not test.** A claim is scoped to the releases, tool versions and topology it was run on.
7. **AI use is disclosed.** If an agent wrote or helped write your contribution, say so in the pull request, in the
   `Author:` line of the template. Commit messages stay plain descriptions of the change.

## Contribute an experiment or a validation

You ran something from an experiment, a runbook step or your own attempt, on a lab.

1. Open an [experiment report or validation evidence](https://github.com/OzarLand/openstack-upgrade-journeys/issues/new?template=experiment-report.yml)
   issue if you only want to report. Or go straight to a pull request.
2. In a pull request, add:
   - an experiment record from [`docs/templates/experiment-record.md`](docs/templates/experiment-record.md) under
     `journeys/<journey>/experiments/`, named `EXP-NNN-short-topic.md`, with the next free number;
   - a validation record from [`docs/templates/validation-record.yaml`](docs/templates/validation-record.yaml) under
     `journeys/<journey>/validation/`, named `VAL-NNN.yaml`;
   - the redacted evidence under `journeys/<journey>/evidence/EXP-NNN/`.
3. Record the exact versions (OpenStack, Kolla-Ansible, container image tags, host OS, database and message queue
   versions), the topology, the date, who ran it, **the steps you did not run**, and the result, including a failure.
   A failed experiment is a result; it is merged like any other.
4. Do not change the status of a procedure in the same pull request unless the evidence is in it. A status change is
   reviewed against the evidence rules; the person who wrote a procedure does not validate it.

## Contribute a production report

You followed or adapted something from this repository on a real platform, or a similar upgrade, and you want the
community to know what happened.

- Use the same issue form and choose "production" as the environment. A production report is recorded even when it is
  too thin to validate anything: it is supporting information, and it still counts as a warning if it describes a
  failure.
- To move something to `PRODUCTION-VALIDATED`, the report needs the release and tool versions, the topology and
  backends (in general terms), what was run, what was observed, the date or period, and your GitHub handle. Only a
  human operator other than the author of the procedure can provide it.
- Describe your platform at the level of "three controllers, twenty computes, Ceph RBD, OVS". Not names, not
  addresses, not your organisation.

## Correct or challenge something

- A procedure that is wrong, unsafe or missing a warning: use the
  [wrong or unsafe procedure](https://github.com/OzarLand/openstack-upgrade-journeys/issues/new?template=unsafe-or-wrong-procedure.yml)
  form. If following it could cause damage before it is fixed, or you found a secret, use the
  [security policy](SECURITY.md) instead of a public issue.
- A decision you disagree with: add your argument to the decision record's dissent section in a pull request, or open
  an issue. Dissent is content; it is kept, not overwritten.
- A newer upstream release or a changed behaviour: open an issue; affected items become `NEEDS-REVALIDATION`.

## Where knowledge belongs

Journey-specific work stays here. General knowledge goes where OzarLand already keeps it, and is linked from here:
a symptom of a single instance goes to
[openstack-vm-runbooks](https://github.com/OzarLand/openstack-vm-runbooks); how Kolla-Ansible behaves or a
release-to-release note goes to
[kolla-ansible-deployment-patterns](https://github.com/OzarLand/kolla-ansible-deployment-patterns). The
[repository assessment](journeys/ussuri-to-2026.1/assessments/08-repository-organization.md) explains the split.

## Rules for runbooks

- Every step has a validation tag and a risk marker, from [`docs/templates/runbook-step.md`](docs/templates/runbook-step.md).
- Every state-changing step has `> ⚠️ **State-changing.**`; every destructive step has `> 🛑 **Destructive.**`, with the
  [four answers](https://github.com/OzarLand/ozarland/blob/main/docs/conventions/risk-warnings.md): what changes, who
  is affected, what must be true before, how to undo it or why it cannot be undone. Anything touching the database
  directly is destructive. Reviewers may refuse to merge a runbook without these.
- A runbook is `draft` until its steps have been run by someone other than its author; its page status is never higher
  than its weakest step.
- A runbook that depends on a point of no return says where it is, near the top.

## Sensitive data

Never publish, in files, issues, pull requests or comments:

- passwords, tokens, keys, certificates, `passwords.yml`, Keystone or database credentials, `clouds.yaml`, openrc files;
- real hostnames, domains, IP or MAC addresses; use `controller-1`, `example.org`, `192.0.2.0/24`, `fa:16:3e:00:00:01`;
- customer, employer, project or person names (your GitHub handle is fine);
- **database dumps and backups**, even of a lab: they contain tokens, hashes and ids. Describe row counts and queries
  instead;
- unredacted logs and command output. Redact first, and keep the error text.

Evidence is text: command output, redacted logs, row counts, timings. Do not commit images, archives, VM disks or dumps.
The rules are those of the OzarLand
[sensitive data convention](https://github.com/OzarLand/ozarland/blob/main/docs/conventions/sensitive-data.md); the
pull request template asks you to confirm them.
