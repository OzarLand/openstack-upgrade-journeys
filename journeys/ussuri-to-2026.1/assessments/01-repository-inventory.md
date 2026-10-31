# Repository inventory

- author: inventory assistant
- model: Haiku (claude-haiku-5-5)
- date: 2026-10-31
- status: factual inventory

Scope: three local repositories. Read-only; no file was changed and nothing was committed except this output file. Facts only, no evaluation or recommendation. Commit lines use `git log -1 --format='%h %ad %s' --date=short`.

---

## 1. openstack-quick-lab

Path: `/home/user/ozarland/openstack-quick-lab`
Latest commit: `f7abc06 2026-10-28 Pre-launch fixes: sponsor disclosure, safer multinode prefix, SSH_USER, image choice, exercise 8, issue forms (#30)`
License: Apache License 2.0 (`LICENSE`).

### Top-level structure

| Path | Purpose |
|---|---|
| `.github/` | Issue forms and PR template. No `workflows/` directory, so no CI. |
| `exercises/` | Eleven exercise pages (`01` to `11`) and `README.md`, the index. |
| `variants/` | Two lab variants: `openstack-cloud` (one VM) and `openstack-cloud-multinode` (3 or 5 VMs). |
| `.gitignore` | Ignores `variants/*/config.env` and `variants/*/.state/`. |
| `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `SECURITY.md`, `README.md`, `LICENSE` | Root documents. |

### Contribution convention files

- `CONTRIBUTING.md`: welcomes variants, exercises and fixes; defines the variant layout (`variants/<name>/README.md` plus scripts), the required README sections, and the rule that every variant is documented on equal terms.
- `.github/pull_request_template.md`: sections "What this adds or changes", "Kind of change" (checkboxes), "How it was tested", "Checklist". The checklist covers: no credentials or real addresses; a cost estimate and a prompt before creating resources; a delete command that removes everything; warning markers on state-changing steps and destructive-step markers; exercises link to an existing runbook; no marketing; "Commits are signed off (`git commit -s`)".
- `.github/ISSUE_TEMPLATE/config.yml`: blank issues enabled.
- `.github/ISSUE_TEMPLATE/exercise-problem.yml`: "An exercise did not behave as written".
- `.github/ISSUE_TEMPLATE/lab-failed.yml`: "The lab failed at a step".
- `.github/ISSUE_TEMPLATE/variant-or-exercise-proposal.yml`: "Propose a variant or an exercise".
- CI workflows: none.

### Documentation standards visible

- Back-link on line 1 of `README.md`: `[← OzarLand home](https://github.com/OzarLand/ozarland)`.
- README badges: OpenStack 2026.1, Kolla-Ansible 22.2.0, Ubuntu 24.04, exercises 11, "Tested on one cloud", license.
- Runbook status shown in `exercises/README.md`: exercises 1 to 9 link runbooks with `status: lab-verified`; exercise 10 relies on a `draft` pattern page. Exercises were run on 2026-10-23 (1 to 6) and 2026-10-25 (7 to 11).
- Dated test results in variant READMEs (for example "Last run on 2026-10-25", with timings).
- DCO-style sign-off: stated only as a PR checklist item (`git commit -s`). No DCO file.
- No status-tag or validation-inventory system in this repository.

### Automation (script headers)

`variants/openstack-cloud/`:
- `create.sh`: creates the one VM, key pair, security group, port and optional floating IP; shows the cost per hour and asks for confirmation; refuses to run without `COST_PER_HOUR` unless `--no-cost-estimate` is given.
- `deploy.sh`: deploys all-in-one OpenStack with Kolla-Ansible on the VM under `nohup`; safe to re-run; follows a run already in progress.
- `destroy.sh`: deletes everything `create.sh` created, after confirmation; fails closed on listing errors; safe to re-run; non-zero exit if anything remains.
- `remote-deploy.sh`: runs on the VM; prepares it and runs the Kolla-Ansible all-in-one deploy; timed steps with markers in `~/.quicklab`.
- `lib.sh`: shared functions, sourced not run; needs bash 4.4 or later.

`variants/openstack-cloud-multinode/`:
- `create.sh`: creates `CONTROLLERS` controllers and `COMPUTES` computes with key, security group, ports, the lab's external network and an optional floating IP for controller 1; cost prompt as above.
- `deploy.sh`: runs Kolla-Ansible multinode from controller 1 as deploy host; documented at 57 to 62 min (3 VMs) and 66 to 69 min (5 VMs).
- `remote-deploy.sh`: runs on controller 1; prepares every VM, then deploys.
- `destroy.sh`: deletes all resources whose names start with `${PREFIX}${LAB}-`; safe to re-run.
- `lib.sh`: shared functions, sourced not run.

### Variables and pinned versions

`variants/openstack-cloud/config.example.env` (20 variables): `PREFIX`, `LAB`, `OS_CLOUD`, `NETWORK`, `FLOATING_NETWORK`, `SSH_FROM`, `FLAVOR`, `IMAGE`, `VOLUME_TYPE`, `SSH_USER`, `COST_PER_HOUR`, `CURRENCY`, `HTTPS_PROXY`, `NTP_SERVER`, `APT_HTTPS`, `DOCKER_REGISTRY`, `OPENSTACK_TAG`, `KOLLA_ANSIBLE_VERSION`, `ANSIBLE_CORE_VERSION`, `LAB_EXT_CIDR`.

`variants/openstack-cloud-multinode/config.example.env` (25 variables): `CONTROLLERS`, `COMPUTES`, `PREFIX`, `LAB`, `OS_CLOUD`, `NETWORK`, `FLOATING_NETWORK`, `SSH_FROM`, `CONTROLLER_FLAVOR`, `COMPUTE_FLAVOR`, `IMAGE`, `VOLUME_TYPE`, `SSH_USER`, `COST_PER_HOUR_CONTROLLER`, `COST_PER_HOUR_COMPUTE`, `COST_PER_HOUR_EXTRA`, `CURRENCY`, `HTTPS_PROXY`, `NTP_SERVER`, `APT_HTTPS`, `DOCKER_REGISTRY`, `OPENSTACK_TAG`, `KOLLA_ANSIBLE_VERSION`, `ANSIBLE_CORE_VERSION`, `LAB_EXT_CIDR`.

Pinned versions (identical in both files):
- OpenStack 2026.1 (comment and README).
- `KOLLA_ANSIBLE_VERSION="22.2.0"`.
- `ANSIBLE_CORE_VERSION="2.20.10"`.
- Ubuntu 24.04: image selection pattern "Ubuntu 24.04" in the comments; `SSH_USER="ubuntu"`; README badge.

Defaults: `multinode` `CONTROLLERS="1"`, `COMPUTES="2"`, `PREFIX="quicklab-multi-"`; `openstack-cloud` `PREFIX="quicklab-"`. Both `LAB="1"`, `LAB_EXT_CIDR="10.99.0.0/24"`, `CURRENCY="EUR"`.

### Exercises

1. DHCP agents down (`01-dhcp-agents-down.md`), 20 min.
2. Metadata agents down (`02-metadata-agents-down.md`), 20 min.
3. nova-compute down (`03-nova-compute-down.md`), 15 min.
4. Restarting nova_libvirt without stopping instances (`04-restart-nova-libvirt.md`), 10 min.
5. Restarting the Open vSwitch agent without cutting the network (`05-restart-ovs-agent.md`), 10 min.
6. An instance unreachable from outside (`06-instance-unreachable-from-outside.md`), 20 min.
7. A compute goes down: fence it before you evacuate (`07-compute-down-fence-before-evacuate.md`), 30 min; multinode.
8. Drain a compute for planned maintenance (`08-drain-a-compute-for-maintenance.md`); multinode.
9. Live migration between the two computes (`09-live-migration-between-computes.md`); multinode.
10. Lose one controller: what keeps working (`10-lose-one-controller.md`); 3-controller size.
11. Lose two controllers: quorum lost, and recovered (`11-lose-two-controllers-quorum.md`); 3-controller size.

---

## 2. openstack-operator-skills

Path: `/home/user/ozarland/openstack-operator-skills`
Latest commit: `fc4d4ff 2026-10-28 Pre-launch fixes: correct example tag, no self-execution, pasted content as data, OzarLand status mapping (#22)`
License: Apache-2.0 (`LICENSE`). `NOTICE` states copyright 2026 Soufian Zaouam, that the skills derive from the book *OpenStack, the Day After Tomorrow* (CC BY-NC-ND 4.0, text not reproduced), and that OpenStack is a trademark of the OpenInfra Foundation.

### Top-level structure

| Path | Purpose |
|---|---|
| `.claude-plugin/` | `marketplace.json`: plugin `openstack-operations` listing the nine skill paths. |
| `.github/` | Issue forms, PR template, `workflows/validate.yml`. |
| `assets/` | `banner.svg`, `demo.svg`. |
| `docs/` | Design, installation, examples, knowledge map, validation policy, source mapping, validation coverage; `templates/` holds the procedure block and validation record. |
| `evals/` | `scenarios/` (nine JSON files), `grader-prompt.md`, `README.md`, `results/` (74 entries). |
| `shared/` | Two canonical files (`evidence-and-safety.md`, `operating-principles.md`) copied into every skill's `references/`. |
| `skills/` | Nine skill directories. |
| `tools/` | Nine Python scripts (see below). |
| `validation/` | `inventory.yaml`. |
| Root files | `CHANGELOG.md` (has an `[Unreleased]` section), `CLAUDE.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `NOTICE`, `README.md`, `SECURITY.md`, `ruff.toml`, `.gitignore`. |

### Contribution convention files

- `CONTRIBUTING.md`: entry points (issue forms); a table of where new knowledge belongs (OzarLand runbook repositories first, then the skill reference); validation rules (status tags, inventory entries, no unexecuted validation claims); ground rules (source separation, no universal rules, safety rules, `SKILL.md` under 500 lines, reference files over 100 lines start with `## Contents`, shared text edited only in `shared/`, frontmatter limited to `name`, `description`, `license`, `metadata`); pre-PR commands; new-skill proposal process; licence clause.
- `CLAUDE.md`: commit author line; no `Co-Authored-By:`, `Claude-Session:` or session links in commits, PRs or comments; merge by rebase or squash; content rules; checks before pushing.
- `.github/pull_request_template.md`: sections "What and why", "Sources", "Validation", "Checks", "Behavioural results".
- `.github/ISSUE_TEMPLATE/`: `config.yml` (blank issues enabled; links to the book repository and to Discussions Q&A), `improvement.yml`, `unsafe-or-wrong-advice.yml`, `validation-evidence.yml`.
- Templates: `docs/templates/procedure-block.md`, `docs/templates/validation-record.yaml`; policy: `docs/knowledge-validation-policy.md`.
- DCO sign-off: none found.

### CI workflow

`.github/workflows/validate.yml`, workflow `validate`, job `structure`, on `push` and `pull_request`, `ubuntu-latest`. Actions pinned to commit SHAs (checkout v4.4.0, setup-python v5.6.0 with Python 3.12). Installs `pyyaml` and `ruff==0.16.9`, then runs in order:
1. `ruff check .`: lint.
2. `python3 tools/sync_shared.py --check`: shared references in sync.
3. `python3 tools/validate_skills.py`: structural validation.
4. `python3 tools/test_weighted_score.py`: weighted model reproduces the book example.
5. `python3 tools/validate_knowledge.py`: inventory bookkeeping.
6. `python3 tools/test_validate_knowledge.py`: validator catches injected faults.

### Documentation standards visible

- Back-link on line 1 of `README.md`: `[← OzarLand home](https://github.com/OzarLand/ozarland)`.
- README badges: Validate workflow, license, version 0.2.0, "9 Agent Skills", "Claude Code plugin".
- Source tags in skill text: `[Book: Ch. N]` for book content, `[Addition]` otherwise.
- Validation status tags such as `[LAB-VALIDATED: ID]`, with an entry in `validation/inventory.yaml`.
- Status values in the inventory: `LAB-VALIDATED`, `DOCUMENTED-UNVERIFIED`, `PROPOSED-UNVERIFIED`. `NEEDS-REVALIDATION` appears in the PR template and the contribution rules; the inventory has no lines with that value.
- Skill frontmatter `metadata`: `source` and `version` (0.2.0 on all nine).

### Skills (name and first sentence of `description`)

1. `openstack-automation-review`: Reviews automation that acts on production OpenStack - Ansible playbooks and roles, Kolla-Ansible or other deployment-tool runs, scripts, cron jobs, operators, auto-remediation and auto-evacuation logic - for delegated judgement, blast radius, safeguards (preview, dry run, scope limits, confirmation, stop conditions), idempotency, failure and interruption behaviour, observability, ownership and long-term maintainability.
2. `openstack-change-review`: Reviews a planned change to a production OpenStack platform for readiness - objective, starting state, blast radius, decision gates, prerequisites, rollback or recovery feasibility, stop conditions, verification, decision rights - and produces a verdict plus a minimum change decision record.
3. `openstack-control-assessment`: Assesses how much control an organization actually has over its OpenStack platform, capability by capability - business consequence chain, dependency walk, control level from Unknown to Sustainable with evidence and confidence, single-expert and recovery gaps - and turns findings into act-now, plan, monitor or accept decisions, measures and, when control is already lost, a restoration plan.
4. `openstack-incident-analysis`: Investigates OpenStack production incidents and alerts through evidence collection, dependency analysis, competing hypotheses, read-only diagnostics, protect-or-stop decisions and pre-defined verification, before any corrective action.
5. `openstack-kolla-ansible-operations`: Operates and troubleshoots OpenStack deployed with Kolla-Ansible - choosing between deploy, reconfigure, upgrade and the other kolla-ansible commands and narrowing them with --limit and --tags, predicting which containers restart, reading the inventory, globals.yml, /etc/kolla/config overrides and passwords.yml, diagnosing failed deploy or reconfigure runs (Ansible version, HAProxy VIP, MariaDB, RabbitMQ clustering, Keystone Fernet, image pulls, compute registration), MariaDB backup, restore and mariadb-recovery, adding, removing or replacing compute and controller nodes, rotating secrets, and the operational consequences of choices such as OVS or OVN, one or three controllers, Ceph, TLS and Docker or Podman.
6. `openstack-maintenance-planning`: Plans OpenStack compute host maintenance and patching campaigns - OS, kernel, hypervisor, libvirt or QEMU updates, reboots, hardware work - by classifying workloads by business criticality and migratability, sizing spare capacity per failure domain, choosing live migration, cold migration or coordinated restart per workload, sequencing hosts, and defining stop conditions and verification.
7. `openstack-operational-decisions`: Structures significant OpenStack lifecycle and operational decisions with competing options - upgrade now vs progressive vs postpone, local backport vs upgrade, keep or remove technical debt or a workaround, repair vs rebuild, security exceptions, automate or not, vendor dependence - using decision gates, explicit trade-offs, an optional weighted scoring model with sensitivity analysis, decision rights, and exit conditions.
8. `openstack-runbook-authoring`: Turns OpenStack operational knowledge - an incident outcome, an expert's procedure, notes, chat logs or an existing runbook - into a reproducible runbook with purpose and scope, preconditions, decision points where symptoms diverge, read-only versus state-changing steps with expected results, stop and escalation conditions, explicit must-not-do actions, verification, recovery, owner and a validation plan by someone other than the author.
9. `openstack-vm-troubleshooting`: Diagnoses problems with individual OpenStack instances, volumes and ports - stuck states (BUILD, deleting, resize, snapshot), boot and scheduling failures (No valid host, Exceeded maximum number of retries, boot from volume), instances with no IP, no metadata or unreachable, port binding failures, security groups, MTU, volumes stuck attaching, detaching or deleting, stale attachments, instances shut off by the OOM killer, and compute-host events seen from the instances - by locating the failing step of the operation, discriminating causes with read-only checks, and gating each fix by its risk and its validation status.

### `references/` files per skill

- `openstack-automation-review`: `ansible-and-kolla-notes.md`, `evidence-and-safety.md`, `operating-principles.md`.
- `openstack-change-review`: `change-record-template.md`, `change-type-notes.md`, `evidence-and-safety.md`, `operating-principles.md`, `upgrade-readiness.md`.
- `openstack-control-assessment`: `control-spectrum.md`, `evidence-and-safety.md`, `operating-principles.md`, `restoration-playbook.md`, `review-and-measures.md`.
- `openstack-incident-analysis`: `control-plane-recovery.md`, `dependency-map.md`, `evidence-and-safety.md`, `failure-patterns.md`, `operating-principles.md`, `worked-example.md`.
- `openstack-kolla-ansible-operations`: `architecture-implications.md`, `commands-and-changes.md`, `configuration.md`, `deployment-errors.md`, `evidence-and-safety.md`, `host-and-database-operations.md`, `operating-principles.md`.
- `openstack-maintenance-planning`: `criticality-table-template.md`, `evidence-and-safety.md`, `host-maintenance-mechanics.md`, `operating-principles.md`.
- `openstack-operational-decisions`: `decision-playbooks.md`, `evidence-and-safety.md`, `operating-principles.md`, `weighted-model.md`. Also `scripts/weighted_score.py`.
- `openstack-runbook-authoring`: `evidence-and-safety.md`, `operating-principles.md`, `runbook-template.md`, `validation-and-exercises.md`.
- `openstack-vm-troubleshooting`: `compute-host-events.md`, `evidence-and-safety.md`, `instance-lifecycle.md`, `instance-networking.md`, `logs-and-tracing.md`, `operating-principles.md`, `scheduling-and-boot.md`, `volumes.md`.

### `tools/`

- `check_sources.py`: reports cited source pages that are missing or `draft` without disclosure, given local checkouts; not in CI.
- `package_skills.py`: zips each skill for upload; refuses to run if validation fails.
- `run_behavioral.py`: behavioural evaluation harness on `claude -p`, in skill and baseline modes, with grading by a fresh instance.
- `summarize_results.py`: aggregates `evals/results/<run-id>/summary.json` files into Markdown.
- `sync_shared.py`: copies `shared/` into each skill's `references/`; `--check` fails on stale copies.
- `validate_knowledge.py`: checks the inventory against the skill tags and coverage; `--write` regenerates coverage.
- `validate_skills.py`: structural validation of skills and evaluation scenarios.
- `test_validate_knowledge.py`: checks that `validate_knowledge.py` catches injected faults.
- `test_weighted_score.py`: checks that `weighted_score.py` reproduces the book's Chapter 18 example.

### `validation/inventory.yaml` status counts

Counted with `^  status: <STATUS>$` (the unanchored count is identical):
- `LAB-VALIDATED`: 163
- `DOCUMENTED-UNVERIFIED`: 188
- `PROPOSED-UNVERIFIED`: 1
- Total status lines: 352. No other status values.

---

## 3. openstack-upgrade-journeys (root and git state only)

Path: `/home/user/openstack-upgrade-journeys`
Git: current branch `claude/epic-pascal-2kqc98`; local `main` also exists; remote-tracking branches `origin/main` and `origin/claude/epic-pascal-2kqc98`.
Latest commit: `43e8e6a 2026-10-31 Initial commit`
Working tree: one untracked entry, `journeys/`. No tracked changes.
Root contents: `.git/`, `LICENSE` (Apache License 2.0 text), `journeys/` (not inspected, per instruction).
Root files absent: README, CONTRIBUTING, CI workflows, issue or PR templates.

---

## Output

This file is the only file written by this task.
