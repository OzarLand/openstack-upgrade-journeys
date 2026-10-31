#!/usr/bin/env bash
# Creates the representative resource set through the Ussuri APIs (see scripts/inside/populate.sh). Timed.
. "$(dirname "$0")/lib.sh"; load_secrets
T0=$(date +%s)
docker exec -i -e ADMIN -e USER_ALICE -e USER_BOB -e USER_CAROL ufj-client bash /lab/scripts/inside/populate.sh 2>&1 | tee "$RUN_DIR/populate.log"
log "populate finished in $(( $(date +%s)-T0 )) s"
