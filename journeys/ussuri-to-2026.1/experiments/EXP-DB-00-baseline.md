# EXP-DB-00: Ussuri baseline is complete and restorable

| | |
|---|---|
| **Experiment ID** | EXP-DB-00 |
| **Journey** | ussuri-to-2026.1 |
| **Author / executor** | agent:Agent 5 (lab engineer, Sonnet) both |
| **Date planned / run** | 2026-10-31 / 2026-10-31 |
| **Status** | `LAB-VALIDATED` for restorability and for the coverage that exists, **scope as below**; coverage is **incomplete** (section "Coverage gaps"); the baseline as built also **fails pre-check PC-Q5** (see "Finding"), so a corrected baseline v2 was derived for the migration runs |
| **Evidence class of the claim tested** | Experimentally validated (restore, row counts, checksums); coverage claim: Not validated for the gap items |
| **Risk** | state-changing on a disposable lab (read-only on the preserved backups) |
| **Validation record** | none assigned |

## Scope of this result (mandatory, every record)

| | |
|---|---|
| **Dataset tier** | Tier A (synthetic, created through the Ussuri APIs with the fake virt driver) |
| **Code source and digests** | Ussuri releases from PyPI under `requirements@ussuri-eol` (5095bcd0); image `ufj-ussuri-py38:1`; `evidence/EXP-DB-00/pip-freeze-ussuri-py38.txt` (194 packages) |
| **Database engine and path** | `mariadb:10.3` (10.3.39, library image, `sha256:4f08c16e...`); single node; restore proven by logical dump load and by tarball of the datadir volume |
| **Topology** | container control plane, fake virt driver (3 computes), fake L2 agents with the `fake_agent` test ML2 driver, standalone MariaDB, no Galera, no Kolla images, no data plane |
| **Status line** | `LAB-VALIDATED` — scope: Ussuri baseline schema and API-created data, restorable; synthetic Tier A; fake virt driver; no Kolla images, no Kolla-Ansible, no data plane |
| **Classification of the procedure itself** | Technically possible but unsupported (container stand-in for a Kolla-Ansible Ussuri cloud) |
| **This result does NOT show** | Kolla image behaviour; Galera; production data; durations at production scale; live instances (the fake driver holds no guests); libvirt reconciliation (machine type, CPU model, `vcpu_model`); RabbitMQ; host OS; PCI/SR-IOV; OVN; real Ceph/LVM `connection_info`; HA routers; DHCP ports |

## Hypothesis

The baseline built by Agent 5 contains every checklist item (`experiments/baseline-coverage-checklist.md` with the Agent 4 review) that the lab can produce, is restorable with identical row counts and dump checksum, and records the T0 facts (Keystone `migrate_version`, hashers, `@@GLOBAL.sql_mode`). Refuted by: a restore that differs, or an unlisted gap.

## Initial state

Built by `./ufj.sh up && populate` (about 17 minutes) in `lab/ussuri-db-lab/`, then captured twice (DR-003): A) fake computes and agents stopped, `forced_down=0` (`backups/latest-pre-forced-down`); B) after `compute service set --down` through the Ussuri API (microversion 2.53), final (`backups/latest`). Versions: `evidence/EXP-DB-00/versions.txt`. Host Ubuntu 24.04.5, kernel 6.18.44-fc-v185, Docker 29.9.2, no KVM.

## Prerequisites

Docker, `lab/ussuri-db-lab/`, PyPI access, Docker Hub library images (Hub rate-limited anonymous pulls with HTTP 429 on 2026-10-31; `mirror.gcr.io` was used for later images).

## Expected outcome

Logical and physical restore into fresh MariaDB containers: identical row counts and `CHECKSUM TABLE` of all OpenStack tables and an identical sha256 of the OpenStack dump; every checklist item has count > 0 or a documented "not covered" reason; T0 facts recorded.

## Possible failure modes

| Failure mode | How it would show | What it would mean |
|---|---|---|
| Restore differs | row counts or checksum differ | baseline is not reproducible |
| Gap items silently dropped | missing from `coverage-actions.tsv` | the differential tests see less data than claimed |
| Baseline violates a pre-check | `12-prechecks.sh` FAIL | the baseline is not migratable by the S2c procedure as written |

