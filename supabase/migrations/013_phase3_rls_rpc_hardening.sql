begin;

alter table public.driver_profiles
  add column if not exists rating_average numeric(3, 2) not null default 0,
  add column if not exists rating_count integer not null default 0,
  add constraint driver_profiles_rating_average_valid check (rating_average between 0 and 5),
  add constraint driver_profiles_rating_count_nonnegative check (rating_count >= 0);

create or replace function private.is_safe_json_content(
  value jsonb,
  maximum_bytes integer,
  maximum_depth integer default 8
)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  json_key text;
  child jsonb;
  normalized_key text;
begin
  if value is null
    or octet_length(value::text) > maximum_bytes
    or maximum_depth < 0 then
    return false;
  end if;

  case jsonb_typeof(value)
    when 'object' then
      if (select count(*) from jsonb_object_keys(value)) > 32 then
        return false;
      end if;
      for json_key, child in select entry.key, entry.value from jsonb_each(value) as entry
      loop
        normalized_key := lower(regexp_replace(json_key, '[^a-z0-9]', '', 'g'));
        if json_key !~ '^[a-z][a-z0-9_]{0,63}$'
          or normalized_key in (
            'token', 'accesstoken', 'authorization', 'password', 'secret',
            'cardnumber', 'pan', 'cvv', 'cvc', 'latitude', 'longitude', 'lat', 'lng',
            'message', 'subject', 'body', 'comment', 'resolutionsummary',
            'safepayload', 'rawwwebhookpayload', 'rawwhookpayload', 'rawwebhookpayload',
            'pickup', 'destination', 'location', 'route'
          )
          or not private.is_safe_json_content(child, maximum_bytes, maximum_depth - 1) then
          return false;
        end if;
      end loop;
      return true;
    when 'array' then
      if jsonb_array_length(value) > 32 then
        return false;
      end if;
      for child in select item.value from jsonb_array_elements(value) as item
      loop
        if not private.is_safe_json_content(child, maximum_bytes, maximum_depth - 1) then
          return false;
        end if;
      end loop;
      return true;
    when 'string' then
      return char_length(value #>> '{}') <= 512;
    when 'number', 'boolean', 'null' then
      return true;
    else
      return false;
  end case;
end;
$$;

create or replace function private.is_safe_notification_payload(value jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(value) = 'object'
    and private.is_safe_json_content(value, 2048);
$$;

create or replace function private.is_safe_audit_data(value jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(value) = 'object'
    and private.is_safe_json_content(value, 2048);
$$;

alter table public.audit_records
  add constraint audit_records_previous_data_safe check (private.is_safe_audit_data(previous_data)),
  add constraint audit_records_new_data_safe check (private.is_safe_audit_data(new_data)),
  add constraint audit_records_request_context_safe check (private.is_safe_audit_data(request_context));

create or replace function private.write_audit_record(
  audit_actor_user_id uuid,
  audit_action text,
  audit_target_user_id uuid,
  audit_reason text,
  audit_previous_data jsonb,
  audit_new_data jsonb,
  audit_request_context jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_safe_audit_data(coalesce(audit_previous_data, '{}'::jsonb))
    or not private.is_safe_audit_data(coalesce(audit_new_data, '{}'::jsonb))
    or not private.is_safe_audit_data(coalesce(audit_request_context, '{}'::jsonb)) then
    raise exception using errcode = '22023', message = 'Audit data must contain only bounded safe metadata.';
  end if;

  insert into public.audit_records (
    actor_user_id, action, target_user_id, audit_reason,
    previous_data, new_data, request_context
  ) values (
    audit_actor_user_id, audit_action, audit_target_user_id, audit_reason,
    coalesce(audit_previous_data, '{}'::jsonb),
    coalesce(audit_new_data, '{}'::jsonb),
    coalesce(audit_request_context, '{}'::jsonb)
  );
end;
$$;

update public.driver_profiles as profiles
set rating_average = aggregates.rating_average,
    rating_count = aggregates.rating_count
from (
  select ratee_user_id, round(avg(score)::numeric, 2)::numeric(3, 2) as rating_average,
    count(*)::integer as rating_count
  from public.ratings
  group by ratee_user_id
) as aggregates
where profiles.user_id = aggregates.ratee_user_id;

create or replace function private.refresh_driver_rating_aggregate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  aggregate_average numeric(3, 2);
  aggregate_count integer;
begin
  perform 1 from public.driver_profiles where user_id = new.ratee_user_id for update;
  if not found then
    raise exception using errcode = '23503', message = 'Rating ratee Driver was not found.';
  end if;

  select round(avg(score)::numeric, 2)::numeric(3, 2), count(*)::integer
  into aggregate_average, aggregate_count
  from public.ratings
  where ratee_user_id = new.ratee_user_id;

  update public.driver_profiles
  set rating_average = coalesce(aggregate_average, 0), rating_count = aggregate_count
  where user_id = new.ratee_user_id;
  return new;
end;
$$;

drop trigger if exists ratings_refresh_driver_aggregate on public.ratings;
create trigger ratings_refresh_driver_aggregate
after insert on public.ratings
for each row execute function private.refresh_driver_rating_aggregate();

create or replace function public.rider_create_rating(
  target_trip_id uuid,
  requested_score smallint,
  requested_comment text default null,
  requested_feedback_tags jsonb default '[]'::jsonb
)
returns public.ratings
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  target_trip public.trips%rowtype;
  result public.ratings%rowtype;
  normalized_comment text := nullif(btrim(requested_comment), '');
  normalized_tags jsonb := coalesce(requested_feedback_tags, '[]'::jsonb);
begin
  caller_id := private.require_nonblocked_rider();
  select * into target_trip from public.trips where id = target_trip_id for share;
  if not found or target_trip.status <> 'completed' or target_trip.rider_id <> caller_id then
    raise exception using errcode = '42501', message = 'Only the completed Trip Rider can create this Rating.';
  end if;
  if requested_score not between 1 and 5 or not private.is_valid_feedback_tags(normalized_tags) then
    raise exception using errcode = '22023', message = 'Rating score or feedback tags are invalid.';
  end if;
  if normalized_comment is not null and char_length(normalized_comment) not between 1 and 1000 then
    raise exception using errcode = '22023', message = 'Rating comment is invalid.';
  end if;

  insert into public.ratings (trip_id, rater_user_id, ratee_user_id, score, comment, feedback_tags)
  values (target_trip.id, caller_id, target_trip.driver_id, requested_score, normalized_comment, normalized_tags)
  on conflict (trip_id) do nothing returning * into result;
  if not found then
    select * into result from public.ratings where trip_id = target_trip.id for share;
    if result.rater_user_id <> caller_id then
      raise exception using errcode = '42501', message = 'Rating already belongs to another Rider.';
    end if;
    if result.score <> requested_score
      or result.comment is distinct from normalized_comment
      or result.feedback_tags <> normalized_tags then
      perform private.write_audit_record(caller_id, 'rating.idempotency_payload_mismatch', target_trip.driver_id, null,
        jsonb_build_object('trip_id', target_trip.id, 'rating_id', result.id),
        jsonb_build_object('trip_id', target_trip.id));
      raise exception using errcode = '55000', message = 'Rating retry does not match the existing Rating.';
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
returns public.notifications
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.notifications%rowtype;
  normalized_type text := btrim(requested_type_code);
  normalized_title text := btrim(requested_title);
  normalized_body text := btrim(requested_body);
  normalized_payload jsonb := coalesce(requested_safe_payload, '{}'::jsonb);
  normalized_key text := nullif(btrim(requested_deduplication_key), '');
begin
  if not exists (select 1 from public.users where id = target_recipient_user_id) then
    raise exception using errcode = '23503', message = 'Notification recipient does not exist.';
  end if;
  insert into public.notifications (recipient_user_id, type_code, title, body, safe_payload, expires_at, deduplication_key)
  values (target_recipient_user_id, normalized_type, normalized_title, normalized_body,
    normalized_payload, requested_expires_at, normalized_key)
  on conflict (recipient_user_id, type_code, deduplication_key) where deduplication_key is not null do nothing
  returning * into result;
  if not found then
    select * into result from public.notifications
    where recipient_user_id = target_recipient_user_id
      and type_code = normalized_type and deduplication_key = normalized_key
    for share;
    if result.title <> normalized_title or result.body <> normalized_body
      or result.safe_payload <> normalized_payload or result.expires_at is distinct from requested_expires_at then
      perform private.write_audit_record(null, 'notification.idempotency_payload_mismatch', target_recipient_user_id, null,
        jsonb_build_object('type_code', normalized_type), jsonb_build_object('type_code', normalized_type));
      raise exception using errcode = '55000', message = 'Notification retry does not match the existing Notification.';
    end if;
  else
    perform private.write_audit_record(null, 'notification.created', target_recipient_user_id, null,
      '{}'::jsonb, jsonb_build_object('notification_id', result.id, 'type_code', result.type_code));
  end if;
  return result;
end;
$$;

create or replace function public.user_create_help_request(
  requested_category_code text, requested_subject text, requested_message text,
  requested_priority public.help_request_priority default 'normal', target_trip_id uuid default null,
  target_payment_id uuid default null, requested_idempotency_key text default null
)
returns public.help_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  result public.help_requests%rowtype;
  normalized_category text := btrim(requested_category_code);
  normalized_subject text := btrim(requested_subject);
  normalized_message text := btrim(requested_message);
  normalized_key text := nullif(btrim(requested_idempotency_key), '');
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
  values (caller_id, normalized_category, normalized_subject, normalized_message, requested_priority,
    target_trip_id, target_payment_id, normalized_key)
  on conflict (requester_user_id, idempotency_key) where idempotency_key is not null do nothing returning * into result;
  if not found then
    select * into result from public.help_requests
    where requester_user_id = caller_id and idempotency_key = normalized_key
    for share;
    if result.category_code <> normalized_category or result.subject <> normalized_subject
      or result.message <> normalized_message or result.priority <> requested_priority
      or result.trip_id is distinct from target_trip_id or result.payment_id is distinct from target_payment_id then
      perform private.write_audit_record(caller_id, 'help_request.idempotency_payload_mismatch', caller_id, null,
        jsonb_build_object('help_request_id', result.id), jsonb_build_object('help_request_id', result.id));
      raise exception using errcode = '55000', message = 'HelpRequest retry does not match the existing HelpRequest.';
    end if;
  else
    perform private.write_audit_record(caller_id, 'help_request.created', caller_id, null,
      '{}'::jsonb, jsonb_build_object('help_request_id', result.id, 'category_code', result.category_code));
  end if;
  return result;
end;
$$;

do $$
declare
  function_record record;
begin
  for function_record in
    select p.oid::regprocedure as signature
    from pg_proc as p
    join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
  loop
    execute format('revoke all on function %s from public', function_record.signature);
  end loop;
end;
$$;

revoke all on function private.is_safe_json_content(jsonb, integer, integer),
  private.is_safe_audit_data(jsonb), private.refresh_driver_rating_aggregate()
from public, anon, authenticated, service_role;

comment on column public.driver_profiles.rating_average is 'Trusted aggregate refreshed transactionally when a Rating is created.';
comment on column public.driver_profiles.rating_count is 'Trusted aggregate refreshed transactionally when a Rating is created.';

commit;
