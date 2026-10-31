#!/usr/bin/env bash
# Records the versions of the host, Docker, the infra containers and every installed service into the evidence dir.
. "$(dirname "$0")/lib.sh"; load_secrets
O="$EVIDENCE_DIR/versions.txt"; mkdir -p "$EVIDENCE_DIR"
{
echo "# versions recorded $(date -u +%FT%TZ)"
echo "host os:      $(. /etc/os-release; echo "$PRETTY_NAME")"
echo "host kernel:  $(uname -r)"
echo "host python:  $(python3 --version 2>&1)"
echo "docker:       $(docker version --format 'client {{.Client.Version}} / server {{.Server.Version}}')"
echo "cpu/mem:      $(nproc) vCPU, $(free -g | awk '/Mem:/ {print $2}') GB RAM"
echo "kvm:          $([ -e /dev/kvm ] && echo present || echo absent); /lib/modules: $([ -d /lib/modules ] && echo present || echo absent)"
echo "mariadb:      $(mysql_root -N -e 'select version()') (image $MARIADB_IMAGE, $(docker image inspect "$MARIADB_IMAGE" -f '{{.Id}}' | cut -c1-19))"
echo "rabbitmq:     $(docker exec ufj-rabbitmq rabbitmqctl --version) (Erlang/OTP $(docker exec ufj-rabbitmq erl -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().'))"
echo "memcached:    $(docker exec ufj-memcached memcached -h | head -1)"
echo "app python:   $(docker run --rm "$PYIMG_TAG" python --version 2>&1)"
echo "app image:    $PYIMG_TAG $(docker image inspect "$PYIMG_TAG" -f '{{.Id}}' | cut -c1-19)"
echo "--- service packages (pip, ussuri-eol constraints)"
docker run --rm "$PYIMG_TAG" sh -c 'grep -iE "^(keystone|glance|openstack-placement|nova|neutron|cinder|python-openstackclient|osc-placement|neutron-lib|oslo.db|oslo.messaging|oslo.config|SQLAlchemy|alembic|sqlalchemy-migrate|eventlet|PyMySQL|keystonemiddleware|os-brick|os-vif|taskflow|gunicorn)==" /opt/ussuri/pip-freeze.txt'
echo "--- running containers"
docker ps --filter name='^ufj-' --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | sort
} > "$O"
cat "$O"
