# Commit SHA mapping after the history rewrite of 2026-10-31

On the owner's request, the commit messages of branch `claude/epic-pascal-2kqc98` were normalised to the OzarLand
conventions: plain messages, signed off in the owner's name (`ozarland/docs/agents.md`). Only the messages and the
author and committer fields changed. Every tree is identical, so every file and file hash recorded in the evidence is
unchanged. Experiment records that cite a harness commit (for example `2f3e48a` or `85faf67`) refer to the old
identifiers: use this table to find the rewritten commit with the same content.

| Old commit | New commit | Subject |
|---|---|---|
| `43e8e6add26f` | `0ab18721754a` | Initial commit |
| `466106b68b38` | `bfb1c97c6eb0` | Ussuri to 2026.1 journey: mission brief, agent allocation and lab decision records |
| `632afa261cf6` | `a78bcded31c7` | Ussuri to 2026.1 journey: factual inventory of the OzarLand repositories |
| `be7bad0659c4` | `70d7c88998b1` | Repository scaffolding: README, contribution rules, validation statuses and templates |
| `75b06d1e2d45` | `6050770d0d85` | Ussuri lab (work in progress): image build files and registry probes |
| `fb58d70ccf6f` | `6d88b4152102` | Ussuri to 2026.1 journey: operational risk, workload preservation and recovery assessments (Stage 1) |
| `c27b6c7297e5` | `dd5382631ba0` | Ussuri lab (work in progress): infrastructure, configuration and Keystone scripts, pip freeze |
| `9debdaa80abb` | `e207784b4ad0` | Ussuri to 2026.1 journey: independent initial Red Team assessment (Stage 1) |
| `8565c9c04e0c` | `82261db672a4` | Ussuri to 2026.1 journey: Stage 1 work in progress (Kolla-Ansible and database assessments, lab scripts) |
| `f2b5e43ea762` | `6b66c2e157b0` | Ussuri to 2026.1 journey: database migration strategy and recovery requirements (Stage 1) |
| `2810e7432036` | `bb3be19c46ea` | Ussuri to 2026.1 journey: release compatibility deliverables and DR-002 (Keystone bridge window) |
| `bd7892fd0bf9` | `7959dceff685` | Ussuri to 2026.1 journey: Stage 2 architecture proposals P1-P4 and experiment plan |
| `c5c71c6a59c6` | `5710264db5f4` | Ussuri lab (work in progress): baseline evidence updates |
| `7b7582077d1e` | `f41983554e3f` | Ussuri to 2026.1 journey: Red Team Stage 3 review and corrective actions (P2 fencing and Nova gate, DR-003, coverage checklist, mandatory scope block) |
| `7b62423fc51a` | `2ed1827c93ec` | Ussuri lab (work in progress): README, Kolla build probe logs, quick-lab extension draft |
| `bf38d1cf66d1` | `504fbbe2cb8e` | Ussuri to 2026.1 journey: work in progress from lab and database agents |
| `fecd07aedead` | `392f7bdf4929` | Ussuri to 2026.1 journey: declared differences frozen, fast-forward pre-checks, checklist review, DR-003 resolved (no workaround flag by default) |
| `d7090584e300` | `52db554f2925` | Ussuri to 2026.1 journey: Ussuri container lab baseline captured (fenced and forced-down states), restore proven, lab report |
| `7b8e51eaba55` | `3b119ced6d2b` | Ussuri to 2026.1 journey: Stage 4 first runs (EXP-DB-00 baseline record, EXP-DB-N1 direct jump refused, R0 schema calibration, EXP-DB-01 R1 failed on stop conditions) |
| `663fffcaa554` | `e4488e0d1060` | Ussuri to 2026.1 journey: EXP-DB-01 root-cause analysis and DR-004 (Cinder 23.5.0 step for unreleased use_quota fix) |
| `93a1ae35e516` | `2cfe87164a62` | Ussuri to 2026.1 journey: Red Team Stage 5 review of first results |
| `14ff8e8b731f` | `647d68c87abe` | Ussuri to 2026.1 journey: Amendment 1 to the frozen declared differences and pre-checks (A1-A7, H1b, PC-C1 gate, PC-C4, PC-V3) |
| `90f37d816c0e` | `861cca57884c` | Ussuri lab (work in progress): baseline v4 evidence and Cinder 2023.2 image build files |
| `2a830e49fe31` | `4f5a395f34a1` | Ussuri to 2026.1 journey: evidence integrity note for EXP-DB-01, corrected records, implemented frozen checks, baseline v4, Cinder H1b, dry runs |
| `f29824c0b9e4` | `1c2f814aa40f` | Ussuri to 2026.1 journey: Amendment 2 proposed (Nova shadow_migrate_version), old-filter review |
| `68d0e907d464` | `1efe80d6d659` | Ussuri to 2026.1 journey: Red Team Stage 5b closure review; Amendment 2 accepted |
| `a76e283aacc1` | `50d02894ff05` | Ussuri to 2026.1 journey: architecture P2 carries the Cinder 23.5.0 step and the moved Cinder point of no return |
| `2f3e48a36465` | `b65f5326ee81` | Ussuri lab: harness for the strict EXP-DB-01 re-run (Amendment 2, N-3 reconciliation, A3 archive check, verdict logic), dry run d3 |
| `a6597d6d5886` | `a4d431b4c57d` | Ussuri to 2026.1 journey: EXP-DB-01 strict run R2 passed (harness 2f3e48a, baseline v4, Cinder H1b) - LAB-VALIDATED within the container-lab scope |
| `85faf6779a74` | `613681c72cc6` | Ussuri to 2026.1 journey: VAL-001, consolidated progress report 01, journey status and agent table updated |
| `f7c4aa443b6a` | `dfbce707383d` | Ussuri lab (work in progress): 2026.1 service runtime scaffolding, H4r re-derivation evidence so far |
| `941850529ded` | `c3a4ee73183d` | Ussuri to 2026.1 journey: architecture P2 carries the Kolla-Ansible deploy-on-migrated-databases findings |
| `f74bd7c57f81` | `e76504f64a99` | Ussuri lab (work in progress): H4r re-derivation evidence |
| `0c81bd51ddd9` | `7e084bc2914e` | Ussuri to 2026.1 journey: H4r re-derivation (strict, PASS, harness 85faf67 = 2f3e48a for lab/) as source for service experiments |
| `6520be494696` | `11f2019d2c7c` | Ussuri lab (work in progress): 2026.1 service runtime and EXP-SVC-01 dry runs (not a result) |
| `c3afa909ab83` | `7510fb43c09b` | Ussuri lab (work in progress): EXP-SVC-01 harness updates |
