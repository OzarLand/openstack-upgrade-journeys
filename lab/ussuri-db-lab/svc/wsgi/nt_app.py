# gunicorn entry for neutron-server: the 2026.1 packages ship neutron.wsgi.api; argv must not carry gunicorn's options
import sys
sys.argv = ['neutron-server', '--config-file', '/etc/neutron/neutron.conf']
import neutron.db.migration.models.head  # noqa: E402,F401  lab: imports every DB model module (backrefs such as Port.port_forwardings and Port.distributed_port_binding)
import sqlalchemy.orm; sqlalchemy.orm.configure_mappers()  # noqa: E402  lab: backrefs exist only once the mappers are configured; get_ports() reads one before any query ran
from neutron.wsgi.api import application  # noqa: E402,F401
