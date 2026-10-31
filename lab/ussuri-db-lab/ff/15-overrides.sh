#!/usr/bin/env bash
# Writes the override config files (second --config-file): ONLY connection options and an unreachable transport_url.
# Files: <svc>.conf (real databases), <svc>-ref.conf (the <db>_ref reference schemas), nova-cell0.conf, nova-cell0-ref.conf.
. "$(dirname "$0")/lib.sh"; ff_vars "${1:?run id}"; umask 077
O="$CFG_FF/override"; mkdir -p "$O"
c() { echo "mysql+pymysql://$1:$2@ufj-mariadb/$3?charset=utf8"; }
TQ='transport_url = rabbit://unreachable:unreachable@127.0.0.1:1//'
for sfx in "" _ref; do f=""; [ -n "$sfx" ] && f="-ref"
  printf '[database]\nconnection = %s\n' "$(c keystone $DBPW_KEYSTONE keystone$sfx)" > "$O/keystone$f.conf"
  printf '[database]\nconnection = %s\n' "$(c glance $DBPW_GLANCE glance$sfx)" > "$O/glance$f.conf"
  printf '[placement_database]\nconnection = %s\n' "$(c placement $DBPW_PLACEMENT placement$sfx)" > "$O/placement$f.conf"
  printf '[DEFAULT]\n%s\n[api_database]\nconnection = %s\n[database]\nconnection = %s\n' "$TQ" "$(c nova $DBPW_NOVA nova_api$sfx)" "$(c nova $DBPW_NOVA nova$sfx)" > "$O/nova$f.conf"
  printf '[DEFAULT]\n%s\n[api_database]\nconnection = %s\n[database]\nconnection = %s\n' "$TQ" "$(c nova $DBPW_NOVA nova_api$sfx)" "$(c nova $DBPW_NOVA nova_cell0$sfx)" > "$O/nova-cell0$f.conf"
  printf '[DEFAULT]\n%s\n[database]\nconnection = %s\n' "$TQ" "$(c neutron $DBPW_NEUTRON neutron$sfx)" > "$O/neutron$f.conf"
  printf '[DEFAULT]\n%s\n[database]\nconnection = %s\n' "$TQ" "$(c cinder $DBPW_CINDER cinder$sfx)" > "$O/cinder$f.conf"
done
chmod -R a+rX "$O"
