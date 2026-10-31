#!/usr/bin/env bash
# Builds ufj-svc-2026.1:1 (2026.1 services + gunicorn + python-openstackclient). usage: svc/build-image.sh
. "$(dirname "$0")/../scripts/lib.sh"; ctx="$LAB_DIR/svc/image"; mkdir -p "$ctx/ca"
args=(); CA="${LAB_CA_BUNDLE:-}"; [ -z "$CA" ] && [ -f /root/.ccr/ca-bundle.crt ] && CA=/root/.ccr/ca-bundle.crt
[ -n "$CA" ] && { cp "$CA" "$ctx/ca/ca-bundle.crt"; args+=(--build-arg PIP_CERT=/tmp/ca/ca-bundle.crt); }
for v in https_proxy http_proxy no_proxy; do [ -n "${!v:-}" ] && args+=(--build-arg "$v"); done
docker build -t ufj-svc-2026.1:1 "${args[@]}" "$ctx" > "$ctx/build.log" 2>&1 || { tail -20 "$ctx/build.log"; die "build failed"; }
rm -rf "$ctx/ca"; mkdir -p "$EVIDENCE_DIR/../EXP-SVC-01"; docker run --rm ufj-svc-2026.1:1 cat /opt/ff/pip-freeze-svc.txt > "$EVIDENCE_DIR/../EXP-SVC-01/pip-freeze-svc-2026.1.txt"
echo "built $(docker image inspect ufj-svc-2026.1:1 -f '{{.Id}}')"
