#!/usr/bin/env bash
# Checks C1-C10 after one hop (C1 = the hop script's own exit codes). usage: 40-checks.sh <run> <rel> <hop: 0|1|1b|2|3|4|5> [--t0]
# --t0 : only take the T0 snapshot. Exit codes: 0 pass; 1 stop condition (undeclared difference, failed check); 3 HARD stop
# (PC-C1 gate: never overridden, not even in observe mode). Comparator = ff/tools/compare.py (frozen artefact, Amendment 1).
. "$(dirname "$0")/lib.sh"; ff_vars "${1:?run}"; REL="${2:?release}"; HOP="${3:?hop}"; T0ONLY="${4:-}"; set +e
case "$HOP" in 0) H=T0;; 5) H=H4r;; *) H="H$HOP";; esac; OUT="$RUN_EV/$H"; mkdir -p "$OUT" "$CFG_FF/snap"
DBS=$(IFS=,; echo "${OS_DBS[*]}"); REFS=$(IFS=,; for d in "${OS_DBS[@]}"; do printf '%s_ref ' "$d"; done | tr ' ' ',' | sed 's/,$//')
snap() { docker run --rm --network "$NET_FF" -v "$CFG_FF/snap":/snap -v "$FF_DIR":/ffsrc:ro "$TOOL_IMG" python /ffsrc/tools/snap.py --host ufj-mariadb --password "$DB_ROOT" "$@"; }
cmp() { docker run --rm -v "$CFG_FF/snap":/snap -v "$FF_DIR":/ffsrc:ro "$TOOL_IMG" python /ffsrc/tools/compare.py "$@"; }
t0=$(date +%s)
if [ "$T0ONLY" = --t0 ]; then
  snap --dbs "$DBS" --out /snap/T0 | tail -1; ff_sql "SELECT 'mariadb',version()" > "$OUT/engine.txt"; echo "T0 snapshot $(( $(date +%s)-t0 )) s" | tee "$OUT/timing.txt"; exit 0
fi
STOP=0; HARD=0; : > "$OUT/summary.txt"; say() { echo "$*" | tee -a "$OUT/summary.txt"; }
RELC="$REL"; [ "$HOP" = 1b ] && RELC=2023.2     # cinder release at this checkpoint
CF() { echo "--config-file /etc/$1/$2 --config-file /etc/ff/$3"; }
# ---- PC-C1 (hard gate after H1b; observation at H1, V-C1a/V-C2a) and the deleted-row prediction
nv=$(ff_sql "SELECT COUNT(*) FROM cinder.volumes WHERE use_quota IS NULL" 2>/dev/null); ns=$(ff_sql "SELECT COUNT(*) FROM cinder.snapshots WHERE use_quota IS NULL" 2>/dev/null)
dv=$(ff_sql "SELECT COUNT(*) FROM cinder.volumes WHERE use_quota IS NULL AND deleted=0" 2>/dev/null); ds=$(ff_sql "SELECT COUNT(*) FROM cinder.snapshots WHERE use_quota IS NULL AND deleted=0" 2>/dev/null)
pv=$(python3 -c "import json;print(json.load(open('$CFG_FF/snap/predictions.json'))['deleted_volumes'])"); ps=$(python3 -c "import json;print(json.load(open('$CFG_FF/snap/predictions.json'))['deleted_snapshots'])")
GATE=1b; [ "${H1B:-1}" = 0 ] && GATE=1
say "[PC-C1] use_quota NULL (deleted included): volumes=$nv snapshots=$ns; of which non-deleted: volumes=$dv snapshots=$ds; predicted soft-deleted at T0: volumes=$pv snapshots=$ps"
if [ "$HOP" = 1 ] && [ "$GATE" = 1b ]; then
  if [ "$nv" = "$pv" ] && [ "$ns" = "$ps" ] && [ "$dv" = 0 ] && [ "$ds" = 0 ]; then say "[V-C1a/V-C2a] H1 left exactly the predicted soft-deleted rows NULL (non-deleted rows set): PASS"; else say "[V-C1a/V-C2a] H1 result differs from the prediction: STOP"; STOP=1; fi
