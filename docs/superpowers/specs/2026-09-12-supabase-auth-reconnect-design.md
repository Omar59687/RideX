# Supabase Auth Reconnection and Signup Repair Design

## Goal

Restore reliable RideX email/password signup against the existing hosted
Supabase project, establish a reproducible CLI workflow, and verify that every
new public account is created as a Rider with matching `users` and
`rider_profiles` records.

## Current Evidence

- Supabase Dashboard user creation fails with `Database error creating new
  user`.
- RideX application signup also fails.
- The local repository is linked to a hosted Supabase project, but no permanent
  CLI executable is installed.
- `public.handle_new_user()` requires `display_name`; Dashboard-created users do
  not necessarily supply that metadata.
- Local migrations later changed public signup to Rider-only, but repository
  documentation says earlier database work was not deployed remotely. Remote
  migration drift is therefore a likely contributing cause.
- Missing historical test users must be investigated as possible project
  mismatch, database reset, or manual deletion. Project suspension alone will
  not be accepted as the cause without evidence.

## Selected Approach

Use a pinned project-local Supabase CLI rather than an untracked Dashboard SQL
patch or a destructive project recreation. The CLI version will be recorded in
the repository so teammates run the same tool through `npx supabase`.

Work occurs only on `codex/supabase-auth-reconnect`. Unrelated generated Flutter
changes were preserved in a named Git stash before the branch was created.

## Diagnostic Flow

1. Install and pin the Supabase CLI as a development dependency.
2. Authenticate through the official CLI login flow and verify the existing
   project reference.
3. Confirm that the Flutter Supabase URL, CLI link, and resumed Dashboard project
   identify the same project without printing secrets.
4. Inspect remote migration history, the active signup trigger/function, Auth
   configuration, Auth logs, and corresponding Postgres errors.
5. Compare the remote schema with committed migrations without resetting or
   recreating the hosted database.
6. Reproduce signup using a uniquely named disposable test account after the
   failing boundary is understood.

## Repair Rules

- If the remote database is merely behind, deploy only the reviewed missing
  committed migrations in order.
- If the latest committed trigger still cannot support both RideX and Dashboard
  creation, add a new additive migration; never rewrite an applied migration.
- Public signup remains Rider-only. Driver and Admin roles remain trusted
  administrative transitions, never signup metadata.
- `display_name` from the RideX app is normalized and preserved. For a trusted
  Dashboard-created user with no display name, the trigger derives a bounded,
  nonempty fallback from the email local part instead of aborting the Auth
  transaction.
- The trigger remains `SECURITY DEFINER` with an empty controlled search path,
  explicit schema qualification, least-privilege execution grants, and
  idempotent profile creation behavior.
- No service-role or database password is stored in Git, Dart defines, logs, or
  documentation.

## Verification

1. Add or update pgTAP coverage for app metadata signup, missing-display-name
   Dashboard signup, malicious role metadata, duplicate/conflicting profile
   behavior, and Rider-only creation.
2. Run a clean local migration reset and the focused signup test.
3. Run the complete database suite and relevant Flutter authentication tests.
4. Deploy only after local verification passes and remote drift is documented.
5. Create a hosted test user and confirm exactly one Auth user, one public user,
   one Rider profile, and no Driver/Admin profile.
6. Sign in through RideX and verify profile loading and Rider routing.
7. Record sanitized before/after evidence, exact deployed migrations, and CLI
   version. Remove the disposable test user only if explicitly included in the
   final verification cleanup.

## Failure Handling and Safety

- Stop on project-reference mismatch, unexpected remote-only migrations,
  destructive diff, missing credentials, or unrelated schema drift.
- Do not run remote reset, delete the project, wipe users, or apply a broad
  schema push.
- Prefer a reversible additive correction. If deployment fails, report the
  failing migration and leave remote data intact.
- Preserve and do not stage unrelated teammate or generated-file changes.

## Completion Criteria

- The pinned CLI is usable by the team.
- Local and hosted project identity are confirmed.
- The exact root cause is documented.
- Dashboard and RideX signups succeed.
- New accounts are Rider-only and have consistent public profile rows.
- Local and remote verification passes with no secrets or unrelated changes.
