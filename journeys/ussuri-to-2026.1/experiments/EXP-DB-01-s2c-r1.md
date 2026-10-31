# EXP-DB-01 (R1): S2c database fast-forward Ussuri -> 2023.1 -> 2024.1 -> 2025.1 -> 2026.1, engine line E1

| | |
|---|---|
| **Experiment ID** | EXP-DB-01 |
| **Journey** | ussuri-to-2026.1 |
| **Author / executor** | agent:Agent 5 (Sonnet) both |
| **Date planned / run** | 2026-10-31 / 2026-10-31 |
| **Status** | **`FAILED`** against the pre-registered strict criteria: the strict runs hit named stop conditions (SC-PC-Q5 on baseline v1; SC-DIFF after H1 on baseline v2, pending acceptance of the R0 amendments) and one informational run hit SC-CMD at H2 (Cinder). One informational run on a corrected baseline (v3, observe mode) **completed all hops and the idempotency re-run**, with the exceptions listed under "Stop conditions" (C9 `cinder-status` FAILURE; R0 amendments not yet accepted). That run does not carry a validated status because it is not a strict pass |
| **Evidence class of the claim tested** | Technically possible but unsupported (S2c); the per-hop commands are Officially supported only for single-release steps |
| **Risk** | destructive on disposable copies |
| **Validation record** | none assigned |

## Scope of this result (mandatory, every record)

| | |
|---|---|
| **Dataset tier** | Tier A (synthetic, created through the Ussuri APIs with the fake virt driver). Baseline v1 = `backups/latest`; v2 = v1 with the PC-Q5 offender replaced (Ussuri API); v3 = v2 after `cinder-manage db purge 0` on Ussuri (supported tool) |
| **Code source and digests** | PyPI under each release's upper-constraints: `evidence/EXP-DB-01/pip-freeze-<rel>.txt`, `uc-ref-<rel>.txt` (requirements commits), `images.txt` (image ids), `image-digests.txt` (MariaDB and python base images). keystone 23.0.2/25.0.0/27.1.0/29.1.0, glance 26.1.0/28.2.0/30.2.0/32.0.0, placement 9.0.0/11.0.1/13.0.1/15.0.0, nova 27.5.1/29.4.0/31.3.1/33.0.2, neutron 22.2.1/24.2.2/26.0.6/28.0.2, cinder 22.3.0/24.5.0/26.4.0/28.0.0 (last numeric version of each series in `releases` `deliverables/{antelope,caracal,epoxy,gazpacho}`); python 3.10 / 3.11 / 3.12 / 3.12 (all `Requires-Python` satisfied); `setuptools==69.5.1` pinned in the images because current setuptools has no `pkg_resources` |
| **Database engine and path** | E1 stepwise on one node, wsrep off not applicable (no Galera): `mariadb:10.3` 10.3.39 -> 10.5.29 -> 10.6.28 (bridge hop H1) -> 10.11.19 (H2, H3) -> 11.4.13 (H4, H4r); clean shutdown (`innodb_fast_shutdown=0`), `mariadb-upgrade` and `mariadb-check --all-databases --check-upgrade` after every step, all exit 0. 10.6, 10.11, 11.4 and the python bases were pulled through `mirror.gcr.io` (Docker Hub HTTP 429); digests recorded |
| **Topology** | one-shot containers (production-style rendered config + override with the connection and an unreachable `transport_url` only) against a standalone MariaDB container with the network alias `ufj-mariadb`, so `cell_mappings` stay byte-identical; no services, no RabbitMQ, no Galera, no Kolla images, no Kolla-Ansible, no data plane |
| **Status line** | `FAILED` (strict criteria not met) — scope: database schema and data migration Ussuri -> 2026.1 by the S2c code sequence, upstream code from PyPI under each release's upper-constraints, standalone MariaDB library images (no Galera), synthetic Tier A dataset generated through Ussuri APIs with the fake virt driver, no Kolla images, no Kolla-Ansible, no data plane |
| **Classification of the procedure itself** | Technically possible but unsupported |
| **This result does NOT show** | Kolla image behaviour; Galera; production data or production-scale durations (the dataset has 11 instances and about 4,100 rows in total); live instances; libvirt reconciliation (machine type, CPU model); RabbitMQ; host OS; service start-up on the migrated databases (EXP-SVC-01); rollback (EXP-RB-01); engine line E2 and R2/R3; the differential equality with the staircase (EXP-DB-02/03) |

## Hypothesis

