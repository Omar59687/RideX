import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SupabaseProvenanceState {
  notStarted,
  demo,
  initializing,
  trusted,
  unverified,
  failed,
  invalidated,
}

/// Nonsecret diagnostic view. No SDK session, key, token or raw error.
final class SupabaseProvenanceSnapshot {
  const SupabaseProvenanceSnapshot._(this.state, this.endpoint);
  final SupabaseProvenanceState state;
  final Uri? endpoint;
}

final class SupabaseProvenanceException implements Exception {
  const SupabaseProvenanceException();
  @override
  String toString() => 'Supabase initialization provenance unavailable.';
}

/// Private evidence from an initialization owned by this boundary. An endpoint
/// string or a caller-supplied client can never construct this record.
final class _OwnedInitialization {
  const _OwnedInitialization(this.endpoint, this.client, this.disposalState);
  final Uri endpoint;
  final SupabaseClient client;
  final SupabaseDisposalState disposalState;
}

/// A checked access capability, not an everlasting authentication/approval
/// lease. Future consumers must recheck [client] around every awaited operation.
/// No constructor accepts a client/namespace pair. Namespace authority comes
/// only from the trusted integration registry passed to [driverAccess].
final class VerifiedSupabaseDriverAccess {
  VerifiedSupabaseDriverAccess._(this._source, this._record, this.backend);
  final SupabaseInitializationProvenance _source;
  final _OwnedInitialization _record;
  final DriverBackendIdentity backend;

  /// The original application client, only while provenance is still valid.
  SupabaseClient? get client =>
      _source._currentRecord() == _record ? _record.client : null;
}

/// One-shot initialization boundary. The application uses [application]; a
/// separately constructed instance cannot attest to an already initialized SDK.
/// Instances accept configuration only, never a client, SDK callback or token.
///
/// Supabase Flutter 2.15.4 calls its synchronous _init before its first await.
/// Capture immediately after invoking initialize, then verify the SAME object
/// on completion. This assumption is covered against the installed SDK tests.
/// No await separates the pre-existing check, invocation and initial capture.
///
/// Pre-existing SDK state and repeated initialization never acquire trust.
/// Concurrent/repeated requests revoke this boundary rather than initializing
/// a second client. Failure and observed replacement are permanently fail-closed.
/// Unobserved transient SDK mutations cannot be detected through its public API;
/// trusted composition must exclusively own SDK initialization/replacement.
final class SupabaseInitializationProvenance {
  SupabaseInitializationProvenance();

  static final application = SupabaseInitializationProvenance();
  SupabaseProvenanceState _state = SupabaseProvenanceState.notStarted;
  _OwnedInitialization? _record;
  Future<void>? _pending;
  bool _attempted = false;

  SupabaseProvenanceSnapshot get snapshot {
    _currentRecord();
    return SupabaseProvenanceSnapshot._(_state, _record?.endpoint);
  }

  /// Retains normal startup semantics: demo does not initialize Supabase;
  /// pre-existing state remains available to normal application features.
  /// Credentials are used only for the original SDK initialization, never
  /// copied into the provenance record or returned in its diagnostic view.
  Future<void> initialize(SupabaseEnvironment? environment) {
    final SupabaseEnvironment? validated;
    try {
      validated = environment == null
          ? null
          : EnvConfig.validateSupabaseEnvironment(
              url: environment.url,
              publishableKey: environment.publishableKey,
            );
    } on EnvConfigException {
      _attempted = true;
      _record = null;
      _state = SupabaseProvenanceState.failed;
      rethrow;
    }
    if (_attempted) {
      _record = null;
      _state = SupabaseProvenanceState.unverified;
      return _pending ?? Future<void>.value();
    }
    _attempted = true;
    if (validated == null) {
      _state = SupabaseProvenanceState.demo;
      return Future<void>.value();
    }
    if (_sdkClient() != null) {
      _state = SupabaseProvenanceState.unverified;
      return Future<void>.value();
    }
    _state = SupabaseProvenanceState.initializing;
    try {
      final initialization = Supabase.initialize(
        url: validated.url,
        publishableKey: validated.publishableKey,
        debug: false,
      );
      final created = _sdkClient();
      final disposalState =
          created == null ? null : Supabase.instance.disposalState;
      // Keep unsupported URL forms working as before for normal app startup,
      // but do not publish query/fragment/path material as trusted identity.
      final endpoint = Uri.parse(validated.url);
      final safeEndpoint =
          !endpoint.hasQuery && !endpoint.hasFragment && endpoint.path.isEmpty;
      final pending = _finish(initialization, created,
          safeEndpoint ? endpoint : null, disposalState);
      _pending = pending;
      return pending;
    } on Object {
      _record = null;
      _state = SupabaseProvenanceState.failed;
      throw const SupabaseProvenanceException();
    }
  }

  Future<void> _finish(Future<Supabase> initialization, SupabaseClient? created,
      Uri? endpoint, SupabaseDisposalState? disposalState) async {
    try {
      final result = await initialization;
      if (_state != SupabaseProvenanceState.initializing) return;
      if (disposalState?.hasStarted == true ||
          created?.isDisposingOrDisposed == true) {
        _state = SupabaseProvenanceState.invalidated;
        return;
      }
      if (created == null ||
          disposalState == null ||
          !identical(result.client, created) ||
          !identical(_sdkClient(), created) ||
          endpoint == null) {
        _state = SupabaseProvenanceState.unverified;
        return;
      }
      _record = _OwnedInitialization(endpoint, created, disposalState);
      _state = SupabaseProvenanceState.trusted;
    } on Object {
      _record = null;
      _state = SupabaseProvenanceState.failed;
      throw const SupabaseProvenanceException();
    }
  }

  /// No default namespace, URL-derived namespace, or fallback authorization.
  /// An empty/unknown registry denies Driver access without breaking startup.
  VerifiedSupabaseDriverAccess? driverAccess(
      DriverBackendRegistry approvedBackends) {
    final record = _currentRecord();
    if (record == null) return null;
    final backend = approvedBackends.resolve(record.endpoint);
    return backend == null
        ? null
        : VerifiedSupabaseDriverAccess._(this, record, backend);
  }

  _OwnedInitialization? _currentRecord() {
    final record = _record;
    if (record == null) return null;
    if (record.disposalState.hasStarted ||
        record.client.isDisposingOrDisposed ||
        !identical(_sdkClient(), record.client)) {
      _record = null;
      _state = SupabaseProvenanceState.invalidated;
      return null;
    }
    return record;
  }

  static SupabaseClient? _sdkClient() {
    try {
      final sdk = Supabase.instance;
      if (!sdk.isInitialized || sdk.isDisposingOrDisposed) return null;
      final client = sdk.client;
      return client.isDisposingOrDisposed ? null : client;
    } on AssertionError {
      // instance asserts before initialization in debug/test. In release the
      // public isInitialized flag above detects the same state explicitly.
      return null;
    }
  }
}
