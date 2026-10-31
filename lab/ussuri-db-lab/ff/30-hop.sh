#!/usr/bin/env bash
# One hop of S2c on a run's database: the db syncs and online data migrations of release <rel>, in the order of
# assessments/04 section 3 steps 6-10. Every command is timed and logged; any non-zero exit is SC-CMD (exit 1, nothing is retried
# or edited). usage: 30-hop.sh <run> <rel> <hop-number>   (hop 5 = the idempotency re-run H4r of release 2026.1)
. "$(dirname "$0")/lib.sh"; ff_vars "${1:?run}"; REL="${2:?release}"; HOP="${3:?hop}"; set +e
H="H$HOP"; [ "$HOP" = 5 ] && H="H4r"; OUT="$RUN_EV/$H"; mkdir -p "$OUT/logs"; : > "$OUT/steps.tsv"
CF() { echo "--config-file /etc/$1/$2 --config-file /etc/ff/$3"; }   # service, base conf, override
sm() { # sm <command-name> <svc> <config files...>: PC-E1 session sql_mode of the engine this command will use (captured per command)
  local n=$1 svc=$2; shift 2
  ff_oneshot "$REL" "$svc" -- python /ffsrc/tools/session_sqlmode.py "$n" "$@" >> "$OUT/sql-mode.tsv" 2>&1 || { echo "SC-PC-E1: $n runs under a non-strict (or unreadable) session sql_mode"; tail -3 "$OUT/sql-mode.tsv"; exit 1; }
}
step() { # step <name> <svc> -- <command...>   (runs in the release image)
  local n=$1 svc=$2; shift 3; local t0 rc; t0=$(date +%s.%N)
  ff_oneshot "$REL" "$svc" -- "$@" > "$OUT/logs/$n.raw" 2>&1; rc=$?
  ff_redact < "$OUT/logs/$n.raw" | gzip -9n > "$OUT/logs/$n.log.gz"
  printf '%s\t%s\t%.1f\n' "$n" "$rc" "$(echo "$(date +%s.%N) - $t0" | bc)" | tee -a "$OUT/steps.tsv"
  if [ $rc -ne 0 ]; then echo "SC-CMD: $n exited $rc"; ff_redact < "$OUT/logs/$n.raw" | tail -25; rm -f "$OUT/logs/"*.raw; exit 1; fi
  return 0
}
odm_loop() { # odm_loop <name> <svc> <max> -- <command...>: repeat until exit 0 (record every run)
  local n=$1 svc=$2 max=$3; shift 4; local i rc t0
  for i in $(seq 1 "$max"); do
    t0=$(date +%s.%N); ff_oneshot "$REL" "$svc" -- "$@" > "$OUT/logs/$n-$i.raw" 2>&1; rc=$?
    ff_redact < "$OUT/logs/$n-$i.raw" | gzip -9n > "$OUT/logs/$n-$i.log.gz"
    printf '%s-%s\t%s\t%.1f\n' "$n" "$i" "$rc" "$(echo "$(date +%s.%N) - $t0" | bc)" | tee -a "$OUT/steps.tsv"
    ff_redact < "$OUT/logs/$n-$i.raw" | grep -E "matched query|\| +[a-z_]+ +\| +[0-9]+ +\| +[0-9]+ +\||Total (Needed|Found)" > "$OUT/logs/$n-$i.summary.txt" 2>/dev/null
    [ $rc -eq 0 ] && { cp "$OUT/logs/$n-$i.raw" "$OUT/logs/$n.final.raw"; ff_redact < "$OUT/logs/$n.final.raw" > "$OUT/odm-$n.txt"; rm -f "$OUT/logs/"*.raw; return 0; }
    [ $rc -ne 1 ] && { echo "SC-CMD: $n exited $rc"; ff_redact < "$OUT/logs/$n-$i.raw" | tail -20; exit 1; }   # 1 = more to do
  done
  echo "SC-CMD: $n did not reach exit 0 in $max runs"; exit 1
}
KS="$(CF keystone keystone.conf keystone.conf)"; GL="$(CF glance glance-api.conf glance.conf)"; PL="$(CF placement placement.conf placement.conf)"
NV="$(CF nova nova.conf nova.conf)"; NV0="$(CF nova nova.conf nova-cell0.conf)"; NT="--config-file /etc/neutron/neutron.conf --config-file /etc/neutron/ml2_conf.ini --config-file /etc/ff/neutron.conf"; CI="$(CF cinder cinder.conf cinder.conf)"
LOCAL=""; [ "$REL" != ussuri ] && LOCAL="--local_cell"
t0=$(date +%s); : > "$OUT/sql-mode.tsv"
if [ "$HOP" = 1b ]; then
  # H1b (DR-004): Cinder-only step with cinder 23.5.0 (release image ufj-ff-2023.2); then the PC-C1 gate is evaluated by 40-checks.sh
  sm cinder-db_sync cinder /etc/cinder/cinder.conf /etc/ff/cinder.conf
  step cinder-db_sync     cinder -- cinder-manage $CI db sync
  sm cinder-odm cinder /etc/cinder/cinder.conf /etc/ff/cinder.conf
  odm_loop cinder-odm     cinder 10 -- cinder-manage $CI db online_data_migrations
  echo "total_seconds $(( $(date +%s)-t0 ))" | tee -a "$OUT/steps.tsv"; exit 0
fi
sm keystone-db_sync keystone /etc/keystone/keystone.conf /etc/ff/keystone.conf
step keystone-db_sync   keystone -- keystone-manage $KS db_sync
sm nova-api_db_sync nova /etc/nova/nova.conf /etc/ff/nova.conf
step nova-api_db_sync   nova -- nova-manage $NV api_db sync
sm nova-db_sync-cell0 nova /etc/nova/nova.conf /etc/ff/nova-cell0.conf
step nova-db_sync-cell0 nova -- nova-manage $NV0 db sync $LOCAL
sm nova-db_sync-cell1 nova /etc/nova/nova.conf /etc/ff/nova.conf
step nova-db_sync-cell1 nova -- nova-manage $NV db sync $LOCAL
sm cinder-db_sync cinder /etc/cinder/cinder.conf /etc/ff/cinder.conf
step cinder-db_sync     cinder -- cinder-manage $CI db sync
sm cinder-odm cinder /etc/cinder/cinder.conf /etc/ff/cinder.conf
odm_loop cinder-odm     cinder 10 -- cinder-manage $CI db online_data_migrations
sm nova-odm-cell1 nova /etc/nova/nova.conf /etc/ff/nova.conf
odm_loop nova-odm       nova 10 -- nova-manage $NV db online_data_migrations
sm nova-odm-cell0 nova /etc/nova/nova.conf /etc/ff/nova-cell0.conf
odm_loop nova-odm-cell0 nova 10 -- nova-manage $NV0 db online_data_migrations
sm glance-db_sync glance /etc/glance/glance-api.conf /etc/ff/glance.conf
step glance-db_sync     glance -- glance-manage $GL db sync
sm placement-db_sync placement /etc/placement/placement.conf /etc/ff/placement.conf
step placement-db_sync  placement -- placement-manage $PL db sync
sm neutron-upgrade neutron /etc/neutron/neutron.conf /etc/ff/neutron.conf
step neutron-upgrade    neutron -- neutron-db-manage $NT upgrade heads
sm placement-odm placement /etc/placement/placement.conf /etc/ff/placement.conf
odm_loop placement-odm  placement 10 -- placement-manage $PL db online_data_migrations
echo "total_seconds $(( $(date +%s)-t0 ))" | tee -a "$OUT/steps.tsv"
