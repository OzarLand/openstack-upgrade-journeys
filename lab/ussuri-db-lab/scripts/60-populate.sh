#!/usr/bin/env bash
# Creates the representative resource set through the Ussuri APIs (see scripts/inside/populate.sh). Timed.
. "$(dirname "$0")/lib.sh"; load_secrets
T0=$(date +%s)
docker exec -i -e ADMIN -e USER_ALICE -e USER_BOB -e USER_CAROL ufj-client bash /lab/scripts/inside/populate.sh 2>&1 | tee "$RUN_DIR/populate.log"
docker exec -i -e ADMIN -e USER_ALICE -e USER_BOB -e USER_CAROL ufj-client bash /lab/scripts/inside/coverage.sh 2>&1 | tee "$RUN_DIR/coverage.log"
# archive the force-deleted instance(s) into the shadow tables (official nova-manage operation, Ussuri code)
oneshot nova -- nova-manage --config-file /etc/nova/nova.conf db archive_deleted_rows --verbose 2>&1 | tee "$RUN_DIR/archive.log" || true   # exit 1 = rows were archived
"$(dirname "$0")/61-odm.sh"
log "populate finished in $(( $(date +%s)-T0 )) s"
