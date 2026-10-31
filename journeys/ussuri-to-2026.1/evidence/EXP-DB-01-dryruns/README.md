# Dry runs of the revised harness (not experiments, not strict runs)

Baseline v4 (`lab/ussuri-db-lab/backups-v4/`), observe mode, uncommitted harness. Purpose: show that the implemented checks work
before the architect commits the harness and gives the go for the strict re-run of EXP-DB-01. Nothing here carries a status.

| Run | Setting | Result |
|---|---|---|
| `d1` | `H1B=0` (no Cinder 23.5.0 step) | pre-checks all PASS on v4 (PC-V3, PC-G1a, PC-O1 per cell, PC-C4, PC-Q3, PC-Q5 = 0); after H1: **HARD STOP by PC-C1** (volumes=3, snapshots=2 `use_quota` NULL = exactly the predicted soft-deleted rows; V-C1a/V-C2a prediction matches). This is the proof that the safeguard works |
| `d2` | default (with H1b) | H1 PASS (201 declared schema differences = A1..A4 + S-1, 0 undeclared; C9 0 FAILURE, keystone-status runs); **H1b PASS**: cinder 23.5.0, PC-C1 gate PASS (0 and 0), cinder vs reference 32 declared / 0 undeclared, other databases identical to H1; SC-ENGINE clean restart: 0 `[ERROR]` after restart at every step; H2..H4r: counts/fingerprints 0 undeclared, H4r == H4; **schema comparison: 12 UNDECLARED lines at H2..H4r** = nova and nova_cell0 `shadow_migrate_version` (see below) |

Finding for Agent 4 (needs a declaration or an explanation): `nova.shadow_migrate_version` and `nova_cell0.shadow_migrate_version`
exist only in the migrated schema, at every hop H1..H4r (12 lines: table, 3 columns, index, key, for 2 databases). They are the legacy shadow of
the `migrate_version` table. In R1b/R1c/R0 they were classified "S-1" by a shell filter that matched the substring `migrate_version`, i.e. **hidden**;
the revised comparator matches the table name exactly and shows them (`d2/recheck-comparator-sha-714c13df/`). The comparator was edited after d2 for this reason;
the d2 live `schema-diff.txt` files are unchanged and the recheck is a separate directory.
