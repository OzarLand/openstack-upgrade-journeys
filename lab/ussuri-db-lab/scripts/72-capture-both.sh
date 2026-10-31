#!/usr/bin/env bash
# DR-003 end state: capture A (computes stopped, NOT forced down) -> forced-down via the API -> capture B (final baseline).
D="$(dirname "$0")"; STAGE=pre-forced-down "$D/70-capture.sh" && "$D/71-forced-down.sh" && STAGE=final "$D/70-capture.sh"
