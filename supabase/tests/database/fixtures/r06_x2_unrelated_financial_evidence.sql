-- LOCAL ONLY: unrelated evidence exercises reassignment without changing the
-- exact recovery snapshot or inventing another accepted Trip.
insert into public.booking_requests(id,rider_id,pickup,destination,vehicle_type_code,payment_method)
select '84e8e5d2-4126-4c27-893b-b70e5318a180',rider_id,pickup,destination,vehicle_type_code,'cash'
from public.booking_requests where id='84e8e5d2-4126-4c27-893b-b70e5318a184';
insert into public.fare_quotes(id,booking_request_id,rider_id,status,pickup,destination,
 route_distance_meters,route_duration_seconds,vehicle_type_code,breakdown,fixed_fare_fils,
 pricing_configuration_id,pricing_version,quote_version,locked_at)
select '90532842-03bf-4644-a656-2cad3edf37d0','84e8e5d2-4126-4c27-893b-b70e5318a180',
 rider_id,status,pickup,destination,route_distance_meters,route_duration_seconds,vehicle_type_code,
 breakdown,fixed_fare_fils,pricing_configuration_id,pricing_version,quote_version,locked_at
from public.fare_quotes where id='90532842-03bf-4644-a656-2cad3edf37d1';
insert into public.payments(id,booking_request_id,rider_id,method,fare_quote_id,
 authorized_amount_fils,final_amount_fils,cash_status)
values ('cbbb4b94-ac92-49b9-8b43-1f370c783e50','84e8e5d2-4126-4c27-893b-b70e5318a180',
 'd3c3dc11-a840-4712-a6a4-599b4ae27329','cash','90532842-03bf-4644-a656-2cad3edf37d0',2550,2550,'cashSelected');
insert into public.refunds(id,payment_id,amount_fils,reason_code,requested_by_admin_id)
values ('8168236a-6a53-4a08-8dfa-f79e68fe8901','cbbb4b94-ac92-49b9-8b43-1f370c783e50',
 2550,'LOCAL unrelated evidence','d3c3dc11-a840-4712-a6a4-599b4ae27329');
insert into public.processed_webhook_events(id,provider_name,provider_event_id)
values ('8168236a-6a53-4a08-8dfa-f79e68fe8902','stripe','LOCAL-unlinked-event');
