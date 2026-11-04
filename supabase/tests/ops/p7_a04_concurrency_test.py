"""P7-A04 real independent PostgreSQL-session races; new disposable cluster only.
Run: python supabase/tests/ops/p7_a04_concurrency_test.py
No hosted connections, published ports, mounted volumes or existing stack changes.
"""
import json
import re
import uuid
from pathlib import Path
import r06_x2_local_test as h


def uid(n): return 'a7020000-0000-0000-0000-' + str(n).zfill(12)
def vid(n): return 'a7021000-0000-0000-0000-' + str(n).zfill(12)
def bid(n): return 'a7032000-0000-0000-0000-' + str(n).zfill(12)
def auth(n=None):
    role = 'service_role' if n is None else 'authenticated'
    sub = '' if n is None else uid(n)
    return f"select set_config('request.jwt.claim.sub','{sub}',false); select set_config('request.jwt.claim.role','{role}',false); set role {role};\n"
def offer(b,d):
    return f"select public.backend_create_driver_match_offer('{bid(b)}','{uid(d)}','{vid(d)}',3000,(select version from public.booking_requests where id='{bid(b)}'));"
def accept(b,d,key='accept'):
    return f"select public.driver_transition_trip((select id from public.driver_match_offers where booking_request_id='{bid(b)}' and driver_id='{uid(d)}'),'accepted',1,'{key}');"
def decline(b,d):
    return f"select public.driver_decline_match_offer((select id from public.driver_match_offers where booking_request_id='{bid(b)}' and driver_id='{uid(d)}'),1,'decline');"


def run_race(c,base,label,setup,first,second,second_states,trip_count,rollback=False):
    db=h.clone(c,base)
    h.sql(c,db,h.expand(h.ROOT/'supabase/tests/fixtures/p7_a04_matching.sql'))
    h.sql(c,db,setup)
    tag='p7a04_'+uuid.uuid4().hex[:8]
    one=h.session(c,db,tag+'_first'); two=None
    try:
        one.stdin.write('\\set VERBOSITY verbose\nbegin;\n'+first+f"\nset application_name='{tag}_ready';\n")
        one.stdin.flush()
        h.await_activity(c,tag+'_ready',"state='idle in transaction'",one)
        two=h.session(c,db,tag+'_second')
        two.stdin.write('\\set VERBOSITY verbose\nbegin;\n'+second+'\n');two.stdin.flush()
        h.await_activity(c,tag+'_second',"wait_event_type='Lock' and cardinality(pg_blocking_pids(pid))>0",two)
        code,err=h.finish(one,'rollback;' if rollback else 'commit;')
        if code: raise RuntimeError(label+': first session failed: '+err)
        code,err=h.finish(two,'commit;')
        states=re.findall(r'ERROR:\s+([A-Z0-9]{5}):',err)
        actual=states[0] if states else ('OK' if code==0 else 'UNCLASSIFIED')
        if actual not in second_states: raise RuntimeError(label+': unexpected second result '+actual+' '+err)
        checks=h.sql(c,db,"""select json_build_object(
          'trips',(select count(*) from public.trips),
          'payments',(select count(*) from public.payments),
          'receipts',(select count(*) from public.receipts),
          'duplicate_driver',(select count(*) from (select driver_id from public.trips
            where status not in ('completed','cancelledByRider','cancelledByDriver','cancelledByAdmin','failed') group by driver_id having count(*)>1) x),
          'duplicate_booking',(select count(*) from (select booking_request_id from public.trips group by booking_request_id having count(*)>1) x),
          'bad_trip_reference',(select count(*) from public.driver_availability a where a.state='onTrip' and not exists(select 1 from public.trips t where t.id=a.active_trip_id and t.driver_id=a.driver_id)),
          'open_failed_offer',(select count(*) from public.driver_match_offers o join public.booking_requests b on b.id=o.booking_request_id where o.status='offered' and b.status in ('cancelled','expired')));
          """).stdout.strip()
        facts=json.loads(checks)
        if facts != dict(trips=trip_count,payments=trip_count,receipts=0,duplicate_driver=0,duplicate_booking=0,bad_trip_reference=0,open_failed_offer=0):
            raise RuntimeError(label+': partial/inconsistent outcome '+checks)
        print('PASS '+label+': real lock waiter; contender='+actual+'; atomic invariants verified',flush=True)
    finally:
        for proc in (one,two):
            if proc is not None and proc.poll() is None:
                h.finish(proc,'rollback;')


