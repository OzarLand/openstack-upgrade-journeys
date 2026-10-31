# Recovery and rollback plan: Ussuri to 2026.1

| | |
|---|---|
| Author | Agent 6, OpenStack Operations and Reliability Expert (OzarLand multi-agent team, Stage 1) |
| Model | Sonnet (high reasoning) |
| Date | 2026-10-31 |
| Status | `PROPOSED-UNVERIFIED`. No step here has been run. Procedures cited from OzarLand skills carry their own lab tags (2026.1 labs, not this journey). |
| Inputs read | `00-mission-brief.md`; `openstack-change-review` (`SKILL.md` steps 6-7, `upgrade-readiness.md`), `openstack-kolla-ansible-operations` (`host-and-database-operations.md` "MariaDB backup and restore", "Recovering a stopped Galera cluster"; `architecture-implications.md` "From 2025.1 to 2026.1"), `openstack-incident-analysis` (`control-plane-recovery.md`), `openstack-maintenance-planning`, `openstack-control-assessment`; upstream `nova@origin/stable/2026.1:nova/objects/service.py:284`. |
| Companions | `06-operational-risk-assessment.md`, `06-workload-preservation-strategy.md` |

Rule that frames this file (`openstack-change-review` step 6): "We have rollback" must mean a credible path and a known-good state to return to. If no credible recovery exists, the change fails the recovery gate and the verdict is "not ready", not a score. Describe what proceeding would mean to the accountable owner, and keep the verdict.

---

## 1. What "rollback" means here, precisely

There is no downgrade of an OpenStack schema or of a Kolla-Ansible deployment. The `openstack-kolla-ansible-operations` skill states it for 2025.1 to 2026.1: `kolla-ansible upgrade` recreates every container and runs schema migrations; there is no downgrade; 2025.1 images do not run on a 2026.1 schema; "the way back after it: restore databases and `/etc/kolla`, redeploy 2025.1 images, losing everything since the backup" (KA-ARCH-28, `DOCUMENTED-UNVERIFIED`). The same holds across Ussuri to 2026.1, with more rows in the loss column.

What a "return to the previous state" consists of, in full. **All** of these must exist, not most:

| Component of the old state | Where it lives | Backed up how | Fails if missing |
|---|---|---|---|
| Every service database at one point in time (keystone, nova, nova_api, nova_cell0, neutron, cinder, glance, placement, heat if used, others) | One Galera cluster (Kolla-Ansible default shard) | `kolla-ansible mariadb-backup` (Mariabackup, no downtime, files on `mariadb_backup_host` only, root-only directory `full-<date>-<id>/`, off-host copy needed) (`host-and-database-operations.md`, KA-OPS-12 `LAB-VALIDATED`; KA-OPS-13 off-host copy `DOCUMENTED-UNVERIFIED`) | Restore returns to a mix of times if services were writing during the backup; take it with the API frozen |
| Deployment configuration | `/etc/kolla/`, `globals.yml`, `passwords.yml`, inventory, custom config overrides, certificates | File copy, off-host, versioned | Cannot redeploy the same cloud; passwords differ from DB hashes |
| Keystone Fernet and credential keys | Keystone key repositories on controllers | File copy, off-host, encrypted | Tokens, EC2 and application credentials unusable after restore |
| Ussuri container images and the Kolla-Ansible/Ansible/Python toolchain that deploys them | Hosts' local Docker store, a registry, the deploy host's virtualenv | `docker save` per image on every host, private registry mirror, frozen `pip freeze` and wheel cache | **Rollback cannot redeploy.** The brief reports public Ussuri tags `inactive` and 401 to anonymous pulls; that is a finding to verify, not a certainty about the outside world. `kolla-ansible prune-images` or `docker rmi` of old tags "removes the quickest way back" (KA-ARCH-30, `LAB-VALIDATED`) |
| Host OS and host configuration (Bionic, kernel, OVS kernel module, netplan/network config, bonds, VLANs, MTU, Docker daemon config, chrony, local users, LVM VG for Cinder) | Each host's disk | Image or file-level backup; **better: keep old system disks aside** or install the new OS on new disks | A reinstalled host cannot return to Bionic unless the old disk or an image exists |
| Local ephemeral instance disks | `/var/lib/docker/volumes/nova_compute/_data` on each compute | Not backed up by the database backup. Block migration, snapshot, or filesystem copy | Data loss on reinstall |
| Cinder data (Ceph pools, LVM VG) | Storage backend | Backend-native snapshot/replication; Cinder backups to a target | A DB restore does not restore data written after the backup, and volume deletions made after the backup are not undone in the DB |
| Glance image bytes | File store or Ceph pool | Backend copy | Image rows restored, bytes gone |
| RabbitMQ state | Not needed to restore; can be reset | Not backed up | n/a (but see `control-plane-recovery.md` for reset caveats) |

