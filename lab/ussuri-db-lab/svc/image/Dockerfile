# 2026.1 runtime image for EXP-SVC-*: the migration image plus a WSGI server and the 2026.1 clients, under the same upper-constraints.
FROM ufj-ff-2026.1:1
COPY ca/ /tmp/ca/
ARG PIP_CERT=
RUN /opt/ff/bin/pip install --no-cache-dir -c /build/upper-constraints.txt gunicorn python-openstackclient osc-placement \
 && /opt/ff/bin/pip freeze > /opt/ff/pip-freeze-svc.txt
