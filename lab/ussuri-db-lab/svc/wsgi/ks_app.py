# gunicorn entry for keystone: the 2026.1 packages ship keystone.wsgi.api; argv must not carry gunicorn's options
import sys
sys.argv = ['keystone']
from keystone.wsgi.api import application  # noqa: E402,F401
