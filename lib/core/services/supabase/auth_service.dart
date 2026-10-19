import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/repositories/driver_eligibility_repository.dart';
import 'package:ridex/core/services/supabase/supabase_initialization_provenance.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  const AuthService(this._client);

  final SupabaseClient _client;

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
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> metadata,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: metadata,
    );
  }

  Future<void> signOut() => _client.auth.signOut();
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
