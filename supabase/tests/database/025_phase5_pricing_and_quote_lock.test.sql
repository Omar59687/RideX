begin;

select plan(6);

select is(
  (
    select count(*)::integer
    from public.pricing_configurations
    where is_active
  ),
  3,
  'Phase 5 bootstraps one active pricing configuration per vehicle type'
);

select is(
  (
    select count(distinct vehicle_type_code)::integer
    from public.pricing_configurations
    where is_active
  ),
  3,
  'all supported vehicle types have active pricing'
);

select is(
  (
    select count(*)::integer
    from public.pricing_configurations
    where is_active
      and base_fare_fils = 500
      and per_kilometer_fils = 300
      and per_minute_fils = 50
      and per_stop_fils = 200
      and minimum_fare_fils = 1000
      and rounding_increment_fils = 50
  ),
  3,
  'active bootstrap rows use the approved integer-fils formula'
);

select is(
  (
    select count(*)::integer
    from public.pricing_configurations
    where is_active
      and pricing_version > 0
  ),
  3,
  'active pricing rows are versioned'
);

select is(
  (
    select count(*)::integer
    from public.pricing_configurations
    where is_active
      and vehicle_type_code in (
        'economy'::public.vehicle_type_code,
        'comfort'::public.vehicle_type_code,
        'xl'::public.vehicle_type_code
      )
  ),
  3,
  'the active rows cover economy, comfort, and xl'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.rider_lock_fare_quote(uuid,uuid,integer,integer)',
    'EXECUTE'
  ),
  'authenticated Riders can lock only through the ownership-checking wrapper'
);

select * from finish();
rollback;
