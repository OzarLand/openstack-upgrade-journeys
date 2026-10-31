#!/usr/bin/env bash
# Ussuri online data migrations and checks; the output is the T0 "remaining" summary. Exit codes are recorded, not fatal.
. "$(dirname "$0")/lib.sh"; load_secrets; set +e +o pipefail
# Ussuri online data migrations and checks, saved as the T0 "0 remaining" summaries (official Ussuri commands)
{
  echo "# Ussuri ODM summaries at T0 $(date -u +%FT%TZ)"
  for i in 1 2 3 4 5; do echo "== nova-manage db online_data_migrations (run $i)"; oneshot nova -- nova-manage --config-file /etc/nova/nova.conf db online_data_migrations 2>&1 | tail -25; rc=${PIPESTATUS[0]}; echo "exit=$rc"; [ "$rc" = 0 ] && break; done
  echo "== placement-manage db online_data_migrations"; oneshot placement -- placement-manage --config-file /etc/placement/placement.conf db online_data_migrations 2>&1 | tail -15; echo "exit=${PIPESTATUS[0]}"
  echo "== cinder-manage db online_data_migrations"; oneshot cinder -- cinder-manage --config-file /etc/cinder/cinder.conf db online_data_migrations 2>&1 | tail -15; echo "exit=${PIPESTATUS[0]}"
  echo "== glance-manage db check"; oneshot glance -v ufj-glance-images:/var/lib/glance -- glance-manage --config-file /etc/glance/glance-api.conf db check 2>&1 | tail -5; echo "exit=${PIPESTATUS[0]}"
  echo "== nova-status upgrade check"; oneshot nova -- nova-status --config-file /etc/nova/nova.conf upgrade check 2>&1 | tail -30
} > "$RUN_DIR/odm-T0.txt" 2>&1
mkdir -p "$EVIDENCE_DIR"; cp "$RUN_DIR/odm-T0.txt" "$EVIDENCE_DIR/odm-T0.txt"
