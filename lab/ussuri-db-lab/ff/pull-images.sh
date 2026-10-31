#!/usr/bin/env bash
# Pulls each image once. Docker Hub's anonymous rate limit (HTTP 429) blocked pulls on 2026-10-31, so images are pulled
# through mirror.gcr.io (a public mirror of the Docker Hub library) and re-tagged; digests are recorded for comparison.
. "$(dirname "$0")/../scripts/lib.sh"
OUT="${1:-$EVIDENCE_DIR/../EXP-DB-01/image-digests.txt}"; mkdir -p "$(dirname "$OUT")"; : > "$OUT"
for img in mariadb:10.5 mariadb:10.6 mariadb:10.11 mariadb:11.4 python:3.10 python:3.11 python:3.12; do
  if ! docker image inspect "$img" >/dev/null 2>&1; then
    docker pull -q "mirror.gcr.io/library/$img" >/dev/null 2>&1 && docker tag "mirror.gcr.io/library/$img" "$img" || docker pull -q "$img" >/dev/null
  fi
  echo "$img $(docker image inspect "$img" -f '{{index .RepoDigests 0}} id={{.Id}}' 2>/dev/null || echo NOT-PULLED)" | tee -a "$OUT"
done
echo "mariadb:10.3 $(docker image inspect mariadb:10.3 -f '{{index .RepoDigests 0}} id={{.Id}}') (pulled earlier from Docker Hub)" | tee -a "$OUT"
