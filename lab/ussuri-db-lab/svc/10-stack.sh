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
  src=${1:?source volume}; { docker ps -aq --filter label=org.ozarland.svc=1 | xargs -r docker rm -f; } >/dev/null 2>&1 || true
  docker volume rm ufj-svc-data ufj-svc-glance ufj-svc-compute1-state ufj-svc-compute2-state ufj-svc-compute3-state >/dev/null 2>&1 || true; docker volume create ufj-svc-data >/dev/null; docker volume create ufj-svc-glance >/dev/null
  docker run --rm -v ufj-glance-images:/from:ro -v ufj-svc-glance:/to mariadb:11.4 sh -c 'cp -a /from/. /to/'
  docker run --rm -v "$src":/from:ro -v ufj-svc-data:/to mariadb:11.4 sh -c 'cp -a /from/. /to/' && echo "cloned $src -> ufj-svc-data";;
infra)
  docker network inspect $SNET >/dev/null 2>&1 || docker network create $SNET >/dev/null
  srun db ufj-mariadb -v ufj-svc-data:/var/lib/mysql -e MYSQL_ROOT_PASSWORD="$DB_ROOT" -- mariadb:11.4 --character-set-server=utf8 --collation-server=utf8_general_ci --log-bin=mysql-bin --binlog-format=ROW --skip-name-resolve --max-connections=1000 --innodb-buffer-pool-size=512M
  docker volume rm ufj-svc-rabbit >/dev/null 2>&1 || true
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
  for pair in glance:glance-api-paste.ini cinder:api-paste.ini neutron:api-paste.ini nova:api-paste.ini; do s=${pair%%:*}; f=${pair#*:}
    docker run --rm $SIMG cat /opt/ff/etc/$s/$f > "$SVC_RUN/etc/$s/$f" 2>/dev/null || echo "no 2026.1 $s/$f in the image"; done
  # neutron: the WSGI app and the rpc server take one config file; ml2_conf.ini is appended (sections are disjoint)
  cat "$SVC_RUN/etc/neutron/ml2_conf.ini" >> "$SVC_RUN/etc/neutron/neutron.conf"
  # config changes needed by 2026.1 (each is also listed in svc/config-changes.txt)
  sed -i 's/^backend = oslo_cache.memcache_pool/backend = dogpile.cache.pymemcache/' "$SVC_RUN/etc/keystone/keystone.conf"
  sed -i 's/^enabled_filters = AvailabilityZoneFilter,/enabled_filters = /' "$SVC_RUN/etc/nova/nova.conf"
  NPW=$(awk '/^\[keystone_authtoken\]/{a=1;next} /^\[/{a=0} a&&/^password *=/{sub(/^password *= */,"");print;exit}' "$SVC_RUN/etc/nova/nova.conf")
  printf '\n[service_user]\nsend_service_user_token = true\nauth_url = http://ufj-keystone:5000\nauth_type = password\nproject_domain_name = Default\nuser_domain_name = Default\nproject_name = service\nusername = nova\npassword = %s\nregion_name = RegionOne\n' "$NPW" >> "$SVC_RUN/etc/nova/nova.conf"
  sed -i '0,/^use_stderr = true/s//use_stderr = true\ndebug = true/' "$SVC_RUN/etc/nova/nova.conf"
  printf '\n[upgrade_levels]\ncompute = auto\n' >> "$SVC_RUN/etc/nova/nova.conf"
  for f in nova/nova.conf neutron/neutron.conf cinder/cinder.conf glance/glance-api.conf; do
    printf '\n[oslo_messaging_rabbit]\nrabbit_quorum_queue = true\nrabbit_transient_quorum_queue = true\nuse_queue_manager = true\namqp_durable_queues = true\n' >> "$SVC_RUN/etc/$f"; done
  printf '[DEFAULT]\ncompute_driver = ufj_fake2026.UfjFake2026Driver\n[database]\nconnection =\n[api_database]\nconnection =\n' > "$SVC_RUN/etc/nova/nova-compute.conf"
  chmod -R a+rX "$SVC_RUN";;
keystone)
  srun keystone ufj-keystone "${W[@]}" -v "$SVC_RUN/etc/keystone:/etc/keystone:ro" -v "$SVC_RUN/keys:/var/lib/ufj/keys:ro" -- $SIMG gunicorn --chdir /wsgi --bind 0.0.0.0:5000 --workers 2 --threads 4 --worker-class gthread --timeout 120 ks_app:application;;
