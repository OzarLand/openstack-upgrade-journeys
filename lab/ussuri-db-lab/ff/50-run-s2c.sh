#!/usr/bin/env bash
# S2c run: T0 snapshot, pre-checks, engine line E1 (10.3 -> 10.5 -> 10.6 [bridge hop 2023.1] -> 10.11 [2024.1, 2025.1] -> 11.4 [2026.1]),
# hops H1..H4 and the idempotency re-run H4r. usage: 50-run-s2c.sh <run> [baseline|empty] [--observe]
# Strict (default): the first stop condition ends the run. --observe: stop conditions are RECORDED and the run goes on
# (informational; a failing migration command or engine step still ends it, and nothing is ever edited by hand).
. "$(dirname "$0")/lib.sh"; ff_vars "${1:?run}"; MODE="${2:-baseline}"; OBS=0; [ "${3:-}" = --observe ] && OBS=1; set +e
[ $OBS = 1 ] && export PROVISIONAL=1
LOG="$RUN_EV/run.log"; exec > >(tee -a "$LOG") 2>&1
echo "== run $RUN mode=$MODE observe=$OBS started $(date -u +%FT%TZ)"; T00=$(date +%s)
# STRICT mode (default): baseline v4, H1b enabled, committed clean harness, pass/fail exactly per ff/55-verdict.sh; any stop -> FAILED,
# no in-place re-analysis. OBSERVE mode is a dry run: informational, it can never carry a status.
if [ $OBS = 0 ]; then
  case "$(readlink -f "$BASE_BACKUP")" in *backups-v4/*) ;; *) echo "REFUSED: a strict run uses baseline v4 (BASE_BACKUP=.../backups-v4/latest)"; exit 1;; esac
  [ "${H1B:-1}" = 0 ] && { echo "REFUSED: a strict run includes H1b (DR-004)"; exit 1; }
  [ "$MODE" = baseline ] || { echo "REFUSED: a strict run starts from the baseline"; exit 1; }
fi
fail_verdict() { if [ $OBS = 0 ]; then "$FF_DIR/55-verdict.sh" "$RUN" >/dev/null 2>&1; echo "VERDICT: FAILED - $1 (strict run; recorded live; no in-place re-analysis)" >> "$RUN_EV/verdict.txt"; else echo "DRY RUN (observe mode): informational, no status. Last event: $1" > "$RUN_EV/verdict.txt"; fi; }
STOPPED=0
stopcheck() { # stopcheck <rc> <label>   (rc 3 = HARD stop: PC-C1 gate; ends the run even in observe mode)
  if [ "$1" -eq 3 ]; then echo "!! HARD STOP at $2 (PC-C1)"; echo "RESULT hard-stop $2" > "$RUN_EV/result.txt"; fail_verdict "HARD STOP PC-C1 at $2"; exit 3; fi
  if [ "$1" -ne 0 ]; then echo "!! STOP CONDITION at $2"; STOPPED=1; [ $OBS = 1 ] || { echo "== run $RUN ended at $2 (strict)"; echo "RESULT strict-stop $2" > "$RUN_EV/result.txt"; fail_verdict "stop condition at $2"; exit 1; }; fi; }
if [ $OBS = 0 ]; then "$FF_DIR/00-version.sh" "$RUN" --strict || exit 1; else "$FF_DIR/00-version.sh" "$RUN" >/dev/null; fi
[ -d "$CFG_FF" ] && docker inspect "$DB_FF" >/dev/null 2>&1 || "$FF_DIR/10-new-copy.sh" "$RUN" "$MODE" || exit 1
# pre-checks first (PC-V3, PC-G1a, PC-O1 run Ussuri tools on the copy; T0 is taken AFTER them), then the T0 snapshot
[ "$MODE" = baseline ] && { "$FF_DIR/12-prechecks.sh" "$RUN" >/dev/null; rc=$?; grep -E "^FAIL" "$RUN_EV/prechecks.txt"; stopcheck $rc "pre-checks"; }
"$FF_DIR/40-checks.sh" "$RUN" 2023.1 0 --t0
hop() { # hop <engine-image|-> <release> <n> [check-release]
  if [ "$1" != - ]; then "$FF_DIR/20-engine.sh" "$RUN" "$1" || { echo "!! SC-ENGINE"; echo "RESULT engine-stop $1" > "$RUN_EV/result.txt"; fail_verdict "SC-ENGINE at $1"; exit 1; }; fi
  "$FF_DIR/30-hop.sh" "$RUN" "$2" "$3" || { echo "!! SC-CMD in hop $3"; echo "RESULT command-stop hop $3" > "$RUN_EV/result.txt"; fail_verdict "command failure in hop $3"; exit 1; }
  "$FF_DIR/40-checks.sh" "$RUN" "${4:-$2}" "$3"; stopcheck $? "checks after hop $3"
}
for img in mariadb:10.5 mariadb:10.6; do "$FF_DIR/20-engine.sh" "$RUN" $img || { echo "RESULT engine-stop $img" > "$RUN_EV/result.txt"; fail_verdict "SC-ENGINE at $img"; exit 1; }; done
hop - 2023.1 1
[ "${H1B:-1}" != 0 ] && hop - 2023.2 1b 2023.1   # DR-004: Cinder-only step with cinder 23.5.0, then the PC-C1 gate
hop mariadb:10.11 2024.1 2
hop - 2025.1 3
hop mariadb:11.4 2026.1 4
hop - 2026.1 5
# end of the hops: targeted checks, A3 archive check on a disposable copy, verdict (strict) - all read-only for the H4r database
"$FF_DIR/46-targeted.sh" "$RUN" >/dev/null 2>&1
"$FF_DIR/60-a3-archive.sh" "$RUN" 2>&1 | tail -3
if [ $OBS = 0 ]; then "$FF_DIR/55-verdict.sh" "$RUN" | tail -4; else echo "DRY RUN (observe mode): informational, no status." > "$RUN_EV/verdict.txt"; fi
echo "== run $RUN finished $(date -u +%FT%TZ) total $(( $(date +%s)-T00 )) s, stop conditions hit: $STOPPED"
echo "RESULT finished stopped=$STOPPED total_seconds=$(( $(date +%s)-T00 ))" > "$RUN_EV/result.txt"
[ $OBS = 0 ] && [ $STOPPED != 0 ] && exit 1
exit 0
