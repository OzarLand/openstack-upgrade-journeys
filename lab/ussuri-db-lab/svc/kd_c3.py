"""EXP-KD-01 C-3: feed `nova-manage cell_v2 list_cells --verbose` of the migrated deployment to kolla_ansible.nova_filters.extract_cell
(kolla-ansible 22.2.0, unpacked at /kolla) with the Kolla default cell name '' and with the lab's cell name 'cell1'.  Passwords in the
output are masked here (and again by the caller)."""
import re
import subprocess
import sys

sys.path.insert(0, '/kolla')
from kolla_ansible import nova_filters  # noqa: E402

p = subprocess.run(['nova-manage', 'cell_v2', 'list_cells', '--verbose'], capture_output=True, text=True)
lines = p.stdout.splitlines()
print('nova-manage cell_v2 list_cells --verbose exit code', p.returncode, '; table lines:', len(lines))


def mask(s):
    return re.sub(r'(://[^:/@]+:)[^@]+@', r'\1***@', s)


for l in lines:
    print('  ' + mask(l))
for name in ('', 'cell1'):
    try:
        r = nova_filters.extract_cell({'stdout_lines': lines}, name)
    except Exception as e:  # noqa
        r = 'EXCEPTION %s: %s' % (type(e).__name__, e)
    if isinstance(r, dict):
        r = {k: (mask(v) if isinstance(v, str) else v) for k, v in r.items()}
    print('extract_cell(%r) -> %s' % (name, r))