## Baseline preservation

`backups/baseline-20261031T114357Z-final` (`latest`) and `...T114211Z-pre-forced-down` under `lab/ussuri-db-lab/backups/` (git-ignored; contain hashes, Fernet keys, lab passwords). `MANIFEST.sha256` verified before every restore. Checksums of all 47 files before and after Stage 4 work: `evidence/EXP-DB-01/baseline-checksums-{before,mid,after}.txt`. Restore tested (below).

## Steps

| # | Step | Risk | Run? |
|---|---|---|---|
| 1 | Build image, `up`, `populate` (base set, `coverage.sh`, archive, ODMs) | state-changing (lab) | yes |
| 2 | Capture A (stop computes + agents, proof, inventories, dumps, counts, checksums, tarballs) | state-changing (lab) | yes |
| 3 | `compute service set --down` for each compute through the API | state-changing (lab) | yes |
| 4 | Capture B (final) | state-changing (lab) | yes |
| 5 | Logical and physical restore test; full lab restore from tarballs; API inventory compare | read-only for the backups | yes |
| 6 | Pre-checks PC-* on a restored copy (`ff/12-prechecks.sh`) | read-only | yes |

## Evidence

`journeys/ussuri-to-2026.1/evidence/EXP-DB-00/` (copies) and `evidence/lab-baseline/` (full set): `coverage-actions.tsv` (every creation attempt; secrets scrubbed), `coverage-counts-T0.tsv` and `coverage-counts-T0-corrections.tsv` (T0 counts of every checklist item, read-only SELECTs), `odm-T0.txt`, `restore-test.txt`, `verify-after-restore-into-lab.txt`, `fence-proof.txt`, `nova-services-table.tsv`, `forced-down-api-output.txt`, `schema-versions.tsv`, `prechecks-on-restored-copy.txt`, `pre-forced-down/`. Redacted: all generated passwords, application-credential and EC2 secrets, TOTP blob.

## Database consistency

* Restore: logical and physical PASS; 571 tables identical (the two InnoDB statistics tables are engine-maintained and excluded), `CHECKSUM TABLE` identical for 542 OpenStack tables, dump sha256 `cec9cd76b9f77c362020ba4811bdb79029d7236c8a78804b59729af21d129c6b`. Full lab restore from tarballs: 22 s, inventory compare 0 differences.
* T0 facts: Keystone `migrate_version` = `keystone` 109, `keystone_expand`/`data_migrate`/`contract` = **078** (not 079; V-K1 applies at H1); glance `ussuri_contract01`; placement `b5c396305c25`; nova 407 / nova_api 72; cinder 136; neutron heads `5c85685d616d`, `d8bdf05313f4`. Password hasher: all 9 users `$2b$` (bcrypt); no `sha512_crypt` (Ussuri cannot produce it: `keystone/conf/identity.py:111-114`). `@@GLOBAL.sql_mode` = `STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION`.
* Predictions for the declared changes (from the restored copy, `prechecks-on-restored-copy.txt`): Cinder `default` quota classes for `backups`/`backup_gigabytes` **absent**, so R-5 predicts **+2** at H2; one `consistencygroups` quota-class row (V-C6) and none in `quotas`, `quota_usages` or `reservations`; 0 temporary admin-metadata rows; 1 port with a `trusted` profile (R-8: `porttrusted` = 1 row); 0 `network:dhcp` ports; compute_id residue: 0 instances with a host but no compute node, 1 instance with `host` NULL (ERROR, cell0).
* Pre-checks: all PASS except **PC-Q5**.

### Finding: PC-Q5 fails on the baseline as built

