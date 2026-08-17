# RideX

RideX is a Flutter ride-hailing graduation project for Jordan. It includes a
complete Rider V2 demonstration, a preserved driver experience, and future
administration scope.

## Rider V2

The native Flutter rider flow covers authentication, destination-first booking,
pickup confirmation, vehicle and fare selection, driver search, trip states,
completion and rating, history and details, profile, notifications, and
settings. Urban Aurora light and dark themes use bundled Plus Jakarta Sans
fonts, native SVG identity assets, and Google Maps on the Rider and Driver home
screens. Route and trip previews remain custom-painted until their owning
implementation phases. The curated design
references under `references/UI/` are never embedded at runtime.

When Supabase is configured, email/password authentication, session restoration,
profile roles, blocked state, driver approval, and sign-out use the real backend.
Without configuration, deterministic mock authentication and profile repositories
keep local development and tests self-contained.

Phone OTP, place search, routing, continuous Driver tracking,
booking/history persistence, card payments,
promotions, rewards, calls/messages, safety services, notification delivery,
saved-place persistence, and rating persistence are not production integrations.
The UI presents these as disabled, Coming soon, session-local, or explicit demo
behavior.

## Setup

RideX targets Flutter 3.27.3 and Dart 3.6.1.

```powershell
flutter pub get
flutter run
```

To use Supabase, supply both values as Dart defines:

```powershell
flutter run --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_PUBLISHABLE_KEY=<key>
```

Do not commit backend credentials. Live Supabase tests skip unless intentionally
configured.

### Google Maps and foreground location

Checkpoint 4A supports Google Maps on Android and iOS with one foreground
current-location request. It does not request background location.

Android configuration:

1. Enable only Maps SDK for Android in Google Cloud Console.
2. Create an Android-restricted key for `com.ridex.app` and the applicable
   debug/release signing certificate fingerprints.
3. Add the key to ignored `android/local.properties`:

   ```properties
   MAPS_API_KEY=your_restricted_android_key
   ```

iOS configuration:

1. Enable only Maps SDK for iOS in Google Cloud Console.
2. Create an iOS-restricted key for bundle identifier `com.ridex.app`.
3. Create ignored `ios/Flutter/config.local.xcconfig`:

   ```text
   GOOGLE_MAPS_API_KEY=your_restricted_ios_key
   ```

Enable the in-app Google Maps surface with the non-secret Dart flag:

```powershell
flutter run --dart-define=GOOGLE_MAPS_ENABLED=true
```

Use separate restricted Android and iOS keys. Do not enable Places, Geocoding,
Routes, or Directions APIs for Checkpoint 4A. Mobile Maps keys are client-visible;
application restrictions, API restrictions, quotas, and monitoring are required.
If the flag or native key is absent, RideX uses a safe map fallback and remains
usable.

### Google place search and geocoding

Checkpoint 4B uses Places API (New), including Autocomplete (New) and Place
Details (New), plus Geocoding API v4 through the authenticated Supabase
`places` Edge Function. Flutter does not call these Google web services
directly.

Google Cloud configuration:

1. Enable Places API (New) and Geocoding API v4.
2. Create a separate server-side key restricted to only those two APIs.
3. Keep the Android and iOS Maps SDK keys unchanged and Maps-only.
4. Configure Google Cloud quotas, budget alerts, and usage monitoring.

The function also applies per-Rider operation and concurrency limits. These are
instance-local safeguards, not a replacement for Google Cloud hard quotas. If
the Edge environment cannot provide stable egress IP addresses, use controlled
egress backend infrastructure before production if IP application restriction
is required.

Store the server credential only as the Supabase Edge Function secret
`GOOGLE_MAPS_WEB_SERVICES_API_KEY`. For local function development, use an
ignored `supabase/functions/.env` file. For hosted functions, configure the
secret through Supabase secret management. Never add this key to Dart defines,
Flutter source, Android resources, iOS resources, or Git.

Deploy `supabase/functions/places` with JWT verification enabled. The function
also verifies that the caller is an authenticated, unblocked Rider. Local Mock
mode uses explicit deterministic demo results and never calls Google; configured
Supabase mode never falls back to those results after an API failure.

Before release, publish RideX Terms of Use and a Privacy Policy that disclose
place-search and precise-location processing and incorporate the required
Google Maps Platform terms and privacy links.

## Verification

```powershell
dart format lib test
flutter analyze
flutter test
```

## Documentation

- [Rider V2 plan](docs/ai/plans/RIDER_UI_V2_PLAN.md)
- [Project context](docs/ai/ops/PROJECT_CONTEXT.md)
- [Architecture](docs/ai/ops/ARCHITECTURE.md)
- [Approved decisions](docs/ai/ops/DECISIONS.md)
- [Current status and handoff](docs/ai/ops/CURRENT_STATUS.md)
## Environment configuration

RideX reads Dart environment configuration at compile time. It does not load
`.env` files at runtime. Native Maps keys use the ignored platform files
documented above.

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
