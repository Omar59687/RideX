# P6-R01/R02 Driver Cash completion implementation

Date: 2026-10-25. Base: `fc3224c8abe4013031a6fd953363764029ce2997`.
Branch: `feature/p6-r01-r02-driver-cash-integration`. Status authority:
[SPRINT_TRACKER.md](SPRINT_TRACKER.md). Implementation is submitted for review,
not merged or runtime-approved by this record. Phase 6 remains unapproved.

## Implemented composition

- `lib/core/repositories/supabase_driver_completion_source.dart` implements
  `CanonicalDriverCompletionSource` over the verified application SDK client and
  `AuthService.driverBinding`. It pins the original SDK Session/backend/Driver/epoch,
  validates canonical user and approval, reads the Driver's `driver_availability`
  row, and resolves its active Trip through canonical `trips` data. No screen input,
  MockTrip, booking ID/version or caller-generated Trip assignment supplies authority.
- The source requires matching Driver/Trip identity, Cash, `inProgress` and positive
  persisted Trip version. It checks availability again and revalidates eligibility
  after the Trip read. One completion key is generated only after validated context;
  subsequent loads retain the original command or reject a changed Trip/version.
  The existing composition rechecks canonical Trip/version before dispatch.
- `lib/core/services/trips/driver_completion_staging_gateway.dart` maps the existing
  journal outcomes to the existing coordinator. Only `CompletionCreated` permits
  dispatch. Existing/conflicting/corrupt/unacknowledged evidence never permits it.
- `application_completion_store.dart` conditionally selects native storage, or a
  fail-closed unsupported-platform boundary. Native storage uses path_provider's
  application support directory plus `driver_cash_completion/`; the existing file
  journal partitions records by trusted namespace and Driver. Missing directory,
  plugin, I/O, synchronization and acknowledgement failures prevent dispatch.
  There is no cache/temp fallback or SharedPreferences journal replacement.
- `lib/core/providers/driver_cash_completion_providers.dart` composes the existing
  AuthService owner, provenance, source, journal gateway, coordinator and
  `SupabaseDriverCashCompletionComposition`. Disposing the presentation owner revokes
  its publication rights and binding, without disposing the shared SDK/auth owner.
  SDK changes also invalidate stale presentation; no new epoch owner is created.
- `driver_cash_completion_controller.dart` and `driver_cash_completion_panel.dart`
  provide an optional canonical-screen seam: explicit readiness check, processing,
  verified/unverified receipt, unresolved, authorization, storage and network states.
  Completion is one-attempt/single-flight; neither errors nor remounts replay journal
  evidence. Receipt failure can retain canonical completed-Trip truth without claiming
  issuance. No UI says Cash paid based only on local state.
- The existing `driver_active_trip_screen.dart`, MockTripsRepository, routes and
  active mock controller are unchanged. The new panel is deliberately not mounted
  there. A UUID-shaped mock Trip does not grant canonical authority.

## Configuration and exact remaining owner decision

The existing local runtime configuration selects the nonsecret endpoint
`https://ykasivejjchupswqyxpm.supabase.co`. Only that URL was inspected; no key or
credential was copied into this branch or documentation. Example configuration
contains a placeholder and is not approval of a deployment namespace.

No approved production endpoint-to-journal-namespace mapping exists in the inspected
code or Phase 6 records. `approvedDriverCompletionBackendsProvider` therefore returns
an empty `DriverBackendRegistry`: production completion is DISABLED before SDK
reads, storage opening or financial dispatch.

The owner must explicitly approve this pair:

- Endpoint: `https://ykasivejjchupswqyxpm.supabase.co` (or explicitly select another target).
- Namespace: an owner-selected stable, nonsecret, unique journal namespace conforming
  to `DriverBackendIdentity` rules. **No namespace value is proposed or inferred.**

The approval must identify the environment and its long-term journal identity;
changing that identity must not hide unresolved evidence. After approval, add the
reviewed registry entry in integration configuration; never derive it from a URL,
user/session, screen or free-form runtime flag. Registry tests use explicit isolated
`.invalid` endpoints and test namespaces only.

## Verification executed for this implementation

Installed toolchain: Flutter 3.35.3 / Dart 3.9.2. The direct path_provider dependency
is pinned at 2.1.5; Android 2.2.5 and foundation 2.3.2 are locked without raising the
existing lockfile SDK minima. No existing dependency was upgraded. The macOS plugin
registrant adds only the required path provider registration.

Focused command:

```powershell
flutter test --no-pub test/driver_cash_production_integration_test.dart test/driver_cash_composition_test.dart test/driver_completion_coordinator_test.dart test/file_driver_completion_command_store_test.dart test/driver_authority_foundation_test.dart test/driver_cash_completion_hook_test.dart test/architecture_boundary_test.dart test/supabase_driver_completion_adapter_test.dart --reporter expanded
```

Result: **319 PASS / 0 FAIL / 0 SKIP**, including **33 new regressions**. Coverage
includes canonical ownership and approval, invalid backend namespace, SDK A-B-A,
application revocation during user/profile/availability/Trip/RPC reads, version change
before and during staging, non-Cash and inactive Trips, concurrent taps, actual native
journal write failure, application-support location, unknown RPC response, no replay
on remount, receipt absence/lineage, and UUID-shaped mock authority rejection.
Tests use the real installed SDK redirected to local loopback HTTP fixtures, real
journal files in independently allocated test directories, and injected plugin paths.
They do not contact hosted Supabase or execute a real financial transaction.

`flutter analyze --no-pub`: **No issues found**. Read-only formatting: **10 Dart files,
0 changed**. `git diff --check` and documentation link checks pass. The complete
Flutter suite was not rerun. Historical #52 owner results remain separate evidence.
No physical device, hosted Cash/receipt acceptance, migration, deployment, Stripe
credential or production financial operation is verified by this record.

## Status and next work

- **R01 PARTIAL:** canonical source and fail-closed configuration boundary implemented
  and locally tested. Exact deployment namespace approval remains open.
- **R02 PARTIAL:** bounded provider, persistent journal binding, one-attempt coordinator
  and canonical UI seam implemented and locally tested. Activation is disabled;
  no canonical Driver screen has been mounted or runtime-accepted. This follows the
  authorized fallback for the existing mock screen, not completion of production activation.
- Existing journal limitations remain: flush/readback does not prove universal
  power-loss durability, stale lock sentinels block, app-data/backup rollback and
  cross-device coordination are unverified. No repair, deletion, replay or retirement
  procedure is added.
- Next owner-dependent task: approve the endpoint/namespace pair, then narrowly enable
  the reviewed registry and mount the panel only in a canonical Driver experience.
  Keep the global mock Trip repository isolated; do not fabricate a matched Trip.
- Next independent implementation task: **P6-R03**, bind explicit read-only Cash
  recovery/unresolved evidence to the same owner and journal. Do not activate replay
  or retirement. Controlled hosted Cash/receipt acceptance remains **P6-R07** under
  separate test authorization; Phase 7 matching remains outside this PR.
