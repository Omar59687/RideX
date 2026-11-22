"""Local-only Card matching races against a fresh disposable cluster."""
import p7_a04_concurrency_test as p
import r06_x2_local_test as h


def main():
    container = h.create_cluster()
    print('isolated container:', container, flush=True)
    base = h.build_database(container)
    booking = p.bid(5)
    setup = f"""
update private.p8_card_matching_gate set enabled=true;
insert into public.booking_requests(id,rider_id,pickup,destination,vehicle_type_code,payment_method)
values('{booking}','{p.uid(7)}','{{"latitude":0,"longitude":0}}','{{"latitude":1,"longitude":1}}','economy','card');
select public.backend_calculate_fare_quote('{booking}',1,2000,600,null);
select public.backend_lock_fare_quote((select id from public.fare_quotes where booking_request_id='{booking}'),1,1);
""" + p.auth(7) + f"select public.rider_confirm_booking('{booking}',2,'card-confirm');\n" + p.auth() + p.offer(5,1)
    p.run_race(container,base,'Card duplicate acceptance',setup,p.auth(1)+p.accept(5,1),p.auth(1)+p.accept(5,1),{'OK'},1)
    p.run_race(container,base,'Card cancellation before acceptance',setup,p.auth(7)+f"select public.rider_cancel_booking('{booking}',4,'changed_mind');",p.auth(1)+p.accept(5,1),{'40001','55000'},0)
    p.run_race(container,base,'Card acceptance before cancellation',setup,p.auth(1)+p.accept(5,1),p.auth(7)+f"select public.rider_cancel_booking('{booking}',4,'changed_mind');",{'55000'},1)
    accepted = setup + p.auth(1) + p.accept(5,1)
    pending = p.auth() + f"select public.backend_record_payment_attempt((select id from public.payments where booking_request_id='{booking}'),'initialAuthorization',1600,'pending-card-race',null);"
    cancel_trip = p.auth(7) + f"select public.rider_cancel_trip((select id from public.trips where booking_request_id='{booking}'),1,'OTHER');"
    p.run_race(container,base,'Pending authorization before cancellation',accepted,pending,cancel_trip,{'55000'},1)

    session_setup = accepted + "reset role; create table if not exists auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);" + f"insert into auth.sessions values ('55555555-5555-4555-8555-555555555555','{p.uid(7)}',null);"
    command = p.auth() + f"select public.backend_prepare_card_authorization_for_session('{p.uid(7)}','55555555-5555-4555-8555-555555555555',extract(epoch from now())::bigint+300,(select id from public.trips where booking_request_id='{booking}'),(select id from public.payments where booking_request_id='{booking}'),1,1,'command-race');"
    p.run_race(container,base,'Duplicate session-bound authorization',session_setup,command,command,{'OK'},1)
    p.run_race(container,base,'Session-bound authorization versus cancellation',session_setup,command,cancel_trip,{'55000'},1)




if __name__ == '__main__':
    main()
