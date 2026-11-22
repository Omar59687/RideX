"""Combined local preview: fresh network-none PostgreSQL, no financial transitions."""
import json
import uuid
from pathlib import Path
import r06_x2_local_test as h
import p7_a04_concurrency_test as auth


def main():
    c = h.create_cluster()
    detail = json.loads(h.docker('inspect', c).stdout)[0]
    if detail['HostConfig']['NetworkMode'] != 'none' or detail['Mounts'] or detail['HostConfig']['PortBindings']:
        raise RuntimeError('unsafe database environment')
    print('isolated cluster:', c, flush=True)
    base = h.build_database(c)
    for name in ('p8_a05_a02_gate_read.test.sql', 'p8_a03_webhook_admission.test.sql',
                 'p8_local_integration_safety.test.sql', 'p8_a04_legacy_read_privacy.test.sql',
                 'p8_a04_financial_reads.test.sql', '019_phase3_safe_exposure_hardening.test.sql',
                 '020_phase3_driver_finance_exposure_correction.test.sql',
                 '20261028150000_cash_only_rider_booking_confirmation.test.sql',
                 '20261028150001_cash_only_booking_confirmation_concurrency.test.sql'):
        h.tap(c, h.clone(c, base), Path('supabase/tests/database') / name)
    fake = h.clone(c, base)
    h.sql(c, fake, Path('supabase/tests/fakes/local_fake_identity.sql').read_text(encoding='utf-8-sig'))
    h.tap(c, fake, Path('supabase/tests/fakes/local_fake_identity.test.sql'))
    race = h.clone(c, base)
    h.sql(c, race, Path('supabase/tests/fakes/local_fake_identity.sql').read_text(encoding='utf-8-sig'))
    h.sql(c, race, 'update local_fake_fixture.gate set enabled=true;')
    tag = 'p8int_' + uuid.uuid4().hex[:8]
    query = "local_fake_fixture.claim('d0000000-0000-4000-8000-000000000002','local_fake_demo','verified_fake')"
    one = h.session(c, race, tag + '_one')
    two = None
    try:
        one.stdin.write('begin;\n' + auth.auth() + f"select {query};\nset application_name='{tag}_ready';\n")
        one.stdin.flush()
        h.await_activity(c, tag + '_ready', "state='idle in transaction'", one)
        two = h.session(c, race, tag + '_two')
        two.stdin.write('begin;\n' + auth.auth() + f"do $$ begin if {query} <> 'existing' then raise exception 'bad retry'; end if; end $$;\n")
        two.stdin.flush()
        h.await_activity(c, tag + '_two', "wait_event_type='Lock' and cardinality(pg_blocking_pids(pid))>0", two)
        if h.finish(one, 'commit;')[0] or h.finish(two, 'commit;')[0]:
            raise RuntimeError('fake identity race failed')
        if h.sql(c, race, 'select count(*) from local_fake_fixture.identity;').stdout.strip() != '1':
            raise RuntimeError('fake identity count mismatch')
        print('PASS local fake identity concurrency: real lock waiter', flush=True)
    finally:
        for proc in (one, two):
            if proc is not None and proc.poll() is None:
                h.finish(proc, 'rollback;')


if __name__ == '__main__':
    main()
