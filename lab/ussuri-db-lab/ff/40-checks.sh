#!/usr/bin/env bash
# Checks C1-C10 after one hop (C1 is the hop script's own exit codes). usage: 40-checks.sh <run> <rel> <hop> [--t0]
# --t0 : only take the T0 snapshot. Exit 1 if any UNDECLARED difference or failing check (a named stop condition).
. "$(dirname "$0")/lib.sh"; ff_vars "${1:?run}"; REL="${2:?release}"; HOP="${3:?hop}"; T0ONLY="${4:-}"; set +e
H="H$HOP"; [ "$HOP" = 5 ] && H="H4r"; [ "$HOP" = 0 ] && H="T0"; OUT="$RUN_EV/$H"; mkdir -p "$OUT" "$CFG_FF/snap"
DBS=$(IFS=,; echo "${OS_DBS[*]}"); REFS=$(IFS=,; for d in "${OS_DBS[@]}"; do printf '%s_ref ' "$d"; done | tr ' ' ',' | sed 's/,$//')
snap() { docker run --rm --network "$NET_FF" -v "$CFG_FF/snap":/snap -v "$FF_DIR":/ffsrc:ro "$TOOL_IMG" python /ffsrc/tools/snap.py --host ufj-mariadb --password "$DB_ROOT" "$@"; }
t0=$(date +%s)
if [ "$T0ONLY" = --t0 ]; then
  snap --dbs "$DBS" --out /snap/T0 | tail -1; ff_sql "SELECT 'mariadb',version()" > "$OUT/engine.txt"; echo "T0 snapshot $(( $(date +%s)-t0 )) s" | tee "$OUT/timing.txt"; exit 0
fi
STOP=0; : > "$OUT/summary.txt"; say() { echo "$*" | tee -a "$OUT/summary.txt"; }
"$FF_DIR/45-refs.sh" "$RUN" "$REL" || { say "[C4] reference build FAILED"; exit 1; }
snap --dbs "$DBS,$REFS" --out /snap/$H | tail -1
# ---- C2/C3 versions and bookkeeping
CF() { echo "--config-file /etc/$1/$2 --config-file /etc/ff/$3"; }
V() { ff_oneshot "$REL" "$1" -- "${@:2}" 2>&1 | ff_redact | grep -vE "^$|WARNING|Warning|warn|INFO|DEBUG|Deprecat|deprecat" ; }
{
 echo "== nova api_db version"; V nova nova-manage $(CF nova nova.conf nova.conf) api_db version
 echo "== nova db version cell1"; V nova nova-manage $(CF nova nova.conf nova.conf) db version
 echo "== nova db version cell0"; V nova nova-manage $(CF nova nova.conf nova-cell0.conf) db version
 echo "== keystone db_version"; V keystone keystone-manage $(CF keystone keystone.conf keystone.conf) db_version
 echo "== cinder db version"; V cinder cinder-manage $(CF cinder cinder.conf cinder.conf) db version
 echo "== glance db version"; V glance glance-manage $(CF glance glance-api.conf glance.conf) db version
 echo "== glance db check (exit)"; ff_oneshot "$REL" glance -- glance-manage $(CF glance glance-api.conf glance.conf) db check >/dev/null 2>&1; echo "exit=$?"
 echo "== placement db version"; V placement placement-manage $(CF placement placement.conf placement.conf) db version
 echo "== neutron current"; V neutron neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/ml2_conf.ini --config-file /etc/ff/neutron.conf current
 echo "== neutron has_offline_migrations (exit)"; ff_oneshot "$REL" neutron -- neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/ml2_conf.ini --config-file /etc/ff/neutron.conf has_offline_migrations >/dev/null 2>&1; echo "exit=$?"
 echo "== neutron check_migration (exit)"; ff_oneshot "$REL" neutron -- neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/ml2_conf.ini --config-file /etc/ff/neutron.conf check_migration >/dev/null 2>&1; echo "exit=$?"
} > "$OUT/versions.txt" 2>&1
# bookkeeping rows: migrated vs reference (alembic) and recorded (migrate_version)
{
 for d in keystone glance placement nova_api nova nova_cell0 neutron cinder; do for t in alembic_version migrate_version; do
   a=$(ff_sql "SELECT GROUP_CONCAT(CONCAT_WS('/',$( [ $t = alembic_version ] && echo version_num || echo repository_id,version) ) ORDER BY 1 SEPARATOR ';') FROM \`$d\`.\`$t\`" 2>/dev/null)
   b=$(ff_sql "SELECT GROUP_CONCAT(CONCAT_WS('/',$( [ $t = alembic_version ] && echo version_num || echo repository_id,version) ) ORDER BY 1 SEPARATOR ';') FROM \`${d}_ref\`.\`$t\`" 2>/dev/null)
   printf '%s.%s migrated=[%s] reference=[%s] %s\n' "$d" "$t" "${a:-absent}" "${b:-absent}" "$([ "${a:-absent}" = "${b:-absent}" ] && echo equal || echo DIFFERENT)"
 done; done
} > "$OUT/bookkeeping.txt" 2>&1
# ---- C4 schema vs reference
: > "$OUT/schema-diff.txt"; sdiff_u=0
for d in "${OS_DBS[@]}"; do
  docker run --rm -v "$CFG_FF/snap":/snap -v "$FF_DIR":/ffsrc:ro "$TOOL_IMG" python /ffsrc/tools/compare.py schema --snap /snap/$H --a $d --b ${d}_ref > "$OUT/schema-$d.txt"
  grep -vE "^#|^SUMMARY" "$OUT/schema-$d.txt" | while IFS=$'\t' read -r cls msg; do
    if echo "$msg" | grep -q "migrate_version"; then echo "DECLARED(S-1)	$d	$cls	$msg"
    elif [ "${PROVISIONAL:-0}" = 1 ] && echo "$msg" | grep -qE "^CHECK only in migrated: [a-z_0-9]+ \`[a-z_0-9]+\` in \(0,1\)"; then echo "PROPOSED(R0-A1)	$d	$cls	$msg"
    elif [ "${PROVISIONAL:-0}" = 1 ] && echo "$msg" | grep -qE "shadow_alembic_version"; then echo "PROPOSED(R0-A2)	$d	$cls	$msg"
    elif [ "${PROVISIONAL:-0}" = 1 ] && echo "$msg" | grep -qE "column shadow_quota_usages.resource"; then echo "PROPOSED(R0-A3)	$d	$cls	$msg"
    elif [ "${PROVISIONAL:-0}" = 1 ] && [ "$d" = cinder ] && echo "$msg" | grep -qE "name quota_usages .*quota_usages_project_id_key"; then echo "PROPOSED(R0-A4)	$d	$cls	$msg"
    else echo "UNDECLARED	$d	$cls	$msg"; fi
  done >> "$OUT/schema-diff.txt"