fi
if [ "$HOP" = "$GATE" ] || { [ "$HOP" != 0 ] && [ "$HOP" != 1 ] && [ "$HOP" != 1b ]; }; then
  if [ "$nv" = 0 ] && [ "$ns" = 0 ]; then say "[PC-C1] GATE PASS (0 and 0)"; else say "[PC-C1] GATE FAIL: STOP (SC-PC-C1, hard). Never fix by SQL, never purge."; HARD=1; STOP=1; fi
fi
if [ "$HOP" = 1b ]; then ONLY=cinder REL_CINDER=2023.2 "$FF_DIR/45-refs.sh" "$RUN" "$REL" || { say "[C4] reference build FAILED"; exit 1; }
else REL_CINDER="$RELC" "$FF_DIR/45-refs.sh" "$RUN" "$REL" || { say "[C4] reference build FAILED"; exit 1; }; fi
snap --dbs "$DBS,$REFS" --out /snap/$H | tail -1
V() { ff_oneshot "$1" "$2" -- "${@:3}" 2>&1 | ff_redact | grep -vE "^$|WARNING|Warning|warn|INFO|DEBUG|Deprecat|deprecat" ; }
{
 if [ "$HOP" != 1b ]; then
 echo "== nova api_db version"; V "$REL" nova nova-manage $(CF nova nova.conf nova.conf) api_db version
 echo "== nova db version cell1"; V "$REL" nova nova-manage $(CF nova nova.conf nova.conf) db version
 echo "== nova db version cell0"; V "$REL" nova nova-manage $(CF nova nova.conf nova-cell0.conf) db version
 echo "== keystone db_version"; V "$REL" keystone keystone-manage $(CF keystone keystone.conf keystone.conf) db_version
 fi
 echo "== cinder db version (release $RELC)"; V "$RELC" cinder cinder-manage $(CF cinder cinder.conf cinder.conf) db version
 if [ "$HOP" != 1b ]; then
 echo "== glance db version"; V "$REL" glance glance-manage $(CF glance glance-api.conf glance.conf) db version
 echo "== glance db check (exit)"; ff_oneshot "$REL" glance -- glance-manage $(CF glance glance-api.conf glance.conf) db check >/dev/null 2>&1; echo "exit=$?"
 echo "== placement db version"; V "$REL" placement placement-manage $(CF placement placement.conf placement.conf) db version
 echo "== neutron current"; V "$REL" neutron neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/ml2_conf.ini --config-file /etc/ff/neutron.conf current
 echo "== neutron has_offline_migrations (exit)"; ff_oneshot "$REL" neutron -- neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/ml2_conf.ini --config-file /etc/ff/neutron.conf has_offline_migrations >/dev/null 2>&1; echo "exit=$?"
 echo "== neutron check_migration (exit)"; ff_oneshot "$REL" neutron -- neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/ml2_conf.ini --config-file /etc/ff/neutron.conf check_migration >/dev/null 2>&1; echo "exit=$?"
 fi
} > "$OUT/versions.txt" 2>&1
{ for d in $( [ "$HOP" = 1b ] && echo cinder || echo keystone glance placement nova_api nova nova_cell0 neutron cinder ); do for t in alembic_version migrate_version; do
   a=$(ff_sql "SELECT GROUP_CONCAT(CONCAT_WS('/',$( [ $t = alembic_version ] && echo version_num || echo repository_id,version) ) ORDER BY 1 SEPARATOR ';') FROM \`$d\`.\`$t\`" 2>/dev/null)
   b=$(ff_sql "SELECT GROUP_CONCAT(CONCAT_WS('/',$( [ $t = alembic_version ] && echo version_num || echo repository_id,version) ) ORDER BY 1 SEPARATOR ';') FROM \`${d}_ref\`.\`$t\`" 2>/dev/null)
   printf '%s.%s migrated=[%s] reference=[%s] %s\n' "$d" "$t" "${a:-absent}" "${b:-absent}" "$([ "${a:-absent}" = "${b:-absent}" ] && echo equal || echo DIFFERENT)"
 done; done; } > "$OUT/bookkeeping.txt" 2>&1
