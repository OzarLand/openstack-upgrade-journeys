# EXP-SVC-02: operations on pre-existing (Ussuri-created) resources through the 2026.1 services

| | |
|---|---|
| **Experiment ID** | EXP-SVC-02 |
| **Journey** | ussuri-to-2026.1 |
| **Author / executor** | agent:lab-and-automation-engineer (Agent 5b, model Fable; takes over from Agent 5a, whose run `strict-r1` was interrupted) / executed in the Docker lab of this repository |
| **Date planned / run** | 2026-10-31 / 2026-10-31 (`strict-r2`, 19:37-19:43 UTC) |
| **Status** | LAB-VALIDATED (all 22 checked operations passed in `strict-r2`; no FAILED item remains) |
| **Evidence class of the claim tested** | Experimentally validated (in the lab scope below); the procedure stays Technically possible but unsupported |
| **Risk** | state-changing (on disposable clones only) |
| **Validation record** | not assigned yet (the architect assigns VAL ids; VAL-001 covers the database fast-forward this run builds on) |

## Scope of this result (mandatory, every record)

| | |
|---|---|
| **Dataset tier** | **Tier A** (synthetic, created through the Ussuri APIs by the lab's `populate` step: Ussuri baseline v4, about 400 objects, see EXP-DB-00), fast-forwarded to 2026.1 by VAL-001 (strict re-derivation `derive-h4r`, verdict PASS) |
| **Code source and digests** | image `ufj-svc-2026.1:1` (`sha256:9bdad819349b6bb9f9577cbc70579405579c1959b8543075a24366a6b8ff6d43`) = PyPI under the 2026.1 upper-constraints, Python 3.12, plus gunicorn, pymemcache, python-memcached, python-openstackclient 9.0.1, osc-placement; `pip freeze` in `evidence/EXP-SVC-01/pip-freeze-svc-2026.1.txt`. Kolla-Ansible behaviour reproduced from the released `kolla-ansible 20.6.0` wheel (2026.1), read-only, see Deviations |
| **Database engine and path** | MariaDB 11.4 library image; a cold copy (`10-stack.sh clone`) of volume `ufj-ff-derive-h4r-data` (H4r state of `derive-h4r`; durable copy `backups-ff/derive-h4r-datadir-mariadb11.4.tgz`, sha256 `c57a988c…b6b2526` checked after the run); baseline v4 manifest (21 files) checked before and after the run: `strict-r2/baseline-manifests.txt` |
| **Topology** | one container per service on one Docker network, single MariaDB (no Galera), fresh RabbitMQ 4.x (quorum queues), memcached; keystone, placement, nova-api, neutron and cinder-api under gunicorn; three fake computes (`svc/ufj_fake2026.py`, FakeDriver subclass) re-adopting the Ussuri hosts `ufj-compute1..3` (DR-003 state d, RPC cap 6.5); fake L2 agents; Ussuri control plane stopped (no old clients) |
| **Status line** | `LAB-VALIDATED` — scope: tokens, credentials, stop/start, resize and resize-confirm, volume attach/detach (Ussuri-era and new attachments), volume snapshot, quota enforcement, port and server creation on Ussuri-created resources, through the 2026.1 services on a cold copy of the H4r database with fake computes, Kolla-equivalent Keystone bootstrap and service roles; no Kolla images, no Kolla-Ansible, no hypervisor, no data plane |
| **Classification of the procedure itself** | Technically possible but unsupported (S2c) |
| **This result does NOT show** | behaviour with a real hypervisor (libvirt: resize, attach and snapshot are no-ops in the fake driver; `connection_info` is never consumed by os-brick), Galera, Kolla image behaviour, ML2/OVN or OVS agents (port binding by fake agents), encryption of volume data (only the Cinder/Nova control path of the encrypted volume), Glance image data (fake driver uploads none), durations at production scale, RabbitMQ migration from a live 3.8 broker |

## Hypothesis

From the H4r database (VAL-001) with the 2026.1 services in DR-003 state (d), the usual operations on resources created under Ussuri (tokens for old users, credential decryption, stop/start, resize, volume attach and detach, snapshot, quota, port and server creation on an old network) succeed, provided the Keystone state that Kolla-Ansible 2026.1 creates at deploy time is present. Refuted if any such operation fails for a reason rooted in the migrated data.

The interrupted run `strict-r1` (Agent 5a, 18:59-19:20 UTC, `evidence/EXP-SVC-02/strict-r1/`, `INTERRUPTED.txt`) is **interrupted, not a result**. It is used here only as the source of the failure to investigate: volume detach and resize of a server with an attached volume failed (volume stuck in `detaching`, server `ERROR`).

## Cause of the `strict-r1` failures (investigation, from the logs of that stack)

* nova-compute (`ufj-svc-compute1/2`, 19:02:16 and 19:05:16): `cinderclient.exceptions.ClientException: ConflictNovaUsingAttachment: Detach volume from instance … using the Compute API (HTTP 409)` raised inside `do_detach_volume` (detach) and `_terminate_volume_connections` (resize).
* cinder-api, on the same requests: `WARNING keystonemiddleware.auth_token … A valid token was submitted as a service token, but it was not a valid service token. This is incorrect but backwards compatible behaviour.` Nova did send a service token (`[service_user] send_service_user_token = true`, config change 7), but the token of the `nova` user carried the roles `admin, member, reader` only: the role **`service` did not exist** in the migrated Keystone (`roles-before.txt`: `admin reader member`). Cinder since Yoga/2023.1 (CVE-2023-2088 hardening) deletes an attachment that belongs to a Nova instance only when the caller presents a service token with a role in `service_token_roles` (default `service`); otherwise it answers 409 `ConflictNovaUsingAttachment`.
* Nothing in the migrated attachment rows is at fault: the Ussuri-era attachment of `a-vol1` on `a-vm1` (row created 2026-10-31 11:22 under Ussuri, `attach_status attached`, connector and connection_info present, `vol1-attachment-row-before.txt`) detached and re-attached cleanly in `strict-r2` once the role existed. A fresh nova token after granting the role carried `admin, member, reader, service`, and a live attach/detach on the `strict-r1` stack then succeeded with no Cinder warning.
* Phase 3B of `strict-r1` (the same remedy applied on the running stack) was inconclusive, not negative: `a-vm1` was already in `vm_state error` from the failed resize (its detach/resize answered 409 "while it is in vm_state error"), and the `a-vm2` resize asked for the flavor it already had (400 "instances must change flavor"). One late warning (19:10:03) came from a nova-api worker still holding a service token issued before the grant.

**Verdict: (a) lab artefact.** Kolla-Ansible 2026.1 (20.6.0) creates exactly what was missing: `keystone-manage bootstrap` adds the roles `manager` and `service` (measured in EXP-KD-01 C-2), and `roles/{nova,cinder,neutron}/defaults/main.yml` `*_ks_user_roles` grant `service` to the nova, cinder and neutron users (`roles/cinder/templates/cinder.conf.j2` also sets `service_token_roles_required = true`). Not (b): the fake driver is not involved in the 409. Not (c): no defect of `volume_attachment.connection_info` or `attachment_id` was found; Ussuri-era attachments work.

## Initial state

H4r database (VAL-001) cloned into `ufj-svc-data`; 2026.1 services started by `svc/10-stack.sh up` (render, keystone, **bootstrap**, other services), three fake computes re-adopting `ufj-compute1..3` (all `enabled up`, `compute-services.txt`; RPC version 6.5 selected from minimum service version 72, `rpc-cap.txt`). Ussuri `ufj-*` containers stopped. Roles after bootstrap: `admin manager member reader service`; nova, cinder and neutron each hold `admin` and `service` in project `service` (`service-user-roles.txt`).

## Prerequisites

VAL-001 (H4r database), EXP-SVC-01 (the 2026.1 runtime on H4r, state d), EXP-KD-01 C-2 (effect of `keystone-manage bootstrap` on H4r). Baseline v4 (`backups-v4/latest`) for the Ussuri-rendered configuration, Fernet/credential keys and passwords.

## Expected outcome

Every row of `results.tsv` `OK`; zero `not a valid service token` lines in cinder-api; no HTTP 500, ERROR or `IncompatibleObjectVersion` lines in any service log during the run.

## Possible failure modes

| Failure mode | How it would show | What it would mean |
|---|---|---|
| Fernet or credential keys not usable | token issue fails; EC2/TOTP blobs not decrypted | key material not carried over (would refute the Keystone part) |
| Ussuri-era attachment not understood by 2026.1 | detach of `a-vol1` fails after the role fix | real migration defect in `volume_attachment` / BDM rows (case c) |
| Service token still refused | cinder-api warning or 401/409 with the role present | cause other than the missing role |
| Quota rows not enforced | 6th server of bob or a 495 GiB volume of alice accepted | quota tables not migrated correctly |
| Old network unusable | port or server creation on `a-net1` fails or stays unbound | Neutron data defect |

## Baseline preservation

Every run clones the H4r volume into `ufj-svc-data` (`10-stack.sh clone`); the source volume and the archive are never written. `backups-v4/latest/MANIFEST.sha256`: 21 OK before (19:37:18) and after (19:43:29). Archive `derive-h4r-datadir-mariadb11.4.tgz` sha256 matches its record after the run. `strict-r2/baseline-manifests.txt`.

## Deviations (lab changes made before `strict-r2`, each reproducing what Kolla-Ansible 2026.1 deploys)

1. `svc/10-stack.sh bootstrap` (run by `up` after Keystone answers): `keystone-manage bootstrap` with Kolla's arguments, the stored admin password and the stored endpoint URLs (KD-01 C-2 showed this call only adds roles `manager`/`service` and rewrites the implied-role chain on H4r), then `role add --user {nova,cinder,neutron} --project service service`. `config-changes.txt` item 12.
2. `cinder.conf [keystone_authtoken] service_token_roles_required = true` as in Kolla's `cinder.conf.j2` (`config-changes.txt` item 13). With it an invalid service token is rejected instead of downgraded, so `strict-r2` is the stricter test.
3. Harness (`40-exp-svc-02.sh`): the remedy phase 3B was removed (the role is now part of the stack start); phase 3 adds detach and re-attach of the Ussuri-era attachment `a-vol1`/`a-vm1`, resize of `a-vm1` (`ufj.tiny` → `ufj.small`, volume attached) and `a-vm2` (`ufj.small` → `ufj.medium`, encrypted volume attached) with confirm, and the cinder service-token warning count; flavor names corrected to `ufj.*`; strict labels refuse to run with uncommitted `lab/` changes.

No migrated data was changed by hand. Harness commit `3ba36d8b275a06a6092fe624118b4ec1e26a3dcb` (`lab/` clean at run time, `harness.txt`; script sha256 `275a74d5…8853ae`). A dry run `dry-r2` (19:30-19:36 UTC) preceded it with the same outcome.

## Steps

| # | Step | Risk | Run? |
|---|---|---|---|
| 1 | clone H4r → `ufj-svc-data`; infra; `up` (render, keystone, bootstrap, glance, placement, nova, neutron, cinder); computes 1-3 re-adopted, forced-down cleared, Nova control services restarted once (DR-003 steps 4-5) | state-changing (clone) | yes |
| 2 | tokens: password tokens for alice and bob; new application credential of alice and a token from it; list of her 3 pre-existing application credentials | state-changing | yes, 4 OK |
| 3 | credentials: alice's EC2 credential listed with decrypted secret; TOTP credential blob decrypted | read-only | yes, 2 OK |
| 4 | stop/start `a-vm3` (boot volume); resize-confirm of `a-migrate` left in VERIFY_RESIZE by Ussuri | state-changing | yes, 2 OK |
| 5 | detach the Ussuri-era attachment `a-vol1` from `a-vm1` → `available`; re-attach → `in-use` | state-changing | yes, 2 OK |
| 6 | attach `a-vol2` to `a-vm2` → `in-use`; detach → `available` (new attachment on old objects) | state-changing | yes, 2 OK |
| 7 | resize `a-vm1` with `a-vol1` attached → VERIFY_RESIZE → confirm → ACTIVE, flavor `ufj.small`; resize `a-vm2` with encrypted `a-enc-vol` attached → VERIFY_RESIZE → confirm → ACTIVE, flavor `ufj.medium` | state-changing | yes, 4 OK |
| 8 | snapshot of old volume `a-vol2` → `available`; server image of `a-vm3` → `active` (no data, fake driver; INFO) | state-changing | yes, 1 OK + 2 INFO |
| 9 | quota: bob (limit 5, used 1) creates 4 servers, the 6th is refused 403 "Quota exceeded for instances: Requested 1, but already used 5 of 5"; alice's 495 GiB volume refused 413 `VolumeSizeExceedsAvailableQuota`, a 1 GiB volume accepted | state-changing | yes, 3 OK |
| 10 | port on old network `a-net1`; server with old flavor `ufj.tiny`, old image `ufj-image-a`, on `a-net1` → ACTIVE on `ufj-compute1`, address `192.168.10.x`, binding `ovs`/`ufj-compute1` | state-changing | yes, 2 OK + 1 INFO |
| 11 | cleanup of created objects; log scan | state-changing | yes |

## Evidence

`journeys/ussuri-to-2026.1/evidence/EXP-SVC-02/strict-r2/`: `run.log` and `results.tsv` (22 OK, 0 FAIL, 6 INFO), `harness.txt`, `baseline-manifests.txt`, `compute-services.txt`, `agents.txt`, `roles-before.txt` and `service-user-roles.txt` (Keystone state after bootstrap), `vol1-attachment-row-before.txt` (the Ussuri-era attachment row), `detach-vol1.txt`, `reattach-vol1.txt`, `attach.txt`, `detach.txt`, `resize-a-vm1.txt`, `resize-a-vm2.txt`, `confirm-migrate.txt`, `img.txt`, `cinder-service-token-lines.txt` (empty: 0 warnings), `rpc-cap.txt`, `service-log-errors.txt`. Passwords and token/secret values are redacted or not recorded. `strict-r1/` is kept as the interrupted investigation run; `dry-r2/` is the dry run of the final harness.

## Database consistency

Not re-checked by a comparator in this experiment (the operations create and delete objects by design). `IncompatibleObjectVersion`/`ObjectActionError`: 0 lines in all 14 service logs. Schema state is that of VAL-001 (unchanged by Kolla's `db sync`, EXP-KD-01 C-1); `keystone-manage bootstrap` adds role rows as measured in KD-01 C-2.

## Service checks

Control plane answering after `up`; three computes `enabled up`; RPC version 6.5 selected by nova-api and nova-conductor from minimum service version 72; http500-lines=0, error-lines=0 for nova-api, nova-conductor, nova-scheduler, neutron, neutron-rpc, cinder-api, cinder-scheduler, cinder-volume, glance, keystone, placement, compute1-3 (`service-log-errors.txt`); 0 service-token warnings in cinder-api.

## Workload checks

See Steps 4-10: all exercised operations passed. Not exercised: live or cold migration, evacuation, floating IPs, security-group changes, image data upload, console, metadata service, anything requiring a hypervisor or data plane.

## Conclusion

Confirmed. Pre-existing Ussuri resources (users, credentials, servers, volumes with Ussuri-era attachments, networks, flavors, images, quotas) are operable through the 2026.1 services on the H4r database. The `strict-r1` failures were a lab artefact: the Keystone `service` role that Kolla-Ansible 2026.1 creates at deploy time (`keystone-manage bootstrap` plus `*_ks_user_roles`) was absent, so Cinder 2026.1 refused Nova's attachment deletes (409 `ConflictNovaUsingAttachment`). For the real procedure this is a reminder, not a risk: Kolla's `deploy`/`upgrade` runs these steps, but any operator who starts 2026.1 services on a migrated database **without** Kolla's Keystone registration will see exactly this failure (volume detach and resize with attached volumes), and with Kolla's `service_token_roles_required = true` an HTTP 401 instead. Worth a warning in the runbook. Unknown: the same operations with a real hypervisor (libvirt and os-brick consume `connection_info`; the fake driver does not).

## Status

`LAB-VALIDATED` in the scope stated above, on `strict-r2` (harness commit `3ba36d8`, 22/22 OK). No item is FAILED; the `strict-r1` run is interrupted, not a result. Steps not run: none of the planned list. Validation record: to be assigned by the architect.

## Corrections (2026-10-31, after Red Team Stage 5d; the text above is kept as written)

* **RT-B-13, Kolla-Ansible version.** Wherever the text above cites "kolla-ansible 20.6.0 wheel (2026.1)" or "Kolla-Ansible 2026.1 (20.6.0)", read **kolla-ansible 22.2.0** (the 2026.1 series is 22.x; 20.x is 2025.1). The artefact the role defaults were read from is the same one EXP-KD-01 used: `kolla_ansible-22.2.0-py3-none-any.whl` from PyPI, sha256 `010e077c95d172e152f253bba4c0af43b537c987439d1c4601e9edc6adaeac34`; the Red Team re-read `roles/cinder/defaults/main.yml:330-333` and `roles/cinder/templates/cinder.conf.j2:133` at `kolla-ansible@origin/stable/2026.1` and found the role defaults identical, so the conclusion does not change.
* **RT-N-32, partial grant set.** The lab granted the role `service` to **three** service users only (nova, cinder, neutron, `service-user-roles.txt`). Kolla-Ansible grants it to **every** service user it registers (glance, placement, cinder, nova, neutron and every other enabled service). Three were sufficient for the operations tested here; the grant set is partial and must be complete (all service users) in later runs (EXP-SVC-03 or K-01) and in the runbook step KD-M6.
* **RT-N-31, wording.** Read "lab artefact" in the Cause and Conclusion sections as: *deploy-time Keystone state required by 2026.1 Cinder, created by Kolla-Ansible's `keystone-manage bootstrap` and `service-ks-register` tasks, absent from every Ussuri database; an ordering gate (KD-M6) in the procedure*, not a lab accident.
* **RT-N-35, scope.** The application-credential token used a **new** credential of a pre-existing user; the pre-existing secrets were not retained by the baseline. This belongs in the scope table above.
