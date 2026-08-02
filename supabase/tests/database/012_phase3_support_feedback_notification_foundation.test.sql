begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
values
  ('00000000-0000-0000-0000-000000000000', 'c1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'support-rider@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Support Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'c1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'support-other-rider@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Other Rider"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'c1000000-0000-0000-0000-000000000011', 'authenticated', 'authenticated', 'support-driver@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Support Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'c1000000-0000-0000-0000-000000000012', 'authenticated', 'authenticated', 'support-other-driver@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Other Driver"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'c1000000-0000-0000-0000-000000000020', 'authenticated', 'authenticated', 'support-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Support Admin"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'c1000000-0000-0000-0000-000000000021', 'authenticated', 'authenticated', 'support-other-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Other Admin"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'c1000000-0000-0000-0000-000000000030', 'authenticated', 'authenticated', 'support-blocked@example.com', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Blocked Rider"}', now(), now(), '', '', '', '');
update public.users set role = 'driver' where id in ('c1000000-0000-0000-0000-000000000011', 'c1000000-0000-0000-0000-000000000012');
update public.users set role = 'admin' where id in ('c1000000-0000-0000-0000-000000000020', 'c1000000-0000-0000-0000-000000000021');
update public.users set is_blocked = true where id = 'c1000000-0000-0000-0000-000000000030';
delete from public.rider_profiles where user_id in ('c1000000-0000-0000-0000-000000000011', 'c1000000-0000-0000-0000-000000000012', 'c1000000-0000-0000-0000-000000000020', 'c1000000-0000-0000-0000-000000000021');
insert into public.driver_profiles (user_id, approval_status, is_online, is_available) values
  ('c1000000-0000-0000-0000-000000000011', 'approved', false, false),
  ('c1000000-0000-0000-0000-000000000012', 'approved', false, false);
insert into public.vehicles (id, driver_id, vehicle_type_code, make, model, color, registration_plate, seat_capacity, is_active) values
  ('c1100000-0000-0000-0000-000000000011', 'c1000000-0000-0000-0000-000000000011', 'economy', 'Toyota', 'Camry', 'White', 'SF 011', 4, true),
  ('c1100000-0000-0000-0000-000000000012', 'c1000000-0000-0000-0000-000000000012', 'economy', 'Toyota', 'Corolla', 'Black', 'SF 012', 4, true);
