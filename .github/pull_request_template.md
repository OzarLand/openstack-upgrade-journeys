## What this adds or changes

<!-- One sentence. Link the issue it comes from, if any. -->

Author: <!-- your GitHub handle, or e.g. "OzarLand <role> agent (AI agent)" -->

## Kind of change

- [ ] Experiment record and/or validation record (with evidence)
- [ ] Decision record
- [ ] Assessment, compatibility matrix or dependency graph
- [ ] Runbook, rollback or troubleshooting page
- [ ] Templates, validation rules or other docs
- [ ] Community files

## Evidence and status

<!-- If this adds or changes a status, say which item (EXP-NNN, VAL-NNN, DR-NNN, runbook step) and from what to what.
For a run: release and Kolla-Ansible versions, topology, date, who ran it, steps run and NOT run, result.
Write "no status change" if there is none. Write "not run" for anything you did not run. -->

## Checklist

- [ ] No credentials, `passwords.yml`, `clouds.yaml`, keys, real hostnames, domains, IP or MAC addresses.
- [ ] No database dumps, backups, images or archives; logs and outputs in `evidence/` are redacted.
- [ ] No status is higher than its recorded evidence; reading docs or code is not counted as validation.
- [ ] Unknown values are written `unknown`, not guessed. Claims carry an evidence class and, where they cite upstream, `repo@ref:path`.
- [ ] Every state-changing step has a ⚠️ warning; every destructive step (including any direct database change) has a 🛑 warning.
- [ ] The person who validates is not the author of the procedure.
- [ ] One topic in this pull request.
- [ ] Commits are signed off (`git commit -s`).
- [ ] AI involvement, if any, is stated in the `Author:` line above.
