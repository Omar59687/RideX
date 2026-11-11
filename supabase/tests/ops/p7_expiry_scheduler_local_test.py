"""Run scheduler pgTAP and a full isolated migration replay via the R06 harness."""
import r06_x2_local_test as h
import uuid


FIXTURE = h.ROOT / 'supabase/tests/fixtures/p7_a04_matching.sql'
BID = 'a7032000-0000-0000-0000-000000000002'
DRIVER = 'a7020000-0000-0000-0000-000000000008'
VEHICLE = 'a7021000-0000-0000-0000-000000000008'


def setup(c, db, due=False):
    h.sql(c, db, h.expand(FIXTURE))
    h.sql(c, db, "update public.booking_requests set status='searching', searching_at=clock_timestamp() where id='%s';" % BID)
    h.sql(c, db, "select set_config('request.jwt.claim.role','service_role',false); set role service_role; select public.backend_create_driver_match_offer('%s','%s','%s',3000,(select version from public.booking_requests where id='%s')); reset role;" % (BID, DRIVER, VEHICLE, BID))
    if due:
        h.sql(c, db, "with t as (select clock_timestamp() n) update public.driver_match_offers set offered_at=t.n-interval '15 seconds',expires_at=t.n from t;")


def skip_locked(c, base):
    db = h.clone(c, base); setup(c, db, due=True)
    tag = 'p7sched_skip_' + uuid.uuid4().hex[:8]
    one = h.session(c, db, tag+'_holder'); two = None
    try:
        one.stdin.write("begin; select id from public.booking_requests where id='%s' for update; set application_name='%s_ready';\n" % (BID, tag)); one.stdin.flush()
        h.await_activity(c, tag+'_ready', "state='idle in transaction'", one)
        two = h.session(c, db, tag+'_tick')
        two.stdin.write("set request.jwt.claim.role='service_role'; set role service_role; do $$ begin if public.backend_expire_due_booking_matches(25)<>0 then raise exception 'held booking processed'; end if; end $$;\n"); two.stdin.flush()
        h.await_activity(c, tag+'_tick', "state='idle'", two)
        code, err = h.finish(two)
        if code: raise RuntimeError('SKIP LOCKED tick failed: '+err)
        result = h.sql(c, db, "select status from public.driver_match_offers;").stdout.strip()
        if result != 'offered': raise RuntimeError('SKIP LOCKED changed held booking: '+result)
        h.finish(one, 'rollback;')
        print('PASS scheduler SKIP LOCKED independent-session contention', flush=True)
    finally:
        for p in (one, two):
            if p is not None and p.poll() is None: h.finish(p, 'rollback;')


def expiry_accept(c, base):
    db = h.clone(c, base); setup(c, db, due=True)
    tag = 'p7sched_accept_' + uuid.uuid4().hex[:8]
    one = h.session(c, db, tag+'_expire'); two = None
    try:
        one.stdin.write("begin; set request.jwt.claim.role='service_role'; set role service_role; select public.backend_expire_due_booking_matches(25); set application_name='"+tag+"_ready';\n"); one.stdin.flush()
        h.await_activity(c, tag+'_ready', "state='idle in transaction'", one)
        two = h.session(c, db, tag+'_accept')
        two.stdin.write("\\set VERBOSITY verbose\nbegin; set request.jwt.claim.role='authenticated'; set role authenticated; select set_config('request.jwt.claim.sub','"+DRIVER+"',false); select public.driver_transition_trip((select id from public.driver_match_offers where booking_request_id='"+BID+"'),'accepted',2,'scheduler-race');\n"); two.stdin.flush()
        h.await_activity(c, tag+'_accept', "wait_event_type='Lock' and cardinality(pg_blocking_pids(pid))>0", two)
        if h.finish(one, 'commit;')[0]: raise RuntimeError('scheduler winner failed')
        code, err = h.finish(two, 'commit;')
        if not code or not any(state in err for state in ('40001','55000')): raise RuntimeError('expired offer was not rejected: '+err)
        value = h.sql(c, db, "select (select count(*)=0 from public.trips) and (select count(*)=0 from public.payments) and (select status='expired' from public.driver_match_offers) and (select status='searching' from public.booking_requests where id='"+BID+"');").stdout.strip()
        if value != 't': raise RuntimeError('scheduler acceptance race corrupted canonical state')
        print('PASS scheduler expiry versus acceptance: real lock waiter; no Trip/payment created', flush=True)
    finally:
        for proc in (one, two):
            if proc is not None and proc.poll() is None: h.finish(proc, 'rollback;')


def main():
    container = h.create_cluster()
    try:
        db = h.build_database(container)
        testdb = h.clone(container, db)
        script = h.expand(h.ROOT / 'supabase/tests/database/20261111103410_p7_matching_expiry_scheduler.test.sql')
        result = h.sql(container, testdb, script)
        output = result.stdout
        if 'not ok' in output.lower() or 'Looks like you failed' in output:
            raise RuntimeError('scheduler pgTAP assertions failed:\n' + output)
        print(output, flush=True)
        print('PASS scheduler pgTAP on full isolated migration chain', flush=True)
        skip_locked(container, db)
        expiry_accept(container, db)
    finally:
        # Disposable labeled container intentionally retained for inspection.
        pass


if __name__ == '__main__':
    main()