insert into public.pricing_configurations (id, vehicle_type_code, pricing_version, base_fare_fils, per_kilometer_fils, per_minute_fils, per_stop_fils, minimum_fare_fils, is_active)
values ('c1200000-0000-0000-0000-000000000001', 'economy', 1, 500, 300, 50, 200, 1000, true);
insert into public.booking_requests (id, rider_id, pickup, destination, vehicle_type_code, payment_method) values
  ('c1200000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 'economy', 'cash'),
  ('c1200000-0000-0000-0000-000000000012', 'c1000000-0000-0000-0000-000000000002', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 'economy', 'cash');
insert into public.fare_quotes (id, booking_request_id, rider_id, status, pickup, destination, route_distance_meters, route_duration_seconds, vehicle_type_code, breakdown, fixed_fare_fils, pricing_configuration_id, pricing_version, quote_version, locked_at) values
  ('c1200000-0000-0000-0000-000000000003', 'c1200000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001', 'locked', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 1000, 300, 'economy', '{}', 1000, 'c1200000-0000-0000-0000-000000000001', 1, 1, now()),
  ('c1200000-0000-0000-0000-000000000013', 'c1200000-0000-0000-0000-000000000012', 'c1000000-0000-0000-0000-000000000002', 'locked', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 1000, 300, 'economy', '{}', 1000, 'c1200000-0000-0000-0000-000000000001', 1, 1, now());
update public.booking_requests set fare_quote_id = case id when 'c1200000-0000-0000-0000-000000000002' then 'c1200000-0000-0000-0000-000000000003'::uuid else 'c1200000-0000-0000-0000-000000000013'::uuid end;
insert into public.trips (id, booking_request_id, fare_quote_id, rider_id, driver_id, vehicle_id, status, payment_method, pickup, destination, route_distance_meters, route_duration_seconds, original_fare_fils, current_fare_fils, completed_at) values
  ('c1200000-0000-0000-0000-000000000004', 'c1200000-0000-0000-0000-000000000002', 'c1200000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000011', 'c1100000-0000-0000-0000-000000000011', 'completed', 'cash', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 1000, 300, 1000, 1000, now()),
  ('c1200000-0000-0000-0000-000000000014', 'c1200000-0000-0000-0000-000000000012', 'c1200000-0000-0000-0000-000000000013', 'c1000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000012', 'c1100000-0000-0000-0000-000000000012', 'accepted', 'cash', '{"latitude":31.95,"longitude":35.93}', '{"latitude":31.96,"longitude":35.94}', 1000, 300, 1000, 1000, null);
insert into public.payments (id, booking_request_id, trip_id, rider_id, method, fare_quote_id, authorized_amount_fils, final_amount_fils, cash_status) values
  ('c1200000-0000-0000-0000-000000000005', 'c1200000-0000-0000-0000-000000000002', 'c1200000-0000-0000-0000-000000000004', 'c1000000-0000-0000-0000-000000000001', 'cash', 'c1200000-0000-0000-0000-000000000003', 1000, 1000, 'cashSelected');

select has_table('public', 'ratings', 'ratings table exists');
select has_table('public', 'notifications', 'notifications table exists');
select has_table('public', 'help_requests', 'help requests table exists');
select col_is_pk('public', 'ratings', 'id', 'ratings have UUID primary keys');
select has_fk('public', 'help_requests', 'help requests link users, trips, and payments');
select has_index('public', 'ratings', 'ratings_ratee_created_at_idx', 'received rating index exists');
select has_index('public', 'notifications', 'notifications_recipient_unread_idx', 'unread notification index exists');
select has_index('public', 'help_requests', 'help_requests_admin_status_updated_at_idx', 'help request assignment index exists');
select ok((select relrowsecurity from pg_class where oid = 'public.ratings'::regclass), 'ratings RLS is enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.notifications'::regclass), 'notifications RLS is enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.help_requests'::regclass), 'help requests RLS is enabled');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.rider_create_rating('c1200000-0000-0000-0000-000000000004', 5::smallint, 'Excellent trip', '["clean_car","safe_driver"]'::jsonb)$$, 'completed Trip Rider creates a Rating');
select is((select count(*) from public.ratings), 1::bigint, 'Rider reads submitted rating');
select is((select ratee_user_id from public.ratings), 'c1000000-0000-0000-0000-000000000011'::uuid, 'assigned Driver is the only ratee');
select lives_ok($$select public.rider_create_rating('c1200000-0000-0000-0000-000000000004', 5::smallint, 'Excellent trip', '["clean_car","safe_driver"]'::jsonb)$$, 'duplicate rating is repeat-safe');
select is((select count(*) from public.ratings), 1::bigint, 'repeat-safe Rating does not duplicate');
select throws_ok($$select public.rider_create_rating('c1200000-0000-0000-0000-000000000004', 0::smallint, null, '[]'::jsonb)$$, '22023', 'Rating score or feedback tags are invalid.', 'score below one is denied');
select throws_ok($$select public.rider_create_rating('c1200000-0000-0000-0000-000000000004', 6::smallint, null, '[]'::jsonb)$$, '22023', 'Rating score or feedback tags are invalid.', 'score above five is denied');
select throws_ok($$select public.rider_create_rating('c1200000-0000-0000-0000-000000000004', 5::smallint, repeat('x', 1001), '[]'::jsonb)$$, '22023', 'Rating comment is invalid.', 'rating comment is bounded');
select throws_ok($$select public.rider_create_rating('c1200000-0000-0000-0000-000000000004', 5::smallint, null, '["bad tag"]'::jsonb)$$, '22023', 'Rating score or feedback tags are invalid.', 'rating tags are structurally validated');
select throws_ok($$insert into public.ratings (trip_id, rater_user_id, ratee_user_id, score) values ('c1200000-0000-0000-0000-000000000014', auth.uid(), 'c1000000-0000-0000-0000-000000000012', 5)$$, '42501', null, 'direct Rating insert is denied');
select throws_ok($$update public.ratings set score = 1$$, '42501', null, 'direct Rating update is denied');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.rider_create_rating('c1200000-0000-0000-0000-000000000004', 5::smallint, null, '[]'::jsonb)$$, '42501', 'Only the completed Trip Rider can create this Rating.', 'wrong Rider is denied');
select throws_ok($$select public.rider_create_rating('c1200000-0000-0000-0000-000000000014', 5::smallint, null, '[]'::jsonb)$$, '42501', 'Only the completed Trip Rider can create this Rating.', 'non-completed Trip is denied');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000011', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.ratings), 1::bigint, 'Driver reads received Rating only');
select throws_ok($$select public.rider_create_rating('c1200000-0000-0000-0000-000000000004', 5::smallint, null, '[]'::jsonb)$$, '42501', 'Only a non-blocked Rider can manage bookings.', 'Driver-to-Rider ratings are impossible');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000020', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.ratings), 1::bigint, 'Admin has Rating moderation visibility');
reset role;