From the Ussuri baseline, running for each of 2023.1, 2024.1, 2025.1, 2026.1 the db syncs and online data migrations of `assessments/04` section 3 migrates every database with exit 0 everywhere, online migrations reach 0, the schema equals a fresh reference except declared differences, rows and fingerprints equal T0 except declared transformations, and a second 2026.1 run changes nothing. Refuted by any stop condition.

## Initial state

Restored copies of the preserved baseline; the copy is proven equal to the baseline by dump sha256 before each run (v1 `cec9cd76...`, v2 `8d4b9695...`, v3 recorded in `baseline-v3/`). Pre-checks PC-* (`12-prechecks.sh`, `r1/prechecks.txt`): all pass on v1 except PC-Q5. Config parity (`r1c/config-parity.txt`): the one-shot config equals the rendered file except `[DEFAULT] transport_url` (override); `quota_backups=7`, `quota_backup_gigabytes=2500` (CP-C1) and the Neutron plugin list are the production-style values; no Neutron sub-projects installed in any image or in the baseline (CP-Q1).

## Prerequisites

EXP-DB-00 (baseline), R0 (calibration; amendments still to be accepted), N1 not required.

## Expected outcome

As the hypothesis.

## Possible failure modes

| Failure mode | How it would show | What it would mean |
|---|---|---|
| A pre-check fails | `prechecks.txt` | the dataset cannot be migrated by this procedure as written |
| A command exits non-zero | `steps.tsv` | SC-CMD |
| Undeclared schema/row/fingerprint difference | `schema-diff.txt`, `data-diff.txt` | SC-DIFF |
| A status tool reports FAILURE | `status-tools.txt` | C9 |
| H4r differs from H4 | `idempotency-diff.txt` | SC-IDEMP |

## Baseline preservation

`backups/latest` and `backups/latest-pre-forced-down` were only read. sha256 of all 47 files of each: `baseline-checksums-before.txt`, `-mid.txt`, `-after.txt` are **identical** (digest of digests `054a9630ee68b126`), and both `MANIFEST.sha256` verify after the work. `backups-v2/`, `backups-v3/` are new, separate captures (git-ignored). The final database of the completed run is kept as `backups-ff/r1c-H4r-openstack.sql.gz` (sha256 `84c1073e...`) with all snapshots (`backups-ff/r1c-snap/`) for the differential tests. Restore of the baselines was tested (EXP-DB-00).

## Steps

| # | Step | Risk | Run? |
|---|---|---|---|
| 1 | Build four release images, pull MariaDB 10.5/10.6/10.11/11.4 | read-only | yes |
| 2 | **R1 strict on v1** (`ff/50-run-s2c.sh r1 baseline`): T0 snapshot, pre-checks | read-only | yes: stopped at PC-Q5 |
| 3 | Create baseline v2 (Ussuri API: replace the PC-Q5 offender) and capture | state-changing (lab) | yes |
| 4 | **R1b strict on v2**: engine 10.5, 10.6, H1, checks | destructive (copy) | yes: stopped after H1 |
| 5 | **R1o observe on v2**: continue past stop conditions | destructive (copy) | yes: command failure at H2 |
| 6 | Create baseline v3 (`cinder-manage db purge 0` on Ussuri) and capture | state-changing (lab) | yes |
| 7 | **R1c observe on v3**: all hops, H4r | destructive (copy) | yes: completed |
| 8 | Targeted value checks and config parity on R1c's final database | read-only | yes |

Per hop (`30-hop.sh`, order of `04` section 3 steps 6-10 with step 10 at every hop): `keystone-manage db_sync`; `nova-manage api_db sync`; `nova-manage db sync --local_cell` for cell0 then cell1; `cinder-manage db sync`; `cinder-manage db online_data_migrations`; `nova-manage db online_data_migrations`; `glance-manage db sync`; `placement-manage db sync`; `neutron-db-manage upgrade heads`; `placement-manage db online_data_migrations`. No `alembic stamp`, no edit of bookkeeping tables or rows at any time.

## Evidence

`evidence/EXP-DB-01/`: `r1/` (strict v1), `r1b/` (strict v2), `r1o/` (observe v2), `r1c/` (observe v3: per hop `H1..H4r` with `steps.tsv`, per-command logs, `odm-*.txt`, `versions.txt`, `bookkeeping.txt`, `schema-<db>.txt`, `schema-diff.txt`, `data-diff.txt`, `status-tools.txt`, `summary.txt`; `engine-*`, `targeted-checks.txt`, `config-parity.txt`, `final-dump.sha256`), `baseline-v2/`, `baseline-v3/`, image files, `engine-sql-mode.txt`, baseline checksums. Redacted: generated passwords (scanned: 0 hits). Not kept: dumps.

## Database consistency

### Runs and stop conditions hit