# ---- C4 comparison A (classified by the comparator against Amendment 1)
: > "$OUT/schema-diff.txt"
for d in $( [ "$HOP" = 1b ] && echo cinder || echo "${OS_DBS[*]}" ); do
  cmp schema --snap /snap/$H --a $d --b ${d}_ref --hop $HOP > "$OUT/schema-$d.txt"
  grep -vE "^SUMMARY" "$OUT/schema-$d.txt" | awk -v d="$d" -F'\t' '{print $1"\t"d"\t"$2"\t"$3"\t"$4}' >> "$OUT/schema-diff.txt"
done
su=$(grep -c "^UNDECLARED" "$OUT/schema-diff.txt"); sd=$(grep -c "^DECLARED" "$OUT/schema-diff.txt")
# the declared set must be exactly: A1 (8.7 list) + A2/A3/A4 + A7 (H2 only) + S-1 + S-3.4 (12 lines, nova and nova_cell0), and nothing else
ids=$(grep '^DECLARED' "$OUT/schema-diff.txt" | cut -f3 | sort -u | tr '\n' ' ')
for i in $ids; do case "$i" in A1/S-3.1|A2/S-3.2|A3/S-3.3|A4/S-N.1|S-1a|S-1c/S-1d|S-3.4) ;; A7/S-2.1) [ "$HOP" = 2 ] || { say "[C4] A7 declared outside H2: STOP"; STOP=1; } ;; *) say "[C4] unexpected declared id $i: STOP"; STOP=1;; esac; done
n34=$(grep -c $'^DECLARED\t[a-z_0-9]*\tS-3.4' "$OUT/schema-diff.txt"); [ "$HOP" != 1b ] && [ "$n34" != 12 ] && { say "[C4] S-3.4 lines = $n34 (expected exactly 12): STOP"; STOP=1; }
say "[C4] schema vs reference$( [ "$HOP" = 1b ] && echo ' (cinder only, reference built by cinder 23.5.0)'): $sd declared (ids: $(grep '^DECLARED' "$OUT/schema-diff.txt" | cut -f3 | sort | uniq -c | awk '{printf "%s x%s; ",$2,$1}')), $su UNDECLARED"; [ "$su" -gt 0 ] && STOP=1
# ---- C5/C6 comparison B
if [ "$HOP" = 1b ]; then
  cmp data --t0 /snap/T0 --now /snap/$H --hop 1b --pred /snap/predictions.json --only-db cinder > "$OUT/data-diff.txt" 2>&1; rcd=$?
  cmp same --a /snap/H1 --b /snap/H1b --exclude-db cinder > "$OUT/others-unchanged-from-H1.txt" 2>&1; rco=$?
  say "[C5/C6] cinder vs T0: $(tail -1 "$OUT/data-diff.txt"); other databases H1b vs H1: $(tail -1 "$OUT/others-unchanged-from-H1.txt")"; [ $rcd -ne 0 ] || [ $rco -ne 0 ] && STOP=1
else
  cmp data --t0 /snap/T0 --now /snap/$H --hop $HOP --pred /snap/predictions.json > "$OUT/data-diff.txt" 2>&1; rcd=$?
  say "[C5/C6] counts+fingerprints vs T0: $(tail -1 "$OUT/data-diff.txt")"; [ $rcd -ne 0 ] && STOP=1
