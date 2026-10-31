# EXP-KD-01: Kolla-Ansible deploy-time behaviour on the migrated (H4r) databases

| | |
|---|---|
| **Experiment ID** | EXP-KD-01 (tests C-1 to C-4 of `assessments/03-kolla-deploy-on-migrated-databases.md`, section 6; C-5 is in EXP-SVC-01) |
| **Journey** | ussuri-to-2026.1 |
| **Author / executor** | agent:Agent 5 (Sonnet) both |
| **Date planned / run** | 2026-10-31 / 2026-10-31 |
| **Status** | `LAB-VALIDATED` (scope below) |
| **Harness** | lab commit `2ce87a4` (committed before the strict run, `lab/` tree clean: `evidence/EXP-KD-01/strict-r1/harness.txt`); script `lab/ussuri-db-lab/svc/30-exp-kd-01.sh`, `svc/kd_c3.py`; Kolla code: `kolla_ansible-22.2.0-py3-none-any.whl` from PyPI, sha256 `010e077c95d172e152f253bba4c0af43b537c987439d1c4601e9edc6adaeac34`, only `kolla_ansible/nova_filters.py` is executed |
| **Evidence** | `evidence/EXP-KD-01/strict-r1/` (strict), `evidence/EXP-KD-01/dry-kd1/` (dry run, same script before the commit) |

## Scope of this result (mandatory, every record)

| | |
|---|---|
| **Dataset tier** | the Tier-B lab dataset of baseline v4, fast-forwarded (H4r of the re-derivation `derive-h4r`, verdict PASS) |
| **Code source and digests** | image `ufj-svc-2026.1:1` (2026.1 services from PyPI under the 2026.1 upper-constraints; pip freeze in `evidence/EXP-SVC-01/pip-freeze-svc-2026.1.txt`); the commands are the ones listed in section 1 of the Kolla assessment, typed by hand, **not** produced by running Kolla-Ansible or Kolla images |
| **Database engine and path** | MariaDB 11.4.13 library image, cold copy of volume `ufj-ff-derive-h4r-data` (a fresh copy for each of the three parts C-1, C-2, C-3/C-4) |
| **Topology** | single MariaDB, one-shot containers with the rendered 2026.1 configuration (`svc/config-changes.txt`), Keystone container only in C-2; no Kolla images, no Kolla-Ansible, no Galera, no ProxySQL |
| **Status line** | `LAB-VALIDATED` — scope: Kolla's documented deploy-time database commands, `keystone-manage bootstrap` and `nova-manage cell_v2` calls run by hand from the 2026.1 PyPI image against a standalone MariaDB 11.4 copy of the fast-forwarded lab database; Kolla-Ansible and the Kolla images were not run; heat and horizon are not installed in the lab |
| **Classification of the procedure itself** | Technically possible but unsupported (S2c) |
| **This result does NOT show** | that Kolla-Ansible issues exactly these commands with these arguments (taken from the assessment, not re-derived), behaviour of `service-ks-register` (Ansible module), Galera or ProxySQL, `heat-manage db_sync`, Horizon `migrate`, Neutron subproject heads other than `neutron`, Glance's `log_bin_trust_function_creators` toggle |

## Hypothesis

C-1: Kolla's deploy-time commands change nothing on a 2026.1-head database (metadefs additions are declared). C-2: `keystone-manage bootstrap` resets the admin password if it differs, updates endpoint URLs and role/implied-role rows. C-3: `extract_cell` with `''` does not find the lab's cell named `cell1`. C-4: `create_cell` returns 2 when either the transport or the database string matches an existing cell, and creates a second mapping on the same database when both differ.

## Steps and results (`strict-r1`)

| Part | Result |
|---|---|
| **C-1** two passes of 11 commands each (`keystone-manage db_sync`; `glance-manage db sync` and `db_load_metadefs`; `placement-manage db sync` and `db online_data_migrations`; `nova-manage api_db sync`, `db sync --local_cell` for cell0 and cell1, `cell_v2 map_cell0`; `neutron-db-manage --subproject neutron upgrade heads`; `cinder-manage db sync`) | every command exit 0 in both passes (`c1/steps.tsv`). Comparator `same` (row counts, per-row fingerprints, schema, 8 databases): **H4r to pass 1: 0 differences; pass 1 to pass 2: 0 differences** (`c1/diff-s0-s1.txt`, `diff-s1-s2.txt`). No Glance metadef rows were added (they were already present in H4r), so no declared additions were needed |
| **C-2** `keystone-manage bootstrap` (Kolla arguments: user admin, project admin, role admin, service keystone, region RegionOne, the three URLs) | step 1 (lab password, stored URLs `http://ufj-keystone:5000/v3/`): exit 0, admin authenticates, **no new password row**, but roles and implied roles change: **new roles `manager` and `service`, and the implied role `admin -> member` is replaced by `admin -> manager` and `manager -> member`** (implied_role 2 -> 3 rows, role 3 -> 5; `c2/state-diffs.txt`). Step 2 (different password): **the admin password is reset**: the lab password then fails with HTTP 401, the new one works, one new `password` row for admin, and **`revocation_event` goes from 1501 rows to 1** (earlier events pruned, one new event). Step 3 (changed URLs): the three `endpoint` rows are **updated in place** (same ids, new URL), nothing else changes |
| **C-3** `extract_cell` of kolla-ansible 22.2.0 on the real output of `nova-manage cell_v2 list_cells --verbose` (2026.1, 6 table lines) | `extract_cell('')` returns `None` (the lab's cell is named `cell1`); `extract_cell('cell1')` returns the cell (uuid `3a38ca82-...`). The 2026.1 output format is still parsed by the filter. With `nova_cell_name: ''` Kolla therefore takes the `create_cell` branch for this database |
| **C-4** `create_cell` | (i) no arguments (the conductor's own transport URL and `[database]` connection): **exit 2**, "The specified transport_url and/or database_connection combination already exists for another cell with uuid 3a38ca82-..."; nothing created. (ii) same database string, different transport URL: **exit 2**, same message, nothing created. (iii) different transport URL **and** a different database string for the same database (`?kd=1` suffix): **exit 0, a second cell mapping with an empty name** pointing at the same `nova` database is created (`c34/cell-mappings-3-after-iii.tsv`: ids 1 cell0, 2 cell1, 3 unnamed); afterwards `extract_cell('')` returns the duplicate and `extract_cell('cell1')` the original |

## Conclusion

C-1 holds: Kolla's schema/bootstrap commands are no-ops on the migrated database, and idempotent. The two traps predicted for Nova are real: with Kolla's default empty `nova_cell_name` and the lab's cell named `cell1`, `extract_cell` does not find the cell; `create_cell` is then harmless only while the transport or the database string equals the stored one. In a real migration both strings change (new RabbitMQ and new database address), so the case (iii) outcome, a second mapping on the same database, is what to expect unless `nova_cell_name` is set to the existing name or the stored mapping is updated first. `keystone-manage bootstrap` is not a no-op: it adds roles `manager` and `service`, rewrites the implied-role chain, resets a different admin password (and prunes revocation events), and rewrites endpoint URLs; all four are intended Kolla behaviours but the first and the last two are visible changes to production data.

## Status

`LAB-VALIDATED` (scope above). Deviation: the commands were run by hand from the assessment's table, not by Kolla-Ansible; the lab password of the second bootstrap was a throw-away string, not stored.
