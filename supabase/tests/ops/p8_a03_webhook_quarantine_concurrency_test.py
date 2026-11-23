"""Network-isolated duplicate webhook quarantine race; never invokes a provider."""
import hashlib
import uuid
from pathlib import Path
import p7_a04_concurrency_test as p
import r06_x2_local_test as h


def safe_setup(source):
    marker = "select is(public.backend_quarantine_test_webhook('evt_SyntheticOne'"
    # This broad fixture contains a rolled-back synthetic financial transition.
    # Exclude that entire block and fail closed if transition calls reappear.
    start = 'savepoint trusted_commands;'
    end = 'rollback to trusted_commands;'
    if source.count(start) != 1 or source.count(end) != 1:
        raise RuntimeError('unsafe fixture boundaries changed')
    before, rest = source.split(start, 1)
    _, after = rest.split(end, 1)
    source = before + after
    setup = source[:source.index(marker)] + "\nreset role; revoke execute on function public.backend_prepare_card_command(uuid,uuid,uuid,integer,integer,text,text,text) from service_role; commit;"
    # Require explicit review of any fixture change before executing SQL.
    if hashlib.sha256(setup.encode()).hexdigest() != '68610a2c881b23539d44f8d06de0714799b7446da35ad9977de7ef7b2f01558e':
        raise RuntimeError('fixture changed; review for financial writes before updating digest')
    if 'backend_complete_payment_attempt(' in setup or 'backend_transition_payment(' in setup:
        raise RuntimeError('financial transition in concurrency setup')
    return setup


def main():
    c = h.create_cluster()
    print('isolated container:', c, flush=True)
    base = h.build_database(c)
    db = h.clone(c, base)
    source = h.expand(Path('supabase/tests/database/p8_a03_webhook_quarantine.test.sql'))
    setup = safe_setup(source)
    output = h.sql(c, db, 'set search_path=public,extensions;\n' + setup).stdout
    if 'not ok' in output:
        raise RuntimeError('canonical synthetic setup failed')
    query = """public.backend_quarantine_test_webhook('evt_Race','payment_intent.succeeded',repeat('a',64),'pi_SyntheticOne',
      (select id from public.trips where booking_request_id='a7032000-0000-0000-0000-000000000099'),
      (select id from public.payments where booking_request_id='a7032000-0000-0000-0000-000000000099'),
      (select id from public.payment_attempts where idempotency_key='p8-card-attempt'),1600,'JOD')"""
    tag = 'p8quarantine_' + uuid.uuid4().hex[:8]
    one = h.session(c, db, tag + '_first')
    two = None
    try:
        one.stdin.write('begin;\n' + p.auth() + f"do $$ begin if {query} <> 'quarantined' then raise exception 'bad first outcome'; end if; end $$;\nset application_name='{tag}_ready';\n")
        one.stdin.flush()
        h.await_activity(c, tag + '_ready', "state='idle in transaction'", one)
        two = h.session(c, db, tag + '_second')
        two.stdin.write('begin;\n' + p.auth() + f"do $$ begin if {query} <> 'duplicate' then raise exception 'bad replay outcome'; end if; end $$;\n")
        two.stdin.flush()
        h.await_activity(c, tag + '_second', "wait_event_type='Lock' and cardinality(pg_blocking_pids(pid))>0", two)
        if h.finish(one, 'commit;')[0] or h.finish(two, 'commit;')[0]:
            raise RuntimeError('duplicate race failed')
        result = h.sql(c, db, "select (select count(*)=1 from private.p8_test_webhook_quarantine) and (select count(*)=1 from public.payment_attempts where status='pending') and (select count(*)=1 from public.payments where card_status='cardPaymentPending');").stdout.strip()
        if result != 't':
            raise RuntimeError('duplicate race violated financial invariants')
        print('PASS duplicate webhook: real lock waiter, one quarantined event, no financial transition', flush=True)

        one = h.session(c, db, tag + '_inspect_first')
        one.stdin.write('begin;\n' + p.auth() + f"do $$ begin if public.backend_inspect_quarantined_test_event('evt_Race')->>'outcome' <> 'UNKNOWN' then raise exception 'unexpected outcome'; end if; end $$;\nset application_name='{tag}_inspect_ready';\n")
        one.stdin.flush()
        h.await_activity(c, tag + '_inspect_ready', "state='idle in transaction'", one)
        two = h.session(c, db, tag + '_inspect_second')
        two.stdin.write('begin;\n' + p.auth() + "select public.backend_inspect_quarantined_test_event('evt_Race');\n")
        two.stdin.flush()
        h.await_activity(c, tag + '_inspect_second', "wait_event_type='Lock' and cardinality(pg_blocking_pids(pid))>0", two)
        if h.finish(one, 'commit;')[0] or h.finish(two, 'commit;')[0]:
            raise RuntimeError('concurrent inspection failed')
        result = h.sql(c, db, "select (select count(*)=1 from private.p8_test_webhook_quarantine) and (select count(*)=1 from public.payment_attempts where status='pending') and (select count(*)=1 from public.payments where card_status='cardPaymentPending');").stdout.strip()
        if result != 't':
            raise RuntimeError('concurrent inspection changed financial state')
        print('PASS concurrent reconciliation context inspection: serialized, no financial transition', flush=True)

    finally:
        for process in (one, two):
            if process is not None and process.poll() is None:
                h.finish(process, 'rollback;')


if __name__ == '__main__':
    main()