fi
# N-3 reconciliation: updated_at row counts of the N-3 tables vs the ODM migrated counts / predictions of THIS hop (consecutive snapshots)
case "$HOP" in 1) PREV=T0;; 1b) PREV=H1;; 2) [ -d "$CFG_FF/snap/H1b" ] && PREV=H1b || PREV=H1;; 3) PREV=H2;; 4) PREV=H3;; 5) PREV=H4;; esac
docker run --rm -v "$CFG_FF/snap":/snap -v "$FF_DIR":/ffsrc:ro -v "$OUT":/hop:ro "$TOOL_IMG" python /ffsrc/tools/reconcile_n3.py --prev /snap/$PREV --now /snap/$H --hopdir /hop --hop $HOP --pred /snap/predictions.json > "$OUT/n3-reconciliation.txt" 2>&1; rcn=$?
say "[N-3] $(tail -1 "$OUT/n3-reconciliation.txt") (previous snapshot $PREV)"; [ $rcn -ne 0 ] && STOP=1
if [ "$HOP" = 5 ]; then
  cmp same --a /snap/H4 --b /snap/H4r > "$OUT/idempotency-diff.txt" 2>&1; rci=$?
  say "[IDEM] H4r vs H4 (no exclusions): $(tail -1 "$OUT/idempotency-diff.txt")"; [ $rci -ne 0 ] && STOP=1
fi
grep -q DIFFERENT "$OUT/bookkeeping.txt" && say "[C2] bookkeeping rows differing from the reference (migrate_version expected for keystone/glance): $(grep DIFFERENT "$OUT/bookkeeping.txt" | cut -d' ' -f1 | tr '\n' ' ')"
# ---- C9 offline status tools (keystone with the baseline's key repository mounted, RT-N-16)
{
 for s in "neutron:neutron-status:--config-file /etc/neutron/neutron.conf --config-file /etc/ff/neutron.conf:$REL" "cinder:cinder-status:$(CF cinder cinder.conf cinder.conf):$RELC" "keystone:keystone-status:$(CF keystone keystone.conf keystone.conf):$REL" "glance:glance-status:$(CF glance glance-api.conf glance.conf):$REL" "placement:placement-status:$(CF placement placement.conf placement.conf):$REL"; do
   svc=${s%%:*}; rest=${s#*:}; tool=${rest%%:*}; rest=${rest#*:}; rr=${rest##*:}; args=${rest%:*}
   [ "$HOP" = 1b ] && [ "$svc" != cinder ] && continue
   echo "== $tool upgrade check ($rr)"; ff_oneshot "$rr" "$svc" -- $tool $args upgrade check 2>&1 | ff_redact | grep -vE "WARNING|DEBUG|Deprecat" | tail -40; echo "exit=${PIPESTATUS[0]}"
 done
} > "$OUT/status-tools.txt" 2>&1
fails=$(grep -c "Result: Failure" "$OUT/status-tools.txt"); warns=$(grep -c "Result: Warning" "$OUT/status-tools.txt"); ovn=$(grep -c "OVN" "$OUT/status-tools.txt"); toolerr=$(awk '/^== /{t=$0; w=0} /Result: Warning/{w=1} /^exit=1$/{ if(!w) c++ } END{print c+0}' "$OUT/status-tools.txt")
ksran=$(sed -n '/^== keystone-status/,/^== glance-status/p' "$OUT/status-tools.txt" | grep -c "Result: ")
[ "$HOP" != 1b ] && [ "$ksran" = 0 ] && { say "[C9] keystone-status did not run (no result table): STOP"; STOP=1; }
say "[C9] status tools: $fails FAILURE results; $warns warning result(s), of which OVN-related lines: $ovn (neutron-status exit 1 on the OVN warning is a WARNING, recorded, not a tool error); keystone-status results: $ksran; $toolerr real tool errors (exit 1 with no result at all; must be 0) - see status-tools.txt"; [ "$fails" -gt 0 ] && { say "[C9] STOP: a status tool reports FAILURE"; STOP=1; }; [ "$toolerr" -gt 0 ] && { say "[C9] STOP: a status tool failed to run"; STOP=1; }
[ -s "$OUT/../sql-mode.tsv" ] || true
say "[C10] checks seconds: $(( $(date +%s)-t0 )); hop timings in steps.tsv"
say "RESULT $H: $([ $HARD = 1 ] && echo 'HARD STOP (PC-C1)' || { [ $STOP = 0 ] && echo PASS || echo 'STOP (undeclared difference or failed check)'; })"
[ $HARD = 1 ] && exit 3; exit $STOP