done
sdiff_u=$(grep -c "^UNDECLARED" "$OUT/schema-diff.txt"); say "[C4] schema vs reference: $(grep -c '^DECLARED' "$OUT/schema-diff.txt") declared, $(grep -c '^PROPOSED' "$OUT/schema-diff.txt") proposed (R0, not yet accepted), $sdiff_u UNDECLARED differences (structural: $(grep -c $'UNDECLARED\t[a-z_0-9]*\tstructural' "$OUT/schema-diff.txt"), name-only: $(grep -c $'UNDECLARED\t[a-z_0-9]*\tname-only' "$OUT/schema-diff.txt"))"; [ "$sdiff_u" -gt 0 ] && STOP=1
# ---- C5/C6 counts and fingerprints vs T0
docker run --rm -v "$CFG_FF/snap":/snap -v "$FF_DIR":/ffsrc:ro "$TOOL_IMG" python /ffsrc/tools/compare.py data --t0 /snap/T0 --now /snap/$H --hop $HOP $( [ "${PROVISIONAL:-0}" = 1 ] && echo --provisional) > "$OUT/data-diff.txt" 2>&1; rcd=$?
say "[C5/C6] counts+fingerprints vs T0: $(tail -1 "$OUT/data-diff.txt")"; [ $rcd -ne 0 ] && STOP=1
if [ "$HOP" = 5 ]; then
  docker run --rm -v "$CFG_FF/snap":/snap -v "$FF_DIR":/ffsrc:ro "$TOOL_IMG" python /ffsrc/tools/compare.py idem --a /snap/H4 --b /snap/H4r > "$OUT/idempotency-diff.txt" 2>&1; rci=$?
  say "[IDEM] H4r vs H4: $(tail -1 "$OUT/idempotency-diff.txt")"; [ $rci -ne 0 ] && STOP=1
fi
grep -q DIFFERENT "$OUT/bookkeeping.txt" && { say "[C2] bookkeeping rows differ from the reference: $(grep DIFFERENT "$OUT/bookkeeping.txt" | tr '\n' ';')"; }
# ---- C7 ODM summaries were saved by 30-hop.sh; C9 offline status tools
{
 for s in "neutron:neutron-status:--config-file /etc/neutron/neutron.conf --config-file /etc/ff/neutron.conf" "cinder:cinder-status:$(CF cinder cinder.conf cinder.conf)" "keystone:keystone-status:$(CF keystone keystone.conf keystone.conf)" "glance:glance-status:$(CF glance glance-api.conf glance.conf)" "placement:placement-status:$(CF placement placement.conf placement.conf)"; do
   svc=${s%%:*}; rest=${s#*:}; tool=${rest%%:*}; args=${rest#*:}
   echo "== $tool upgrade check"; ff_oneshot "$REL" "$svc" -- $tool $args upgrade check 2>&1 | ff_redact | grep -vE "WARNING|DEBUG|Deprecat" | tail -30; echo "exit=${PIPESTATUS[0]}"
 done
} > "$OUT/status-tools.txt" 2>&1
fails=$(grep -c "Failure" "$OUT/status-tools.txt"); say "[C9] status tools: $fails FAILURE lines (see status-tools.txt)"; [ "$fails" -gt 0 ] && { say "[C9] STOP: a status tool reports FAILURE"; STOP=1; }
say "[C10] snapshot+checks seconds: $(( $(date +%s)-t0 )); hop timings in steps.tsv"
say "RESULT $H: $([ $STOP = 0 ] && echo PASS || echo 'STOP (undeclared difference or failed check)')"
exit $STOP
