# gunicorn entry for placement: the 2026.1 packages ship placement.wsgi.api; argv must not carry gunicorn's options
import sys
sys.argv = ['placement']
from placement.wsgi.api import application  # noqa: E402,F401
