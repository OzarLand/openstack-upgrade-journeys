# ufj-ussuri-py38: Ussuri control plane code from PyPI, installed under the ussuri-eol upper constraints.
# Not Kolla: no systemd/Apache, no Kolla set_configs. Built in two stages so the runtime has no compiler.
ARG PYIMG=python:3.8-buster
FROM ${PYIMG} AS build
# Optional TLS-intercepting proxy CA (build.sh copies it to ca/ when LAB_CA_BUNDLE is set); empty when not needed.
COPY ca/ /tmp/ca/
ARG PIP_CERT=
# pip 24.1+ rejects some 2020-era package metadata; keep pip/setuptools old enough for Ussuri sdists.
RUN python -m venv /opt/ussuri && /opt/ussuri/bin/pip install -q 'pip==23.3.2' 'setuptools==57.5.0' 'wheel==0.37.1'
COPY upper-constraints-ussuri-eol.txt requirements-lab.txt /build/
RUN /opt/ussuri/bin/pip install --no-cache-dir -c /build/upper-constraints-ussuri-eol.txt -r /build/requirements-lab.txt \
 && /opt/ussuri/bin/pip freeze > /opt/ussuri/pip-freeze.txt \
 && /opt/ussuri/bin/pip check > /opt/ussuri/pip-check.txt 2>&1 || true

FROM python:3.8-slim-buster
COPY --from=build /opt/ussuri /opt/ussuri
ENV PATH=/opt/ussuri/bin:$PATH PYTHONUNBUFFERED=1
RUN mkdir -p /etc/ufj /var/lib/ufj /var/log/ufj
LABEL org.ozarland.ufj="ussuri fast-forward journey lab" org.ozarland.release="ussuri-eol"