**What a DB restore does not restore** (`host-and-database-operations.md`, "Restore a Galera cluster", *Destructive*): "every OpenStack database returns to the backup; everything written after it is unknown to OpenStack while hypervisors, Ceph and network may still hold it." Instances created, resized, deleted, volumes attached, ports created, FIPs allocated after the backup are an inconsistency between the database and the world, and each needs reconciliation by hand. This is why a rollback decision gets harder with every minute after the point of no return, and why the freeze (phase P2 below) is a safeguard, not a convenience.

Galera restore evidence from OzarLand's lab: both emptied nodes took a full SST one after another, the recovery took 3 min 9 s, all `Synced`, data at the incremental's point, with ~100 MB of data. "Not run: single-node restore, several incrementals, a large database (SST and role time-outs)" (KA-OPS-14). The production restore time is `unknown` until measured.

---

## 2. Gates before any irreversible step (G1-G8)

A phase marked `Destructive` below does not start until all eight hold, each with evidence the approver can see.

| Gate | Condition | Evidence | Skill source |
|---|---|---|---|
| G1 Restore proof | The DB backup and `/etc/kolla` backup have been **restored once on a scratch host** by a person other than the author, compared against production, timed at production size | Restore log, diff of row counts per table and service lists, wall-clock time | `control-spectrum.md` "We have backups"; 2025.1 to 2026.1 notes go/no-go ("restored once on a scratch host") |
| G2 Image and toolchain supply | Every container image of every release you may deploy **or roll back to** is saved locally on each host and mirrored in a private registry, digests recorded; the deploy-host toolchain for each release is frozen | Digest list, `docker images` on each host, a test pull from the private registry on a clean host | Brief (Ussuri tags inactive, 401); `architecture-implications.md` KA-ARCH-30 |
| G3 Representative rehearsal | The whole sequence (including the failing paths) has been executed on a non-production environment of the same shape and a copy of production data, with timings recorded | Rehearsal report with measured durations and defects | `upgrade-readiness.md` ("Test coverage"); "one all-in-one run does not validate a multinode rolling upgrade" |
| G4 Capacity | Per-failure-domain spare capacity covers the batch size and the migration concurrency | Calculation with real numbers | `openstack-maintenance-planning` step 5 |
| G5 Business criticality and owner approval | Criticality table exists; each owner has agreed the downtime/degradation class for their workloads | Table; recorded approvals | `criticality-table-template.md`; `operating-principles.md` "Technical teams assess technical risk; authorized owners accept business risk" |
| G6 Single-writer and fencing | There is no state in which two planes (or two copies of a DB) can both write to the same Ceph image, LVM volume, nova local disk or compute host. Old-plane control channels to a converted host are removed | Written ownership rule, fenced hosts list | Companion file, single-writer rule |
| G7 Monitoring | Alerts and dashboards exist for the **new** state, and the old state's alerts are known to still fire: compute service down, agents `XXX`, Galera size/state, RabbitMQ alarms and queue growth, libvirt domain count vs Nova instance count, floating IP probes | Screenshots of alert tests | `upgrade-readiness.md` "Monitoring readiness" |
| G8 Decision rights | Named person can approve, named person can stop; both reachable during the window; the on-call can reach them | Roster and contact test | `openstack-change-review` step 9 |

If a gate fails because a condition is missing, the first recommended action is to create the condition, not to choose (`openstack-operational-decisions` step 5).

---

## 3. Phase plan with point of no return, restorability, stop conditions, approver

Phases are common to all strategies; rows say where a strategy differs. Role names are placeholders for the organisation to fill: **Platform owner** (accountable for the cloud and its recovery), **Service owner** (business owner of a workload), **Change authority** (can accept a `Destructive` change; may be the same as platform owner), **Rehearsal reviewer** (a person who did not write the procedure).

### P0. Inventory and rehearsal (no production change)

