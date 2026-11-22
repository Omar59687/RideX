"""Real loopback HTTP against a new network-isolated disposable PostgreSQL cluster."""
import json
import os
from pathlib import Path
import subprocess
import r06_x2_local_test as h


def main():
    container = h.create_cluster()
    print('isolated container:', container, flush=True)
    details = json.loads(h.docker('inspect', container).stdout)[0]
    if details['HostConfig']['NetworkMode'] != 'none' or details['Mounts'] or details['HostConfig']['PortBindings']:
        raise RuntimeError('database isolation not guaranteed')
    base = h.build_database(container)
    db = h.clone(container, base)
    source = h.expand(Path('supabase/tests/database/p8_a03_webhook_quarantine.test.sql'))
    marker = "select is(public.backend_quarantine_test_webhook('evt_SyntheticOne'"
    setup = source[:source.index(marker)] + "\nreset role; revoke execute on function public.backend_prepare_card_command(uuid,uuid,uuid,integer,integer,text,text,text) from service_role; commit;"
    output = h.sql(container, db, 'set search_path=public,extensions;\n' + setup).stdout
    if 'not ok' in output:
        raise RuntimeError('synthetic canonical setup failed')
    env = os.environ.copy()
    env.update(P8_HTTP_CONTAINER=container, P8_HTTP_DB=db)
    result = subprocess.run(['deno', 'test', '--no-config', '--no-lock', '--cached-only', '--allow-net=127.0.0.1', '--allow-run=docker', '--allow-env=P8_HTTP_CONTAINER,P8_HTTP_DB', 'supabase/functions/stripe-test-webhook/http_integration_test.ts'], env=env, check=False)
    if result.returncode:
        raise RuntimeError('real loopback HTTP integration failed')


if __name__ == '__main__':
    main()
