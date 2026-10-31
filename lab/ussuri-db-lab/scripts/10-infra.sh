#!/usr/bin/env bash
# Starts MariaDB 10.3, RabbitMQ 3.8 and memcached on the ufj-net network; creates the service databases/users and
# the RabbitMQ user. Idempotent: existing containers/volumes/databases are kept.
. "$(dirname "$0")/lib.sh"; need docker; load_secrets
docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
for v in "${VOLUMES[@]}"; do docker volume inspect "$v" >/dev/null 2>&1 || docker volume create "$v" >/dev/null; done

running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]; }
exists()  { docker inspect "$1" >/dev/null 2>&1; }
start_or_create() { # name; remaining args = docker create args
  local n=$1; shift
  if running "$n"; then return 0; elif exists "$n"; then docker start "$n" >/dev/null; else docker run -d --name "$n" "$@" >/dev/null; fi
}

# Kolla-Ansible Ussuri's galera.cnf: utf8, binlog ROW, innodb. (Galera/wsrep and clustering are NOT reproduced: one node.)
start_or_create ufj-mariadb --network "$NET" --hostname ufj-mariadb \
  -v ufj-mariadb-data:/var/lib/mysql -e MYSQL_ROOT_PASSWORD="$DB_ROOT" \
  --label org.ozarland.ufj=1 --restart unless-stopped "$MARIADB_IMAGE" \
  --character-set-server=utf8 --collation-server=utf8_general_ci \
  --log-bin=mysql-bin --binlog-format=ROW --expire-logs-days=14 --default-storage-engine=innodb \
  --innodb-autoinc-lock-mode=2 --max-connections=1000 --skip-name-resolve --innodb-buffer-pool-size=512M
start_or_create ufj-rabbitmq --network "$NET" --hostname ufj-rabbitmq \
  -v ufj-rabbitmq-data:/var/lib/rabbitmq -e RABBITMQ_DEFAULT_USER=openstack -e RABBITMQ_DEFAULT_PASS="$RABBIT" \
  --label org.ozarland.ufj=1 --restart unless-stopped "$RABBIT_IMAGE"
start_or_create ufj-memcached --network "$NET" --hostname ufj-memcached --label org.ozarland.ufj=1 \
  --restart unless-stopped "$MEMCACHED_IMAGE" memcached -m 128

log "waiting for MariaDB"
for i in $(seq 1 90); do mysql_root -e 'select 1' >/dev/null 2>&1 && break; sleep 2; done
mysql_root -e 'select version()' >/dev/null || die "MariaDB did not come up"
log "MariaDB $(mysql_root -N -e 'select version()')"
if [ "${UFJ_SKIP_DB_BOOTSTRAP:-0}" != 1 ]; then
for svc in keystone glance placement nova neutron cinder; do
  pw_var="DBPW_$(echo $svc | tr a-z A-Z)"; pw="${!pw_var}"
  dbs=("$svc"); [ "$svc" = nova ] && dbs=(nova_api nova nova_cell0)
  for d in "${dbs[@]}"; do
    mysql_root -e "CREATE DATABASE IF NOT EXISTS \`$d\` CHARACTER SET utf8 COLLATE utf8_general_ci;
      CREATE USER IF NOT EXISTS '$svc'@'%' IDENTIFIED BY '$pw'; ALTER USER '$svc'@'%' IDENTIFIED BY '$pw';
      GRANT ALL PRIVILEGES ON \`$d\`.* TO '$svc'@'%';"
  done
done
fi  # UFJ_SKIP_DB_BOOTSTRAP: a restore must not write to the restored database
log "waiting for RabbitMQ"
for i in $(seq 1 60); do docker exec ufj-rabbitmq rabbitmq-diagnostics -q ping >/dev/null 2>&1 && break; sleep 3; done
docker exec ufj-rabbitmq rabbitmqctl --version | sed 's/^/RabbitMQ /'
log "infra up"