The checklist item "multi-segment network" was created with two VLAN segments on the same physical network (`ufj-multiseg`, `vlan/physnet1` 150 and 151). That is a duplicate for `(network_id, network_type, physical_network)` and violates pre-check PC-Q5. Neutron's Yoga revision `e981acd076d3` (`neutron@origin/stable/2026.1:.../versions/yoga/expand/e981acd076d3_add_networksegments_database_constraint.py`) creates exactly that unique constraint, and `fc153938cdc1` (2023.1) replaces it only afterwards, so the chain would fail. Strict R1 on this baseline therefore stops at PC-Q5 (`evidence/EXP-DB-01/r1/`). The fix is a change on Ussuri with supported tooling: through the Ussuri API the network was deleted and re-created with a VLAN segment plus a VXLAN segment (`tools/coverage_rest.py multisegment` updated), and **baseline v2** was captured (`lab/ussuri-db-lab/backups-v2/`, `evidence/EXP-DB-01/baseline-v2/`). The only row-count difference between v1 and v2 is `neutron.segmenthostmappings` 9 → 6 (`rowcount-diff-vs-v1.txt`). v1 is unchanged and still the preserved baseline. v2 was captured at the final stage only (computes stopped and forced down; no pre-forced-down variant).

### Residue: Nova `fill_virtual_interface_list` "9 matched, 0 migrated"

`odm-T0.txt`: `9 rows matched query fill_virtual_interface_list, 0 migrated`, `Total Needed 9, Completed 0`, exit 0 on every run. Source (`nova@ussuri-eol:nova/objects/virtual_interface.py`, `fill_virtual_interface_list`, and `nova/cmd/manage.py` `_run_migration`/`online_data_migrations`): the function returns `(count_all, count_hit)`. `count_all` counts every live instance whose `InstanceInfoCache` holds `network_info` and which it compared against the DB; `count_hit` counts instances whose `virtual_interfaces` rows it had to rebuild. "Found" = 9 examined instances, "done" = 0 rebuilt. `online_data_migrations` loops `while ran != 0` where `ran` sums **done**, so it ends with exit 0 although found stays 9 on every run. The log lines "InstanceInfoCache object has not set NetworkInfo field. Skipping" are the ERROR-without-network instances. This is therefore **not pending work**. Side effect that matters for the differential checks: each run deletes and recreates a marker row (`virtual_interfaces.instance_uuid = FAKE_UUID`, address `ff:ff:ff:ff:ff:ff/...`, tag = last examined instance) and a deleted FAKE instance row in each cell (`_set_or_delete_marker_for_migrate_instances`). Declared as a **residue to re-check at every hop**: found = number of live instances with a network cache, done must stay 0, exit 0; and the marker rows in `nova.virtual_interfaces`/`nova_cell0.virtual_interfaces` are expected to change between hops (not listed in `declared-differences.md`: a proposed addition).

## Service checks

Ussuri API services and the three fake computes ran during population; at capture the computes and agents were stopped (`fence-proof.txt`), the services table shows all `nova-compute` rows at version 51, `forced_down=1` after the API call (`nova-services-table.tsv`), `forced_down=0` in capture A.

## Workload checks

Fake virt driver: no real guests. 11 servers (ACTIVE, SHUTOFF, VERIFY_RESIZE, ERROR) as API records only.

## Conclusion

Restorability: confirmed. Coverage: confirmed for the items marked covered in `coverage-actions.tsv`; **not covered** (reason in the log and in report 05): cinder `temporary='True'` admin metadata and `migration_status target:%` (no backup/migration data path), nova `pci_devices` NULL uuid, nova legacy-cell-DB quotas (by design), deleted instance on a host whose node row is gone, HA router (`ha_router_networks`), DHCP ports, libvirt blobs/PCI/OVN/real storage. Partial: pinned-CPU instance in ERROR (`ValueError` in conductor scheduling, not investigated), `consistencygroups` usage/reservation rows 0, image members 0, hashers only bcrypt, ODM `fill_virtual_interface_list` residue. Because the checklist accepts "not covered with reason", the pass criterion is met, but any claim about those paths stays `Not validated`.

## Status

`LAB-VALIDATED` (scope above) for restorability and covered items; `Not validated` for the gap items; baseline v1 fails PC-Q5 (corrected in v2). Steps not run: Tier B comparison.

## Baseline derivations and v4 (added 2026-10-31 after the Red Team Stage 5 review; RT-N-18, RT-B-08, RT-B-10)

