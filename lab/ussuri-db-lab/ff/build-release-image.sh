#!/usr/bin/env bash
# usage: build-release-image.sh <2023.1|2024.1|2025.1|2026.1>   -> image ufj-ff-<release>:1
. "$(dirname "$0")/../scripts/lib.sh"
rel=$1; case $rel in 2023.1|2023.2) py=3.10;; 2024.1) py=3.11;; 2025.1|2026.1) py=3.12;; *) die "release?";; esac
ctx="$LAB_DIR/ff/image/$rel"; mkdir -p "$ctx/ca"; cp "$LAB_DIR/ff/image/Dockerfile" "$ctx/Dockerfile"
args=(--build-arg PYVER=$py); CA="${LAB_CA_BUNDLE:-}"; [ -z "$CA" ] && [ -f /root/.ccr/ca-bundle.crt ] && CA=/root/.ccr/ca-bundle.crt
[ -n "$CA" ] && { cp "$CA" "$ctx/ca/ca-bundle.crt"; args+=(--build-arg PIP_CERT=/tmp/ca/ca-bundle.crt); }
for v in https_proxy http_proxy no_proxy; do [ -n "${!v:-}" ] && args+=(--build-arg "$v"); done
t0=$(date +%s); docker build -t "ufj-ff-$rel:1" "${args[@]}" "$ctx" > "$ctx/build.log" 2>&1 || { tail -30 "$ctx/build.log"; die "build $rel failed"; }
rm -rf "$ctx/ca" "$ctx/Dockerfile"
EV="$EVIDENCE_DIR/../EXP-DB-01"; mkdir -p "$EV"
docker run --rm "ufj-ff-$rel:1" cat /opt/ff/pip-freeze.txt > "$EV/pip-freeze-$rel.txt"; docker run --rm "ufj-ff-$rel:1" cat /opt/ff/pip-check.txt > "$EV/pip-check-$rel.txt"
cp "$ctx/REF.txt" "$EV/uc-ref-$rel.txt"
echo "release $rel python $py image $(docker image inspect ufj-ff-$rel:1 -f '{{.Id}}') build_seconds $(( $(date +%s)-t0 ))" | tee -a "$EV/images.txt"
