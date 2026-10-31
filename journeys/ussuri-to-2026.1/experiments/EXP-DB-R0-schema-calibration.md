# EXP-DB-R0: schema calibration run on an empty Ussuri schema

| | |
|---|---|
| **Experiment ID** | EXP-DB-R0 (the "R0" of `declared-differences.md` section 3.3) |
| **Journey** | ussuri-to-2026.1 |
| **Author / executor** | agent:Agent 5 (Sonnet) both |
| **Date planned / run** | 2026-10-31 / 2026-10-31 |
| **Status** | `LAB-VALIDATED` for what it measures (schema-only differences of the S2c path on an empty schema); **the amendments below are PROPOSED-UNVERIFIED and need Red Team acceptance**. `declared-differences.md` was NOT edited |
| **Evidence class of the claim tested** | Technically possible but unsupported (S2c) |
| **Risk** | destructive on a disposable copy |
| **Validation record** | none assigned |

## Scope of this result (mandatory, every record)

| | |
|---|---|
| **Dataset tier** | none: empty Ussuri schema (Tier A procedure, no rows beyond what the migrations seed; Nova `map_cell0`/`create_cell` rows only) |
| **Code source and digests** | Ussuri `ufj-ussuri-py38:1` (pip freeze in EXP-DB-00); 2023.1 / 2024.1 / 2025.1 / 2026.1 images `ufj-ff-<rel>:1` (python 3.10 / 3.11 / 3.12 / 3.12) built from PyPI under `requirements@origin/unmaintained/2023.1` (f6aa88bc), `origin/unmaintained/2024.1` (312d8c11), `origin/stable/2025.1` (0e4a61c4), `origin/stable/2026.1` (fab262d9); versions: keystone 23.0.2/25.0.0/27.1.0/29.1.0, glance 26.1.0/28.2.0/30.2.0/32.0.0, placement 9.0.0/11.0.1/13.0.1/15.0.0, nova 27.5.1/29.4.0/31.3.1/33.0.2, neutron 22.2.1/24.2.2/26.0.6/28.0.2, cinder 22.3.0/24.5.0/26.4.0/28.0.0; `evidence/EXP-DB-01/pip-freeze-<rel>.txt`, `images.txt`, `uc-ref-<rel>.txt` |
| **Database engine and path** | E1 stepwise on library images: `mariadb:10.3` (10.3.39) -> 10.5.29 -> 10.6.28 (H1) -> 10.11.19 (H2, H3) -> 11.4.13 (H4, H4r); `mariadb-upgrade` and `mariadb-check --check-upgrade` exit 0 at every step; digests in `evidence/EXP-DB-01/image-digests.txt` (10.6, 10.11, 11.4, python images pulled through `mirror.gcr.io` because Docker Hub answered HTTP 429; 10.3 and 10.5 from Docker Hub) |
| **Topology** | one-shot containers against a standalone MariaDB, no services, no Galera, no Kolla images, no data plane |
| **Status line** | `LAB-VALIDATED` — scope: database schema calibration of the S2c code sequence Ussuri -> 2023.1 -> 2024.1 -> 2025.1 -> 2026.1 on an empty schema, upstream code from PyPI under each release's upper-constraints, standalone MariaDB library images (no Galera), no Kolla images, no Kolla-Ansible, no data plane |
| **Classification of the procedure itself** | Technically possible but unsupported |
| **This result does NOT show** | anything about data-dependent behaviour (there are no rows); Galera; production tables; Kolla image behaviour |

## Hypothesis

On an empty Ussuri schema, the S2c path reaches the 2026.1 heads with every command exiting 0, and the schema differences between the migrated databases and fresh reference schemas built by the same code on the same server are limited to the candidate classes S-3 (i)-(iii) and the S-1 bookkeeping tables. Refuted by a failing command or a difference of another kind.

## Initial state

Empty Ussuri schemas built with Ussuri tools only (`keystone-manage db_sync`, `glance-manage db_sync`, `placement-manage db sync`, `nova-manage api_db sync`, `cell_v2 map_cell0`, `create_cell`, `db sync`, `neutron-db-manage upgrade heads`, `cinder-manage db sync`; no bootstrap, no ODM), on `mariadb:10.3`, with the rendered baseline config files + override (connection options and an unreachable `transport_url` only).

## Prerequisites

Images of section "Scope"; `lab/ussuri-db-lab/ff/` (`10-new-copy.sh r0 empty`, `50-run-s2c.sh r0 empty --observe`).

## Expected outcome

All commands exit 0; versions at the 2026.1 heads; schema differences only of the predicted classes.

