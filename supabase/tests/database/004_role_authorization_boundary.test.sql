begin;

create extension if not exists pgtap with schema extensions;

select plan(29);

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'malicious-signup@example.com',
    '',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Malicious Signup","role":"admin"}',
    now(),
    now(),
    '',
    '',
    '',
    ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'promotion-target@example.com',
    '',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Promotion Target","role":"driver"}',
    now(),
    now(),
    '',
    '',
    '',
    ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'admin@example.com',
    '',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Admin"}',
    now(),
    now(),
    '',
    '',
    '',
    ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000004',
    'authenticated',
    'authenticated',
    'blocked-admin@example.com',
    '',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Blocked Admin"}',
    now(),
    now(),
    '',
    '',
    '',
    ''
  );

update public.users
set role = 'admin'
where id in (
  '10000000-0000-0000-0000-000000000003',
  '10000000-0000-0000-0000-000000000004'
);

update public.users
set is_blocked = true
where id = '10000000-0000-0000-0000-000000000004';

delete from public.rider_profiles
where user_id in (
  '10000000-0000-0000-0000-000000000003',
  '10000000-0000-0000-0000-000000000004'
);

select is(
  (select role from public.users where id = '10000000-0000-0000-0000-000000000001'),
  'rider',
  'signup ignores malicious Admin role metadata'
);
select ok(
  exists (
    select 1 from public.rider_profiles
    where user_id = '10000000-0000-0000-0000-000000000001'
  ),
  'signup creates a Rider profile'
);
select ok(
  not exists (
    select 1 from public.driver_profiles
    where user_id = '10000000-0000-0000-0000-000000000001'
  ),
  'signup does not create a Driver profile'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

select throws_ok(
  $$select public.admin_promote_user_to_driver('10000000-0000-0000-0000-000000000002')$$,
  '42501',
  'Only a non-blocked Admin can manage Drivers.',
  'a Rider cannot call the Driver promotion RPC'
);
select throws_ok(
  $$update public.users set role = 'admin' where id = auth.uid()$$,
  '42501',
  null,
  'an authenticated user cannot directly change role'
);
select throws_ok(
  $$update public.driver_profiles set approval_status = 'approved' where user_id = auth.uid()$$,
  '42501',
  null,
  'an authenticated user cannot directly change Driver approval'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000003',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

select lives_ok(
  $$select public.admin_promote_user_to_driver('10000000-0000-0000-0000-000000000002')$$,
  'a non-blocked Admin can promote a Rider'
);

reset role;

select is(
  (select role from public.users where id = '10000000-0000-0000-0000-000000000002'),
  'driver',
  'promotion changes the trusted role to Driver'
);
select ok(
  not exists (
    select 1 from public.rider_profiles
    where user_id = '10000000-0000-0000-0000-000000000002'
  ),
  'promotion removes the old Rider profile'
);
select is(
  (
    select approval_status from public.driver_profiles
    where user_id = '10000000-0000-0000-0000-000000000002'
  ),
  'pending',
  'a promoted Driver always starts pending'
);

set local role authenticated;

select lives_ok(
  $$select public.admin_approve_driver('10000000-0000-0000-0000-000000000002')$$,
  'a non-blocked Admin can approve a Driver'
);

reset role;

select is(
  (
    select approval_status from public.driver_profiles
    where user_id = '10000000-0000-0000-0000-000000000002'
  ),
  'approved',
  'approval stores the approved state'
);
select is(
  (
    select rejection_reason from public.driver_profiles
    where user_id = '10000000-0000-0000-0000-000000000002'
  ),
  null,
  'approval clears a prior rejection reason'
);

set local role authenticated;

select lives_ok(
  $$select public.admin_reject_driver(
    '10000000-0000-0000-0000-000000000002',
    'Documents need review'
  )$$,
  'a non-blocked Admin can reject a Driver'
);

reset role;

select is(
  (
    select approval_status from public.driver_profiles
    where user_id = '10000000-0000-0000-0000-000000000002'
  ),
  'rejected',
  'rejection stores the rejected state'
);
select is(
  (
    select rejection_reason from public.driver_profiles
    where user_id = '10000000-0000-0000-0000-000000000002'
  ),
  'Documents need review',
  'rejection stores the trimmed reason'
);

set local role authenticated;

select throws_ok(
  $$select public.admin_promote_user_to_driver('10000000-0000-0000-0000-000000000003')$$,
  '22023',
  'Only a Rider account can be promoted to Driver.',
  'the RPC cannot demote an Admin to Driver'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000004',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

select throws_ok(
  $$select public.admin_approve_driver('10000000-0000-0000-0000-000000000002')$$,
  '42501',
  'Only a non-blocked Admin can manage Drivers.',
  'a blocked Admin cannot approve a Driver'
);

reset role;

select ok(
  not has_function_privilege('anon', 'public.admin_promote_user_to_driver(uuid)', 'EXECUTE'),
  'anon cannot execute Driver promotion'
);
select ok(
  not has_function_privilege('anon', 'public.admin_approve_driver(uuid)', 'EXECUTE'),
  'anon cannot execute Driver approval'
);
select ok(
  not has_function_privilege('anon', 'public.admin_reject_driver(uuid,text)', 'EXECUTE'),
  'anon cannot execute Driver rejection'
);
select ok(
  has_function_privilege('authenticated', 'public.admin_promote_user_to_driver(uuid)', 'EXECUTE'),
  'authenticated callers can reach the guarded promotion RPC'
);
select ok(
  has_function_privilege('authenticated', 'public.admin_approve_driver(uuid)', 'EXECUTE'),
  'authenticated callers can reach the guarded approval RPC'
);
select ok(
  has_function_privilege('authenticated', 'public.admin_reject_driver(uuid,text)', 'EXECUTE'),
  'authenticated callers can reach the guarded rejection RPC'
);
select is(
  (
    select count(*)
    from pg_proc
    where oid in (
      'public.admin_promote_user_to_driver(uuid)'::regprocedure,
      'public.admin_approve_driver(uuid)'::regprocedure,
      'public.admin_reject_driver(uuid,text)'::regprocedure
    )
      and prosecdef
  ),
  3::bigint,
  'all Driver administration RPCs are SECURITY DEFINER'
);
select is(
  (
    select count(*)
    from pg_proc
    where oid in (
      'public.admin_promote_user_to_driver(uuid)'::regprocedure,
      'public.admin_approve_driver(uuid)'::regprocedure,
      'public.admin_reject_driver(uuid,text)'::regprocedure
    )
      and array_to_string(proconfig, ',') in ('search_path=""', 'search_path=')
  ),
  3::bigint,
  'all Driver administration RPCs have an empty search path'
);
select ok(
  not has_function_privilege('authenticated', 'public.handle_new_user()', 'EXECUTE'),
  'the signup trigger function is not a public RPC'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000003',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

select throws_ok(
  $$select public.admin_reject_driver(
    '10000000-0000-0000-0000-000000000002',
    '   '
  )$$,
  '22023',
  'A rejection reason is required.',
  'Driver rejection requires a non-empty reason'
);

reset role;

select is(
  (
    select count(*)
    from public.users
    where role = 'admin'
      and (
        (
          id = '10000000-0000-0000-0000-000000000003'
          and not is_blocked
        )
        or (
          id = '10000000-0000-0000-0000-000000000004'
          and is_blocked
        )
      )
  ),
  2::bigint,
  'existing Admin roles and blocked state remain intact'
);

select * from finish();
rollback;
