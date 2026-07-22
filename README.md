# RideX

RideX is a Flutter ride-hailing graduation project for Jordan. It includes a
complete Rider V2 demonstration, a preserved driver experience, and future
administration scope.

## Rider V2

The native Flutter rider flow covers authentication, destination-first booking,
pickup confirmation, vehicle and fare selection, driver search, trip states,
completion and rating, history and details, profile, notifications, and
settings. Urban Aurora light and dark themes use bundled Plus Jakarta Sans
fonts, native SVG identity assets, and a custom-painted map. The curated design
references under `references/UI/` are never embedded at runtime.

When Supabase is configured, email/password authentication, session restoration,
profile roles, blocked state, driver approval, and sign-out use the real backend.
Without configuration, deterministic mock authentication and profile repositories
keep local development and tests self-contained.

Phone OTP, live maps and location, booking/history persistence, card payments,
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
