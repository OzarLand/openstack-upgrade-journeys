#!/usr/bin/env bash
# One hop of S2c on a run's database: the db syncs and online data migrations of release <rel>, in the order of
# assessments/04 section 3 steps 6-10. Every command is timed and logged; any non-zero exit is SC-CMD (exit 1, nothing is retried
# or edited). usage: 30-hop.sh <run> <rel> <hop-number>   (hop 5 = the idempotency re-run H4r of release 2026.1)
. "$(dirname "$0")/lib.sh"; ff_vars "${1:?run}"; REL="${2:?release}"; HOP="${3:?hop}"; set +e
H="H$HOP"; [ "$HOP" = 5 ] && H="H4r"; OUT="$RUN_EV/$H"; mkdir -p "$OUT/logs"; : > "$OUT/steps.tsv"
CF() { echo "--config-file /etc/$1/$2 --config-file /etc/ff/$3"; }   # service, base conf, override
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
t0=$(date +%s)
step keystone-db_sync   keystone -- keystone-manage $KS db_sync
step nova-api_db_sync   nova -- nova-manage $NV api_db sync
step nova-db_sync-cell0 nova -- nova-manage $NV0 db sync $LOCAL
step nova-db_sync-cell1 nova -- nova-manage $NV db sync $LOCAL
step cinder-db_sync     cinder -- cinder-manage $CI db sync
odm_loop cinder-odm     cinder 10 -- cinder-manage $CI db online_data_migrations
odm_loop nova-odm       nova 10 -- nova-manage $NV db online_data_migrations
step glance-db_sync     glance -- glance-manage $GL db sync
step placement-db_sync  placement -- placement-manage $PL db sync
step neutron-upgrade    neutron -- neutron-db-manage $NT upgrade heads
odm_loop placement-odm  placement 10 -- placement-manage $PL db online_data_migrations
echo "total_seconds $(( $(date +%s)-t0 ))" | tee -a "$OUT/steps.tsv"