## Possible failure modes

| Failure mode | How it would show | What it would mean |
|---|---|---|
| a sync fails on an empty schema | non-zero exit | the code path is broken independent of data |
| unexplained structural difference | a line in `schema-diff.txt` of another kind | blocks R1 until explained (rule of section 3.3) |

## Baseline preservation

Disposable run `r0` (volume `ufj-ff-r0-data`, container `ufj-ff-r0-db`); the preserved backups were not used.

## Steps

| # | Step | Risk | Run? |
|---|---|---|---|
| 1 | Create the empty Ussuri schema; T0 snapshot | destructive (disposable) | yes |
| 2 | Engine 10.5, 10.6; hop H1 (2023.1), engine 10.11, H2 (2024.1), H3 (2025.1), engine 11.4, H4 (2026.1), H4r (second 2026.1 run) | destructive (disposable) | yes |
| 3 | After each hop: reference schemas `<db>_ref` built by the same code on the same server, comparison A, versions, status tools, idempotency compare | read-only | yes |

## Evidence

`evidence/EXP-DB-R0/`: per hop `H1`..`H4r` (`steps.tsv` timings, per-command logs, `odm-*.txt`, `versions.txt`, `bookkeeping.txt`, `schema-<db>.txt`, `schema-diff.txt`, `data-diff.txt`, `status-tools.txt`, `summary.txt`), `engine-*`, `run.log`. Secrets redacted (generated passwords).

## Database consistency

* **C1**: every command of every hop exited 0 (`steps.tsv`); ODMs (cinder, nova, placement) reached exit 0 in one pass with 0 needed. Hop durations on an empty schema: H1 25 s, H2 23 s, H3 26 s, H4 29 s, H4r 29 s (all commands); each reference-plus-snapshot check 66-86 s.
* **C2**: final heads at H4 = H4r: nova_api `cdeec0c85668`, nova cells `2903cd72dc14`, keystone `742c857f1dfb` + `c88cdce8f248` (expand/contract), cinder `9c74c1c6971f`, glance `2024_1_contract01`, placement `a082b8bb98d0`, neutron `5c85685d616d`, `b1bca967e19d`. Migrated `alembic_version` rows equal the reference rows in every database at every hop (`bookkeeping.txt`). Offline status tools: 0 FAILURE lines. `glance-manage db check` exit 0, `neutron-db-manage has_offline_migrations` and `check_migration` exit 0.
* **C3**: `migrate_version`: persisted only in keystone (rows 109, 079 x3 after H1, i.e. V-K1 applied) and glance (`Glance Migrations/0`); gone for nova, nova_api, cinder from H2 (S-1a/S-1b/S-1c/S-1d confirmed as declared).
* **Idempotency (H4 -> H4r)**: `compare.py idem` reports 0 differences (rows, counts, schema).
* **C4** comparison A (migrated vs reference): see the list of proposed amendments. Totals: H1 153 differences not on the frozen list (151 structural, 2 name-only), H2 138, H3 137, H4 137, H4r 137. **Correction (Red Team Stage 5, 1.3):** the earlier claim "all explained by the six proposals, no difference of another kind appeared" was an over-claim: H2 shows 138 differences = 137 + **one more**, `neutron.portnumaaffinitypolicies.numa_affinity_policy` (migrated `enum(required,preferred,legacy)`, reference also `socket`), which none of A1-A6 covers. It is the Red Team's **A7** (below), transient (H2 only, converges at H3). Also not discussed in the first version: 141 -> 125 Boolean CHECK constraints between H1 and H2; the 16 that disappear are 15 on tables dropped by `054e34dbe6b4` (R-10) and 1 on `subnets.in_use` dropped by `93f394357a27` (V-Q5); MariaDB drops a single-column CHECK with its column.

### Differences observed and proposed amendments (for Red Team acceptance; not applied)

