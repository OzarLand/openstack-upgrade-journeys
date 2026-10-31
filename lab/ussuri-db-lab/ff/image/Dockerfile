# One-shot migration image for one release: the six services from PyPI under that release's upper-constraints.
# Build context = ff/image/<release>/ (upper-constraints.txt, requirements.txt, REF.txt) + ca/ (optional proxy CA).
ARG PYVER=3.12
FROM python:${PYVER}
COPY ca/ /tmp/ca/
ARG PIP_CERT=
COPY upper-constraints.txt requirements.txt REF.txt /build/
RUN python -m venv /opt/ff && /opt/ff/bin/pip install -q -U pip wheel setuptools \
 && /opt/ff/bin/pip install --no-cache-dir -c /build/upper-constraints.txt -r /build/requirements.txt \
 && /opt/ff/bin/pip freeze > /opt/ff/pip-freeze.txt && (/opt/ff/bin/pip check > /opt/ff/pip-check.txt 2>&1 || true)
# pkg_resources (used by nova, keystonemiddleware, ...) was removed from current setuptools: pin the last series that has it
RUN /opt/ff/bin/pip install -q 'setuptools==69.5.1' && /opt/ff/bin/pip freeze > /opt/ff/pip-freeze.txt && (/opt/ff/bin/pip check > /opt/ff/pip-check.txt 2>&1 || true)
ENV PATH=/opt/ff/bin:$PATH PYTHONUNBUFFERED=1
RUN mkdir -p /etc/ff /var/lib/ff
LABEL org.ozarland.ufj="ussuri fast-forward journey one-shot image"
