# gunicorn entry for cinder-api: the 2026.1 packages ship cinder.wsgi.api; argv must not carry gunicorn's options
import sys
sys.argv = ['cinder-api']
from cinder.wsgi.api import application  # noqa: E402,F401