glance)
  srun glance ufj-glance -v "$SVC_RUN/etc/glance:/etc/glance:ro" -v ufj-svc-glance:/var/lib/glance -- $SIMG glance-api --config-file /etc/glance/glance-api.conf;;
placement)
  srun placement ufj-placement "${W[@]}" -v "$SVC_RUN/etc/placement:/etc/placement:ro" -- $SIMG gunicorn --chdir /wsgi --bind 0.0.0.0:8778 --workers 2 --threads 4 --worker-class gthread --timeout 120 pl_app:application;;
nova)
  N=(-v "$SVC_RUN/etc/nova:/etc/nova:ro")
  srun nova-api ufj-nova-api "${W[@]}" "${N[@]}" -- $SIMG gunicorn --chdir /wsgi --bind 0.0.0.0:8774 --workers 2 --threads 4 --worker-class gthread --timeout 180 nv_app:application
  srun nova-conductor ufj-nova-conductor "${N[@]}" -- $SIMG nova-conductor --config-file /etc/nova/nova.conf
  srun nova-scheduler ufj-nova-scheduler "${N[@]}" -- $SIMG nova-scheduler --config-file /etc/nova/nova.conf;;
neutron)
  N=(-v "$SVC_RUN/etc/neutron:/etc/neutron:ro")
  srun neutron-rpc ufj-neutron-rpc "${N[@]}" -- $SIMG neutron-rpc-server --config-file /etc/neutron/neutron.conf
  srun neutron ufj-neutron "${W[@]}" "${N[@]}" -- $SIMG gunicorn --chdir /wsgi --bind 0.0.0.0:9696 --workers 2 --threads 4 --worker-class gthread --timeout 180 nt_app:application;;
cinder)
  C=(-v "$SVC_RUN/etc/cinder:/etc/cinder:ro")
  srun cinder-api ufj-cinder-api "${W[@]}" "${C[@]}" -- $SIMG gunicorn --chdir /wsgi --bind 0.0.0.0:8776 --workers 2 --threads 4 --worker-class gthread --timeout 180 ci_app:application
  srun cinder-scheduler ufj-cinder-scheduler "${C[@]}" -- $SIMG cinder-scheduler --config-file /etc/cinder/cinder.conf
  srun cinder-volume ufj-cinder-volume "${C[@]}" -- $SIMG cinder-volume --config-file /etc/cinder/cinder.conf;;
computes) # computes <n..> : stock nova.virt.fake.FakeDriver, container hostname ufj-compute<n>
  for n in "$@"; do HOSTN=ufj-compute$n srun compute$n ufj-compute$n -v "$SVC_RUN/etc/nova:/etc/nova:ro" -v ufj-svc-compute$n-state:/var/lib/nova -v "$SVC_DIR/ufj_fake2026.py:/opt/ff/lib/python3.12/site-packages/nova/virt/ufj_fake2026.py:ro" -- $SIMG nova-compute --config-file /etc/nova/nova.conf --config-file /etc/nova/nova-compute.conf; done;;
up) # up : render (before any container is created: render replaces the bind-mounted directories) and start every control-plane service
  "$0" render; for s in keystone glance placement nova neutron cinder; do "$0" $s; done
  swait http://ufj-keystone:5000/v3 120 && swait http://ufj-glance:9292/ 120 && swait http://ufj-placement:8778/ 120 && swait http://ufj-nova-api:8774/ 180 && swait http://ufj-neutron:9696/ 180 && swait http://ufj-cinder-api:8776/ 180 && echo "control plane answering";;
down) { docker ps -aq --filter label=org.ozarland.svc=1 | xargs -r docker rm -f; } >/dev/null 2>&1 || true; echo "removed ufj-svc-* containers";;
esac
