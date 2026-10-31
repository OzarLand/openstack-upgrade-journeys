#!/usr/bin/env bash
# EXP-KD-01: Kolla-Ansible deploy-time behaviour on the migrated (H4r) databases. Tests C-1..C-4 of assessments/03-kolla-deploy-on-migrated-databases.md.
#   usage: 30-exp-kd-01.sh <label> [c1|c2|c34|all]     evidence: evidence/EXP-KD-01/<label>/
# Each part starts from its own fresh clone of the H4r database (volume $H4R_VOL, never modified). Commands are the ones Kolla runs
# (kolla-ansible 22.2.0 / kolla 22.x bootstrap scripts as cited in the assessment), run from the 2026.1 image against the migrated databases.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
set +eu
LABEL=${1:?label}; PART=${2:-all}
OUT="$EVIDENCE_DIR/../EXP-KD-01/$LABEL"; mkdir -p "$OUT"
H4R_VOL=${H4R_VOL:-ufj-ff-derive-h4r-data}
STK="$SVC_DIR/10-stack.sh"
KD_SNAP="$SVC_RUN/kd"
DBS=keystone,glance,placement,nova_api,nova,nova_cell0,neutron,cinder
KOLLA_SRC=${KOLLA_SRC:-/tmp/claude-0/kolla-ansible-src/x}      # kolla_ansible-22.2.0 wheel, unpacked (sha256 010e077c95d172e1... of the wheel)
note() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$OUT/run.log"; }
redact() { PWENV="$SBASE/config/passwords.env" python3 -c "
import sys,os
vals=[l.strip().split('=',1)[1].strip('\"') for l in open(os.environ['PWENV']) if '=' in l and not l.startswith('#')]
t=sys.stdin.read()
for v in sorted([v for v in vals if len(v)>=8],key=len,reverse=True): t=t.replace(v,'<redacted>')
sys.stdout.write(t)"; }
oneshot() { # oneshot <svc> <cmd...> : run in the 2026.1 image with the rendered config of <svc>; stdout+stderr redacted; returns the command's exit code in \$RC
  local s=$1; shift; local extra=(); [ $s = keystone ] && extra=(-v "$SVC_RUN/keys:/var/lib/ufj/keys:ro")
  docker run --rm --network $SNET "${extra[@]}" -v "$SVC_RUN/etc/$s:/etc/$s:ro" $SIMG "$@" 2>&1 | redact; RC=${PIPESTATUS[0]}; }
step() { # step <name> <svc> <cmd...> : logged to $OUT/<part>/steps.tsv and logs
  local n=$1 s=$2; shift 2; mkdir -p "$OUT/$PTAG/logs"
  oneshot $s "$@" > "$OUT/$PTAG/logs/$n.log"; printf '%s\t%s\n' "$n" "$RC" | tee -a "$OUT/$PTAG/steps.tsv"; }
snap() { # snap <name> : fingerprints of every OpenStack database (read-only SELECTs)
  rm -rf "$KD_SNAP/$1"; mkdir -p "$KD_SNAP"
  docker run --rm --network $SNET -v "$KD_SNAP":/snap -v "$LAB_DIR/ff":/ffsrc:ro $SIMG python /ffsrc/tools/snap.py --host ufj-mariadb --password "$DB_ROOT" --dbs $DBS --out /snap/$1 > /dev/null 2>&1; }
cmpsnap() { # cmpsnap <a> <b> <outfile>
  docker run --rm -v "$KD_SNAP":/snap -v "$LAB_DIR/ff":/ffsrc:ro $SIMG python /ffsrc/tools/compare.py same --a /snap/$1 --b /snap/$2 > "$3" 2>&1; tail -1 "$3" | tee -a "$OUT/run.log"; }
reset() { note "reset: fresh clone of $H4R_VOL"; docker stop ufj-ff-derive-h4r-db >/dev/null 2>&1; "$STK" down >/dev/null; "$STK" clone "$H4R_VOL" >> "$OUT/run.log"; "$STK" infra >> "$OUT/run.log" 2>&1; "$STK" render; }
cell0conf() { # override file for cell0: same connection with the database name nova_cell0
  python3 - "$SVC_RUN/etc/nova/nova.conf" "$SVC_RUN/etc/nova/cell0.conf" <<'PY'
import sys,re,configparser
cp=configparser.ConfigParser(interpolation=None,strict=False); cp.read(sys.argv[1])
c=cp.get('database','connection'); c=re.sub(r'/nova(\?|$)',r'/nova_cell0\1',c)
open(sys.argv[2],'w').write('[database]\nconnection = %s\n'%c)
PY
  chmod a+r "$SVC_RUN/etc/nova/cell0.conf"; }

run_c1() {
  PTAG=c1; mkdir -p "$OUT/c1"; : > "$OUT/c1/steps.tsv"; reset; cell0conf
  note "C-1 snapshot 0 (H4r as cloned)"; snap s0
  for pass in 1 2; do
    note "C-1 pass $pass: Kolla deploy-time commands"; PTAG=c1; : > "$OUT/c1/steps-pass$pass.tsv"
    step p$pass-keystone-db_sync keystone keystone-manage db_sync
    step p$pass-glance-db_sync glance glance-manage --config-file /etc/glance/glance-api.conf db sync
    step p$pass-glance-db_load_metadefs glance glance-manage --config-file /etc/glance/glance-api.conf db_load_metadefs
    step p$pass-placement-db_sync placement placement-manage db sync
    step p$pass-placement-online_data_migrations placement placement-manage db online_data_migrations
    step p$pass-nova-api_db_sync nova nova-manage api_db sync
    step p$pass-nova-db_sync-cell0 nova nova-manage --config-file /etc/nova/nova.conf --config-file /etc/nova/cell0.conf db sync --local_cell
    step p$pass-nova-db_sync-cell1 nova nova-manage db sync --local_cell
    step p$pass-neutron-upgrade neutron neutron-db-manage --config-file /etc/neutron/neutron.conf --subproject neutron upgrade heads
    step p$pass-cinder-db_sync cinder cinder-manage db sync
    step p$pass-nova-map_cell0 nova nova-manage cell_v2 map_cell0
    snap s$pass
    cmpsnap s$((pass-1)) s$pass "$OUT/c1/diff-s$((pass-1))-s$pass.txt"
  done
  cat "$OUT/c1/steps.tsv" | awk -F'\t' '$2!=0' | sed 's/^/NONZERO: /' | tee -a "$OUT/run.log"
}

run_c2() {
  PTAG=c2; mkdir -p "$OUT/c2"; : > "$OUT/c2/steps.tsv"; reset; "$STK" keystone; swait http://ufj-keystone:5000/v3 90
  KS="--bootstrap-username admin --bootstrap-project-name admin --bootstrap-role-name admin --bootstrap-service-name keystone --bootstrap-region-id RegionOne"
  sqls() { # sqls <tag> : non-secret state
    { echo "-- endpoints of service keystone"; sdb -e "select e.id,e.interface,e.url,e.region_id,e.enabled from keystone.endpoint e join keystone.service s on s.id=e.service_id where s.type='identity' order by e.interface"
      echo "-- implied_role"; sdb -e "select p.name prior_role, i.name implied_role from keystone.implied_role r join keystone.role p on p.id=r.prior_role_id join keystone.role i on i.id=r.implied_role_id order by 1,2"
      echo "-- roles"; sdb -e "select name,domain_id from keystone.role order by name"
      echo "-- admin user: enabled and password rows (ids and dates only)"; sdb -e "select u.id,u.enabled,(select count(*) from keystone.password p where p.local_user_id=l.id) password_rows,(select max(created_at) from keystone.password p where p.local_user_id=l.id) last_pw from keystone.user u join keystone.local_user l on l.user_id=u.id where l.name='admin'"
      echo "-- regions"; sdb -e "select id from keystone.region"; } > "$OUT/c2/state-$1.txt" 2>&1; }
  auth() { # auth <label> <password> : token issue as admin with the given password
    docker exec -e P="$2" ufj-svc-client bash -c 'set -a; . /run/svc/admin-openrc; OS_PASSWORD=$P; set +a; openstack token issue -f value -c id >/dev/null 2>/tmp/err && echo "AUTH OK" || { echo "AUTH FAILED: $(head -c 200 /tmp/err)"; }' 2>&1 | redact | sed "s/^/auth($1): /" | tee -a "$OUT/c2/auth.txt" | tee -a "$OUT/run.log"; }
  sqls 0-before; auth "before, lab password" "$ADMIN"
  URLS=$(sdb -N -e "select interface,url from keystone.endpoint e join keystone.service s on s.id=e.service_id where s.type='identity'")
  PUB=$(echo "$URLS" | awk '$1=="public"{print $2}'); INT=$(echo "$URLS" | awk '$1=="internal"{print $2}'); ADM=$(echo "$URLS" | awk '$1=="admin"{print $2}')
  echo "stored keystone endpoint URLs: public=$PUB internal=$INT admin=$ADM" | tee "$OUT/c2/urls.txt"
  snap k0
  note "C-2 step 1: bootstrap with the lab password and the stored URLs"
  step bootstrap-1-same keystone keystone-manage bootstrap $KS --bootstrap-password "$ADMIN" --bootstrap-public-url "$PUB" --bootstrap-internal-url "$INT" --bootstrap-admin-url "$ADM"
  sqls 1-same; auth "after bootstrap 1, lab password" "$ADMIN"; snap k1; cmpsnap k0 k1 "$OUT/c2/diff-1-same.txt"
  note "C-2 step 2: bootstrap with a DIFFERENT password"
  NEWPW="kd-test-$(date +%s)-Zq9"
  step bootstrap-2-newpw keystone keystone-manage bootstrap $KS --bootstrap-password "$NEWPW" --bootstrap-public-url "$PUB" --bootstrap-internal-url "$INT" --bootstrap-admin-url "$ADM"
  sqls 2-newpw; auth "after bootstrap 2, lab password" "$ADMIN"; auth "after bootstrap 2, new password" "$NEWPW"; snap k2; cmpsnap k1 k2 "$OUT/c2/diff-2-newpw.txt"
  note "C-2 step 3: bootstrap with changed endpoint URLs"
  step bootstrap-3-urls keystone keystone-manage bootstrap $KS --bootstrap-password "$NEWPW" --bootstrap-public-url "http://kd-changed:5000/v3/" --bootstrap-internal-url "http://kd-changed:5000/v3/" --bootstrap-admin-url "http://kd-changed:5000/v3/"
  sqls 3-urls; snap k3; cmpsnap k2 k3 "$OUT/c2/diff-3-urls.txt"
  for f in 1-same 2-newpw 3-urls; do echo "=== state after bootstrap $f vs before"; diff "$OUT/c2/state-0-before.txt" "$OUT/c2/state-$f.txt"; done > "$OUT/c2/state-diffs.txt" 2>&1
  grep -c . "$OUT/c2/state-diffs.txt" | sed 's/^/state diff lines: /' | tee -a "$OUT/run.log"
}

run_c34() {
  PTAG=c34; mkdir -p "$OUT/c34"; : > "$OUT/c34/steps.tsv"; reset
  cellrows() { sdb -e "select id,uuid,name,disabled,(transport_url<>'none:///') has_transport,(database_connection is not null) has_db from nova_api.cell_mappings order by id" > "$OUT/c34/cell-mappings-$1.tsv" 2>&1; cat "$OUT/c34/cell-mappings-$1.tsv" | tee -a "$OUT/run.log"; }
  cellrows 0-before
  note "C-3: list_cells --verbose, then kolla_ansible.nova_filters.extract_cell('') and extract_cell('cell1') (kolla-ansible 22.2.0 code)"
  docker run --rm --network $SNET -v "$SVC_RUN/etc/nova:/etc/nova:ro" -v "$KOLLA_SRC":/kolla:ro -v "$SVC_DIR/kd_c3.py":/kd_c3.py:ro $SIMG python /kd_c3.py 2>&1 | redact | tee "$OUT/c34/c3-extract-cell.txt" | tee -a "$OUT/run.log"
  note "C-4 case (i): create_cell with the conductor's own transport_url and [database] (Kolla, nova_cell_name='' -> no --name)"
  step create_cell-i nova nova-manage cell_v2 create_cell; cat "$OUT/c34/logs/create_cell-i.log" | tee -a "$OUT/run.log"; cellrows 1-after-i
  note "C-4 case (ii): same DB URL, different transport_url"
  step create_cell-ii nova nova-manage cell_v2 create_cell --transport-url "rabbit://openstack:x@kd-other-host:5672/"; cat "$OUT/c34/logs/create_cell-ii.log" | tee -a "$OUT/run.log"; cellrows 2-after-ii
  note "C-4 case (iii): different transport_url AND a different DB URL string for the same database (query suffix) -> second mapping expected"
  DBU=$(python3 - <<PY
import configparser
cp=configparser.ConfigParser(interpolation=None,strict=False); cp.read("$SVC_RUN/etc/nova/nova.conf")
print(cp.get('database','connection')+'&kd=1' if '?' in cp.get('database','connection') else cp.get('database','connection')+'?kd=1')
PY
)
  step create_cell-iii nova nova-manage cell_v2 create_cell --transport-url "rabbit://openstack:x@kd-other-host:5672/" --database_connection "$DBU"; cat "$OUT/c34/logs/create_cell-iii.log" | tee -a "$OUT/run.log"; cellrows 3-after-iii
  step list_cells-final nova nova-manage cell_v2 list_cells --verbose; cat "$OUT/c34/logs/list_cells-final.log" | tee -a "$OUT/run.log"
  docker run --rm --network $SNET -v "$SVC_RUN/etc/nova:/etc/nova:ro" -v "$KOLLA_SRC":/kolla:ro -v "$SVC_DIR/kd_c3.py":/kd_c3.py:ro $SIMG python /kd_c3.py 2>&1 | redact > "$OUT/c34/c3-extract-cell-after-duplicate.txt"
  note "extract_cell after the duplicate mapping exists:"; cat "$OUT/c34/c3-extract-cell-after-duplicate.txt" | tee -a "$OUT/run.log"
}
{ echo "harness commit: $(git -C "$LAB_DIR/../.." rev-parse HEAD)"; echo "lab/ files changed since that commit:"; git -C "$LAB_DIR/../.." status --porcelain -- lab | grep -v '^??'; echo "script sha256: $(sha256sum "$0" | cut -d' ' -f1)"; echo "kolla-ansible wheel sha256: $(sha256sum /tmp/claude-0/kolla-ansible-src/*.whl 2>/dev/null | cut -d' ' -f1)"; echo "image: $(docker image inspect $SIMG --format '{{.Id}}')"; echo "label: $LABEL part: $PART"; } > "$OUT/harness.txt"
case $LABEL in strict*) [ -z "$(git -C "$LAB_DIR/../.." status --porcelain -- lab | grep -v '^??')" ] || { echo "STRICT run refused: lab/ has uncommitted changes"; exit 3; };; esac
case $PART in c1) run_c1;; c2) run_c2;; c34) run_c34;; all) run_c1; run_c2; run_c34;; esac
note "done: $LABEL $PART"
