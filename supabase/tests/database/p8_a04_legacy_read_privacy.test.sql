begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
\ir fixtures/r06_x2_reserved_target.sql
-- Additional initial rows only; no financial or trip transition RPCs.
insert into auth.users(id,email,raw_user_meta_data) values
 ('fa000000-0000-4000-8000-000000000001','a04-admin@example.invalid','{}'),
 ('fa000000-0000-4000-8000-000000000002','a04-blocked-admin@example.invalid','{}');
update public.users set role='admin',is_blocked=(id='fa000000-0000-4000-8000-000000000002') where id in ('fa000000-0000-4000-8000-000000000001','fa000000-0000-4000-8000-000000000002');
insert into public.booking_requests(id,rider_id,pickup,destination,vehicle_type_code,payment_method)
select ('ba000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'d3c3dc11-a840-4712-a6a4-599b4ae27329','{"latitude":31.9,"longitude":35.9}','{"latitude":32.0,"longitude":36.0}','economy','cash' from generate_series(1,3) n;
insert into public.fare_quotes(id,booking_request_id,rider_id,status,pickup,destination,route_distance_meters,route_duration_seconds,vehicle_type_code,breakdown,fixed_fare_fils,pricing_configuration_id,pricing_version,quote_version)
select ('bb000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,('ba000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'d3c3dc11-a840-4712-a6a4-599b4ae27329','calculated','{"latitude":31.9,"longitude":35.9}','{"latitude":32.0,"longitude":36.0}',1000,300,'economy','{}',1000,(select id from public.pricing_configurations where is_active and vehicle_type_code='economy' limit 1),1,1 from generate_series(1,3) n;
insert into public.trips(id,booking_request_id,fare_quote_id,rider_id,driver_id,vehicle_id,status,payment_method,pickup,destination,route_distance_meters,route_duration_seconds,original_fare_fils,current_fare_fils,created_at)
select ('bc000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,('ba000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,('bb000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'d3c3dc11-a840-4712-a6a4-599b4ae27329','f148a7ec-7e85-48ef-847f-8e9eea880e1b','48d007ab-c13c-4ff8-93f3-1dc7f1e6975d','completed','cash','{"latitude":31.9,"longitude":35.9}','{"latitude":32.0,"longitude":36.0}',1000,300,1000,1000,'2026-01-01T00:00:00Z' from generate_series(1,3) n;
insert into public.payments(id,booking_request_id,trip_id,rider_id,method,fare_quote_id,authorized_amount_fils,final_amount_fils,cash_status)
select ('bd000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,('ba000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,('bc000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'d3c3dc11-a840-4712-a6a4-599b4ae27329','cash',('bb000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,1000,1000,'cashSelected' from generate_series(1,3) n;
insert into public.receipts(id,receipt_number,trip_id,fare_quote_id,payment_id,rider_snapshot,driver_snapshot,vehicle_snapshot,pickup_snapshot,destination_snapshot,ordered_stops_snapshot,fare_breakdown_snapshot,amount_paid_fils,currency,payment_method,source_versions)
values('be000000-0000-4000-8000-000000000001','RDX-20260101-AAAAAAAA','bc000000-0000-4000-8000-000000000001','bb000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000002','{}','{}','{}','{}','{}','[]','{}',1000,'JOD','cash','{}');
insert into public.receipts(id,receipt_number,trip_id,fare_quote_id,payment_id,rider_snapshot,driver_snapshot,vehicle_snapshot,pickup_snapshot,destination_snapshot,ordered_stops_snapshot,fare_breakdown_snapshot,amount_paid_fils,currency,payment_method,source_versions)
values('be000000-0000-4000-8000-000000000003','RDX-20260101-AAAAAAAB','bc000000-0000-4000-8000-000000000003','bb000000-0000-4000-8000-000000000003','bd000000-0000-4000-8000-000000000003','{}','{}','{}','{}','{}','[]','{}',1000,'JOD','cash','{}');
select set_config('request.jwt.claim.sub','d3c3dc11-a840-4712-a6a4-599b4ae27329',true);
set local role authenticated;
select is((select id from public.user_trip_payment_summary('bc000000-0000-4000-8000-000000000003')),'bd000000-0000-4000-8000-000000000003'::uuid,'owner retains canonical Payment ID');
select is((select id from public.user_trip_receipt_summary('bc000000-0000-4000-8000-000000000003')),'be000000-0000-4000-8000-000000000003'::uuid,'owner receipt summary unchanged');
select throws_ok($$select * from public.user_trip_receipt_summary('bc000000-0000-4000-8000-000000000002')$$,'P0002','Receipt was not found.','owner missing receipt preserves P0002');
select is((select receipt_evidence from public.user_trip_financial_read_v1('bc000000-0000-4000-8000-000000000001')),'unverified','mismatched Receipt remains unverified');
select throws_ok($$select * from public.user_trip_receipt_summary('not-a-uuid')$$,'22P02',null,'malformed identity rejected');
select set_config('request.jwt.claim.sub','f148a7ec-7e85-48ef-847f-8e9eea880e1b',true);
select is((select id from public.user_trip_receipt_summary('bc000000-0000-4000-8000-000000000003')),'be000000-0000-4000-8000-000000000003'::uuid,'assigned Driver retains receipt access');
select throws_ok($$select * from public.user_trip_payment_summary('bc000000-0000-4000-8000-000000000003')$$,'P0002','Payment was not found.','assigned Driver denied payment');
select set_config('request.jwt.claim.sub','d3c3dc11-a840-4712-a6a4-599b4ae27320',true);
select throws_ok($$select * from public.user_trip_payment_summary('bc000000-0000-4000-8000-000000000003')$$,'P0002','Payment was not found.','foreign Trip payment uses missing response');
select throws_ok($$select * from public.user_trip_payment_summary('ffffffff-ffff-4fff-8fff-ffffffffffff')$$,'P0002','Payment was not found.','nonexistent Trip payment same response');
select throws_ok($$select * from public.user_trip_receipt_summary('bc000000-0000-4000-8000-000000000003')$$,'P0002','Receipt was not found.','foreign Trip receipt uses missing response');
select throws_ok($$select * from public.user_trip_receipt_summary('ffffffff-ffff-4fff-8fff-ffffffffffff')$$,'P0002','Receipt was not found.','nonexistent Trip receipt same response');
select throws_ok($$select * from public.user_payment_summary('bd000000-0000-4000-8000-000000000003')$$,'P0002','Payment was not found.','foreign Payment ID uses missing response');
select throws_ok($$select * from public.user_payment_summary(null)$$,'P0002','Payment was not found.','missing Payment ID same response');
select throws_ok($$select * from public.user_payment_attempt_summaries('bd000000-0000-4000-8000-000000000003')$$,'P0002','Payment was not found.','foreign attempts use missing response');
select throws_ok($$select * from public.user_refund_statuses('bd000000-0000-4000-8000-000000000003')$$,'P0002','Payment was not found.','foreign refunds use missing response');
select throws_ok($$select * from public.user_receipt_summary('be000000-0000-4000-8000-000000000003')$$,'P0002','Receipt was not found.','foreign Receipt ID uses missing response');
select throws_ok($$select * from public.user_receipt_summary(null)$$,'P0002','Receipt was not found.','missing Receipt ID same response');
select set_config('request.jwt.claim.sub','fa000000-0000-4000-8000-000000000001',true);
select is((select count(*) from public.user_trip_payment_summary('bc000000-0000-4000-8000-000000000003')),1::bigint,'active admin payment read retained');
select is((select count(*) from public.user_trip_receipt_summary('bc000000-0000-4000-8000-000000000003')),1::bigint,'active admin receipt read retained');
select set_config('request.jwt.claim.sub','fa000000-0000-4000-8000-000000000002',true);
select throws_ok($$select * from public.user_trip_payment_summary('bc000000-0000-4000-8000-000000000003')$$,'P0002','Payment was not found.','blocked admin denied');
select throws_ok($$select * from public.user_trip_receipt_summary('bc000000-0000-4000-8000-000000000003')$$,'P0002','Receipt was not found.','blocked admin receipt denied');
reset role;
update public.users set is_blocked=true where id='d3c3dc11-a840-4712-a6a4-599b4ae27329';
set local role authenticated;
select set_config('request.jwt.claim.sub','d3c3dc11-a840-4712-a6a4-599b4ae27329',true);
select throws_ok($$select * from public.user_trip_payment_summary('bc000000-0000-4000-8000-000000000003')$$,'P0002','Payment was not found.','blocked Rider denied');
select throws_ok($$select * from public.user_trip_receipt_summary('bc000000-0000-4000-8000-000000000003')$$,'P0002','Receipt was not found.','blocked Rider receipt denied');
reset role;
select ok(not has_function_privilege('anon','public.user_trip_payment_summary(uuid)','execute'),'anonymous payment access denied');
select ok(not has_function_privilege('anon','public.user_trip_receipt_summary(uuid)','execute'),'anonymous receipt access denied');
select * from finish();
rollback;
