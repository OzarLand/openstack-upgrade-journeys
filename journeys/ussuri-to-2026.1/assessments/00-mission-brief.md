# Mission brief for agents (Stage 1)

Shared context for every agent of the Ussuri → 2026.1 journey. Read it fully before starting.

## The question

Can an existing Kolla-Ansible **Ussuri** OpenStack deployment reach **OpenStack 2026.1** through a single upgrade
journey, without deploying and operating every intermediate release? If not, what is the safest practical path with
the fewest intermediate deployments? Data integrity and operational safety beat speed. Never present an unsupported
procedure as supported.

Release train (for reference, verify yourself): Ussuri (2020.1), Victoria, Wallaby, Xena, Yoga, Zed, 2023.1 Antelope
(SLURP), 2023.2 Bobcat, 2024.1 Caracal (SLURP), 2024.2 Dalmatian, 2025.1 Epoxy (SLURP), 2025.2 Flamingo,
2026.1 (SLURP). Kolla-Ansible for Ussuri is 10.x; for 2026.1 it is 22.x.

## Workspace (all local, already present)

| Path | What |
|---|---|
| `/home/user/openstack-upgrade-journeys` | The journey repository (git, branch `claude/epic-pascal-2kqc98`). Write deliverables only where your brief says. Do **not** commit: the architect commits. |
| `/home/user/ozarland/openstack-operator-skills` | OzarLand skills. `skills/<name>/SKILL.md` and `references/`. Validation policy: `docs/knowledge-validation-policy.md`. |
| `/home/user/ozarland/openstack-quick-lab` | OzarLand lab scripts (2026.1 only, needs an OpenStack cloud account). |
| `/home/user/ozarland/kolla-ansible-deployment-patterns` | OzarLand Kolla-Ansible pages; `version-notes/` holds a 2025.1→2026.1 upgrade report (lab-run). |
| `/home/user/ozarland/ozarland` | Community rules: `docs/conventions/`, `docs/knowledge-lifecycle.md`, `docs/review-policy.md`, `docs/agents.md`. |
| `/home/user/src/{nova,neutron,keystone,glance,cinder,placement,horizon,kolla,kolla-ansible,requirements,oslo.db,releases}` | Upstream OpenStack git repos (GitHub mirrors), partial clones with **all** branches and tags, no checkout. Read files with `git -C /home/user/src/nova show <ref>:<path>`, list with `git ls-tree -r --name-only <ref> <dir>`, `git log`. Old series exist as tags `<series>-eol` (e.g. `ussuri-eol`) or branches `origin/unmaintained/<series>`, current ones as `origin/stable/<series>`. Blobs download on demand (a first read can take a few seconds). |

The shared clones are read-only for you: do not check out, reset or modify them. If you need a working tree, use
`git worktree add` into your own scratch dir, or `git show`.

## Network constraints of this environment (as of 2026-10-31)

- Reachable: GitHub over git (clone/fetch), PyPI (`pip download`), Docker Hub **library** images (mariadb, rabbitmq,
  ubuntu, python).
- **Blocked**: docs.openstack.org, opendev.org, releases.openstack.org, tarballs.opendev.org, quay.io; GitHub web pages
  via curl return 403 (use git).
- Docker Hub `kolla/*` images (Ussuri…Yoga tags still listed) answer **401** to an anonymous pull token; tag metadata shows
  `status: inactive`. Treat this as a finding to verify, not a certainty about the outside world.
- No KVM, no kernel modules dir, 4 vCPU, 15 GB RAM, ~30 GB free disk, Docker 29 (daemon running), Ubuntu 24.04 host,
  Python 3.13.
- No OpenStack cloud credentials: openstack-quick-lab's cloud variants cannot be run from here.

Use the upstream source trees (docs sources live in `doc/source/`, release notes in `releasenotes/notes/`, upgrade
guides in `doc/source/admin/upgrades*` / `doc/source/user/upgrade*`, migrations under `*/db/*migrat*`) as your primary
evidence. Cite every important finding as `repo@ref:path` (and line or symbol when useful), or a commit SHA.

## Evidence and status vocabulary (mandatory)

Classify every claim as one of: **Officially supported**, **Technically possible but unsupported**, **Experimentally
validated** (only if executed in this mission's lab, with evidence), **Not validated**, **Incompatible**.

Validation statuses for procedures/experiments: `PROPOSED-UNVERIFIED`, `DOCUMENTED-UNVERIFIED`, `LAB-VALIDATED`,
`PRODUCTION-VALIDATED`, `NEEDS-REVALIDATION`, `FAILED`. Reading code or docs is never validation. No invented
outputs, versions, dates or results: write `unknown` when you do not know, and say what would establish it.

## OzarLand skills (mandatory)

Read the SKILL.md of the skills your brief names and apply them. Reference them by name where they shaped your
reasoning. The nine skills: openstack-kolla-ansible-operations, openstack-change-review,
openstack-maintenance-planning, openstack-operational-decisions, openstack-runbook-authoring,
openstack-automation-review, openstack-vm-troubleshooting, openstack-incident-analysis, openstack-control-assessment.

## Conventions

English. Markdown. Plain, operator-oriented writing. Mermaid for diagrams. No credentials, real hostnames or
addresses. Start each deliverable with a metadata block: author agent and role, model, date (2026-10-31), status,
inputs read. Keep a "Open questions / what I could not verify" section at the end of each deliverable.
