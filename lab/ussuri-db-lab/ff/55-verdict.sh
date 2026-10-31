#!/usr/bin/env bash
# Strict-run verdict, exactly the pass list of the Red Team Stage 5b closure review. PASS only if every line passes; otherwise FAILED.
# Reads the live outputs of the run; never re-analyses (it only greps what the checks already wrote).  usage: 55-verdict.sh <run>
. "$(dirname "$0")/lib.sh"; ff_vars "${1:?run}"; set +e
V="$RUN_EV/verdict.txt"; : > "$V"; BAD=0
chk() { if [ "$2" = ok ]; then echo "PASS  $1" >> "$V"; else echo "FAIL  $1  [$3]" >> "$V"; BAD=1; fi; }
HOPS="H1 H1b H2 H3 H4 H4r"
# 1. every command exit 0; every ODM loop ends at exit 0 (a loop only ends on exit 0 or aborts the run)
bad=""; for h in $HOPS; do [ -f "$RUN_EV/$h/steps.tsv" ] || { bad="$bad $h(missing)"; continue; }
  awk -F'\t' -v h=$h '$1!~/total_seconds/ && $1!~/-odm/ && $2!=0 {print h":"$1" rc="$2}' "$RUN_EV/$h/steps.tsv"; done > "$RUN_EV/.badcmd"; [ -s "$RUN_EV/.badcmd" ] && bad="$bad $(tr '\n' ' ' < "$RUN_EV/.badcmd")"; rm -f "$RUN_EV/.badcmd"
for h in $HOPS; do for o in cinder-odm nova-odm nova-odm-cell0 placement-odm; do
  [ "$h" = H1b ] && [ "$o" != cinder-odm ] && continue; [ "$h" = H4r ] && [ "$o" = cinder-odm ] && true
  last=$(grep -P "^$o-[0-9]+\t" "$RUN_EV/$h/steps.tsv" 2>/dev/null | tail -1 | cut -f2); [ "$last" = 0 ] || bad="$bad $h:$o(last rc=${last:-none})"; done; done
chk "every command exit 0 and every ODM (Nova per cell incl. cell0, Cinder, Placement) ends at exit 0, at all hops" "$([ -z "$bad" ] && echo ok || echo bad)" "$bad"
# 2. pre-checks
chk "all PC-* pass (PC-V3, G1a, O1 per cell, C4, Q3, Q5, Q6, E1 ...)" "$(grep -q 'SC overall: PASS' "$RUN_EV/prechecks.txt" && ! grep -q '^FAIL' "$RUN_EV/prechecks.txt" && echo ok || echo bad)" "$(grep '^FAIL' "$RUN_EV/prechecks.txt" | cut -c1-80 | tr '\n' ';')"
chk "PC-C1 gate 0/0 after H1b (deleted rows included)" "$(grep -q 'GATE PASS' "$RUN_EV/H1b/summary.txt" 2>/dev/null && echo ok || echo bad)" ""
# 3. PC-E1 session mode per hop and service
b=""; for h in $HOPS; do f="$RUN_EV/$h/sql-mode.tsv"; n=$(grep -c . "$f" 2>/dev/null); exp=12; [ $h = H1b ] && exp=2; [ "${n:-0}" -ge $exp ] && ! grep -q 'NOT-STRICT\|Traceback' "$f" || b="$b $h(lines=${n:-0})"; done
chk "PC-E1 session sql_mode captured per command at every hop and strict" "$([ -z "$b" ] && echo ok || echo bad)" "$b"
# 4. C4 / C5-C6 / N-3 / C9 / idempotency per hop
for h in $HOPS; do s="$RUN_EV/$h/summary.txt"
  chk "$h C4 schema vs reference: 0 UNDECLARED, declared set = 8.7 + A2/A3/A4 + A7(H2) + S-1 + S-3.4" "$(grep -q '\[C4\].* 0 UNDECLARED' "$s" && ! grep -q 'unexpected declared id\|declared outside\|S-3.4 lines' "$s" && echo ok || echo bad)" "$(grep '\[C4\]' "$s" | cut -c1-120)"
  chk "$h C5/C6: 0 undeclared$( [ $h = H1b ] && echo ' (cinder; other databases identical to H1)')" "$(grep '\[C5/C6\]' "$s" | grep -q 'undeclared=0.*undeclared=0\|undeclared=0$' && echo ok || echo bad)" "$(grep '\[C5/C6\]' "$s" | cut -c1-140)"
  chk "$h N-3 reconciliation with the ODM migrated counts" "$(grep -q 'N-3\] N3-RECONCILIATION PASS' "$s" && echo ok || echo bad)" "$(grep '\[N-3\]' "$s" | cut -c1-120)"
  chk "$h C9: 0 FAILURE, no tool error, keystone-status ran" "$(grep '\[C9\]' "$s" | grep -q ' 0 FAILURE results' && ! grep -q 'C9\] STOP\|did not run' "$s" && echo ok || echo bad)" "$(grep '\[C9\]' "$s" | cut -c1-140)"
done
chk "H4r == H4: zero differences (no exclusions)" "$(grep -q '\[IDEM\].*undeclared=0' "$RUN_EV/H4r/summary.txt" 2>/dev/null && echo ok || echo bad)" ""
# 5. engine
b=""; for e in "$RUN_EV"/engine-*; do [ -f "$e/result.txt" ] || continue; grep -q 'since the clean restart.*: 0$' "$e/result.txt" && ! grep -qx SC-ENGINE "$e/result.txt" || b="$b $(basename $e)"; done
chk "SC-ENGINE: mariadb-upgrade/check exit 0 and clean-restart scan clean at every engine step" "$([ -z "$b" ] && ls -d "$RUN_EV"/engine-* >/dev/null 2>&1 && echo ok || echo bad)" "$b"
# 6. targeted checks and A3
chk "targeted checks (frozen list section 5): no ASSERT-FAIL" "$([ -f "$RUN_EV/targeted-checks.txt" ] && ! grep -q "^ASSERT-FAIL" "$RUN_EV/targeted-checks.txt" && grep -q "^ASSERT-PASS" "$RUN_EV/targeted-checks.txt" && echo ok || echo bad)" "$(grep "^ASSERT-FAIL" "$RUN_EV/targeted-checks.txt" 2>/dev/null | cut -c1-100 | tr '\n' ';')"
chk "A3 archive_deleted_rows check on a disposable copy of H4r (exit 0/1, no error), purge message recorded" "$(grep -q 'PASS' "$RUN_EV/A3/result.txt" 2>/dev/null && echo ok || echo bad)" ""
# 7. scope: baseline v4, H1B, harness committed
chk "baseline v4, H1b enabled, harness committed (see harness.txt)" "$(grep -q 'uncommitted harness changes.*: 0$' "$RUN_EV/harness.txt" && readlink -f "$BASE_BACKUP" | grep -q backups-v4 && [ "${H1B:-1}" != 0 ] && echo ok || echo bad)" "$(grep -E '^(commit|uncommitted)' "$RUN_EV/harness.txt" | tr '\n' ' ')"
if [ $BAD = 0 ]; then echo "VERDICT: PASS - eligible for LAB-VALIDATED with the ruling-4 scope line plus 'procedure includes a Cinder-only 2023.2 step (DR-004), Technically possible but unsupported'. Commit $(grep '^commit' "$RUN_EV/harness.txt" | cut -d' ' -f2)." >> "$V"
else echo "VERDICT: FAILED - recorded live; no in-place re-analysis (a re-run gets a new run id and a new record)." >> "$V"; fi
cat "$V"; exit $BAD
