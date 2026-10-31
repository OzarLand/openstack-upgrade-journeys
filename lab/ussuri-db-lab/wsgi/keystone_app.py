# WSGI entry for gunicorn: the wheel does not install pbr's keystone-wsgi-public script, and the app factory
# would otherwise parse gunicorn's command line as keystone options.
import sys
sys.argv = ['keystone-wsgi-public']
from keystone.server.wsgi import initialize_public_application  # noqa: E402
application = initialize_public_application()