def audit_fk_race(c,base):
    db=h.clone(c,base)
    h.sql(c,db,h.expand(h.ROOT/'supabase/tests/fixtures/p7_a04_matching.sql'))
    h.sql(c,db,auth()+offer(1,1)+offer(1,2))
    h.sql(c,db,"""create function public.p7_a04_test_pause() returns trigger language plpgsql as $$
      begin if current_setting('ridex.test_pause',true)='on' then
        perform pg_advisory_xact_lock(704001); end if; return new; end; $$;
      create trigger p7_a04_test_pause before insert on public.trips for each row execute function public.p7_a04_test_pause();""")
    tag='p7a04_fk_'+uuid.uuid4().hex[:8]
    barrier=h.session(c,db,tag+'_barrier'); one=None;two=None
    try:
        barrier.stdin.write("begin; select pg_advisory_xact_lock(704001);\n");barrier.stdin.flush()
        h.await_activity(c,tag+'_barrier',"state='idle in transaction'",barrier)
        one=h.session(c,db,tag+'_accept')
        one.stdin.write("begin; set ridex.test_pause='on';\n"+auth(1)+accept(1,1)+"\n");one.stdin.flush()
        h.await_activity(c,tag+'_accept',"wait_event_type='Lock' and cardinality(pg_blocking_pids(pid))>0",one)
        two=h.session(c,db,tag+'_block')
        two.stdin.write('begin;\n'+auth(3)+f"select public.admin_set_user_blocked('{uid(2)}',true,'local competing Driver');\n");two.stdin.flush()
        h.await_activity(c,tag+'_block',"wait_event_type='Lock' and cardinality(pg_blocking_pids(pid))>0",two)
        if h.finish(barrier,'commit;')[0]:raise RuntimeError('barrier failed')
        if h.finish(one,'commit;')[0]:raise RuntimeError('acceptance/audit failed')
        if h.finish(two,'commit;')[0]:raise RuntimeError('competing block failed')
        value=h.sql(c,db,f"select (select count(*)=1 from public.trips) and (select count(*)=1 from public.payments) and (select a.state='offline' and u.is_blocked from public.driver_availability a join public.users u on u.id=a.driver_id where a.driver_id='{uid(2)}');").stdout.strip()
        if value!='t':raise RuntimeError('competing block/audit invariants failed')
        print('PASS competing-Driver block versus acceptance audit: two real lock barriers; no FK deadlock',flush=True)
    finally:
        for proc in (barrier,one,two):
            if proc is not None and proc.poll() is None:h.finish(proc,'rollback;')


def accepted_retry_cancel_race(c,base):
    db=h.clone(c,base)
    h.sql(c,db,h.expand(h.ROOT/'supabase/tests/fixtures/p7_a04_matching.sql'))
    h.sql(c,db,auth()+offer(1,1)+auth(1)+accept(1,1))
    h.sql(c,db,"""create function public.p7_a04_test_pause_cancel() returns trigger language plpgsql as $$
      begin if current_setting('ridex.test_pause',true)='on' then
        perform pg_advisory_xact_lock(704002); end if; return new; end; $$;
      create trigger p7_a04_test_pause_cancel before update of status on public.trips for each row execute function public.p7_a04_test_pause_cancel();""")
    tag='p7a04_retry_'+uuid.uuid4().hex[:8]
    barrier=h.session(c,db,tag+'_barrier');one=None;two=None
    try:
        barrier.stdin.write("begin; select pg_advisory_xact_lock(704002);\n");barrier.stdin.flush()
        h.await_activity(c,tag+'_barrier',"state='idle in transaction'",barrier)
        one=h.session(c,db,tag+'_cancel')
        one.stdin.write("begin; set ridex.test_pause='on';\n"+auth(1)+"select public.driver_transition_trip((select id from public.trips),'cancelledByDriver',1,'cancel-after-accept');\n");one.stdin.flush()
        h.await_activity(c,tag+'_cancel',"wait_event_type='Lock' and cardinality(pg_blocking_pids(pid))>0",one)
        two=h.session(c,db,tag+'_retry')
        two.stdin.write('begin;\n'+auth(1)+accept(1,1)+'\n');two.stdin.flush()
        h.await_activity(c,tag+'_retry',"wait_event_type='Lock' and cardinality(pg_blocking_pids(pid))>0",two)
        if h.finish(barrier,'commit;')[0]:raise RuntimeError('retry barrier failed')
        code,err=h.finish(one,'commit;')
        if code:raise RuntimeError('cancel versus retry failed '+err)
        code,err=h.finish(two,'commit;')
        if code:raise RuntimeError('accepted retry failed '+err)
        value=h.sql(c,db,f"select (select count(*)=1 from public.trips) and (select status='cancelledByDriver' from public.trips) and (select state='offline' from public.driver_availability where driver_id='{uid(1)}') and (select cash_status='cancelled' from public.payments);").stdout.strip()
        if value!='t':raise RuntimeError('retry/cancel invariants failed')
        print('PASS accepted-offer retry versus Trip cancellation: two real lock barriers; no Trip/availability inversion',flush=True)
    finally:
        for proc in (barrier,one,two):
            if proc is not None and proc.poll() is None:h.finish(proc,'rollback;')


