#!/usr/bin/env bash
# Track K probe: pip-install kolla 10.4.0 (Ussuri series) in python:3.8 and try `kolla-build base openstack-base`
# for ubuntu:18.04 against the host Docker daemon. Time-boxed by the caller (timeout). Output: kolla-probe/probe.log
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cp "$HERE/../image/upper-constraints-ussuri-eol.txt" "$HERE/upper-constraints.txt"
CA=/root/.ccr/ca-bundle.crt; [ -f "$CA" ] && cp "$CA" "$HERE/ca-bundle.crt"
docker run --rm --network host --name ufj-kolla-build-probe -v /var/run/docker.sock:/var/run/docker.sock -v "$HERE":/probe \
  -e https_proxy -e http_proxy -e no_proxy -e GIT_SSL_CAINFO=/probe/ca-bundle.crt -e PIP_CERT=/probe/ca-bundle.crt -e REQUESTS_CA_BUNDLE=/probe/ca-bundle.crt \
  python:3.8-buster bash -c '
set -x
pip install -q "pip==23.3.2" "setuptools==57.5.0" && pip install -q -c /probe/upper-constraints.txt kolla==10.4.0 docker 2>&1 | tail -3
kolla-build --version
cp /probe/kolla-build.conf /tmp/kb.conf
# oslo.config DictOpt syntax is key:value (a colon inside the value is kept)
[ -n "$https_proxy" ] && printf "build_args = https_proxy:%s,http_proxy:%s\n" "$https_proxy" "${http_proxy:-$https_proxy}" >> /tmp/kb.conf
kolla-build --config-file /tmp/kb.conf --threads 1 "^base$" "^openstack-base$"
echo "kolla-build exit: $?"
' > "$HERE/probe.log" 2>&1
echo "probe exit $?" >> "$HERE/probe.log"