| Run | Dataset | Mode | Result | Stop condition |
|---|---|---|---|---|
| R1 | v1 | strict | stopped at the pre-checks, no hop run | **SC-PC-Q5**: network `ufj-multiseg` has two `vlan/physnet1` segments (150, 151): duplicate for `(network_id, network_type, physical_network)`; Yoga `e981acd076d3` would create the unique constraint before `fc153938cdc1` replaces it (`r1/pc-q5-offending-rows.txt`) |
| R1b | v2 | strict | engine 10.5, 10.6 and H1 ran, every command exit 0; stopped after H1 | **SC-DIFF**: 153 schema differences (151 structural, 2 name-only) not on the frozen list = exactly the R0 classes R0-A1..A4 (pending acceptance); data: `neutron.portbindingports` dropped at H1 instead of H2 (R0-A5); **C9** `cinder-status` FAILURE "Service UUIDs" (see below) |
| R1o | v2 | observe | H1 commands exit 0 and checks as R1b (R0 classes shown as PROPOSED); **H2 `cinder-manage db sync` exit 1** | **SC-CMD**: `oslo_db.exception.DBDataError: (1265, "Data truncated for column 'use_quota' at row 6") [SQL: ALTER TABLE volumes MODIFY use_quota BOOL NOT NULL DEFAULT true]` (revision `9ab1b092a404`). Cause: the one soft-deleted volume still has `use_quota` NULL after the 2023.1 `cinder-manage db online_data_migrations`, which reported 8 volumes + 2 snapshots migrated and then **0 needed on every re-run**, although an ORM query with `read_deleted='yes'` finds the NULL row. The code (`use_quota_online_data_migration`) says it covers deleted rows; the observed behaviour does not. The declared entry V-C1 ("applied to deleted rows as well") is therefore **not true in this run**. Root cause in the code not isolated |
| R1c | v3 (v2 + Ussuri `cinder-manage db purge 0`) | observe | **all five hops completed, every command exit 0**, H4r idempotent | **C9** (below); the schema classes R0-A1..A4 and R0-A5 are PROPOSED, not accepted |

### R1c results per check (observe, v3; engine E1)

* **C1** exit codes: all hops, all commands 0; every ODM ended with exit 0 on its first pass (`odm-*.txt`). Cinder ODM at H1: 8 volumes and 2 snapshots migrated. Nova ODM: nothing at H1; H2 `populate_instance_compute_id`: 12 found, 10 migrated in the first pass, then **1 found, 0 migrated on every later run at H2, H3, H4, H4r with exit 0** = the declared residue N-R1 (the one ERROR instance with `host` NULL, equal to the T0 prediction); this answers open point 7.3 (the tool exits 0 when only N-R1 remains). The Ussuri residue "`fill_virtual_interface_list` 9 matched / 0 migrated" is **gone from H1 on** (0 needed at every hop).
* **C2** versions at H4r: nova_api `cdeec0c85668`, nova cells `2903cd72dc14`, keystone `742c857f1dfb` + `c88cdce8f248`, cinder `9c74c1c6971f`, glance `2024_1_contract01`, placement `a082b8bb98d0`, neutron `5c85685d616d` + `b1bca967e19d`; the `alembic_version` rows equal the reference rows in every database at every hop (`bookkeeping.txt`); `glance-manage db check` exit 0; `neutron-db-manage has_offline_migrations` and `check_migration` exit 0.
* **C3** `migrate_version`: remains in keystone (109, expand/data_migrate/contract **078 -> 079 at H1**, V-K1) and glance (`Glance Migrations/0`); dropped for nova, nova_cell0, nova_api, cinder from H2 (R-1).
* **C4** schema vs fresh reference on the same server: H1 48 declared + 153 PROPOSED, **0 other**; H2..H4r 24 declared + 137 PROPOSED, **0 other**. The PROPOSED ones are R0-A1 (Boolean CHECK constraints), A2, A3, A4 (`EXP-DB-R0`).
* **C5/C6** counts and per-row/per-column fingerprints vs T0 (`data-diff.txt`, re-run from the snapshots with the final comparator): H1 23 declared + 1 proposed + **0 undeclared**; H2 100/0/0; H3 102/0/0; H4 103/0/0; H4r 103/0/0. Targeted checks (`targeted-checks.txt`): `use_quota` all true (8 volumes, 2 snapshots) and NOT NULL; R-5 `default/backups=7`, `default/backup_gigabytes=2500` (predicted +2); V-C6 `consistencygroups` quota class soft-deleted; `compute_id` set for 10 of 11 instances, mismatches 0, the 11th is the host-NULL residue; V-Q4 port forwarding split `192.168.10.50:22-22 ext 2222-2222`; V-Q6 four default SG rules; V-Q7 `porttrusted` 1 row, profile emptied; V-Q8 `tags` `utf8mb4_bin`, HEX values equal T0 (including the non-ASCII ones); V-Q9 `vxlan` ranges `physical_network` `''`; mapping `schema_version` `1.0`; `placement.consumer_types` 0 rows, `consumer_type_id` NULL on 12/12.
* **C7** ODM summaries saved per hop (`odm-*.txt`).
* **C8** engine: `mariadb-upgrade` and `mariadb-check` exit 0 at every step. At the first start of 10.6 (and of 11.4 in N1) the error log shows `Incorrect definition of table mysql.event: expected column 'definer' ... found type char(141)` and "Event Scheduler disabled" **before** `mariadb-upgrade` ran; after it, the check is clean. Recorded, not classified as SC-ENGINE (needs Red Team judgement).
* **C9** status tools: `cinder-status upgrade check` exit 2 at **every** hop: "Service UUIDs: Failure: Services and volumes must have a service UUID" - caused by the ERROR volume `a-boot` (create-from-image failed on Ussuri, `service_uuid` NULL); not fixable by the Queens ODM (it has nothing to do). `keystone-status` could not run (needs the Fernet repository, not mounted in the one-shot: tool error exit 1); `neutron-status` exit 1 from H2 on: only the warning "OVN support for BM provisioning over IPv6: failed to connect to OVN" (environment). `glance-status`, `placement-status` exit 0. By the pass condition "no FAILURE", **C9 fails**.
* **C10** durations (one-shot containers, 11-instance dataset, about 4,100 rows, single node): hop commands H1 24 s, H2 23 s, H3 28 s, H4 27 s, H4r 29 s (each command 1.3-3.3 s, longest `nova-manage db sync` 3.1 s, `neutron-db-manage upgrade heads` 3.2 s); engine steps: start 3-5 s, `mariadb-upgrade` + check 1-3 s each; reference build + snapshot + comparisons 72-82 s per hop; whole run 555 s. These are **not** extrapolable to production table sizes.
* **Idempotency**: H4 -> H4r: 0 schema, 0 count, 0 row differences, all commands exit 0 (`r1c/H4r/idempotency-diff.txt`).

