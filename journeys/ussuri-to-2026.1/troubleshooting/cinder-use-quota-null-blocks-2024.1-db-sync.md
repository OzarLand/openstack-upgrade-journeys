# Cinder `db sync` fails at 2024.1: `use_quota` NULL on soft-deleted volumes or snapshots

| Metadata | |
|---|---|
| Applies to | Any upgrade that runs cinder 2023.1 code and then cinder 2024.1 or later code: the **supported** 2023.1 → 2024.1 SLURP upgrade, and the database fast-forward of this journey |
| Status | Symptom and cause `LAB-VALIDATED`: reproduced in this journey's container lab (EXP-DB-01, `experiments/EXP-DB-01-root-cause-analysis.md`). Avoidance through cinder 23.5.0 `LAB-VALIDATED` in the same lab (VAL-001). Not reproduced on a Kolla-Ansible or production platform. |
| Upstream | Bug [#2070475](https://bugs.launchpad.net/cinder/+bug/2070475), fixed by commit `a3c90fb4c` ("[stable-only] Fix online data migrations"). The fix is on the `unmaintained/2023.1` branch only; **no 2023.1 release contains it**. The first and only release with it is cinder **23.5.0** (2023.2). |
| Who is exposed | Clouds that have soft-deleted volumes or snapshots created before the `use_quota` column existed (before Xena). A cloud that was ever on Wallaby or earlier and never purged Cinder's deleted rows is likely exposed. |

## Symptom

`cinder-manage db sync` with 2024.1 or later code stops in migration `9ab1b092a404` ("Make use_quota non nullable") with:

```text
DataError: (1265, "Data truncated for column 'use_quota' at row …")
```

The step before it gave no sign of trouble: `cinder-manage db online_data_migrations` with 2023.1 code reported
nothing left to migrate.

## Cause

- The 2023.1 online data migration that fills `use_quota` runs with the default `read_deleted='no'`. It therefore
  never sees soft-deleted rows, which keep `use_quota` NULL. The MariaDB general log in the lab shows the query
  running with `WHERE volumes.deleted = false`.
- The 2024.1 migration then makes the column NOT NULL, assuming the earlier online migrations have covered every row.
  Under strict `sql_mode` it fails.

Checked at the release tags:

| Cinder release | Series | Covers deleted rows |
|---|---|---|
| 22.3.0 (last 2023.1 release) | 2023.1 | no |
| 23.4.0 | 2023.2 | no |
| 23.5.0 | 2023.2 | yes |

Kolla images for 2023.1 are built from branch content, so they *may* contain the fix where PyPI releases do not. Check
the code in your image; do not assume.

## Check before running any 2024.1 code (read-only)

```sql
-- On the cinder database, after the 2023.1 (or 2023.2) online data migrations have reported 0 remaining.
SELECT 'volumes' AS tbl, deleted, COUNT(*) FROM volumes WHERE use_quota IS NULL GROUP BY deleted
UNION ALL
SELECT 'snapshots', deleted, COUNT(*) FROM snapshots WHERE use_quota IS NULL GROUP BY deleted;
```

Expected result before 2024.1: **no rows**. Any row, with `deleted` = 1 or 0, means that 2024.1 `db sync` will fail
(or, under a non-strict `sql_mode`, silently write a value). This is check PC-C1 of the journey
(`experiments/fast-forward-checks.md`).

## Avoidance used in this journey

After the 2023.1 step, run Cinder **23.5.0** (2023.2): `cinder-manage db sync`, then
`cinder-manage db online_data_migrations` until 0 remain. Then run the check above, and continue to 2024.1
(DR-004). On a supported staircase that passes through 2023.2, make sure the 2023.2 Cinder you run is 23.5.0 or
contains commit `a3c90fb4c`, and run its online data migrations to completion.

## What not to do

- **Do not `UPDATE` the rows by hand.** The correct value depends on the volume's temporary or migration status
  (`calculate_use_quota`), and hand edits bypass the code that knows it.
- **Do not purge to make it pass.** `cinder-manage db purge` deletes soft-deleted rows. That is a data-retention
  decision for the data owners, not a fix. In this journey it was used once, in an informational run, and was judged
  to have "moved the goalposts" (Red Team Stage 5).

## Evidence

- `experiments/EXP-DB-01-root-cause-analysis.md`
- `decision-records/DR-004-cinder-2023.2-step.md`
- `evidence/EXP-DB-01/strict-r2/` (H1: 3 volumes and 2 snapshots left NULL; H1b: filled; PC-C1 0/0; H2 passed)
- `validation/VAL-001-exp-db-01-strict-r2.yaml`
