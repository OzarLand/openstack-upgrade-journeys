# gunicorn entry for nova-api: the 2026.1 packages ship nova.wsgi.osapi_compute; argv must not carry gunicorn's options
import sys
sys.argv = ['nova-api']
from nova.wsgi.osapi_compute import application  # noqa: E402,F401
