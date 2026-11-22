"""Local-only fake identity tests. No provider, financial transitions, or network."""
import json
import uuid
from pathlib import Path
import r06_x2_local_test as h
import p7_a04_concurrency_test as p


def main():
    container = h.create_cluster()
    info = json.loads(h.docker('inspect', container).stdout)[0]
    if info['HostConfig']['NetworkMode'] != 'none' or info['Mounts'] or info['HostConfig']['PortBindings']:
        raise RuntimeError('expected newly created network-isolated container')
    print('network-isolated cluster:', container, flush=True)
    # Replay only committed migrations; preserve and exclude unfinished provenance work.
    import subprocess
    result = subprocess.run(['git', 'ls-tree', '-r', '--name-only', 'HEAD', '--', 'supabase/migrations'], capture_output=True, text=True, check=True)
    paths = [Path(line) for line in result.stdout.splitlines() if line.endswith('.sql')]
    if not paths: raise RuntimeError('no committed migrations')
    base = 'fake_base_' + uuid.uuid4().hex[:10]
    h.sql(container, 'postgres', f'create database "{base}";')
    h.sql(container, base, (h.ROOT / 'supabase/tests/ops/r06_x2_bootstrap.sql').read_text())
    for path in paths:
        # The checked-out migration must equal HEAD, otherwise stop without executing it.
        committed = subprocess.run(['git', 'show', 'HEAD:' + path.as_posix()], capture_output=True, check=True).stdout
        actual = path.read_bytes()
        if committed.replace(b'\r\n', b'\n') != actual.replace(b'\r\n', b'\n'):
            raise RuntimeError('committed migration differs from worktree: ' + str(path))
        h.sql(container, base, actual.decode('utf-8-sig'))
    print('committed migration chain:', len(paths), 'applied', flush=True)
    h.sql(container, base, Path('supabase/tests/fakes/local_fake_identity.sql').read_text(encoding='utf-8-sig'))
    h.tap(container, h.clone(container, base), Path('supabase/tests/fakes/local_fake_identity.test.sql'))
    db = h.clone(container, base)
    h.sql(container, db, 'update local_fake_fixture.gate set enabled=true;')
    tag = 'fake_' + uuid.uuid4().hex[:8]
    query = "local_fake_fixture.claim('d0000000-0000-4000-8000-000000000002','local_fake_demo','verified_fake')"
    one = h.session(container, db, tag+'_one'); two = None
    try:
        one.stdin.write('begin;\n'+p.auth()+f"select {query};\nset application_name='{tag}_ready';\n"); one.stdin.flush()
        h.await_activity(container, tag+'_ready', "state='idle in transaction'", one)
        two = h.session(container, db, tag+'_two')
        two.stdin.write('begin;\n'+p.auth()+f"do $$ begin if {query} <> 'existing' then raise exception 'bad retry'; end if; end $$;\n"); two.stdin.flush()
        h.await_activity(container, tag+'_two', "wait_event_type='Lock' and cardinality(pg_blocking_pids(pid))>0", two)
        if h.finish(one, 'commit;')[0] or h.finish(two, 'commit;')[0]: raise RuntimeError('race failed')
        print('PASS concurrent identical claim: lock waiter, one durable identity', flush=True)
        if h.sql(container, db, 'select count(*) from local_fake_fixture.identity;').stdout.strip() != '1': raise RuntimeError('duplicate identity')
    finally:
        for process in (one, two):
            if process is not None and process.poll() is None: h.finish(process, 'rollback;')
    for name in ['20261028150000_cash_only_rider_booking_confirmation.test.sql', '20261028150001_cash_only_booking_confirmation_concurrency.test.sql']:
        h.tap(container, h.clone(container, base), Path('supabase/tests/database') / name)

if __name__ == '__main__': main()
