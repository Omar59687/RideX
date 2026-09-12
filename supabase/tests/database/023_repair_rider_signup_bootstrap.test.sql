begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    '23000000-0000-0000-0000-000000000001',
    'authenticated', 'authenticated', 'app-rider-023@example.com', '', now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"  App Rider  ","role":"admin"}',
    now(), now(), '', '', '', ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '23000000-0000-0000-0000-000000000002',
    'authenticated', 'authenticated', 'dashboard.rider@example.com', '', now(),
    '{"provider":"email","providers":["email"]}', '{}',
    now(), now(), '', '', '', ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '23000000-0000-0000-0000-000000000003',
    'authenticated', 'authenticated', 'blank-name@example.com', '', now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"   ","role":"driver"}',
    now(), now(), '', '', '', ''
  );

select is(
  (select display_name from public.users
   where id = '23000000-0000-0000-0000-000000000001'),
  'App Rider',
  'application display name is trimmed and preserved'
);
select is(
  (select display_name from public.users
   where id = '23000000-0000-0000-0000-000000000002'),
  'dashboard.rider',
  'Dashboard signup derives a display name from the email local part'
);
select is(
  (select display_name from public.users
   where id = '23000000-0000-0000-0000-000000000003'),
  'blank-name',
  'blank metadata display name uses the email fallback'
);
select is(
  (select count(*) from public.users
   where id::text like '23000000-0000-0000-0000-%' and role = 'rider'),
  3::bigint,
  'all public signup paths create Rider users'
);
select is(
  (select count(*) from public.rider_profiles
   where user_id::text like '23000000-0000-0000-0000-%'),
  3::bigint,
  'every new user receives exactly one Rider profile'
);
select is(
  (select count(*) from public.driver_profiles
   where user_id::text like '23000000-0000-0000-0000-%'),
  0::bigint,
  'signup metadata cannot create Driver profiles'
);
select is(
  (select count(*) from public.users
   where id::text like '23000000-0000-0000-0000-%'),
  3::bigint,
  'each Auth user has exactly one public user row'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.handle_new_user()', 'execute'
  ),
  'authenticated clients cannot call the signup trigger function'
);
select ok(
  not has_function_privilege('anon', 'public.handle_new_user()', 'execute'),
  'anonymous clients cannot call the signup trigger function'
);
select ok(
  (
    select array_to_string(proconfig, ',') in ('search_path=""', 'search_path=')
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'public'
      and pg_proc.proname = 'handle_new_user'
  ),
  'signup trigger function retains an empty search path'
);
select throws_ok(
  $$insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, email_change, email_change_token_new, recovery_token
    ) values (
      '00000000-0000-0000-0000-000000000000',
      '23000000-0000-0000-0000-000000000004',
      'authenticated', 'authenticated', null, '', '{}', '{}', now(), now(),
      '', '', '', ''
    )$$,
  '22023',
  'Email is required.',
  'signup still rejects a missing email'
);
select ok(
  (select bool_and(char_length(display_name) between 1 and 100)
   from public.users where id::text like '23000000-0000-0000-0000-%'),
  'all generated display names satisfy the bounded profile contract'
);

select * from finish();
rollback;
