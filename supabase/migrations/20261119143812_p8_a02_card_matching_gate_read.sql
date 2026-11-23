begin;
-- Only the trusted server can read this switch. Missing state fails closed.
create function public.backend_card_matching_enabled()
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode = '42501', message = 'Backend access required.';
  end if;
  return private.p8_card_matching_enabled();
end;
$$;
revoke all on function public.backend_card_matching_enabled() from public, anon, authenticated, service_role;
grant execute on function public.backend_card_matching_enabled() to service_role;
commit;
