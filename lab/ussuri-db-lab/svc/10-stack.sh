#!/usr/bin/env bash
# 2026.1 runtime stack on a COPY of the H4r database.   usage: 10-stack.sh <subcommand> [args]
#   clone <source-volume>   copy a stopped/clean database volume into ufj-svc-data (never the source)
#   infra                   network, MariaDB 11.4 (alias ufj-mariadb), RabbitMQ 4.x (fresh broker, same user/password as the cell mapping), memcached, client
#   render                  2026.1 configuration from the Ussuri-rendered files (changes listed in svc/config-changes.txt)
#   keystone|glance|placement|nova|neutron|cinder   control-plane services      computes <n..>   2026.1 fake computes adopting ufj-compute<n>
#   down                    remove every ufj-svc-* container (volumes kept)
. "$(dirname "$0")/lib.sh"; cmd=${1:?}; shift
W=(-v "$SVC_DIR/wsgi:/wsgi:ro")
case $cmd in
clone)
  src=${1:?source volume}; docker rm -f $(docker ps -aq --filter label=org.ozarland.svc=1) >/dev/null 2>&1
  docker volume rm ufj-svc-data >/dev/null 2>&1; docker volume create ufj-svc-data >/dev/null
  docker run --rm -v "$src":/from:ro -v ufj-svc-data:/to mariadb:11.4 sh -c 'cp -a /from/. /to/' && echo "cloned $src -> ufj-svc-data";;
infra)
  docker network inspect $SNET >/dev/null 2>&1 || docker network create $SNET >/dev/null
  srun db ufj-mariadb -v ufj-svc-data:/var/lib/mysql -e MYSQL_ROOT_PASSWORD="$DB_ROOT" -- mariadb:11.4 --character-set-server=utf8 --collation-server=utf8_general_ci --log-bin=mysql-bin --binlog-format=ROW --skip-name-resolve --max-connections=1000 --innodb-buffer-pool-size=512M
  docker volume rm ufj-svc-rabbit >/dev/null 2>&1
  srun rabbitmq ufj-rabbitmq -v ufj-svc-rabbit:/var/lib/rabbitmq -e RABBITMQ_DEFAULT_USER=openstack -e RABBITMQ_DEFAULT_PASS="$RABBIT" -- rabbitmq:4-management
  srun memcached ufj-memcached -- memcached:1.5 memcached -m 128
  mkdir -p "$SVC_RUN"; rm -rf "$SVC_RUN/client"; mkdir -p "$SVC_RUN/client"
  srun client ufj-svc-client -v "$SVC_RUN/client:/run/svc:ro" -v "$LAB_DIR:/lab:ro" -v "$EVIDENCE_DIR/..:/evidence" -- $SIMG sleep infinity
  for i in $(seq 1 90); do sdb -e 'select 1' >/dev/null 2>&1 && break; sleep 2; done; sdb -N -e 'select version()'
  for i in $(seq 1 60); do docker exec ufj-svc-rabbitmq rabbitmq-diagnostics -q ping >/dev/null 2>&1 && break; sleep 2; done; docker exec ufj-svc-rabbitmq rabbitmqctl version;;
render)
  rm -rf "$SVC_RUN/etc" "$SVC_RUN/keys"; mkdir -p "$SVC_RUN"; tar -C "$SVC_RUN" -xzf "$SBASE/config/rendered-etc.tar.gz"
  mkdir -p "$SVC_RUN/keys"; tar -C "$SVC_RUN/keys" -xzf "$SBASE/volumes/ufj-keystone-keys.tar.gz"
  cp "$SVC_RUN/etc/client/admin-openrc" "$SVC_RUN/client/admin-openrc"
  for pair in glance:glance-api-paste.ini cinder:api-paste.ini neutron:api-paste.ini; do s=${pair%%:*}; f=${pair#*:}
    docker run --rm $SIMG cat /opt/ff/etc/$s/$f > "$SVC_RUN/etc/$s/$f" 2>/dev/null || echo "no 2026.1 $s/$f in the image"; done
  docker run --rm $SIMG sh -c 'ls /opt/ff/etc/nova 2>/dev/null; find /opt/ff -name "api-paste.ini" | head' ;
  chmod -R a+rX "$SVC_RUN";;
esac
