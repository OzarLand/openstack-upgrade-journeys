#!/usr/bin/env bash
# Builds ufj-ussuri-py38:1 (Ussuri services from PyPI under the ussuri-eol upper constraints). Records timing and freeze.
# If a TLS-intercepting proxy is in use, point LAB_CA_BUNDLE at its CA file (it is copied into the build context only).
. "$(dirname "$0")/lib.sh"
CA="${LAB_CA_BUNDLE:-}"; [ -z "$CA" ] && [ -f /root/.ccr/ca-bundle.crt ] && CA=/root/.ccr/ca-bundle.crt
ARGS=(); [ -n "$CA" ] && { cp "$CA" "$LAB_DIR/image/ca/ca-bundle.crt"; ARGS+=(--build-arg PIP_CERT=/tmp/ca/ca-bundle.crt); }
for v in https_proxy http_proxy no_proxy; do [ -n "${!v:-}" ] && ARGS+=(--build-arg "$v"); done
T0=$(date +%s)
docker build -t "$PYIMG_TAG" "${ARGS[@]}" "$LAB_DIR/image"
log "image built in $(( $(date +%s)-T0 )) s"
mkdir -p "$EVIDENCE_DIR"; docker run --rm "$PYIMG_TAG" cat /opt/ussuri/pip-freeze.txt > "$EVIDENCE_DIR/pip-freeze-ussuri-py38.txt"
docker run --rm "$PYIMG_TAG" cat /opt/ussuri/pip-check.txt > "$EVIDENCE_DIR/pip-check.txt"
echo "image build seconds: $(( $(date +%s)-T0 ))" > "$EVIDENCE_DIR/image-build-time.txt"
rm -f "$LAB_DIR/image/ca/ca-bundle.crt"
