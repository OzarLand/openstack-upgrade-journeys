import sys
sys.argv = ['placement-api']
from placement.wsgi import init_application  # noqa: E402
application = init_application()
