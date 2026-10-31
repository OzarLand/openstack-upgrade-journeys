#!/usr/bin/env bash
# Creates an isolated copy for one run: network, volume, MariaDB 10.3 container (network alias ufj-mariadb, so that the
# cell_mappings rows stay byte-identical), rendered baseline configs and override files.
#   10-new-copy.sh <run-id> baseline   restores backups/latest (read-only use of the tarballs) and proves it equals the baseline
#   10-new-copy.sh <run-id> empty      empty Ussuri schema built with Ussuri tools (R0)
. "$(dirname "$0")/lib.sh"; ff_vars "${1:?run id}"; MODE="${2:?baseline|empty}"
docker inspect "$DB_FF" >/dev/null 2>&1 && die "run $RUN already exists: destroy it first (ff/99-destroy-run.sh $RUN)"
docker network create "$NET_FF" >/dev/null; docker volume create "$VOL_FF" >/dev/null
rm -rf "$CFG_FF"; mkdir -p "$CFG_FF/override"; tar -C "$CFG_FF" -xzf "$BASE_BACKUP/config/rendered-etc.tar.gz"   # -> $CFG_FF/etc/<svc>/
mkdir -p "$CFG_FF/etc/keystone/fernet-keys" "$CFG_FF/etc/keystone/credential-keys" "$CFG_FF/keys"; tar -C "$CFG_FF/keys" -xzf "$BASE_BACKUP/volumes/ufj-keystone-keys.tar.gz"   # read-only Fernet/credential key repository for keystone-status (RT-N-16)
chmod -R a+rX "$CFG_FF"
T0=$(date +%s)
if [ "$MODE" = baseline ]; then
  docker run --rm -v "$VOL_FF":/v -v "$BASE_BACKUP/volumes":/in:ro mariadb:10.3 sh -c 'tar -C /v -xzf /in/ufj-mariadb-data.tar.gz'
  ff_db_start mariadb:10.3
  sum=$(docker exec -e MYSQL_PWD="$DB_ROOT" "$DB_FF" mysqldump -uroot --routines --triggers --events --single-transaction --hex-blob --skip-dump-date --databases "${OS_DBS[@]}" | sha256sum | awk '{print $1}')
  [ "$sum" = "$(cat "$BASE_BACKUP/openstack-databases.sql.sha256")" ] && log "copy equals the baseline (dump sha256 $sum)" || die "copy differs from the baseline: $sum"
else
  ff_db_start mariadb:10.3
  for svc in keystone glance placement nova neutron cinder; do
    pw_var="DBPW_$(echo $svc | tr a-z A-Z)"; pw="${!pw_var}"; dbs=("$svc"); [ "$svc" = nova ] && dbs=(nova_api nova nova_cell0)
    for d in "${dbs[@]}"; do ff_sql "CREATE DATABASE IF NOT EXISTS \`$d\` CHARACTER SET utf8 COLLATE utf8_general_ci; CREATE USER IF NOT EXISTS '$svc'@'%' IDENTIFIED BY '$pw'; GRANT ALL PRIVILEGES ON \`$d\`.* TO '$svc'@'%';"; done
  done
fi
echo "$(( $(date +%s)-T0 ))" > "$CFG_FF/copy-seconds.txt"
"$FF_DIR/15-overrides.sh" "$RUN"
if [ "$MODE" = empty ]; then
  U() { ff_oneshot ussuri "$1" -- "${@:2}"; }
  C() { echo "--config-file /etc/$1/$2 --config-file /etc/ff/$3"; }
  ff_oneshot ussuri keystone -- keystone-manage --config-file /etc/keystone/keystone.conf --config-file /etc/ff/keystone.conf db_sync
  ff_oneshot ussuri glance -- glance-manage --config-file /etc/glance/glance-api.conf --config-file /etc/ff/glance.conf db_sync
  ff_oneshot ussuri placement -- placement-manage --config-file /etc/placement/placement.conf --config-file /etc/ff/placement.conf db sync
  N="--config-file /etc/nova/nova.conf --config-file /etc/ff/nova.conf"
  ff_oneshot ussuri nova -- nova-manage $N api_db sync
  ff_oneshot ussuri nova -- nova-manage $N cell_v2 map_cell0 --database_connection "mysql+pymysql://nova:${DBPW_NOVA}@ufj-mariadb/nova_cell0?charset=utf8"
  ff_oneshot ussuri nova -- nova-manage $N cell_v2 create_cell --name=cell1 --verbose
  ff_oneshot ussuri nova -- nova-manage $N db sync
  ff_oneshot ussuri neutron -- neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/ml2_conf.ini --config-file /etc/ff/neutron.conf upgrade heads
  ff_oneshot ussuri cinder -- cinder-manage --config-file /etc/cinder/cinder.conf --config-file /etc/ff/cinder.conf db sync
fi
log "run $RUN ($MODE) ready: db=$DB_FF net=$NET_FF volume=$VOL_FF"
