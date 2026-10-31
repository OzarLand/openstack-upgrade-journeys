# gunicorn entry for neutron-server: the 2026.1 packages ship neutron.wsgi.api; argv must not carry gunicorn's options
import sys
sys.argv = ['neutron-server']
from neutron.wsgi.api import application  # noqa: E402,F401