| Id | Database.table | Difference (observed at H1 .. H4r) | Cause | Evidence |
|---|---|---|---|---|
| R0-A1 (S-3 (i)) | every database except placement: 141 `CHECK` constraints at H1 (cinder 30, glance 1, keystone 10, neutron 64, nova 17, nova_cell0 17, nova_api 2), 125 at H4 (neutron 48) | migrated has `CHECK (col IN (0,1))` on Boolean columns, the reference has none | Ussuri builds with SQLAlchemy **1.3.16** where `Boolean(create_constraint=True)` is the default; 2023.1+ run SQLAlchemy 1.4/2.0 where it defaults to `False`. Checked in the images: `ufj-ussuri-py38` signature `Boolean.__init__(create_constraint=True, ...)`, `ufj-ff-2023.1` (1.4.41) `create_constraint=False`. Values unaffected | `H*/schema-diff.txt` |
| R0-A2 | `nova.shadow_alembic_version`, `nova_cell0.shadow_alembic_version` (table, column `version_num`, PK) | exists only in the reference, all hops | The Alembic initial revision creates a shadow copy of every table including the version table; the legacy chain that built the Ussuri schema had no `alembic_version` to copy. Source line of the shadow loop not located here (grep for the literal name finds none: it is generated) | `H*/schema-nova*.txt` |
| R0-A3 | `nova.shadow_quota_usages.resource`, `nova_cell0.shadow_quota_usages.resource` | migrated `NULL`able, reference `NOT NULL` | legacy shadow table definition vs squashed initial revision (not cited to a line) | same |
| R0-A4 (name-only) | `cinder.quota_usages` unique index/constraint on (`project_id`, `resource`, `race_preventer`) | named `quota_usages_project_id_key` (migrated) vs `project_id` (reference) | legacy migration `141` names it, the squashed initial does not (cause inferred from the name; not cited to a line) | `H*/schema-cinder.txt` |
| R0-A5 | `neutron` tables dropped by `yoga/expand/8160f7a9cebb` (R-9) and `2024.1/expand/054e34dbe6b4` (R-10) | dropped at **H1**, not H2 | `declared-differences.md` assumes S2c step 10 (Glance, Placement, Neutron at the bridge) is dropped by default; the run order used here (`assessments/04` section 3, step 10) runs Neutron at 2023.1, so the Yoga/2023.1 revisions execute at H1. Same for R-6/R-7 only if their revisions are <= 2023.1 (they are 2023.2: H2) | `H1/data-diff.txt` (in the baseline run R1b) |
| R0-A6 | `placement.projects`, `placement.users` | +1 row each, from H1 on (T0 empty) | the sentinel "incomplete consumer" project and user (`00000000-0000-0000-0000-000000000000`, `placement.conf [placement] incomplete_consumer_*`) are created by the 2023.1 placement step (`db sync` or its online migration; not separated), although `create_incomplete_consumers` reported 0. `V-P3` says "no change" | `H*/data-diff.txt` |
| R0-A7 (added by the Red Team) | `neutron.portnumaaffinitypolicies.numa_affinity_policy` | migrated `enum('required','preferred','legacy')` vs reference with `'socket'`, **H2 only** | the Wallaby revision `532aa95457e2` builds the enum from a **library constant** (`sa.Enum(*n_const.PORT_NUMA_POLICIES)`); S2c creates the table at H1 with 2023.1 code and neutron-lib 3.4.3 (no `socket`), the 2024.1 reference is built with neutron-lib 3.11.1; `2024.2/expand/175fa80908e1` adds the value at H3 | `EXP-DB-R0/H2/schema-diff.txt` (I had counted it among the 138 and not classified it) |

### Findings about the tooling of the frozen list itself

* `declared-differences.md` section 2.1 expects `information_schema` comparison to be name-insensitive in a second pass. The comparator (`ff/tools/compare.py`) reports index/constraint **name-only** differences separately (R0-A4 is the only one).
* The pre-registered S-1d entry ("Placement and Neutron have no `migrate_version`; Glance: record at T0") is confirmed: glance keeps `Glance Migrations/0`.

## Service checks

not run (schema calibration only).

## Workload checks

not run.

## Conclusion

On an empty schema the whole S2c code path works: 5 hops, all commands exit 0 in 23-29 s per hop, versions reach the heads, the second 2026.1 run changes nothing. The schema differences are exactly the predicted class S-3 (i) (Boolean CHECK constraints) plus three small items (R0-A2..A4). R0-A5 and R0-A6 are not schema differences but data-path differences that the frozen list does not describe. **Proposed amendment text** (for the Red Team to accept or reject; each entry cites the observation above): add S-3.1 (R0-A1, cause SQLAlchemy `create_constraint` default), S-3.2 (R0-A2), S-3.3 (R0-A3), S-N.1 (R0-A4), amend R-9/R-10 "first executed at: H2 (H1 with S2c step 10)", add V-P4 (R0-A6). A5/A6 and A2/A3/A4 causes are inferred; their source lines were not located, so the Red Team may reject them until cited. `declared-differences.md` is unchanged.

## Status

`LAB-VALIDATED` (scope above) for the calibration; amendments `PROPOSED-UNVERIFIED`.
