[← OzarLand home](https://github.com/OzarLand/ozarland)

<div align="center">

# 🧭 openstack-upgrade-journeys

**Worked investigations of hard OpenStack upgrade paths: what is supported, what is only possible, what was tried in a
lab, and what happened. The first one asks whether Kolla-Ansible Ussuri can reach OpenStack 2026.1 without deploying
every release in between.**

<p>
  <img src="https://img.shields.io/badge/status-early%20investigation-orange.svg" alt="Status: early investigation">
  <img src="https://img.shields.io/badge/validated%20procedures-0-lightgrey.svg" alt="0 validated procedures">
  <img src="https://img.shields.io/badge/journey-Ussuri%20%E2%86%92%202026.1-ED1944.svg" alt="Journey: Ussuri to 2026.1">
  <img src="https://img.shields.io/badge/deployment-Kolla--Ansible-informational.svg" alt="Deployment: Kolla-Ansible">
  <img src="https://img.shields.io/badge/written%20with-AI%20agents-8A2BE2.svg" alt="Written with AI agents">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="License: Apache-2.0"></a>
</p>

<p>
  <a href="#-journeys"><b>Journeys</b></a> ·
  <a href="#-how-claims-are-labelled"><b>Status labels</b></a> ·
  <a href="docs/validation-status.md"><b>Validation rules</b></a> ·
  <a href="#-contributing"><b>Contribute</b></a>
</p>

</div>

---

> [!WARNING]
> **Nothing in this repository is a supported or tested upgrade procedure.** Upgrading across several OpenStack
> releases at once is not what upstream OpenStack or Kolla-Ansible document or test. Read what is written here as
> research notes. Do not run any step on a platform whose data you cannot afford to lose, and never on production
> without your own backups, your own lab rehearsal and your own change review.

> [!NOTE]
> **Status: early (Stage 1, investigation).** No procedure here has been validated yet: the journey is being studied
> from upstream source code and documentation, and the lab experiments are being designed. Reading code or
> documentation is never counted as validation. This repository was created and is being written by a team of AI
> agents (Claude) working from the OzarLand knowledge base and the upstream sources, under the direction of the
> OzarLand owner. No human operator has confirmed anything yet. The agent team is listed in the
> [journey page](journeys/ussuri-to-2026.1/README.md#the-agent-team).

Part of [OzarLand](https://github.com/OzarLand/ozarland): *a shared land for better OpenStack operations.*

Operators with an old Kolla-Ansible deployment often ask the same question: "do I really have to deploy every
release between mine and the current one?" The official answer covers one release at a time, or one SLURP step.
Anything longer is unsupported, so the community has little to rely on. This repository collects, for each such
journey, the evidence, the experiments, the decisions and, only when earned, the runbooks, with the validation
status of each claim written next to it.

## 🗺️ Journeys

| Journey | Question | Stage | Validated |
|---|---|---|---|
| [Ussuri → 2026.1](journeys/ussuri-to-2026.1/README.md) | Can an existing Kolla-Ansible Ussuri deployment reach 2026.1 in one journey? If not, what is the safest path with the fewest intermediate deployments? | 1: investigation | nothing |

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
