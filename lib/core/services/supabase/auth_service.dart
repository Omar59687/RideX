import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/repositories/driver_eligibility_repository.dart';
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

enum DriverBindingFailure { invalidConfiguration, unknownBackend }

final class DriverBindingException implements Exception {
  const DriverBindingException(this.failure);
  final DriverBindingFailure failure;
  @override
  String toString() => 'DriverBindingException($failure)';
}

/// Unwired construction boundary. The trusted integration owner supplies the
/// reviewed endpoint registry and validated deployment environment, NOT a
/// screen-provided namespace. No registry entries are activated in Slice A.
///
/// Creates and exclusively retains its SDK client, so an arbitrary existing
/// client cannot be relabeled with a different endpoint/namespace or privileged
/// headers. Slice B must explicitly adopt this client/auth boundary; it must
/// not run a second independent authority beside the existing singleton.
/// No authentication/session copying, automatic login or provider registration.
final class SupabaseDriverAuthorityBinding
    implements DriverEligibilityTransport {
  SupabaseDriverAuthorityBinding._(this._client, this.backend, this._lifecycle);

  factory SupabaseDriverAuthorityBinding.create({
    required SupabaseEnvironment environment,
    required DriverBackendRegistry approvedBackends,
    required DriverAuthorityLifecycleReader lifecycleReader,
  }) {
    final SupabaseEnvironment? validated;
    try {
      validated = EnvConfig.validateSupabaseEnvironment(
        url: environment.url,
        publishableKey: environment.publishableKey,
      );
    } on EnvConfigException {
      throw const DriverBindingException(
          DriverBindingFailure.invalidConfiguration);
    }
    if (validated == null) {
      throw const DriverBindingException(
          DriverBindingFailure.invalidConfiguration);
    }
    final backend = approvedBackends.resolve(Uri.parse(validated.url));
    if (backend == null) {
      throw const DriverBindingException(DriverBindingFailure.unknownBackend);
    }
    return SupabaseDriverAuthorityBinding._(
      SupabaseClient(validated.url, validated.publishableKey),
      backend,
      lifecycleReader,
    );
  }

  final SupabaseClient _client;
  final DriverBackendIdentity backend;
  final DriverAuthorityLifecycleReader _lifecycle;
  bool _disposed = false;

  AuthService get authService => AuthService(_client);

  @override
  DriverAuthorityOwner get currentOwner {
    final lifecycle = _lifecycle();
    final session = _client.auth.currentSession;
    return DriverAuthorityOwner(
      driverId: session?.user.id,
      backend: backend,
      epoch: lifecycle.epoch,
      hasValidSession: !_disposed &&
          lifecycle.isActive &&
          session != null &&
          !session.isExpired,
    );
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
      final row = await _client
          .from(table)
          .select(columns)
          .eq(identityColumn, driverId)
          .maybeSingle();
      if (!owner.sameOwner(currentOwner) || !currentOwner.isUsable) {
        throw const DriverEligibilityReadException(
            DriverEligibilityFailure.sessionInvalidated);
      }
      return row;
    } on Object catch (error) {
      if (!owner.sameOwner(currentOwner) || !currentOwner.isUsable) {
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

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _client.dispose();
  }
}