set local role service_role;
select lives_ok($$select public.backend_create_notification('c1000000-0000-0000-0000-000000000001', 'trip.completed', 'Trip complete', 'Your trip is complete.', '{"trip_id":"c1200000-0000-0000-0000-000000000004"}', null, 'trip-completed-4')$$, 'service role creates notification');
select lives_ok($$select public.backend_create_notification('c1000000-0000-0000-0000-000000000001', 'trip.completed', 'Trip complete', 'Your trip is complete.', '{"trip_id":"c1200000-0000-0000-0000-000000000004"}', null, 'trip-completed-4')$$, 'notification deduplication is repeat-safe');
select is((select count(*) from public.notifications), 1::bigint, 'notification deduplication prevents duplicates');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.notifications), 1::bigint, 'recipient reads own notification');
select throws_ok($$select public.backend_create_notification(auth.uid(), 'test', 'Title', 'Body')$$, '42501', null, 'notification creation is backend-only');
select lives_ok($$select public.user_mark_notification_read((select id from public.notifications))$$, 'recipient marks notification read');
select ok((select read_at is not null from public.notifications), 'read timestamp is server-controlled');
select lives_ok($$select public.user_mark_notification_read((select id from public.notifications))$$, 'mark-read is idempotent');
select throws_ok($$update public.notifications set recipient_user_id = 'c1000000-0000-0000-0000-000000000002', title = 'Changed'$$, '42501', null, 'users cannot edit notification content or recipient');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.notifications), 0::bigint, 'notification cross-user reads are isolated');
select throws_ok($$select public.user_mark_notification_read((select id from public.notifications limit 1))$$, '42501', 'Notification does not belong to this user.', 'cross-user mark-read is denied');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000020', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.notifications), 1::bigint, 'Admin has restricted notification visibility');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.user_create_help_request('trip', 'Late pickup', 'The driver arrived late.', 'normal', 'c1200000-0000-0000-0000-000000000004', 'c1200000-0000-0000-0000-000000000005', 'help-1')$$, 'Rider creates own linked HelpRequest');
select lives_ok($$select public.user_create_help_request('trip', 'Late pickup', 'The driver arrived late.', 'normal', 'c1200000-0000-0000-0000-000000000004', 'c1200000-0000-0000-0000-000000000005', 'help-1')$$, 'HelpRequest creation is idempotent');
select is((select count(*) from public.help_requests), 1::bigint, 'HelpRequest idempotency prevents duplicates');
select throws_ok($$select public.user_create_help_request('trip', repeat('x', 161), 'Message', 'normal')$$, '23514', null, 'HelpRequest fields are bounded');
select throws_ok($$select public.user_create_help_request('trip', 'Other trip', 'Message', 'normal', 'c1200000-0000-0000-0000-000000000014')$$, '42501', 'Help request Trip must belong to the requester.', 'unrelated Trip is rejected');
select throws_ok($$insert into public.help_requests (requester_user_id, category_code, subject, message) values (auth.uid(), 'trip', 'Direct', 'Direct write')$$, '42501', null, 'direct HelpRequest insert is denied');
select is((select count(*) from public.help_requests), 1::bigint, 'Rider reads own HelpRequest');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000011', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.user_create_help_request('safety', 'Safety concern', 'I need support.', 'high', 'c1200000-0000-0000-0000-000000000004', null, 'driver-help-1')$$, 'Driver creates own HelpRequest');
select throws_ok($$select public.user_create_help_request('payment', 'Payment issue', 'I cannot access this payment.', 'normal', null, 'c1200000-0000-0000-0000-000000000005')$$, '42501', 'Help request Payment must belong to the requester.', 'Driver cannot link a Rider-only Payment');
select is((select count(*) from public.help_requests), 1::bigint, 'Driver reads only own HelpRequest');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is((select count(*) from public.help_requests), 0::bigint, 'HelpRequest cross-user reads are isolated');
select throws_ok($$select public.admin_assign_help_request('c1300000-0000-0000-0000-000000000001', 1, auth.uid())$$, '42501', 'Only a non-blocked Admin can manage Drivers.', 'non-Admin assignment is denied');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000020', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok($$select public.admin_assign_help_request((select id from public.help_requests where requester_user_id = 'c1000000-0000-0000-0000-000000000001'), 1, 'c1000000-0000-0000-0000-000000000021')$$, 'Admin assigns open HelpRequest');
select throws_ok($$select public.admin_resolve_help_request((select id from public.help_requests where requester_user_id = 'c1000000-0000-0000-0000-000000000001'), 1, 'Resolved')$$, '40001', 'Help request version is stale.', 'stale HelpRequest version is denied');
select throws_ok($$select public.admin_resolve_help_request((select id from public.help_requests where requester_user_id = 'c1000000-0000-0000-0000-000000000001'), 2, '')$$, '22023', 'A bounded resolution summary is required.', 'resolution summary is required');
select lives_ok($$select public.admin_resolve_help_request((select id from public.help_requests where requester_user_id = 'c1000000-0000-0000-0000-000000000001'), 2, 'The issue was reviewed and resolved.')$$, 'Admin resolves assigned HelpRequest');
select throws_ok($$select public.admin_assign_help_request((select id from public.help_requests where requester_user_id = 'c1000000-0000-0000-0000-000000000001'), 3, auth.uid())$$, '55000', 'Only open HelpRequests can be assigned.', 'terminal HelpRequest cannot reopen');
select is((select count(*) from public.help_requests), 2::bigint, 'Admin has HelpRequest moderation visibility');
reset role;
select is((select count(*) from public.audit_records where action in ('help_request.created', 'help_request.assigned', 'help_request.resolved')), 4::bigint, 'HelpRequest creation and transitions are audited');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000030', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.user_create_help_request('other', 'Blocked', 'No access.', 'normal')$$, '42501', 'Only a non-blocked Rider or Driver can create help requests.', 'blocked user is denied HelpRequest access');
select throws_ok($$select public.user_mark_notification_read('c1300000-0000-0000-0000-000000000001')$$, '42501', 'Only a non-blocked authenticated user can read notifications.', 'blocked user is denied notification access');
reset role;
set local role anon;
select throws_ok($$select public.rider_create_rating('c1200000-0000-0000-0000-000000000004', 5::smallint, null, '[]'::jsonb)$$, '42501', null, 'anonymous Rating creation is denied');
select throws_ok($$select count(*) from public.notifications$$, '42501', null, 'anonymous notification reads are denied');
reset role;

