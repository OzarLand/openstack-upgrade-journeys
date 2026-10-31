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

## Second step: re-attachment to the repository's original initial commit

The first rewrite also rewrote the GitHub-created initial commit (`43e8e6a`), so the branch no longer descended from
`main`. The branch was then rebased onto the original `43e8e6a`. Trees are again identical. To go from an identifier
in an experiment record to the current commit, apply the table above, then this one.

| After the first rewrite | Current commit |
|---|---|
| `bfb1c97c6eb0` | `e780a9a99712` |
| `a78bcded31c7` | `e5860e6d06fe` |
| `70d7c88998b1` | `50720f97efeb` |
| `6050770d0d85` | `eea8f37376a4` |
| `6d88b4152102` | `1b3f27970c8f` |
| `dd5382631ba0` | `9ce7d054cf96` |
| `e207784b4ad0` | `fa480caf893c` |
| `82261db672a4` | `dd9cded0c064` |
| `6b66c2e157b0` | `90211d75d45a` |
| `bb3be19c46ea` | `451393f19e5c` |
| `7959dceff685` | `a0765aeb9f82` |
| `5710264db5f4` | `7460522925f8` |
| `f41983554e3f` | `a4f197b932ea` |
| `2ed1827c93ec` | `b51a5be3e4a2` |
| `504fbbe2cb8e` | `061525a53e66` |
| `392f7bdf4929` | `49eb8fc6fbcd` |
| `52db554f2925` | `8bb7b1be5ac5` |
| `3b119ced6d2b` | `e2e4d495d317` |
| `e4488e0d1060` | `4d4ffb4b1e1b` |
| `2cfe87164a62` | `c6c9ed3adec4` |
| `647d68c87abe` | `735ac040b524` |
| `861cca57884c` | `481b4deee681` |
| `4f5a395f34a1` | `64f8ca2659ba` |
| `1c2f814aa40f` | `1f06d2b748ee` |
| `1efe80d6d659` | `b50ec52c4fee` |
| `50d02894ff05` | `793ae79b5045` |
| `b65f5326ee81` | `5e7d979455f3` |
| `a4d431b4c57d` | `264a975e6004` |
| `613681c72cc6` | `bfe379654dfd` |
| `dfbce707383d` | `ba80ad6f4e74` |
| `c3a4ee73183d` | `4493c81b1476` |
| `e76504f64a99` | `baf46905f1ed` |
| `7e084bc2914e` | `2e35709009cb` |
| `11f2019d2c7c` | `b14b052ac5a4` |
| `7510fb43c09b` | `1154d2b948b0` |
| `c5e56fbb1a5b` | `c62abff3990f` |
| `1fadf42e4c6e` | `ac428b1d482d` |
| `bb0ecfe0ace4` | `db6b8e459cb9` |
| `fef012b0e150` | `e7b8cf374488` |
| `4ddb122ceed5` | `d37978fe5f12` |
| `af908c71373e` | `5bf85fd6e888` |
| `4741c7b891f6` | `bbf17619b0ed` |
| `7fc791149576` | `c80ac5e34aa9` |
| `f0e29b1bd813` | `c84ae6612b29` |
| `acf4a50be4a1` | `89e7cecc27a1` |
| `205b80b9863f` | `ee0489079228` |
| `7900da689195` | `bc1a50079187` |
| `82006ecb8349` | `1e82bc19e354` |
| `5dd51dbec2d7` | `cbfe86bb9d65` |
| `f1e64d3d237b` | `888bb2e312ce` |
| `d4cb3c84881b` | `4fc68b89f401` |
| `1ceb2f802acd` | `6d2c18cec5b2` |
| `fdc3d0b14a0f` | `55f295ee3c41` |
| `2ce87a474023` | `20566b8ed602` |
| `ca5d8f2ee27e` | `5549a8f87545` |
| `9367a63600c4` | `2b6717c3583b` |
| `101f66f66241` | `30f20d7f708e` |
| `d536b7466f93` | `c5acd449fdc9` |
| `8764c99b49b9` | `16fa2c39b270` |
| `7ab9ece04647` | `24efa107064e` |
| `7405aea89f43` | `c044dc7d3300` |
| `0f59c69ffbf8` | `13f47b1fc4a7` |
| `f3e70aa08b7a` | `427c4d77bef8` |
| `d7dd1b93f971` | `8575ebcf7429` |
| `d45ac27e73e1` | `8c51e77d47d8` |
