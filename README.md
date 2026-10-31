[← OzarLand home](https://github.com/OzarLand/ozarland)

<div align="center">

# 🧭 openstack-upgrade-journeys

### Bringing legacy OpenStack clouds back to a modern release, safely and with evidence

**Many production clouds still run OpenStack releases that went out of maintenance years ago. This project builds
open, evidence-based paths to bring them back to a current release without losing a single VM, volume, network or
user. The first journey takes a Kolla-Ansible Ussuri cloud (2020) to OpenStack 2026.1.**

<p>
  <img src="https://img.shields.io/badge/journey-Ussuri%20%E2%86%92%202026.1-ED1944.svg" alt="Journey: Ussuri to 2026.1">
  <img src="https://img.shields.io/badge/status-lab%20experiments-orange.svg" alt="Status: lab experiments">
  <img src="https://img.shields.io/badge/lab--verified-database%20fast--forward-yellowgreen.svg" alt="Lab-verified: database fast-forward">
  <img src="https://img.shields.io/badge/production--validated-0-lightgrey.svg" alt="0 production-validated procedures">
  <img src="https://img.shields.io/badge/deployment-Kolla--Ansible-informational.svg" alt="Deployment: Kolla-Ansible">
  <img src="https://img.shields.io/badge/written%20with-AI%20agents-8A2BE2.svg" alt="Written with AI agents">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="License: Apache-2.0"></a>
</p>

<p>
  <a href="#-why-this-project"><b>Why</b></a> ·
  <a href="#-first-results-ussuri--20261"><b>First results</b></a> ·
  <a href="#️-journeys"><b>Journeys</b></a> ·
  <a href="docs/validation-status.md"><b>Validation rules</b></a> ·
  <a href="#-contributing"><b>Contribute</b></a>
</p>

</div>

---

Part of [OzarLand](https://github.com/OzarLand/ozarland): *a shared land for better OpenStack operations.*
Led by Soufian Zaouam.

## 🚀 Why this project

Operators of older clouds all face the same wall. The official upgrade path moves one release at a time, or one SLURP
step at a time. From Ussuri, that means **nine upgrades**, **eight intermediate deployments** and **several host
operating-system changes** before reaching a maintained release. Many teams postpone it, and their platforms age
further: security fixes stop, skills fade, and the gap keeps growing.

This repository works on that problem in the open, with the community:

- **One journey per gap.** Each journey covers a starting release and a deployment method, and asks a precise
  question: *can we get there without deploying every release in between, and what is the safest way?*
- **Evidence before advice.** Every claim carries its status: officially supported, technically possible but
  unsupported, lab-verified, or not validated. Failed experiments are published too; they are knowledge.
- **Reproducible laboratories.** Experiments run on copies of a preserved baseline. Their scripts and evidence are in
  this repository, so anyone can re-run them.
- **Independent review.** A separate red-team role challenges every proposal and every result before it is accepted.
- **Workloads first.** VM identity, IP addresses, volumes, images, users and quotas must survive. A successful service
  start is never mistaken for a successful migration.

## 🔬 First results: Ussuri → 2026.1

Work started on 2026-10-31. What is known so far:

| Finding | Status |
|---|---|
| A single direct jump from Ussuri to 2026.1 is **impossible**: 2026.1 Nova, Keystone and Cinder cannot read a Ussuri database. | Confirmed in the lab |
| The databases of every service **can** be brought from Ussuri to 2026.1 **without deploying any intermediate release**, by running the migration code of 2023.1, Cinder 2023.2, 2024.1, 2025.1 and 2026.1 offline. Zero unexpected schema or data difference. | Lab-verified, synthetic data, **unsupported upstream** |
| 2026.1 services start on the migrated databases and find every existing resource again (servers, ports, volumes, images, users, trusts). | Lab-verified, synthetic data |
| A Cinder bug breaks the **official** 2023.1 → 2024.1 upgrade for clouds with old deleted volumes; avoidance documented. | [Documented](journeys/ussuri-to-2026.1/troubleshooting/cinder-use-quota-null-blocks-2024.1-db-sync.md) |
| Kolla-Ansible 2026.1 changes some data when deployed on existing databases (cells, admin password, endpoints); five mandatory steps identified. | Lab-verified for the commands, Kolla itself not yet run |

Still ahead:

- operations on existing resources and a rollback rehearsal;
- a real Kolla-Ansible laboratory with real VMs;
- a run on a sanitized production copy.

Then comes the runbook. The full picture is in the [journey page](journeys/ussuri-to-2026.1/README.md) and the
[progress report](journeys/ussuri-to-2026.1/reports/2026-10-31-progress-report-01.md).

> [!WARNING]
> **Nothing here is a supported or production-validated procedure yet.** Upgrading across several OpenStack releases
> at once is not what upstream OpenStack or Kolla-Ansible document or test. "Lab-verified" means a laboratory run with
> stated limits: a container lab, synthetic data, no Kolla images and no real VMs. Never run a step on a platform
> whose data you cannot afford to lose without your own backups, rehearsal and change review.

> [!NOTE]
> **How this is built.** The investigation is carried out by a team of AI agents with separate roles: architect,
> release compatibility, Kolla-Ansible, database and messaging, laboratory, operations, documentation and an
> independent red team. They work from the upstream OpenStack sources and the
> [OzarLand operator skills](https://github.com/OzarLand/openstack-operator-skills), under the direction of the
> OzarLand owner. No human operator has confirmed a result on a real platform yet, and that is exactly the
> contribution we are looking for.

## 🤝 Running an old cloud? Join in

- **Tell us your starting point:** release, deployment tool, backends, size. It shapes the next journeys.
- **Re-run an experiment** on your own lab and report what you saw, whether it worked or failed.
- **Share production experience** of long upgrades: what broke, what you would do differently.

Start a thread in [OzarLand Discussions](https://github.com/OzarLand/ozarland/discussions) or open an issue here.

## 🗺️ Journeys

| Journey | Question | Stage | Validated |
|---|---|---|---|
| [Ussuri → 2026.1](journeys/ussuri-to-2026.1/README.md) | Can an existing Kolla-Ansible Ussuri deployment reach 2026.1 in one journey? If not, what is the safest path with the fewest intermediate deployments? | Lab experiments | Database fast-forward lab-verified (narrow scope); nothing production-validated |

More journeys (other start releases, other deployment methods) are welcome through an
[*Ideas* discussion](https://github.com/OzarLand/ozarland/discussions/new?category=ideas); a journey is added when someone
is ready to investigate it.

## 🏷️ How claims are labelled

Two vocabularies are used, and they answer different questions.

**What a claim is** (evidence class), for statements about what is possible:
*Officially supported*, *Technically possible but unsupported*, *Experimentally validated* (only when run in a lab with
recorded evidence), *Not validated*, *Incompatible*.

**How well a procedure or experiment has been tested** (validation status), written next to every step:

| Status | In one line | OzarLand page status |
|---|---|---|
| `PROPOSED-UNVERIFIED` | An idea written here; nobody ran it | `draft` |
| `DOCUMENTED-UNVERIFIED` | Taken from upstream docs or code; nobody ran it | `draft` |
| `LAB-VALIDATED` | Run on a lab, result recorded with evidence | `lab-verified` |
| `PRODUCTION-VALIDATED` | A human operator, not the author, confirmed it on a real platform | `validated` |
| `NEEDS-REVALIDATION` | Was validated, something changed | `experimental` |
| `FAILED` | Run and did not work as written; the failure is kept as a warning | not published as a procedure |

Definitions, evidence rules and the mapping to the other OzarLand repositories are in
[`docs/validation-status.md`](docs/validation-status.md). Today every count is zero.

## 🗂️ Repository layout

```text
journeys/<from>-to-<to>/
  README.md                the journey: question, status, map of documents
  compatibility-matrix.md  what is supported or not, release by release
  dependency-graph.md      what must move before what
  assessments/             specialist reports, one per agent and topic
  decision-records/        DR-NNN: one decision, its alternatives and dissent
  experiments/             EXP-NNN: hypothesis, steps, evidence, conclusion
  validation/              VAL-NNN.yaml: structured result of one validation
  evidence/                redacted outputs referenced by experiments
  runbooks/                steps to follow, only built from validated knowledge
  rollback/                what can be undone, and from which point it cannot
  troubleshooting/         symptoms met during the journey
  lessons-learned.md
docs/
  validation-status.md     status definitions, evidence rules, mapping
  templates/               experiment, decision, validation record, runbook step
```

## 🤝 Contributing

The most valuable contribution is **evidence**: you ran a step of an experiment on a lab or on a real platform, and
it worked, failed or worked partly. Second: a step or a claim that is wrong or unsafe.

- Report a run: [experiment report or validation evidence](https://github.com/OzarLand/openstack-upgrade-journeys/issues/new?template=experiment-report.yml)
- Report a wrong or unsafe procedure: [wrong or unsafe procedure](https://github.com/OzarLand/openstack-upgrade-journeys/issues/new?template=unsafe-or-wrong-procedure.yml)
- Anything else, and the rules (sign-off, one topic per pull request, redaction): [CONTRIBUTING.md](CONTRIBUTING.md)

Never publish credentials, real hostnames or addresses, database dumps or unredacted logs
([sensitive data](https://github.com/OzarLand/ozarland/blob/main/docs/conventions/sensitive-data.md)).

## 🌍 Part of OzarLand

**OzarLand: a shared land for better OpenStack operations.** It started as a personal initiative by Soufian Zaouam
to share practical OpenStack operational knowledge, and it is meant to grow into a space where operators exchange
experience, document solutions and help each other run more reliable platforms. It is open to everyone: your
knowledge, questions and corrections are welcome.

| | Repository | What it holds |
|:-:|---|---|
| | [ozarland](https://github.com/OzarLand/ozarland) | Start here: newcomer path, community rules, [Discussions](https://github.com/OzarLand/ozarland/discussions) |
| 🔧 | [openstack-vm-runbooks](https://github.com/OzarLand/openstack-vm-runbooks) | Symptom-driven runbooks for instance problems |
| 🏗️ | [kolla-ansible-deployment-patterns](https://github.com/OzarLand/kolla-ansible-deployment-patterns) | Ways to deploy with Kolla-Ansible, compared |
| 🧪 | [openstack-quick-lab](https://github.com/OzarLand/openstack-quick-lab) | A disposable OpenStack lab to practise on |
| 🤖 | [openstack-operator-skills](https://github.com/OzarLand/openstack-operator-skills) | Claude skills that apply this knowledge |
| 🧭 | `openstack-upgrade-journeys` **(you are here)** | Investigations of hard upgrade paths, with their evidence |

<!-- The last row is proposed. Adding a repository to this block is an owner decision and must be applied to every
     OzarLand repository in the same round of pull requests (docs/conventions/readme-identity.md). -->

## ⚖️ License

[Apache-2.0](LICENSE). OzarLand is not affiliated with the OpenStack Foundation, the OpenInfra Foundation or any
vendor; OpenStack and Kolla-Ansible are the work of their upstream communities.
