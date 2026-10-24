import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/services/session_epoch_owner.dart';
import 'package:ridex/core/repositories/driver_eligibility_repository.dart';
import 'package:ridex/core/services/supabase/supabase_initialization_provenance.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  factory AuthService(SupabaseClient client) =>
      _services[client] ??= AuthService._(client);

  AuthService._(this._client) {
    _epochs = SessionEpochOwner(
      currentIdentity: () {
        if (_client.isDisposingOrDisposed) return null;
        return _client.auth.currentSession?.user.id;
      },
      hasValidSession: () {
        final session = _client.auth.currentSession;
        return !_client.isDisposingOrDisposed &&
            session != null &&
            !session.isExpired;
      },
      events: driverAuthEvents(),
      // Supabase initialize can return while expired-session recovery awaits.
      // This one-shot startup window is cancelled by every revocation.
      startupIdentity: _client.auth.currentSession?.user.id,
    );
  }

  // Wrappers around the same application client must share one authority.
  static final _services = Expando<AuthService>();
  late final SessionEpochOwner _epochs;
  Future<void>? _signingOut;
  bool _authenticationPending = false;

  final SupabaseClient _client;

  DriverAuthorityLifecycle get driverLifecycle => _epochs.lifecycle;

  /// Must precede tracking cleanup and every other logout await.
  void revokeSession() => _epochs.revoke();

  /// B1-B composition seam. No registry default or live completion wiring.
  SupabaseDriverAuthorityBinding driverBinding(
      VerifiedSupabaseDriverAccess access) {
    if (!identical(access.client, _client)) {
      throw const DriverBindingException(DriverBindingFailure.untrustedAccess);
    }
    return SupabaseDriverAuthorityBinding.create(
        access: access, lifecycleReader: () => driverLifecycle);
  }

  Future<void> dispose() => _epochs.dispose();

  Stream<void> authStateChanges() {
    return _client.auth.onAuthStateChange.map((_) {});
  }

  /// Additive, ordered, token-free SDK observations. Slice B must revoke
  /// synchronously BEFORE calling signOut/signIn; this stream cannot do that.
  Stream<DriverAuthEvent> driverAuthEvents() =>
      _client.auth.onAuthStateChange.map((state) => DriverAuthEvent(
            switch (state.event) {
              AuthChangeEvent.initialSession =>
                DriverAuthEventKind.initialSession,
              AuthChangeEvent.signedIn => DriverAuthEventKind.signedIn,
              AuthChangeEvent.signedOut => DriverAuthEventKind.signedOut,
              AuthChangeEvent.tokenRefreshed =>
                DriverAuthEventKind.tokenRefreshed,
              AuthChangeEvent.userUpdated => DriverAuthEventKind.userUpdated,
              AuthChangeEvent.passwordRecovery =>
                DriverAuthEventKind.passwordRecovery,
              AuthChangeEvent.mfaChallengeVerified =>
                DriverAuthEventKind.mfaChallengeVerified,
              _ => DriverAuthEventKind.unknown,
            },
            state.session?.user.id,
          ));

  Session? get currentSession => _client.auth.currentSession;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _authenticate(() =>
        _client.auth.signInWithPassword(email: email, password: password));
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> metadata,
  }) {
    return _authenticate(() => _client.auth.signUp(
          email: email,
          password: password,
          data: metadata,
        ));
  }

  Future<AuthResponse> _authenticate(
      Future<AuthResponse> Function() run) async {
    final ticket = _epochs.beginAuthentication();
    if (_authenticationPending ||
        _signingOut != null ||
        _epochs.isDisposed ||
        _client.isDisposingOrDisposed) {
      throw const AuthException('Authentication is unavailable.');
    }
    // Prevent overlapping SDK logins from installing an older session over a
    // newer accepted identity. A concurrent attempt revokes and fails closed;
    // callers can explicitly retry after the pending operation finishes.
    _authenticationPending = true;
    try {
      final response = await run();
      if (response.session == null) {
        return response; // Confirmation-only signup.
      }
      if (!_epochs.completeAuthentication(ticket, response.session?.user.id)) {
        // GoTrue installs and emits the session before its future completes.
        // Remove this rejected session so a cold start cannot restore it. No
        // newer login can be accepted while this owned cleanup is outstanding.
        if (identical(_client.auth.currentSession, response.session) &&
            !_client.isDisposingOrDisposed) {
          try {
            await _client.auth.signOut();
          } on Object {
            // The SDK removes the local session before awaiting remote logout.
            // Authority stays revoked regardless of remote cleanup failure.
          }
        }
        throw const AuthException('Authentication is unavailable.');
      }
      return response;
    } on Object {
      if (_epochs.lifecycle.epoch == ticket) _epochs.revoke();
      rethrow;
    } finally {
      _authenticationPending = false;
    }
  }

  Future<void> signOut() {
    revokeSession();
    return _signingOut ??= _finishSignOut();
  }

  Future<void> _finishSignOut() async {
    try {
      await _client.auth.signOut();
    } finally {
      _signingOut = null;
    }
  }
}

