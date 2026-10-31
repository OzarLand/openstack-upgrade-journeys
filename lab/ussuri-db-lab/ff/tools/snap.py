#!/usr/bin/env python3
"""Snapshot of OpenStack databases: exact row counts, schema (information_schema, sorted), per-row per-column fingerprints.
usage: snap.py --host H --password PW --dbs a,b,c --out DIR [--no-fp]
Output: DIR/counts.tsv  DIR/schema/<db>/{tables,columns,indexes,keys,checks,triggers,other}.tsv  DIR/fp/<db>.<table>.json.gz
Fingerprint = first 8 hex digits of MD5 of each column value (NULL distinct from ''), keyed by the primary key (all columns
when the table has none). Read-only (SELECT only)."""
import argparse, gzip, json, os
import pymysql

ap = argparse.ArgumentParser()
ap.add_argument('--host'); ap.add_argument('--password'); ap.add_argument('--dbs'); ap.add_argument('--out')
ap.add_argument('--no-fp', action='store_true')
a = ap.parse_args()
c = pymysql.connect(host=a.host, user='root', password=a.password, charset='utf8mb4', autocommit=True)
cur = c.cursor()
def q(sql, args=None):
    cur.execute(sql, args); return cur.fetchall()
os.makedirs(a.out + '/fp', exist_ok=True)
counts = []
for db in a.dbs.split(','):
    sd = '%s/schema/%s' % (a.out, db); os.makedirs(sd, exist_ok=True)
    def w(name, rows):
        with open('%s/%s.tsv' % (sd, name), 'w') as f:
            for r in rows: f.write('\t'.join('' if x is None else str(x) for x in r) + '\n')
    w('tables', q("SELECT TABLE_NAME,ENGINE,TABLE_COLLATION FROM information_schema.TABLES WHERE TABLE_SCHEMA=%s AND TABLE_TYPE='BASE TABLE' ORDER BY 1", db))
    w('columns', q("SELECT TABLE_NAME,COLUMN_NAME,COLUMN_TYPE,IS_NULLABLE,COLUMN_DEFAULT,CHARACTER_SET_NAME,COLLATION_NAME,EXTRA FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=%s ORDER BY 1,2", db))
    w('indexes', q("SELECT TABLE_NAME,INDEX_NAME,NON_UNIQUE,SEQ_IN_INDEX,COLUMN_NAME,IFNULL(SUB_PART,'') FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=%s ORDER BY 1,2,4", db))
    w('keys', q("""SELECT k.TABLE_NAME,k.CONSTRAINT_NAME,k.ORDINAL_POSITION,k.COLUMN_NAME,IFNULL(k.REFERENCED_TABLE_NAME,''),IFNULL(k.REFERENCED_COLUMN_NAME,''),IFNULL(r.UPDATE_RULE,''),IFNULL(r.DELETE_RULE,'')
       FROM information_schema.KEY_COLUMN_USAGE k LEFT JOIN information_schema.REFERENTIAL_CONSTRAINTS r ON r.CONSTRAINT_SCHEMA=k.CONSTRAINT_SCHEMA AND r.CONSTRAINT_NAME=k.CONSTRAINT_NAME AND r.TABLE_NAME=k.TABLE_NAME
       WHERE k.TABLE_SCHEMA=%s ORDER BY 1,2,3""", db))
    w('checks', q("SELECT TABLE_NAME,CONSTRAINT_NAME,CHECK_CLAUSE FROM information_schema.CHECK_CONSTRAINTS WHERE CONSTRAINT_SCHEMA=%s ORDER BY 1,2", db))
    w('triggers', q("SELECT EVENT_OBJECT_TABLE,TRIGGER_NAME,ACTION_TIMING,EVENT_MANIPULATION FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA=%s ORDER BY 1,2", db))
    w('other', q("SELECT TABLE_NAME FROM information_schema.VIEWS WHERE TABLE_SCHEMA=%s UNION ALL SELECT ROUTINE_NAME FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA=%s", (db, db)))
    for (t,) in q("SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA=%s AND TABLE_TYPE='BASE TABLE' ORDER BY 1", db):
        n = q("SELECT COUNT(*) FROM `%s`.`%s`" % (db, t))[0][0]; counts.append((db, t, n))
        if a.no_fp: continue
        cols = [r[0] for r in q("SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=%s AND TABLE_NAME=%s ORDER BY ORDINAL_POSITION", (db, t))]
        pk = [r[0] for r in q("SELECT COLUMN_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA=%s AND TABLE_NAME=%s AND CONSTRAINT_NAME='PRIMARY' ORDER BY ORDINAL_POSITION", (db, t))]
        hs = ["LEFT(MD5(COALESCE(CAST(`%s` AS BINARY), CONCAT(0x00,'NULL'))),8)" % cn for cn in cols]
        pkx = ["CAST(`%s` AS CHAR)" % p for p in pk]
        rows = q("SELECT %s FROM `%s`.`%s`" % (','.join(pkx + hs), db, t))
        res = {}
        for r in rows:
            k, hv = r[:len(pk)], r[len(pk):]
            h = dict(zip(cols, hv))
            key = ':'.join('NULL' if x is None else str(x) for x in k) if pk else ''.join(hv)
            res[key] = h
        with gzip.open('%s/fp/%s.%s.json.gz' % (a.out, db, t), 'wt') as f:
            json.dump({'pk': pk, 'cols': cols, 'rows': res}, f)
with open(a.out + '/counts.tsv', 'w') as f:
    for r in counts: f.write('%s\t%s\t%d\n' % r)
print('snapshot %s: %d tables' % (a.out, len(counts)))