select ok(has_function_privilege('authenticated', 'public.rider_create_rating(uuid,smallint,text,jsonb)', 'EXECUTE'), 'authenticated can execute guarded Rating RPC');
select ok(has_function_privilege('authenticated', 'public.user_create_help_request(text,text,text,public.help_request_priority,uuid,uuid,text)', 'EXECUTE'), 'authenticated can execute guarded HelpRequest RPC');
select ok(not has_function_privilege('authenticated', 'public.backend_create_notification(uuid,text,text,text,jsonb,timestamp with time zone,text)', 'EXECUTE'), 'clients cannot create notifications');
select ok(has_function_privilege('service_role', 'public.backend_create_notification(uuid,text,text,text,jsonb,timestamp with time zone,text)', 'EXECUTE'), 'service role can create notifications');
select is((select count(*) from pg_proc where oid in ('public.rider_create_rating(uuid,smallint,text,jsonb)'::regprocedure, 'public.backend_create_notification(uuid,text,text,text,jsonb,timestamp with time zone,text)'::regprocedure, 'public.user_mark_notification_read(uuid)'::regprocedure, 'public.user_create_help_request(text,text,text,public.help_request_priority,uuid,uuid,text)'::regprocedure, 'public.admin_assign_help_request(uuid,integer,uuid)'::regprocedure, 'public.admin_resolve_help_request(uuid,integer,text)'::regprocedure) and prosecdef), 6::bigint, 'public checkpoint functions are SECURITY DEFINER');
select is((select count(*) from pg_proc where oid in ('public.rider_create_rating(uuid,smallint,text,jsonb)'::regprocedure, 'public.backend_create_notification(uuid,text,text,text,jsonb,timestamp with time zone,text)'::regprocedure, 'public.user_mark_notification_read(uuid)'::regprocedure, 'public.user_create_help_request(text,text,text,public.help_request_priority,uuid,uuid,text)'::regprocedure, 'public.admin_assign_help_request(uuid,integer,uuid)'::regprocedure, 'public.admin_resolve_help_request(uuid,integer,text)'::regprocedure) and array_to_string(proconfig, ',') in ('search_path=""', 'search_path=')), 6::bigint, 'public checkpoint functions have empty search paths');

select * from finish();
rollback;
