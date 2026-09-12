# Supabase Auth Recovery Verification — September 12, 2026

## Incident

The resumed hosted Supabase project was active and still linked to this repository,
but its migration ledger contained only migrations `001` through `003`. Migration
`003` required both `display_name` and a client-supplied Rider/Driver role in Auth
metadata. The current Flutter signup intentionally supplies `display_name` only,
and Supabase Dashboard user creation may supply neither value. The Auth trigger
therefore aborted both creation paths and surfaced `Database error creating new
user`.

The missing test users are consistent with a hosted database recreation or an
older database state, but the available evidence does not identify the exact event
that removed them. The project was not disconnected.

## Repair

- Pinned Supabase CLI `2.111.0` as a project-local development dependency.
- Added migration `023_repair_rider_signup_bootstrap.sql`; migrations `001` through
  `022` were not edited.
- Made every public signup Rider-only, ignoring client-supplied role metadata.
- Preserved trimmed `display_name` when supplied and otherwise derived a bounded
  fallback from the email address.
- Created exactly one RiderProfile for every new Auth user.
- Kept the trigger function security-definer with an empty search path and no
  anonymous/authenticated execute privilege.
- Updated three legacy pgTAP message expectations to match the already-approved
  migration `022` fail-closed ordering. No runtime Payment behavior changed.

## Verification

- Supabase CLI: `2.111.0`.
- Clean local reset: migrations `001` through `023` applied successfully.
- Focused migration `023` pgTAP: 12/12 passed.
- Complete database suite: 20 files, 927 assertions, PASS.
- Database lint: no errors; three pre-existing unused-variable warnings remain.
- Focused Flutter authentication/role/route tests: 28 passed.
- `flutter analyze`: no issues found.
- Hosted migration history: local and remote both list `001` through `023`.
- Hosted Dashboard-style creation with empty metadata: Rider user and RiderProfile
  created; password sign-in passed.
- Hosted app-style metadata creation: display name preserved, supplied Driver role
  ignored, Rider user and RiderProfile created; password sign-in passed.
- Temporary hosted verification users were deleted.

## Security and operational notes

No access token, database password, secret/service-role key, or user password was
added to Git. CLI authentication remains local, and this recovery did not add or
change tracked project-link metadata. The hosted database was migrated forward in
order and was not reset.
