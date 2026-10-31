# EXP-DB-N1: 2026.1 code run directly against the Ussuri database (negative)

| | |
|---|---|
| **Experiment ID** | EXP-DB-N1 |
| **Journey** | ussuri-to-2026.1 |
| **Author / executor** | agent:Agent 5 (Sonnet) both |
| **Date planned / run** | 2026-10-31 / 2026-10-31 |
| **Status** | `FAILED` as predicted: the hypothesis "2026.1 refuses/cannot migrate a Ussuri database for Nova, Keystone and Cinder" is **confirmed**; the experiment itself did not fail to run |
| **Evidence class of the claim tested** | Incompatible (direct jump) - confirmed in the lab |
| **Risk** | destructive on a disposable copy |
| **Validation record** | none assigned |

## Scope of this result (mandatory, every record)

| | |
|---|---|
| **Dataset tier** | Tier A (synthetic, through the Ussuri APIs), **baseline v1** (`backups/latest`) |
| **Code source and digests** | PyPI under `requirements@origin/stable/2026.1` (fab262d9); image `ufj-ff-2026.1:1` (python 3.12); nova 33.0.2, keystone 29.1.0, cinder 28.0.0 (`evidence/EXP-DB-01/pip-freeze-2026.1.txt`); `evidence/EXP-DB-N1/images.txt` |
| **Database engine and path** | `mariadb:10.3` datadir opened directly by `mariadb:11.4` (11.4.13, digest in `image-digests.txt`), `mariadb-upgrade` and `mariadb-check` exit 0 (E3, informational); no fallback to 10.3 was needed |
| **Topology** | one-shot containers against a standalone MariaDB, no services, no Galera, no Kolla images, no data plane |
| **Status line** | `FAILED` (negative experiment; expected) - scope: database schema commands of 2026.1 against a Ussuri schema; synthetic Tier A; no Kolla images |
| **Classification of the procedure itself** | Incompatible |
| **This result does NOT show** | what the other services (Glance, Placement, Neutron) do (not run); behaviour with Galera; behaviour on production-sized data; whether the Zed or 2023.1 bridge succeeds (that is R1) |

## Hypothesis

Running the 2026.1 `db sync` of nova (api and cells), keystone and cinder against the Ussuri database fails, because 2026.1 has no code that converts a legacy sqlalchemy-migrate database to Alembic. Refuted by any exit 0.

## Initial state

Copy of baseline v1 restored from `backups/latest` (equal to the baseline: dump sha256 `cec9cd76...`), MariaDB 10.3 datadir opened by 11.4. Config = production-style rendered files + override (connection and unreachable transport_url only).

## Prerequisites

`ufj-ff-2026.1:1`, `mariadb:11.4`, baseline v1.

## Expected outcome

Non-zero exits with an error that shows the 2026.1 code cannot read the legacy schema.

## Possible failure modes

| Failure mode | How it would show | What it would mean |
|---|---|---|
| 11.4 refuses the 10.3 datadir | engine step fails | fall back to 10.3 (recorded) - did not happen |
| A command exits 0 | exit code | finding 2 of the architecture would be wrong |

## Baseline preservation

Disposable copy on volume `ufj-ff-n1-data`; the backups were only read (checksums before/after in `evidence/EXP-DB-01/baseline-checksums-*.txt`).

## Steps

| # | Step | Risk | Run? |
|---|---|---|---|
| 1 | Restore copy, prove equal to baseline | read-only | yes |
| 2 | Engine: 11.4 on the 10.3 datadir, `mariadb-upgrade`, `mariadb-check` | destructive (copy) | yes |
| 3 | `nova-manage api_db sync`; `nova-manage db sync --local_cell` for cell0 and cell1; `keystone-manage db_sync`; `cinder-manage db sync` (2026.1) | destructive (copy) | yes |

## Evidence

`evidence/EXP-DB-N1/`: `exitcodes.tsv`, `errors-verbatim.txt`, one full redacted log per command, `bookkeeping-after.txt`, `engine-11.4/` (upgrade, check, error logs), `run.log`.

## Database consistency

Exit codes: `nova-api_db_sync` 255, `nova-db_sync-cell0` 255, `nova-db_sync-cell1` 255, `keystone-db_sync` 1, `cinder-db_sync` 1. Verbatim (first error lines, see `errors-verbatim.txt`):

```
nova api_db sync : pymysql.err.OperationalError: (1050, "Table 'cell_mappings' already exists")
nova db sync     : pymysql.err.OperationalError: (1050, "Table 'instances' already exists")   (cell0 and cell1)
keystone db_sync : CRITICAL keystone [-] Unhandled error: sqlalchemy.exc.OperationalError: (pymysql.err.OperationalError) (1050, "Table 'application_credential' already exists")
cinder db sync   : CRITICAL cinder [-] Unhandled error: sqlalchemy.exc.OperationalError: (pymysql.err.OperationalError) (1050, "Table 'services' already exists")
```

The log line before the nova error is `Running upgrade  -> d67eeaabee36, Initial version`: 2026.1 does **not** refuse with a version message; it finds no `alembic_version`, treats the schema as empty and tries to create it from the initial revision, which fails on the first existing table. Side effect on the copy: each failed run leaves an **empty `alembic_version` table** in `nova`, `nova_api`, `nova_cell0`, `keystone` and `cinder` (one more table each than the baseline: 111/33/111/50/36 vs 110/32/110/49/35); `migrate_version` rows are unchanged (nova 407, nova_api 72, keystone 109/78/78/78, cinder 136) and no table was created or altered otherwise (the first CREATE failed). Engine: 11.4.13 started on the upgraded 10.3 datadir; `mariadb-upgrade` and `mariadb-check` exit 0; two error-log lines at start-up, before the upgrade ran: `Incorrect definition of table mysql.event: expected column 'definer' ... found type char(141)` and `Event Scheduler ... disabled` (resolved by `mariadb-upgrade`, E3 informational).

## Service checks

not run (no services).

## Workload checks

not run.

## Conclusion

Confirmed: a direct jump fails for Nova, Keystone and Cinder. The failure is an abrupt `Table ... already exists` (error 1050) during an attempted initial-schema creation, not a version refusal; an operator who ran it against a production database would see the same, and the first statement failing is the only reason nothing else was changed. Remaining unknown: Glance, Placement and Neutron were not run (their Alembic chains are complete in 2026.1; the R1 variant runs them). A side finding for the runbook: a failed attempt leaves empty `alembic_version` tables, which a later bridge run must expect (the 2023.1 bridge stamps/creates it).

## Status

`FAILED` (expected, negative): hypothesis confirmed. Not run: Glance, Placement, Neutron.

## Corrections after the Red Team Stage 5 review (RT-N-20)

* "Refuses" is the wrong verb: 2026.1 `db sync` has no legacy-detection branch; it reads `alembic_version` (absent), treats the schema as fresh and runs the initial revision.
* The clean outcome (no partial schema) depended on the **first statement failing** (`CREATE TABLE cell_mappings` / `instances` / `application_credential` / `services` already existed). A future initial revision that began with a table absent at Ussuri would have left partially created tables, with no clean way back except a restore. This was luck of table order, not a safeguard.
* The empty `alembic_version` left behind is now a pre-check, **PC-V3** (`fast-forward-checks.md` Amendment 1), implemented in `ff/12-prechecks.sh`.
