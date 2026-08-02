begin;

create type public.help_request_status as enum ('open', 'assigned', 'resolved');
create type public.help_request_priority as enum ('low', 'normal', 'high', 'urgent');

create or replace function private.is_valid_feedback_tags(value jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select jsonb_typeof(value) = 'array'
    and jsonb_array_length(value) <= 10
    and not exists (
      select 1 from jsonb_array_elements(value) as tag
      where jsonb_typeof(tag) <> 'string'
        or char_length(btrim(tag #>> '{}')) not between 1 and 32
        or tag #>> '{}' !~ '^[a-z0-9][a-z0-9_-]*$'
    );
$$;

create or replace function private.is_safe_notification_payload(value jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select jsonb_typeof(value) = 'object'
    and char_length(value::text) <= 2048
    and not exists (
      select 1 from jsonb_object_keys(value) as key
      where key !~ '^[a-z][a-z0-9_]{0,63}$'
        or key in ('access_token', 'authorization', 'card_number', 'cvv', 'password', 'secret', 'token')
    );
$$;

create table public.ratings (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null unique references public.trips (id) on delete restrict,
  rater_user_id uuid not null references public.rider_profiles (user_id) on delete restrict,
  ratee_user_id uuid not null references public.driver_profiles (user_id) on delete restrict,
  score smallint not null,
  comment text,
  feedback_tags jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  constraint ratings_score_valid check (score between 1 and 5),
  constraint ratings_comment_bounded check (comment is null or char_length(btrim(comment)) between 1 and 1000),
  constraint ratings_feedback_tags_valid check (private.is_valid_feedback_tags(feedback_tags))
);
create index ratings_ratee_created_at_idx on public.ratings (ratee_user_id, created_at desc);
create index ratings_rater_created_at_idx on public.ratings (rater_user_id, created_at desc);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_user_id uuid not null references public.users (id) on delete restrict,
  type_code text not null,
  title text not null,
  body text not null,
  safe_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  expires_at timestamptz,
  deduplication_key text,
  constraint notifications_type_code_valid check (type_code ~ '^[a-z][a-z0-9_.]{0,63}$'),
  constraint notifications_title_bounded check (char_length(btrim(title)) between 1 and 120),
  constraint notifications_body_bounded check (char_length(btrim(body)) between 1 and 1000),
  constraint notifications_payload_valid check (private.is_safe_notification_payload(safe_payload)),
  constraint notifications_expiry_valid check (expires_at is null or expires_at > created_at),
  constraint notifications_deduplication_key_bounded check (deduplication_key is null or char_length(btrim(deduplication_key)) between 1 and 128)
);
create unique index notifications_recipient_type_deduplication_unique
  on public.notifications (recipient_user_id, type_code, deduplication_key)
  where deduplication_key is not null;
create index notifications_recipient_unread_idx on public.notifications (recipient_user_id, created_at desc)
  where read_at is null;
create index notifications_recipient_created_at_idx on public.notifications (recipient_user_id, created_at desc);

create table public.help_requests (
  id uuid primary key default gen_random_uuid(),
  requester_user_id uuid not null references public.users (id) on delete restrict,
  category_code text not null,
  subject text not null,
  message text not null,
  priority public.help_request_priority not null default 'normal',
  trip_id uuid references public.trips (id) on delete restrict,
  payment_id uuid references public.payments (id) on delete restrict,
  status public.help_request_status not null default 'open',
  assigned_admin_id uuid references public.users (id) on delete restrict,
  resolution_summary text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  version integer not null default 1,
  idempotency_key text,
  constraint help_requests_category_valid check (category_code in ('trip', 'payment', 'safety', 'account', 'other')),
  constraint help_requests_subject_bounded check (char_length(btrim(subject)) between 1 and 160),
  constraint help_requests_message_bounded check (char_length(btrim(message)) between 1 and 4000),
  constraint help_requests_resolution_valid check (
    (status = 'resolved' and char_length(btrim(coalesce(resolution_summary, ''))) between 1 and 1000 and resolved_at is not null)
    or (status <> 'resolved' and resolution_summary is null and resolved_at is null)
  ),
  constraint help_requests_assignment_valid check (
    (status = 'open' and assigned_admin_id is null) or (status in ('assigned', 'resolved') and assigned_admin_id is not null)
  ),
  constraint help_requests_version_positive check (version > 0),
  constraint help_requests_idempotency_key_bounded check (idempotency_key is null or char_length(btrim(idempotency_key)) between 1 and 128)
);
create unique index help_requests_requester_idempotency_unique
  on public.help_requests (requester_user_id, idempotency_key) where idempotency_key is not null;
create index help_requests_requester_created_at_idx on public.help_requests (requester_user_id, created_at desc);
create index help_requests_admin_status_updated_at_idx on public.help_requests (status, updated_at desc);
create index help_requests_assigned_admin_status_idx on public.help_requests (assigned_admin_id, status, updated_at desc) where assigned_admin_id is not null;
create index help_requests_trip_idx on public.help_requests (trip_id) where trip_id is not null;
create index help_requests_payment_idx on public.help_requests (payment_id) where payment_id is not null;

create trigger help_requests_bump_version before update on public.help_requests
for each row execute function private.bump_optimistic_version();
create trigger help_requests_set_updated_at before update on public.help_requests
for each row execute function public.set_updated_at();

create or replace function private.require_nonblocked_rider_or_driver()
returns uuid language plpgsql security definer set search_path = '' as $$
declare caller_id uuid := auth.uid();
begin
  if caller_id is null or not exists (
    select 1 from public.users where id = caller_id and role in ('rider', 'driver') and not is_blocked
  ) then
    raise exception using errcode = '42501', message = 'Only a non-blocked Rider or Driver can create help requests.';
  end if;
  return caller_id;
end;
$$;

create or replace function public.rider_create_rating(
  target_trip_id uuid, requested_score smallint, requested_comment text default null, requested_feedback_tags jsonb default '[]'::jsonb
)
returns public.ratings language plpgsql security definer set search_path = '' as $$
declare caller_id uuid; target_trip public.trips%rowtype; result public.ratings%rowtype;
begin
  caller_id := private.require_nonblocked_rider();
  select * into target_trip from public.trips where id = target_trip_id;
  if not found or target_trip.status <> 'completed' or target_trip.rider_id <> caller_id then
    raise exception using errcode = '42501', message = 'Only the completed Trip Rider can create this Rating.';
  end if;
  if requested_score not between 1 and 5 or not private.is_valid_feedback_tags(coalesce(requested_feedback_tags, '[]'::jsonb)) then
    raise exception using errcode = '22023', message = 'Rating score or feedback tags are invalid.';
  end if;
  if requested_comment is not null and char_length(btrim(requested_comment)) not between 1 and 1000 then
    raise exception using errcode = '22023', message = 'Rating comment is invalid.';
  end if;
  insert into public.ratings (trip_id, rater_user_id, ratee_user_id, score, comment, feedback_tags)
  values (target_trip.id, caller_id, target_trip.driver_id, requested_score, nullif(btrim(requested_comment), ''), coalesce(requested_feedback_tags, '[]'::jsonb))
  on conflict (trip_id) do nothing returning * into result;
  if not found then
    select * into result from public.ratings where trip_id = target_trip.id;
    if result.rater_user_id <> caller_id then
      raise exception using errcode = '42501', message = 'Rating already belongs to another Rider.';
    end if;
  else
    perform private.write_audit_record(caller_id, 'rating.created', target_trip.driver_id, null,
      jsonb_build_object('trip_id', target_trip.id), jsonb_build_object('rating_id', result.id, 'score', result.score));
  end if;
  return result;
end;
$$;

create or replace function public.backend_create_notification(
  target_recipient_user_id uuid, requested_type_code text, requested_title text, requested_body text,
  requested_safe_payload jsonb default '{}'::jsonb, requested_expires_at timestamptz default null,
  requested_deduplication_key text default null
)
returns public.notifications language plpgsql security definer set search_path = '' as $$
declare result public.notifications%rowtype;
begin
  if not exists (select 1 from public.users where id = target_recipient_user_id) then
    raise exception using errcode = '23503', message = 'Notification recipient does not exist.';
  end if;
  insert into public.notifications (recipient_user_id, type_code, title, body, safe_payload, expires_at, deduplication_key)
  values (target_recipient_user_id, btrim(requested_type_code), btrim(requested_title), btrim(requested_body),
    coalesce(requested_safe_payload, '{}'::jsonb), requested_expires_at, nullif(btrim(requested_deduplication_key), ''))
  on conflict (recipient_user_id, type_code, deduplication_key) where deduplication_key is not null do nothing returning * into result;
  if not found then
    select * into result from public.notifications where recipient_user_id = target_recipient_user_id
      and type_code = btrim(requested_type_code) and deduplication_key = nullif(btrim(requested_deduplication_key), '');
  else
    perform private.write_audit_record(null, 'notification.created', target_recipient_user_id, null,
      '{}'::jsonb, jsonb_build_object('notification_id', result.id, 'type_code', result.type_code));
  end if;
  return result;
end;
$$;

create or replace function public.user_mark_notification_read(target_notification_id uuid)
returns public.notifications language plpgsql security definer set search_path = '' as $$
declare caller_id uuid := auth.uid(); result public.notifications%rowtype;
begin
  if caller_id is null or not exists (select 1 from public.users where id = caller_id and not is_blocked) then
    raise exception using errcode = '42501', message = 'Only a non-blocked authenticated user can read notifications.';
  end if;
  select * into result from public.notifications where id = target_notification_id and recipient_user_id = caller_id for update;
  if not found then raise exception using errcode = '42501', message = 'Notification does not belong to this user.'; end if;
  if result.read_at is null then
    update public.notifications set read_at = now() where id = result.id returning * into result;
    perform private.write_audit_record(caller_id, 'notification.read', caller_id, null,
      jsonb_build_object('notification_id', result.id), jsonb_build_object('read_at', result.read_at));
  end if;
  return result;
end;
$$;

create or replace function public.user_create_help_request(
  requested_category_code text, requested_subject text, requested_message text,
  requested_priority public.help_request_priority default 'normal', target_trip_id uuid default null,
  target_payment_id uuid default null, requested_idempotency_key text default null
)
returns public.help_requests language plpgsql security definer set search_path = '' as $$
declare caller_id uuid; result public.help_requests%rowtype;
begin
  caller_id := private.require_nonblocked_rider_or_driver();
  if target_trip_id is not null and not exists (
    select 1 from public.trips where id = target_trip_id and (rider_id = caller_id or driver_id = caller_id)
  ) then raise exception using errcode = '42501', message = 'Help request Trip must belong to the requester.'; end if;
  if target_payment_id is not null and not exists (
    select 1 from public.payments where id = target_payment_id and rider_id = caller_id
  ) then raise exception using errcode = '42501', message = 'Help request Payment must belong to the requester.'; end if;
  if target_trip_id is not null and target_payment_id is not null and not exists (
    select 1 from public.payments where id = target_payment_id and trip_id = target_trip_id
  ) then raise exception using errcode = '22023', message = 'Help request Payment must match its Trip.'; end if;
  insert into public.help_requests (requester_user_id, category_code, subject, message, priority, trip_id, payment_id, idempotency_key)
  values (caller_id, btrim(requested_category_code), btrim(requested_subject), btrim(requested_message), requested_priority,
    target_trip_id, target_payment_id, nullif(btrim(requested_idempotency_key), ''))
  on conflict (requester_user_id, idempotency_key) where idempotency_key is not null do nothing returning * into result;
  if not found then
    select * into result from public.help_requests where requester_user_id = caller_id
      and idempotency_key = nullif(btrim(requested_idempotency_key), '');
  else
    perform private.write_audit_record(caller_id, 'help_request.created', caller_id, null,
      '{}'::jsonb, jsonb_build_object('help_request_id', result.id, 'category_code', result.category_code));
  end if;
  return result;
end;
$$;

create or replace function public.admin_assign_help_request(
  target_help_request_id uuid, expected_version integer, target_admin_id uuid
)
returns public.help_requests language plpgsql security definer set search_path = '' as $$
declare caller_id uuid; result public.help_requests%rowtype;
begin
  caller_id := private.require_nonblocked_admin();
  if expected_version is null or expected_version < 1 then raise exception using errcode = '22023', message = 'A positive expected version is required.'; end if;
  if not exists (select 1 from public.users where id = target_admin_id and role = 'admin' and not is_blocked) then
    raise exception using errcode = '22023', message = 'Help request assignee must be a non-blocked Admin.';
  end if;
  select * into result from public.help_requests where id = target_help_request_id for update;
  if not found or result.status <> 'open' then raise exception using errcode = '55000', message = 'Only open HelpRequests can be assigned.'; end if;
  if result.version <> expected_version then raise exception using errcode = '40001', message = 'Help request version is stale.'; end if;
  update public.help_requests set status = 'assigned', assigned_admin_id = target_admin_id where id = result.id returning * into result;
  perform private.write_audit_record(caller_id, 'help_request.assigned', result.requester_user_id, null,
    jsonb_build_object('help_request_id', result.id, 'version', expected_version), jsonb_build_object('assigned_admin_id', target_admin_id, 'version', result.version));
  return result;
end;
$$;

create or replace function public.admin_resolve_help_request(
  target_help_request_id uuid, expected_version integer, requested_resolution_summary text
)
returns public.help_requests language plpgsql security definer set search_path = '' as $$
declare caller_id uuid; result public.help_requests%rowtype;
begin
  caller_id := private.require_nonblocked_admin();
  if expected_version is null or expected_version < 1 then raise exception using errcode = '22023', message = 'A positive expected version is required.'; end if;
  if char_length(btrim(coalesce(requested_resolution_summary, ''))) not between 1 and 1000 then
    raise exception using errcode = '22023', message = 'A bounded resolution summary is required.';
  end if;
  select * into result from public.help_requests where id = target_help_request_id for update;
  if not found or result.status <> 'assigned' then raise exception using errcode = '55000', message = 'Only assigned HelpRequests can be resolved.'; end if;
  if result.version <> expected_version then raise exception using errcode = '40001', message = 'Help request version is stale.'; end if;
  update public.help_requests set status = 'resolved', resolution_summary = btrim(requested_resolution_summary), resolved_at = now()
    where id = result.id returning * into result;
  perform private.write_audit_record(caller_id, 'help_request.resolved', result.requester_user_id, null,
    jsonb_build_object('help_request_id', result.id, 'version', expected_version), jsonb_build_object('version', result.version));
  return result;
end;
$$;

alter table public.ratings enable row level security;
alter table public.notifications enable row level security;
alter table public.help_requests enable row level security;

create policy ratings_safe_select on public.ratings for select to authenticated using (
  exists (select 1 from public.users where id = auth.uid() and not is_blocked and (
    id = ratings.rater_user_id or id = ratings.ratee_user_id or role = 'admin'
  ))
);
create policy notifications_recipient_or_admin_select on public.notifications for select to authenticated using (
  exists (select 1 from public.users where id = auth.uid() and not is_blocked and (id = notifications.recipient_user_id or role = 'admin'))
);
create policy help_requests_requester_or_admin_select on public.help_requests for select to authenticated using (
  exists (select 1 from public.users where id = auth.uid() and not is_blocked and (id = help_requests.requester_user_id or role = 'admin'))
);

revoke all on table public.ratings, public.notifications, public.help_requests from public, anon, authenticated, service_role;
grant select on table public.ratings, public.notifications, public.help_requests to authenticated;
grant select, insert, update, delete on table public.ratings, public.notifications, public.help_requests to service_role;
revoke all on function private.is_valid_feedback_tags(jsonb), private.is_safe_notification_payload(jsonb), private.require_nonblocked_rider_or_driver() from public, anon, authenticated, service_role;
revoke all on function public.rider_create_rating(uuid, smallint, text, jsonb), public.backend_create_notification(uuid, text, text, text, jsonb, timestamptz, text), public.user_mark_notification_read(uuid), public.user_create_help_request(text, text, text, public.help_request_priority, uuid, uuid, text), public.admin_assign_help_request(uuid, integer, uuid), public.admin_resolve_help_request(uuid, integer, text) from public, anon, authenticated, service_role;
grant execute on function public.rider_create_rating(uuid, smallint, text, jsonb), public.user_mark_notification_read(uuid), public.user_create_help_request(text, text, text, public.help_request_priority, uuid, uuid, text), public.admin_assign_help_request(uuid, integer, uuid), public.admin_resolve_help_request(uuid, integer, text) to authenticated;
grant execute on function public.backend_create_notification(uuid, text, text, text, jsonb, timestamptz, text) to service_role;

commit;