| | |
|---|---|
| Actions | Establish the facts listed as `unknown` in the risk assessment: libvirt/QEMU versions, machine types, `nova_libvirt` `PidMode`, firewall driver, L3 HA, DHCP lease, device-bound instances, local-disk instances, storage backends, host counts, failure domains. Complete the criticality table. Build the rehearsal environment. Produce G1-G8 evidence |
| Point of no return | None |
| Restorable | Everything (nothing changed) |
| Prerequisites | Read-only access; a rehearsal environment (hardware or nested; **this mission's environment has no KVM**, so a real lab must be arranged elsewhere) |
| Stop conditions | The inventory shows a feature that the chosen path cannot handle (e.g. DVR, vGPU, `direct-physical` ports, Zun/Kuryr style services that later releases drop, or an unsupported Neutron mechanism driver) with no owner-approved handling |
| Approver | Platform owner |
| Strategy notes | C needs the same inventory plus a list of integrations that store UUIDs. D adds the question whether Keystone's DB is carried. |

### P1. Backup and restore proof

| | |
|---|---|
| Actions | Enable Mariabackup (`enable_mariabackup: "yes"`, `kolla-ansible reconfigure --tags mariadb`; containers restart one by one if configuration changed), take a full backup, copy it off-host, restore it on a scratch host, compare. Back up `/etc/kolla`, keys, certs. Save images (G2). Backend-level snapshots of Ceph pools/LVM where available |
| Point of no return | None |
| Restorable | Everything |
| Prerequisites | Disk space off-host; a scratch host; the skill's procedure (`host-and-database-operations.md`) adapted to Ussuri's MariaDB (which version Ussuri runs is `unknown`; the OzarLand procedure was run on MariaDB 11.4 on 2026.1 and is not validated for the Ussuri MariaDB image or tooling) |
| Stop conditions | Restore not reproducible; row counts differ; restore time greater than the downtime the owner accepts for a full-failure case |
| Approver | Platform owner, with Rehearsal reviewer sign-off |
| Strategy notes | All strategies. In C, only the old cloud is backed up; the new cloud starts empty. |

### P2. Controlled degradation (freeze)

| | |
|---|---|
| Actions | Announce. Stop accepting writes that change state: block create/delete/resize/snapshot/attach at the API (HAProxy or policy), pause user automation, stop the periodic cleanups. Optionally disable `nova-compute` services so the scheduler places nothing. Verify instance counts at libvirt equal Nova's |
| Point of no return | None, while no service has been recreated |
| Restorable | Re-enable the API (new decision after a stop; `operating-principles.md`) |
| Prerequisites | A tested way to reject writes without making services unstable; a communication to consumers |
| Stop conditions | Bus unstable (RabbitMQ alarm blocking publishers cluster-wide, as on the lab, IA-CP-02); clients retrying into a degraded cloud and creating duplicate instances |
| Approver | Change authority; Service owners informed per criticality table |
| Source | `operating-principles.md` "Controlled degradation"; `control-plane-recovery.md` "Controlled degradation and reopening provisioning" |

### P3. Final consistent backup

| | |
|---|---|
| Actions | With the freeze in place, take the full Mariabackup, `/etc/kolla` and key copy, and record `openstack` inventory snapshot and `virsh` dumps (companion file section 5) |
| Point of no return | None |
| Restorable | This **is** the restore point (call it RP-0) |
| Prerequisites | G1 |
| Stop conditions | Backup incomplete or not copied off-host |
| Approver | Platform owner |

### P4. Control-plane change on production (differs by strategy)

| Strategy | Action | Point of no return | What is restorable | Stop conditions | Approver |
|---|---|---|---|---|---|
| **A**, per release | `kolla-ansible upgrade` (after `pull`, `prechecks`); runs schema migrations, recreates containers | The first completed schema migration of that release on the production DB. Neutron's contract phase needs all neutron-servers stopped and is a potential PNR (`upgrade-readiness.md`) | Restore RP-n (the backup taken just before that hop) + `/etc/kolla` + that release's images + hosts at that release's OS; lose everything since RP-n. Nine hops means nine RPs and nine image sets | Prechecks fail; `nova-status upgrade check` returns 2 or more; any dependency behaves differently from rehearsal; image for the previous release unavailable (G2 broken) | Change authority, per hop |
| **B**, offline walk on the production DB | Stop all services, run the intermediate-release schema/data migrations offline against the production database, then deploy 2026.1 | The first migration command executed against the production DB. Multiple intermediate migrations make a partially migrated DB a state no release can serve | RP-0 only, on a Ussuri control plane rebuilt from Ussuri images. Everything between is lost. If the walk fails halfway, the DB is neither Ussuri nor 2026.1 | Any migration error; row-count or integrity check mismatch; DB cannot be restored within the owner's acceptable full-failure time | Change authority + Platform owner, in person |
| **D**, walk on a **clone** | Restore RP-0 into a **new** Galera on new controllers, walk it offline, deploy 2026.1 on new controllers pointed at that clone. The old production DB and control plane are not modified | None for the old plane. For the new plane: the point where the new plane starts managing production computes/volumes (P5) | The old Ussuri plane is untouched: stop the new plane, unfreeze the old. Anything done by the new plane to shared backends after P5 is not undone by that | Walk fails verification (row counts, FK, service catalogs, policy); new plane cannot see a sample of old computes/ports as expected | Change authority |
| **C** | Build a separate 2026.1 cloud; nothing is done to the old one | None for old; per-workload cut-over has its own PNR (P6) | Old cloud fully intact | New cloud not stable under test load; no capacity | Platform owner |

### P5. Deploy or restart the target control plane

| | |
|---|---|
| Actions | A: containers recreated by the upgrade (previous row). B/D: deploy 2026.1 control plane with Kolla-Ansible 22.x on Noble controllers; HAProxy/ProxySQL/keepalived new; `nova-status upgrade check` with the target code; Kolla-Ansible runs it itself and stops on code above 1 (2026.1 notes) |
| Point of no return | B: the DB is already past it. D: the point at which the new plane connects to production computes or storage and writes (e.g. ports bound, volumes attached, `compute` services registered). Before that point D is fully reversible |
| Restorable | A: RP of the hop. B: RP-0 as above. D: switch VIP/DNS back to the old plane; verify that the old plane's hosts and computes were not touched (G6) |
| Prerequisites | G1-G8; the Nova service-version rule: 2026.1 Nova refuses to start with a compute older than Epoxy (`nova@origin/stable/2026.1:nova/objects/service.py:284`), so the new plane **cannot** register Ussuri computes (see P6) |
| Stop conditions | Any service in the new plane fails its end-to-end test (create network, instance, volume, FIP on a test project on a new test compute); an API behaves differently from rehearsal; monitoring blind spots |
| Approver | Change authority |
| Lab prior | 2025.1 to 2026.1, all-in-one: `kolla-ansible upgrade` 24 min, API gaps Keystone ~10 s, Nova ~15 s, Neutron ~30 s (KA-ARCH-29 `LAB-VALIDATED`); multinode rolling upgrade not run |

### P6. Compute conversion and workload movement

This is the phase that forces instance downtime (risk assessment section 2.2).

| Strategy | Action | Point of no return | Restorable | Stop conditions | Approver |
|---|---|---|---|---|---|
| **A** | Per host per hop: disable compute, live-migrate away to a landing batch (newer first), change OS or release, verify, re-enable. Order: landing batch first because migration toward older QEMU is not supported (MP-MECH-03) | Reinstall of the host OS; for instances, the first live migration to a newer QEMU (cannot migrate back) | Before reinstall: re-enable the host. After: need the old OS image/disk and Ussuri images (G2) | Migrations failing/slowing vs baseline; destination behaves differently; capacity below reserve; monitoring blind spot; authority unreachable | Platform owner for the batch; Service owners for restarts |
| **B** | For each compute: stop instances (owner-agreed class), reinstall Noble, deploy 2026.1 compute, restart instances; record machine types first | The reinstall of the host (old OS gone unless disk kept) and the first start of an instance under the new QEMU | Before reinstall: host and instances untouched. After: the instance's data (shared disk) can be started under the old stack only if an old host and the old plane still exist with a DB matching the world. If the world and DB diverged, that needs reconciliation | An instance fails to start on the new stack (machine type, CPU model, device); host fails to rejoin; anything unexpected in canary | Service owner approves each workload's stop; Platform owner approves each wave |
| **D** | New Noble computes join the new plane empty. Per wave: stop instance, make its disk reachable from the new plane (same Ceph pool under the single-writer rule, or copy), re-create/re-bind on the new compute using carried records, start | Per instance: first start on the new plane (the new plane writes to the disk). Per wave: when the old compute is reinstalled to join the new pool | Before starting on the new plane: instance stays as it was on the old compute (old plane, unchanged). After: needs the old plane to re-adopt the disk, which only works if the old DB still matches (no changes since) and the old compute is intact | As B, plus: any case of two planes both able to start the same instance (R8) | Service owner per workload; Platform owner per wave |
| **C** | Per workload: warm sync, quiesce, final delta, start in new cloud, cut-over (DNS, floating IP address move), observe, then stop old. Old kept for a defined retention | Per workload: deleting the old instance or releasing its address and data; before that, rollback = start old, move address back (needs the reverse data sync if the new side wrote) | Old workload intact until deleted | New side mismatch (data checksum, app health); the address move fails; consumer integration breaks | Service owner per workload |

Rule for all strategies: **one failure domain at a time; one wave at a time; time already invested creates no obligation to continue**; resuming after a stop is a new decision (`openstack-change-review` step 7, `operating-principles.md`).

### P7. Decommission the old state

| | |
|---|---|
| Actions | Remove old images (`docker rmi`), wipe old hosts, delete the old cloud, retire the old DB |
| Point of no return | **This is the real one.** Once the old images, the last RP and the old hosts are gone, there is no way back |
| Restorable | Nothing, beyond what was archived |
| Prerequisites | Observation period passed (the new state "earns trust", `operating-principles.md`; the length is the owner's decision, `unknown`); every wave verified; the old DB archived off-line for audit and history (UUID history is not carried in C) |
| Stop conditions | Any open reconciliation item; any workload not yet verified; backups of the new state not yet restored once |
| Approver | Change authority + Platform owner + each Service owner for their workloads (written) |
| Hint | `prune-images` removed nothing and `docker rmi` of the old tags freed 7 GB on the lab: it is a manual, deliberate action that "removes the quickest way back" (KA-ARCH-30) |

---

## 4. Recovery paths by failure scenario (what a person actually does)

| Scenario | First move | What is restorable | What is lost | Note |
|---|---|---|---|---|
| Upgrade step fails before schema migration | Stop; read the failure; fix forward or abort | The old release with its images and config; DB untouched | Nothing if no DB change | A and B/D(old) |
| Failure after the first production schema migration (A: hop n) | Decision: fix forward or restore RP-n | Control plane at hop n-1 with its images; instances still running (data plane survived) | Changes after RP-n (instances created/deleted, volumes attached) must be reconciled by hand | Quote: Galera restore is `Destructive`, API down from step 2 to the end |
| Failure during the offline walk (B) | Stop; do not retry on the same DB | RP-0 | Everything since RP-0 | The reason D runs the walk on a clone |
| New plane unstable (D) before shared backends touched | Switch VIP/DNS back; unfreeze old | Everything | Nothing | The best-case rollback in the whole set of strategies |
| Instance does not start on new QEMU | Do not retry destructively; read libvirt log; try another host class; consider cold boot with old machine type if the recorded type is available | The instance data (disk) | Instance runtime state | Machine-type issues: `Not validated` (companion risk R4) |
| Host did not come back after reinstall | Fence host; use landing capacity; reinstall again | Data on shared backends; local disks lost if wiped | Local disks if no copy | Keep old disks aside |
| Split-brain between two planes | Stop both writers; fence the old plane's control of hosts; reconcile per image | Backend data up to the last consistent write | Unknown; image-level consistency checks needed | Prevent by G6 |
| Rollback requested after workloads started on the new stack | Decision at the highest level: the old plane's DB does not know what happened | Disk data (backend) | Control-plane records for the interval | Treat as a recovery project, not a rollback. A new restore point must be taken first |

---

## 5. What I would put in the change decision record (`openstack-change-review` step 10)

- Objective in business terms; starting state evidence; blast radius per phase; gate results G1-G8; recovery path per phase from the table above; point of no return per phase; stop conditions; verification design (companion file section 5); decision rights with names; communication plan; what is accepted by choosing this path.
- **Verdict now: not ready** for any strategy, because none of the gates has evidence yet. This is the expected outcome for a Stage 1 desk assessment.

---

## 6. Open questions / what I could not verify

1. MariaDB image and tooling in Ussuri Kolla-Ansible: whether `mariadb-backup`/`mariadb-recovery` commands as described by the OzarLand procedure exist and behave the same in Kolla-Ansible 10.x. The procedure is from 22.2.0. `Not validated`.
2. Production restore time and the SST behaviour on a large database: `unknown`.
3. Whether public images of Ussuri to Yoga are reachable from the production network (quay.io, a mirror), or whether they must be rebuilt from `ussuri-eol`: `unknown`; a rebuild of 2020-era images in 2026 may not be reproducible (`Not validated`).
4. The OS-disk preservation approach for hosts (separate system disk, PXE-switch, image backup): site-specific.
5. How the Nova DB in D reconciles compute records for hosts that are reinstalled under the same hostnames (the `compute_id` behaviour): not read.
6. The exact list of per-service databases in this deployment (Heat, Octavia, Designate, Barbican, others): `unknown`; each is a restore dependency and a version-walk dependency.
7. Any deadline by which the old software must be gone: `unknown`; it bounds how long the old state can be kept as a rollback target.
