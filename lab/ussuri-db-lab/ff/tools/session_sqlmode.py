#!/usr/bin/env python3
"""PC-E1 session capture: builds the oslo.db engine a service's migration tool uses (connection and mysql_sql_mode taken from the
same config files, default TRADITIONAL as in oslo.db) and prints SELECT @@SESSION.sql_mode for every database section.
usage: session_sqlmode.py <label> <config-file>...     exit 1 if a session is not strict (no STRICT_TRANS_TABLES)"""
import configparser, sys
from oslo_db.sqlalchemy import engines
import sqlalchemy

label, files = sys.argv[1], sys.argv[2:]
cp = configparser.ConfigParser(interpolation=None, strict=False)
cp.read(files)
bad = 0
for sec in ('database', 'api_database', 'placement_database'):
    if not cp.has_section(sec) or not cp.get(sec, 'connection', fallback=None):
        continue
    mode = cp.get(sec, 'mysql_sql_mode', fallback='TRADITIONAL')
    eng = engines.create_engine(cp.get(sec, 'connection'), mysql_sql_mode=mode)
    with eng.connect() as c:
        val = c.execute(sqlalchemy.text('SELECT @@SESSION.sql_mode')).scalar()
    strict = 'STRICT_TRANS_TABLES' in val or 'TRADITIONAL' in val
    bad += 0 if strict else 1
    print('%s [%s] configured=%s session=%s %s' % (label, sec, mode, val, 'STRICT' if strict else 'NOT-STRICT'))
sys.exit(1 if bad else 0)
