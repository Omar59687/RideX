begin;

-- Trusted polling primitive only. Scheduling is deliberately a separate,
-- manually reviewed owner operation documented in P7_MATCHING_EXPIRY_SCHEDULER.md.
create function public.backend_expire_due_booking_matches(batch_limit integer default 25)
returns integer
language plpgsql security definer set search_path = '' as $$
declare item record; processed integer := 0;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Service role required.';
  end if;
  if batch_limit is null or batch_limit < 1 or batch_limit > 100 then
    raise exception using errcode = '22023', message = 'Batch limit must be between 1 and 100.';
  end if;
  for item in
    select b.id, b.version
    from public.booking_requests b
    where b.status = 'searching' and b.searching_at is not null
      and (
        b.searching_at + interval '90 seconds' <= clock_timestamp()
        or exists (
          select 1 from public.driver_match_offers o
          where o.booking_request_id = b.id and o.status = 'offered'
            and o.expires_at <= clock_timestamp()
        )
      )
    order by b.searching_at, b.id
    for update skip locked
    limit batch_limit
  loop
    begin
      perform public.backend_expire_booking_match_offers(item.id, item.version);
      processed := processed + 1;
    exception when serialization_failure then
      -- Another canonical transition won after candidate selection. Retry next tick.
      null;
    end;
  end loop;
  return processed;
end;
$$;
revoke all on function public.backend_expire_due_booking_matches(integer) from public, anon, authenticated;
grant execute on function public.backend_expire_due_booking_matches(integer) to service_role;

commit;
