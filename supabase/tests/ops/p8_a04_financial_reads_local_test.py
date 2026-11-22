"""P8-A04 reads and Cash regressions; new network-isolated PostgreSQL only."""
import json
from pathlib import Path
import r06_x2_local_test as h


def main():
    container = h.create_cluster()
    details = json.loads(h.docker('inspect', container).stdout)[0]
    if details['HostConfig']['NetworkMode'] != 'none' or details['Mounts'] or details['HostConfig']['PortBindings']:
        raise RuntimeError('Expected a new network-isolated container')
    print('isolated container:', container, flush=True)
    base = h.build_database(container)
    for name in ('p8_a04_financial_reads.test.sql',
                 '20261028150000_cash_only_rider_booking_confirmation.test.sql',
                 '20261028150001_cash_only_booking_confirmation_concurrency.test.sql'):
        h.tap(container, h.clone(container, base), Path('supabase/tests/database') / name)


if __name__ == '__main__':
    main()
