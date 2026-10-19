# RideX B0 disposal-only SDK snapshots

This is the authorized in-repository snapshot alternative, not an external fork
or a general SDK upgrade. Root `pubspec.yaml` overrides both packages using
repository-relative paths. `pubspec.lock` retains versions 2.13.4 and 2.15.4.
The eventual RideX commit pins these bytes; this candidate remains uncommitted
for independent review. A path lock entry alone does not hash package contents.

## Provenance and bounded footprint

Both published versions correspond to upstream Git commit
`42c7224097e50afe8c7246096940235880f89ff8` in
https://github.com/supabase/supabase-flutter, at `packages/supabase` and
`packages/supabase_flutter`. Version tags resolved to that immutable commit.
The downloaded Pub archives were SHA-256 checked against the original RideX
lockfile and Pub API. All 40 selected files were then byte-compared against
the source archive of that exact Git commit before patching.

Each package contains only its 18 runtime `lib/` files, unchanged published
`pubspec.yaml`, and unchanged MIT `LICENSE`. Examples, upstream test suites,
platform projects, caches and generated metadata are excluded. Both original
licenses remain beside their packages. `PROVENANCE.json` inventories every
selected file with its upstream SHA-256 and both patched file hashes.

The only modified upstream files are:

- `supabase/lib/src/supabase_client.dart`
- `supabase_flutter/lib/src/supabase.dart`

Three added test helpers are under the root `test/helpers/` folder. The actual SDK
regressions run through `test/sdk_disposal_observability_test.dart` and the B0
provenance suite in the root Flutter project. `web_socket_channel` 3.0.3 is
promoted from transitive to direct dev dependency for the local socket gate;
no dependency versions change.
`PATCH.diff` records the entire upstream delta, with no machine paths. It uses
zero context (`git apply --unidiff-zero`) to avoid whitespace-only context lines.

## Disposal contract

`SupabaseClient.isDisposingOrDisposed` is read-only, true synchronously when
`dispose()` is invoked, and never resets. Repeated/reentrant/concurrent calls
return one cleanup future, including the same retained failure. Cleanup attempts
every existing resource in its original order and rethrows the first failure
with its original stack; it does not log raw errors or alter credentials.

`Supabase.disposalState` is a read-only monotonic marker for one initialization.
`hasStarted` becomes true before any disposal await. The convenience getter
`isDisposingOrDisposed` reads the current marker. The SDK singleton remains
reusable after completed cleanup as before: a fresh initialization creates a
new marker, while any retained old marker stays invalid. B0 retains that marker.
Wrapper cleanup captures the current client at invocation, shares one future,
attempts all existing cleanup steps, and clears initialization after cleanup,
including failed cleanup. No automatic reinitialization is added.

Initialization/authentication/session-restoration code and all other runtime
files are unchanged apart from installing a new marker at `_init`. SDK web
hot-restart still calls the real captured client's `dispose()`, so it receives
the same synchronous flag. Native and web cleanup implementations are retained.

These flags indicate disposal start, not successful cleanup. They do not block
every raw-client method or revoke remote credentials. Application provenance is
permanently invalidated when a guarded access observes disposal/replacement.
Consumers must recheck around awaits. Unobserved transient replacement and
restoration of a healthy client remain outside this SDK patch's guarantees.

## Reverification and updates

From the repository root:

```text
python third_party/supabase_disposal/verify_snapshot.py
python third_party/supabase_disposal/verify_snapshot.py --upstream
flutter test --no-pub test/sdk_disposal_observability_test.dart test/supabase_initialization_provenance_test.dart
flutter test --no-pub --platform chrome test/sdk_disposal_observability_test.dart
```

The offline verifier checks the exact runtime footprint and all original/patch
hashes. `--upstream` also downloads the fixed published archives using TLS and
checks their recorded archive/file hashes, without writing or extracting files.

Any SDK update must explicitly review/rebase these two disposal patches, verify
the upstream revision/archive/license and dependency delta, refresh the manifest
and diff, and rerun native/web regressions plus the full application suite.
Do not run a floating upgrade or substitute a global Pub cache edit. Retire the
snapshot only after an official release proves the same disposal guarantees.

## Local verification (2026-10-19)

- Previously failing direct-disposal regression: passed without removing its
  original security assertions; immediate pre-await assertions also pass.
- Native SDK/provenance suites: 28 passed (2 SDK, 26 provenance).
- Focused compatibility selection: 429 passed, including the above suites.
- Configured startup/provider selection: 3 passed.
- Full native Flutter suite: 1,277 passed, 0 failed, 2 existing live-test skips.
- Flutter analysis: no issues. Formatting: 309 Dart files, 0 changes.
- Source/archive integrity, complete dependency delta, tracked diff checks and
  all 55 candidate files' trailing whitespace: clean.