### Open items for the Red Team

* The R0 amendments (A1..A6) are not accepted; until they are, strict R1 stops at H1 (R1b). With them taken as proposed, the only remaining stop in the completed run is C9.
* The Cinder deleted-volume finding is a procedure gap: S2c as written needs a Ussuri-side step (`cinder-manage db purge`, used for v3) or a fix of the cause; v3 has no deleted Cinder rows, so the 'deleted volume' coverage item and the declared V-C1 text about deleted rows are untested.
* PC-Q5 must apply to the coverage checklist itself (a multi-segment network with two segments of the same type and physnet is not migratable by this chain).

## Service checks

not run (EXP-SVC-01).

## Workload checks

not run.

## Conclusion

The S2c code sequence runs end to end on the Tier A dataset, offline, with no manual row or version edit, in about 25 s per hop plus about 75 s of checking, and a second 2026.1 pass changes nothing - **provided** (1) the Ussuri dataset has no duplicate network segments (PC-Q5, found in our own baseline), (2) soft-deleted Cinder volumes are purged on Ussuri first (found at H2: `9ab1b092a404` fails with DataError 1265), and (3) the C9 `cinder-status` FAILURE caused by a service-less ERROR volume is resolved or accepted. Under the frozen strict rules the experiment is `FAILED`: R1 on v1 and v2 hit SC-PC-Q5 and SC-DIFF (the latter only because R0's amendments are not accepted yet), and the unamended chain fails at H2 for any dataset with a soft-deleted volume. Remaining unknown: the root cause of the ODM skipping deleted volumes; engine line E2 (R3); behaviour with Galera, with real data volume and with services started on the result (EXP-SVC-01); the legacy `shadow_*` items of R0 (A2, A3) and whether they hide a defect. Next: Red Team decision on R0-A1..A6, then a strict re-run of R1 on v3 (`BASE_BACKUP=backups-v3/latest ff/50-run-s2c.sh <id> baseline`), then EXP-SVC-01 on `backups-ff/r1c-H4r-openstack.sql.gz`.

## Status

`FAILED` (strict criteria not met: SC-PC-Q5, SC-DIFF, SC-CMD in the informational run, C9). The observe-mode run on baseline v3 completed and is evidence of what the code does, not of a pass. Not run: E2/R2/R3/N2, services, rollback.
