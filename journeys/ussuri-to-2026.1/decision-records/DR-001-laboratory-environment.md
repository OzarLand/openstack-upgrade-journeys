# DR-001 — Laboratory environment for the first experiments

| Field | Value |
|---|---|
| Decision ID | DR-001 |
| Date | 2026-10-31 |
| Responsible agent | Agent 1 — OpenStack Upgrade Architect (lab implementation by Agent 5) |
| Status | Decided for Stage 1–4. To be revisited when a cloud account or a KVM host is available. |

## Context

The mission asks for a Kolla-Ansible Ussuri laboratory built with openstack-quick-lab. The architect probed the
environment available to this mission on 2026-10-31:

| Probe | Result |
|---|---|
| openstack-quick-lab variants | Both create VMs on an OpenStack cloud through `clouds.yaml`. No cloud account is available here (`~/.config/openstack` absent, no `OS_*` variables). Both are pinned to 2026.1 / Kolla-Ansible 22.2.0 / Ubuntu 24.04. |
| Host | Ubuntu 24.04 container, kernel 6.18, 4 vCPU, 15 GB RAM, ~30 GB free disk, no `/dev/kvm`, no `/lib/modules`. Docker 29 daemon can run. |
| Kolla Ussuri images | Docker Hub still lists the `kolla/ubuntu-source-keystone` tag `ussuri` (last pushed 2022-12-31, `status: inactive`), but `registry-1.docker.io` answers **HTTP 401** to the manifest request even with an anonymous pull token, for `ubuntu-source`, `ubuntu-binary` and `centos-source`. |
| quay.io, opendev.org, docs.openstack.org, tarballs.opendev.org | Blocked by this environment's egress policy. |
| GitHub over git, PyPI, Docker Hub library images | Reachable: `mariadb:10.3`, `rabbitmq:3.8-management` and `ubuntu:18.04` pulled. `pip download nova==21.2.4` (Ussuri) works. |

## Alternatives

1. **Kolla-Ansible Ussuri on a cloud VM through quick-lab.** This is the representative option. It is blocked here:
   there are no cloud credentials, the Ussuri images are not pullable, and a nested lab would need Ubuntu 18.04.
   Agent 5 designs it as a quick-lab extension so that it can run as soon as a cloud account and an image mirror
   exist.
2. **Rebuild Kolla Ussuri images locally with `kolla-build`.** Possible in principle. Agent 5 time-boxes a probe.
   Even if it works, there is no KVM and no OVS datapath, so it would give a control plane without a real data plane.
3. **A container control-plane lab built from upstream code (chosen for now).** MariaDB, RabbitMQ and Memcached from
   Docker Hub library images. The real Ussuri services come from PyPI under the `ussuri-eol` upper-constraints. Real
   resources are created through the real APIs, with nova's fake virt driver. This exercises exactly what the central
   research question depends on: the databases and the migration code of every release.

## Decision

Use alternative 3 now, and design alternative 1 as a quick-lab extension (`lab/` in this repository, and later a
contribution proposal to openstack-quick-lab).

## Consequences and limits (stated up front)

- Results from this lab can support claims about **database schema and data migration**, under the scope "upstream
  service code from PyPI, MariaDB library image". They cannot support claims about:
  - Kolla-Ansible playbooks, container images or `/etc/kolla` transformations;
  - the data plane (OVS flows, qemu processes, libvirt);
  - workload continuity, or high availability.
- Under the validation policy, such results are at most `LAB-VALIDATED` for the database-migration claim, with the
  topology recorded as "container control plane, fake virt driver, no Kolla". They never validate the end-to-end
  Kolla-Ansible journey.
- The image availability finding is itself operationally important. An operator who wants a rollback path to Ussuri
  must hold a private mirror of the exact Ussuri images they run. Kolla-Ansible Ussuri cannot pull them back from
  Docker Hub, as observed from this environment.
