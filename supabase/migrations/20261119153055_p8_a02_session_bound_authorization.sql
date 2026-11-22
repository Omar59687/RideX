begin;
-- No service caller may directly assert a Rider ID to the old command.
revoke execute on function public.backend_prepare_card_command(uuid,uuid,uuid,integer,integer,text,text,text) from service_role;
-- This boundary is callable only by the trusted server after Auth has verified
-- the token. SQL derives its Rider from the live GoTrue session and holds that
-- session row until the existing command completes. Capture is intentionally not exposed.
create function public.backend_prepare_card_authorization_for_session(
  verified_actor_id uuid, verified_session_id uuid, token_expires_at bigint,
  target_trip_id uuid, target_payment_id uuid, expected_trip_version integer,
  expected_payment_version integer, operation_key text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare session_actor uuid;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='42501',message='Backend access required.';
  end if;
  if verified_actor_id is null or verified_session_id is null or token_expires_at is null
    or token_expires_at <= extract(epoch from clock_timestamp()) then
    raise exception using errcode='42501',message='Verified session required.';
  end if;
  begin
    execute 'select s.user_id from auth.sessions s where s.id=$1 and s.user_id=$2 and (to_jsonb(s)->>''not_after'' is null or (to_jsonb(s)->>''not_after'')::timestamptz > clock_timestamp()) for share'
      into session_actor using verified_session_id, verified_actor_id;
  exception when undefined_table or undefined_column then
    raise exception using errcode='42501',message='Verified session required.';
  end;
  if session_actor is null or session_actor is distinct from verified_actor_id then
    raise exception using errcode='42501',message='Verified session required.';
  end if;
  return public.backend_prepare_card_command(session_actor,target_trip_id,target_payment_id,
    expected_trip_version,expected_payment_version,'authorize',operation_key,null);
end;
$$;
revoke all on function public.backend_prepare_card_authorization_for_session(uuid,uuid,bigint,uuid,uuid,integer,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.backend_prepare_card_authorization_for_session(uuid,uuid,bigint,uuid,uuid,integer,integer,text) to service_role;
commit;