enum DriverBindingFailure { untrustedAccess }

final class DriverBindingException implements Exception {
  const DriverBindingException(this.failure);
  final DriverBindingFailure failure;
  @override
  String toString() => 'DriverBindingException($failure)';
}

/// Unwired, borrowed access to the B0-verified application singleton. Only the
/// provenance capability supplies the client and backend identity. This binding
/// never initializes, authenticates, signs out, or disposes the shared client.
/// Session epochs remain the responsibility of the injected lifecycle owner.
final class SupabaseDriverAuthorityBinding
    implements DriverEligibilityTransport {
  SupabaseDriverAuthorityBinding._(
      this._access, this._client, this.backend, this._lifecycle);

  factory SupabaseDriverAuthorityBinding.create({
    required VerifiedSupabaseDriverAccess access,
    required DriverAuthorityLifecycleReader lifecycleReader,
  }) {
    final client = access.client;
    if (client == null) {
      throw const DriverBindingException(DriverBindingFailure.untrustedAccess);
    }
    return SupabaseDriverAuthorityBinding._(
        access, client, access.backend, lifecycleReader);
  }

  final VerifiedSupabaseDriverAccess _access;
  final SupabaseClient _client;
  final DriverBackendIdentity backend;
  final DriverAuthorityLifecycleReader _lifecycle;
  bool _disposed = false;

  // Never use the retained SDK object without rechecking its capability.
  SupabaseClient? get _trustedClient {
    if (_disposed) return null;
    final current = _access.client;
    if (!identical(current, _client) || !identical(_access.backend, backend)) {
      return null;
    }
    return current;
  }

  @override
  DriverAuthorityOwner get currentOwner {
    try {
      final lifecycle = _lifecycle();
      final session = _trustedClient?.auth.currentSession;
      return DriverAuthorityOwner(
        driverId: session?.user.id,
        backend: backend,
        epoch: lifecycle.epoch,
        hasValidSession:
            lifecycle.isActive && session != null && !session.isExpired,
      );
    } on Object {
      return DriverAuthorityOwner(
          driverId: null, backend: backend, epoch: -1, hasValidSession: false);
    }
  }

  bool _stillOwned(DriverAuthorityOwner owner) {
    final current = currentOwner;
    return current.isUsable && owner.sameOwner(current);
  }

  @override
  Future<Map<String, Object?>?> readUser(String driverId) =>
      _read('users', 'id, role, is_blocked', 'id', driverId);

  @override
  Future<Map<String, Object?>?> readDriverProfile(String driverId) =>
      _read('driver_profiles', 'user_id, approval_status', 'user_id', driverId);

  Future<Map<String, Object?>?> _read(String table, String columns,
      String identityColumn, String driverId) async {
    final owner = currentOwner;
    if (!owner.isUsable ||
        owner.driverId?.toLowerCase() != driverId.toLowerCase()) {
      throw const DriverEligibilityReadException(
          DriverEligibilityFailure.sessionInvalidated);
    }
    try {
      final client = _trustedClient;
      if (client == null || !_stillOwned(owner)) {
        throw const DriverEligibilityReadException(
            DriverEligibilityFailure.sessionInvalidated);
      }
      final row = await client
          .from(table)
          .select(columns)
          .eq(identityColumn, driverId)
          .maybeSingle();
      if (!_stillOwned(owner)) {
        throw const DriverEligibilityReadException(
            DriverEligibilityFailure.sessionInvalidated);
      }
      return row;
    } on Object catch (error) {
      if (!_stillOwned(owner)) {
        throw const DriverEligibilityReadException(
            DriverEligibilityFailure.sessionInvalidated);
      }
      if (error is DriverEligibilityReadException) rethrow;
      final failure = switch (error) {
        AuthException() => DriverEligibilityFailure.sessionInvalidated,
        PostgrestException(code: '42501' || '403') =>
          DriverEligibilityFailure.authorizationDenied,
        PostgrestException(
          code: 'PGRST301' ||
              'PGRST302' ||
              'PGRST303' ||
              '28000' ||
              '28P01' ||
              '401'
        ) =>
          DriverEligibilityFailure.sessionInvalidated,
        FormatException() ||
        TypeError() =>
          DriverEligibilityFailure.malformedProfile,
        _ => DriverEligibilityFailure.transportUnavailable,
      };
      throw DriverEligibilityReadException(failure);
    }
  }

  /// Revoke local access before returning; the application owns SDK cleanup.
  Future<void> dispose() {
    _disposed = true;
    return Future<void>.value();
  }
}