- No tracked platform files were regenerated. No restricted integration or
  backend files changed. No Pub cache source was edited.

Counts overlap and must not be added. Toolchain: Flutter 3.35.3 / Dart 3.9.2.
Browser verification remains incomplete: Chrome and Edge Flutter JS test hosts
stalled during suite loading and were stopped. The Wasm suite compiled, but
inspection of its wrapper showed HTTP 404 for `/canvaskit/skwasm.js` and
`/canvaskit/skwasm.wasm` in the installed Flutter test harness. No browser test
pass is claimed, no skip was added, and the web hot-restart assertion remains
registered for a working browser harness. These attempts did not alter the
global Flutter SDK. Native checks prove the shared disposal contract; an actual
web hot-restart runtime pass is still needed before claiming web verification.

## Complete candidate file inventory

All 55 candidate paths, including the original B0 files:

```text
lib/app/bootstrap.dart
lib/core/services/supabase/supabase_client_provider.dart
lib/core/services/supabase/supabase_initialization_provenance.dart
pubspec.lock
pubspec.yaml
test/architecture_boundary_test.dart
test/helpers/sdk_disposal_socket.dart
test/helpers/sdk_web_disposal.dart
test/helpers/sdk_web_disposal_stub.dart
test/sdk_disposal_observability_test.dart
test/supabase_initialization_provenance_test.dart
third_party/supabase_disposal/PATCH.diff
third_party/supabase_disposal/PROVENANCE.json
third_party/supabase_disposal/README.md
third_party/supabase_disposal/supabase/LICENSE
third_party/supabase_disposal/supabase/lib/src/auth_http_client.dart
third_party/supabase_disposal/supabase/lib/src/auth_user.dart
third_party/supabase_disposal/supabase/lib/src/constants.dart
third_party/supabase_disposal/supabase/lib/src/counter.dart
third_party/supabase_disposal/supabase/lib/src/platform_io.dart
third_party/supabase_disposal/supabase/lib/src/platform_stub.dart
third_party/supabase_disposal/supabase/lib/src/realtime_client_options.dart
third_party/supabase_disposal/supabase/lib/src/remove_subscription_result.dart
third_party/supabase_disposal/supabase/lib/src/supabase_client.dart
third_party/supabase_disposal/supabase/lib/src/supabase_client_options.dart
third_party/supabase_disposal/supabase/lib/src/supabase_event_types.dart
third_party/supabase_disposal/supabase/lib/src/supabase_query_builder.dart
third_party/supabase_disposal/supabase/lib/src/supabase_query_schema.dart
third_party/supabase_disposal/supabase/lib/src/supabase_realtime_error.dart
third_party/supabase_disposal/supabase/lib/src/supabase_stream_builder.dart
third_party/supabase_disposal/supabase/lib/src/supabase_stream_filter_builder.dart
third_party/supabase_disposal/supabase/lib/src/version.dart
third_party/supabase_disposal/supabase/lib/supabase.dart
third_party/supabase_disposal/supabase/pubspec.yaml
third_party/supabase_disposal/supabase_flutter/LICENSE
third_party/supabase_disposal/supabase_flutter/lib/src/clear_auth_url_parameters.dart
third_party/supabase_disposal/supabase_flutter/lib/src/clear_auth_url_parameters_stub.dart
third_party/supabase_disposal/supabase_flutter/lib/src/clear_auth_url_parameters_web.dart
third_party/supabase_disposal/supabase_flutter/lib/src/constants.dart
third_party/supabase_disposal/supabase_flutter/lib/src/flutter_go_true_client_options.dart
third_party/supabase_disposal/supabase_flutter/lib/src/hot_restart_cleanup_stub.dart
third_party/supabase_disposal/supabase_flutter/lib/src/hot_restart_cleanup_web.dart
third_party/supabase_disposal/supabase_flutter/lib/src/local_storage.dart
third_party/supabase_disposal/supabase_flutter/lib/src/local_storage_stub.dart
third_party/supabase_disposal/supabase_flutter/lib/src/local_storage_web.dart
third_party/supabase_disposal/supabase_flutter/lib/src/passkey/passkey_options_mapper.dart
third_party/supabase_disposal/supabase_flutter/lib/src/platform_io.dart
third_party/supabase_disposal/supabase_flutter/lib/src/platform_stub.dart
third_party/supabase_disposal/supabase_flutter/lib/src/supabase.dart
third_party/supabase_disposal/supabase_flutter/lib/src/supabase_auth.dart
third_party/supabase_disposal/supabase_flutter/lib/src/supabase_passkey.dart
third_party/supabase_disposal/supabase_flutter/lib/src/version.dart
third_party/supabase_disposal/supabase_flutter/lib/supabase_flutter.dart
third_party/supabase_disposal/supabase_flutter/pubspec.yaml
third_party/supabase_disposal/verify_snapshot.py
```