def main():
    c=h.create_cluster();print('ISOLATED_CONTAINER='+c,flush=True)
    details=json.loads(h.docker('inspect',c).stdout)[0]
    if details['HostConfig']['NetworkMode']!='none' or details['Mounts'] or details['HostConfig']['PortBindings']:
        raise RuntimeError('Isolation not guaranteed')
    base=h.build_database(c)
    both=auth()+offer(1,1)+offer(1,2)
    single=auth()+offer(1,1)
    a1=auth(1)+accept(1,1)
    a2=auth(2)+accept(1,2)
    expire=auth()+f"select public.backend_expire_booking_match_offers('{bid(1)}',4);"
    cancel=auth(7)+f"select public.rider_cancel_booking('{bid(1)}',4,'changed_mind');"
    block=auth(3)+f"select public.admin_set_user_blocked('{uid(1)}',true,'P7 local race');"
    change=auth(1)+f"select public.driver_set_availability('offline',null,2); select public.driver_update_vehicle('{vid(1)}',1,'comfort','Toyota','Camry','White','P7 A02 1',4::smallint,null,null); select public.driver_set_availability('available','{vid(1)}',3);"
    cases=[
      ('competing Drivers',both,a1,a2,{'40001','55000'},1,False),
      ('duplicate acceptance lost response',single,a1,auth(1)+accept(1,1),{'OK'},1,False),
      ('acceptance rollback releases contender',both,a1,a2,{'OK'},1,True),
      ('accept before expiry service',single,a1,expire,{'40001'},1,False),
      ('decline before accept',single,auth(1)+decline(1,1),a1,{'40001','55000'},0,False),
      ('accept before decline',single,a1,auth(1)+decline(1,1),{'40001','55000'},1,False),
      ('cancel before accept',single,cancel,a1,{'40001','55000'},0,False),
      ('accept before cancel',single,a1,cancel,{'55000'},1,False),
      ('offer before blocking','',auth()+offer(1,1),block,{'OK'},0,False),
      ('blocking before offer','',block,auth()+offer(1,1),{'42501'},0,False),
      ('Rider blocking before offer','',auth(3)+f"select public.admin_set_user_blocked('{uid(7)}',true,'local Rider block');",auth()+offer(1,1),{'42501'},0,False),
      ('offer before Rider blocking','',auth()+offer(1,1),auth(3)+f"select public.admin_set_user_blocked('{uid(7)}',true,'local Rider block');",{'OK'},0,False),
      ('offer before category change','',auth()+offer(1,1),change,{'40001','55000'},0,False),
      ('category change before offer','',change,auth()+offer(1,1),{'42501'},0,False),
      ('GPS moves between discovery and offer',auth()+f"select * from public.backend_find_nearby_driver_candidates('{bid(1)}',3);",auth(1)+"select public.driver_record_location(null,2,0,1,10,null,null,clock_timestamp());",auth()+offer(1,1),{'55000'},0,False),
    ]
    # Old/inconsistent trusted data can contain two offers but must never produce
    # two active Trips. Canonical creation already rejects the second reservation.
    legacy=single+"reset role; alter table public.driver_match_offers disable trigger driver_match_offers_reserve_driver;"
    legacy+=f"update public.booking_requests set status='searching',searching_at=clock_timestamp() where id='{bid(2)}'; insert into public.driver_match_offers(booking_request_id,fare_quote_id,driver_id,vehicle_id,radius_meters) select id,fare_quote_id,'{uid(1)}','{vid(1)}',3000 from public.booking_requests where id='{bid(2)}'; alter table public.driver_match_offers enable trigger driver_match_offers_reserve_driver;"
    cases.append(('one Driver across two bookings',legacy,a1,auth(1)+accept(2,1),{'55000'},1,False))
    # Expired-offer cleanup wins while acceptance waits. Timestamp-only fixture
    # changes increment version; the contender carries that current version.
    expired=single+"reset role; update public.driver_match_offers set offered_at=now()-interval '16 seconds',expires_at=now()-interval '1 second';"
    expired_accept=a1.replace(",'accepted',1,",",'accepted',2,")
    cases.append(('expiry before accept',expired,expire,expired_accept,{'40001','55000'},0,False))
    for args in cases:run_race(c,base,*args)
    audit_fk_race(c,base)
    accepted_retry_cancel_race(c,base)
    print(f'PASS: {len(cases)+2} real independent-session races; zero deadlocks/timeouts; no partial state',flush=True)


if __name__=='__main__':main()
