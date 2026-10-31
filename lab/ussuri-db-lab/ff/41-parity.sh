#!/usr/bin/env bash
# Config parity (RT-N-02): the one-shot = rendered baseline file + override. Prints the CP-* options as explicitly set in the
# merged configuration, and diffs the merged file against the rendered file: only the override keys may differ.
# usage: 41-parity.sh <run> -> evidence/EXP-DB-01/<run>/config-parity.txt   (secrets redacted)
. "$(dirname "$0")/lib.sh"; ff_vars "${1:?run}"; set +e; O="$RUN_EV/config-parity.txt"
python3 - "$CFG_FF" > "$O.raw" <<'PY'
import configparser, sys, re
root = sys.argv[1]
CP = {'cinder': [('DEFAULT','quota_backups'),('DEFAULT','quota_backup_gigabytes')],
      'nova': [('DEFAULT','default_availability_zone'),('DEFAULT','cpu_allocation_ratio'),('DEFAULT','ram_allocation_ratio'),('DEFAULT','disk_allocation_ratio'),('DEFAULT','initial_cpu_allocation_ratio'),('DEFAULT','initial_ram_allocation_ratio'),('DEFAULT','initial_disk_allocation_ratio')],
      'placement': [('placement','incomplete_consumer_project_id'),('placement','incomplete_consumer_user_id')],
      'neutron': [('DEFAULT','core_plugin'),('DEFAULT','service_plugins')]}
files = {'cinder': ('cinder/cinder.conf','cinder.conf'), 'nova': ('nova/nova.conf','nova.conf'), 'placement': ('placement/placement.conf','placement.conf'), 'neutron': ('neutron/neutron.conf','neutron.conf')}
for svc, (base, ov) in files.items():
    b = configparser.ConfigParser(interpolation=None, strict=False); b.read('%s/etc/%s' % (root, base))
    o = configparser.ConfigParser(interpolation=None, strict=False); o.read('%s/override/%s' % (root, ov))
    m = configparser.ConfigParser(interpolation=None, strict=False); m.read(['%s/etc/%s' % (root, base), '%s/override/%s' % (root, ov)])
    print('== %s' % svc)
    for sec, opt in CP[svc]:
        v = m.get(sec, opt, fallback=None)
        print('  CP %s.%s = %s' % (sec, opt, v if v is not None else '(not set in the file: code default)'))
    diffs = []
    def raw(c): 
        d = {('DEFAULT', k): v for k, v in c.defaults().items()}
        for sec, kv in c._sections.items():
            for k, v in kv.items():
                if k != '__name__': d[(sec, k)] = v
        return d
    rb, rm = raw(b), raw(m)
    for key in set(rb) | set(rm):
        if rb.get(key) != rm.get(key): diffs.append('%s.%s' % key)
    print('  keys that differ from the rendered file (must be override keys only): %s' % sorted(set(diffs)))
    print('  override keys: %s' % sorted('%s.%s' % (s, k) for s in o.sections() + ['DEFAULT'] if s in o for k in o[s]))
PY
ff_redact < "$O.raw" > "$O"; rm -f "$O.raw"
{ echo "== neutron sub-projects installed in the one-shot images (CP-Q1: must equal the baseline = none)"; for r in 2023.1 2024.1 2025.1 2026.1; do echo "$r: $(grep -iE '^neutron-' "$EVIDENCE_DIR/../EXP-DB-01/pip-freeze-$r.txt" | grep -vE '^neutron-lib' | tr '\n' ' ')"; done; echo "ussuri baseline: $(grep -iE '^neutron-' "$EVIDENCE_DIR/pip-freeze-ussuri-py38.txt" | grep -vE '^neutron-lib' | tr '\n' ' ')"; } >> "$O"
cat "$O"