| Baseline | Derived from | Operation (all through supported Ussuri tools) | Row-count differences vs its parent | Status |
|---|---|---|---|---|
| **v1** `backups/latest` | built by `populate` + `coverage.sh` | - | - | the preserved baseline; fails PC-Q5 and PC-C4 (see below) |
| v2 `backups-v2/` | v1 | API: network `ufj-multiseg` deleted and re-created with a VLAN and a VXLAN segment (PC-Q5 remedy) | `neutron.segmenthostmappings` 9 -> 6 (`baseline-v2/rowcount-diff-vs-v1.txt`) | derived; used by R1b, R1o |
| v3 `backups-v3/` | v2 | `cinder-manage db purge 0` | `cinder.reservations` **50 -> 0**, `cinder.volumes` 9 -> 8 (the only soft-deleted volume), `cinder.volume_attachment` 4 -> 3 (`baseline-v3/rowcount-diff-vs-v2.txt`). The record of R1c did not mention the 50 reservations. The checklist item "volumes in deleted state" (count 1 -> 0) was lost | **withdrawn as evidence for Cinder** (a purge is a data-retention decision with its own change record, not a procedure step; DR-004) |
| **v4** `backups-v4/` | v1 | see below | `evidence/EXP-DB-00/v4/rowcount-diff-vs-v1.txt` | derived; the baseline for the strict re-run |

### v4 (Baseline for the strict re-run of EXP-DB-01)

Started from v1 (restored into the lab from `backups/latest`, read-only use). Through the Ussuri API, as an operator would, recorded in `evidence/EXP-DB-00/v4/remedy-evidence.txt`:

1. **PC-Q5 remedy**: the network `ufj-multiseg` (two `vlan/physnet1` segments) deleted and re-created with one VLAN and one VXLAN segment (impact: a lab network with no ports; `neutron.segmenthostmappings` 9 -> 6). PC-Q5 duplicates after: 0. This is the "re-model the network" remedy of `fast-forward-checks.md` for **static** segments; the dynamic-segment variant (hierarchical binding) is not exercised.
2. **PC-C4 remedy**: the ERROR volume `a-boot` (never scheduled, `host` NULL, `service_uuid` NULL) deleted with `openstack volume delete`. Non-deleted volumes with `service_uuid` NULL after: 0. (It is now one more soft-deleted volume.)
3. **Soft-deleted rows for the Cinder defect (DR-004)**: the existing snapshot `a-vol2-snap` deleted; a new volume `a-vol-del2` created, snapshotted (`a-snap-del2`) and both deleted. Result: **soft-deleted volumes 3** (`a-vol-deleted` from v1, `a-boot`, `a-vol-del2`) and **soft-deleted snapshots 2**, all untouched by any purge. Their `use_quota` is NULL after the 2023.1 `db sync` adds the column (the column does not exist on Ussuri; the 2023.1 ODM leaves deleted rows NULL, H1b migrates them). `cinder.reservations` 50 -> 74 and `quota_usages` 13 -> 19 are side effects of the API operations.
4. Ussuri ODMs run again (`odm-T0.txt`: nova, placement, cinder exit 0), then captured (final stage only, computes stopped and forced down as in v1; `MANIFEST.sha256` verified; OpenStack dump sha256 `a811631e...`).

Coverage counts (`evidence/EXP-DB-00/v4/coverage-counts-T0.tsv`): volumes available 4, in-use 3, error 0, deleted 3; snapshots non-deleted 1, deleted 2; `migration_status error` 1 (a non-deleted available volume, unchanged from v1); everything else as in v1 except the rows named above. Gap items unchanged from v1 (temporary admin metadata, `target:%`, PCI NULL uuid, HA router, DHCP ports, deleted instance with missing node).

Findings kept from v1 that remain open: the C9 `cinder-status` FAILURE of v1 came from the ERROR volume; with PC-C4 resolved it can pass on its merits (to be shown by the strict re-run). Whether Kolla-Ansible 2026.1 aborts on `cinder-status` rc 2 is still to be cited (RT-N-19).
