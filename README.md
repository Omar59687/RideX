# RideX

A Flutter ride-booking application with Riverpod state management, GoRouter
navigation, and optional Supabase-backed authentication and profiles.

## Environment configuration

RideX reads environment configuration at compile time with
`String.fromEnvironment`. It does not load `.env` files at runtime.

To run with the local Mock repositories, omit the Supabase defines:

```sh
flutter run
```

To enable Supabase-backed authentication and profiles, provide both required
compile-time values. Replace the placeholders locally; never commit real
configuration values.

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_REPLACE_WITH_PUBLIC_CLIENT_KEY
```

The same `--dart-define` arguments can be supplied to `flutter build`. RideX
requires a valid HTTPS URL. Custom HTTPS Supabase domains are supported.

Both values must be provided together. When both are absent, RideX intentionally
uses Mock mode for development and local tests. Partial, placeholder, malformed,
or insecure configuration is rejected before Supabase initialization.

## Credential safety

Flutter is a public client. It may contain only a Supabase **Publishable key** or
the legacy **anon key**, protected by correctly configured Row Level Security.

Never include any of the following in Flutter source, build arguments checked
into version control, environment examples, logs, or bundled files:

- Supabase `service_role` keys
- Supabase secret keys
- Database passwords or connection strings
- Administrative credentials
- Access tokens, refresh tokens, or user passwords

Local environment, secret, signing, and Supabase temporary files are ignored by
Git. The repository intentionally does not provide an `.env.example` because
`.env` runtime loading is not part of the application configuration workflow.

## Local verification

Run tests without Supabase defines so they remain in Mock mode. The tests named
`live_supabase_*` are opt-in integration tests and must not be run against a
remote project during ordinary local verification.

```sh
flutter analyze
flutter test test/app/config/env_config_test.dart
flutter test test/app/initialization_failure_app_test.dart
```
