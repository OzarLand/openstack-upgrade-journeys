# DR-004 — Add a Cinder-only 2023.2 step (cinder 23.5.0) to the fast-forward path

| Field | Value |
|---|---|
| Decision ID | DR-004 |
| Date | 2026-10-31 |
| Responsible agent | Agent 1 — Architect, on Agent 4's root-cause analysis (`experiments/EXP-DB-01-root-cause-analysis.md`) |
| Validation status | `PROPOSED-UNVERIFIED`. Agent 4 reproduced the failure in the lab, and its fix worked on a copy built with a mixed environment. A strict re-run of EXP-DB-01 on baseline v2 with a proper 2023.2 image is required. |

## Context

The strict EXP-DB-01 run stopped at H2: cinder 2024.1 `9ab1b092a404` failed with MariaDB error 1265 (`ALTER …
use_quota NOT NULL`). One soft-deleted volume still had `use_quota` NULL after the 2023.1 online data migrations had
reported nothing left to do.

## Evidence

- **Reproduced by Agent 4.** The MariaDB general log shows the 2023.1 online data migration query running with
  `WHERE volumes.deleted = false`, so soft-deleted rows are never migrated.
- **Checked by the architect in the source**, with the online data migration body read at release tags:

  | Cinder release | Series | `read_deleted='yes'` in `use_quota_online_data_migration` |
  |---|---|---|
  | 22.3.0 (last 2023.1 release on PyPI) | 2023.1 | no |
  | 23.4.0 | 2023.2 | no |
  | 23.5.0 | 2023.2 | **yes** |

- **The fix** is commit `a3c90fb4c` "[stable-only] Fix online data migrations" (bug #2070475). It was merged to
  `unmaintained/2023.1` after the last 2023.1 release, so no 2023.1 release on PyPI contains it.
- **Not an artefact of skipping releases.** According to the commit, the bug also hits the supported 2023.1 → 2024.1
  path for any deployment that has soft-deleted volumes or snapshots created before `use_quota` existed.

## Alternatives

1. **`cinder-manage db purge` before the bridge.** This removes the affected rows. Rejected as a fix: it is a
   data-retention decision, and it also destroys the test data that exercises this path (baseline v3).
2. **Build 2023.1 Cinder from the `unmaintained/2023.1` branch tip.** This includes the fix, but the code is unreleased
   and untagged. Rejected: there is no stable artefact to pin.
3. **Add a Cinder-only step with the released cinder 23.5.0 (chosen).** Its `db sync` takes the Cinder schema to the
   2023.2 head; then the online data migrations run until nothing remains. A released, pinned artefact.
4. **Hard gate only.** Stop if any `use_quota` NULL row remains before 2024.1 code. Kept, in addition to option 3.

## Decision

The fast-forward path becomes:

1. Ussuri (finish online data migrations) → **2023.1** for all services (the bridge).
2. **Cinder 2023.2 (23.5.0)**: `db sync`, then online data migrations until 0.
3. **Gate PC-C1:** zero `use_quota` NULL rows in `volumes` and `snapshots`, including deleted rows.
4. **2024.1 → 2025.1 → 2026.1** for all services.

## Process lesson (applies to every agent)

Claims about migration code were read at **branch heads**, not at the **released versions actually installed**. The
Red Team's Stage 3 verification (V6) did the same and is corrected here. From now on, every migration claim is
checked at the tag of the version installed in the one-shot images. Kolla images are built from branch content and
could therefore differ from PyPI releases. Lab parity with production images remains open (Red Team RT-N-10), and a
Tier B run must use the exact image digests.

## Upstream contribution

The Cinder 2023.1 → 2024.1 bug affects the supported path. An OzarLand note for operators is warranted (see
`lessons-learned.md`). No upstream report is filed from this mission without the owner's approval.
