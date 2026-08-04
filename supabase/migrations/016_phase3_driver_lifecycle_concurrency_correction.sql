begin;

-- Preserve the verified transition implementation while putting lifecycle
-- serialization ahead of its accepted-assignment path.
alter function public.driver_transition_trip(uuid, public.trip_status, integer, text)
  set schema private;

create function public.driver_transition_trip(target_id uuid, requested_status public.trip_status, expected_version integer, idempotency_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare caller_id uuid := auth.uid(); locked_user public.users%rowtype; locked_profile public.driver_profiles%rowtype;
begin
  if requested_status <> 'accepted' then
    return private.driver_transition_trip(target_id, requested_status, expected_version, idempotency_key);
  end if;
  select * into locked_user from public.users where id = caller_id for update;
  select * into locked_profile from public.driver_profiles where user_id = caller_id for update;
  if caller_id is null or not found or locked_user.role <> 'driver' or locked_user.is_blocked or locked_profile.approval_status <> 'approved' then
    raise exception using errcode = '42501', message = 'Only an approved, non-blocked Driver can manage vehicles or availability.';
  end if;
  return private.driver_transition_trip(target_id, requested_status, expected_version, idempotency_key);
end;
$$;

create or replace function public.admin_reject_driver(target_user_id uuid, reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare caller_id uuid; target_user public.users%rowtype; target_profile public.driver_profiles%rowtype;
begin
  caller_id := private.require_nonblocked_admin();
  if char_length(btrim(coalesce(reason, ''))) not between 1 and 500 then raise exception using errcode = '22023', message = 'A rejection reason is required.'; end if;
  select * into target_user from public.users where id = target_user_id for update;
  select * into target_profile from public.driver_profiles where user_id = target_user_id for update;
  if not found or target_user.role <> 'driver' then raise exception using errcode = 'P0002', message = 'Target Driver account was not found.'; end if;
  caller_id := private.require_nonblocked_admin();
  perform 1 from public.trips where driver_id = target_user_id and status not in ('completed','cancelledByRider','cancelledByDriver','cancelledByAdmin','failed') for update;
  if found then raise exception using errcode = '55000', message = 'A Driver assigned to a nonterminal Trip must be terminated before rejection.'; end if;
  perform private.reconcile_driver_availability(target_user_id);
  perform set_config('ridex.audit_actor_id', caller_id::text, true); perform set_config('ridex.audit_action', 'admin.driver_rejected', true); perform set_config('ridex.audit_reason', btrim(reason), true);
  update public.driver_profiles set approval_status = 'rejected', rejection_reason = btrim(reason) where user_id = target_user_id;
  update public.driver_availability set state = 'offline', vehicle_id = null, reserved_booking_request_id = null, active_trip_id = null, last_heartbeat_at = null where driver_id = target_user_id;
end;
$$;

create or replace function public.admin_set_user_blocked(target_user_id uuid, blocked boolean, audit_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare caller_id uuid; target_user public.users%rowtype; target_profile public.driver_profiles%rowtype;
begin
  caller_id := private.require_nonblocked_admin();
  if char_length(btrim(coalesce(audit_reason, ''))) not between 1 and 500 then raise exception using errcode = '22023', message = 'A nonblank audit reason is required.'; end if;
  select * into target_user from public.users where id = target_user_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'Target account was not found.'; end if;
  if target_user.role = 'driver' then select * into target_profile from public.driver_profiles where user_id = target_user_id for update; end if;
  caller_id := private.require_nonblocked_admin();
  if blocked and target_user.role = 'driver' then
    perform 1 from public.trips where driver_id = target_user_id and status not in ('completed','cancelledByRider','cancelledByDriver','cancelledByAdmin','failed') for update;
    if found then raise exception using errcode = '55000', message = 'A Driver assigned to a nonterminal Trip must be terminated before blocking.'; end if;
    perform private.reconcile_driver_availability(target_user_id);
    update public.driver_availability set state = 'offline', vehicle_id = null, reserved_booking_request_id = null, active_trip_id = null, last_heartbeat_at = null where driver_id = target_user_id;
  end if;
  perform set_config('ridex.audit_actor_id', caller_id::text, true); perform set_config('ridex.audit_action', 'admin.user_blocked_state_set', true); perform set_config('ridex.audit_reason', btrim(audit_reason), true);
  update public.users set is_blocked = blocked where id = target_user_id;
end;
$$;

revoke all on function private.driver_transition_trip(uuid, public.trip_status, integer, text) from public, anon, authenticated, service_role;
revoke all on function public.driver_transition_trip(uuid, public.trip_status, integer, text) from public, anon, service_role;
grant execute on function public.driver_transition_trip(uuid, public.trip_status, integer, text) to authenticated;
commit;
