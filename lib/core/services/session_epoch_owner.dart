import 'dart:async';

import 'package:ridex/core/models/driver_authority.dart';

/// Token-free observation of the authenticated SDK, never a UI profile.
typedef SessionIdentityReader = String? Function();

/// One owner for the application auth client's lifetime. Events can revoke or
/// preserve ownership, but cannot admit it after revocation. Only startup and a
/// matching explicit authentication completion can do that.
final class SessionEpochOwner {
  SessionEpochOwner({
    required SessionIdentityReader currentIdentity,
    required Stream<DriverAuthEvent> events,
    String? startupIdentity,
    bool Function()? hasValidSession,
  })  : _currentIdentity = currentIdentity,
        _hasValidSession = hasValidSession {
    _userId = _valid() ? _identity() : null;
    _restoringUserId = _userId == null ? startupIdentity : null;
    _subscription = events.listen(_observe, onError: (Object _, StackTrace __) {
      revoke();
    }, onDone: revoke);
  }

  final SessionIdentityReader _currentIdentity;
  final bool Function()? _hasValidSession;
  late final StreamSubscription<DriverAuthEvent> _subscription;
  // Never reset on logout, provider rebuild, or client replacement.
  static int _clock = 0;
  int _epoch = ++_clock;
  String? _userId;
  String? _restoringUserId;
  bool _disposed = false;
  bool _suspended = false;
  Future<void>? _disposal;

  bool get isDisposed => _disposed;

  bool _valid() {
    try {
      return _hasValidSession?.call() ?? true;
    } on Object {
      return false;
    }
  }

  String? _identity() {
    try {
      return _currentIdentity();
    } on Object {
      return null;
    }
  }

  DriverAuthorityLifecycle get lifecycle {
    if (_userId != null && _identity() != _userId) revoke();
    if (_userId != null && !_valid() && !_suspended) {
      // Expiry suspends this identity and invalidates in-flight operations.
      // Logout, loss, errors and disposal cancel the refresh window entirely.
      _suspended = true;
      _epoch = ++_clock;
    }
    return DriverAuthorityLifecycle(
        epoch: _epoch, isActive: !_disposed && !_suspended && _userId != null);
  }

  /// A generation ticket, with no credentials or SDK session attached.
  int beginAuthentication() {
    revoke();
    return _epoch;
  }

  bool completeAuthentication(int ticket, String? userId) {
    if (_disposed ||
        ticket != _epoch ||
        userId == null ||
        !_valid() ||
        _identity() != userId) {
      return false;
    }
    _userId = userId;
    _suspended = false;
    return true;
  }

  void revoke() {
    if (_disposed) return;
    _userId = null;
    _restoringUserId = null;
    _suspended = false;
    _epoch = ++_clock;
  }

  void _observe(DriverAuthEvent event) {
    if (_disposed) return;
    if (event.kind == DriverAuthEventKind.signedOut) {
      revoke();
      return;
    }
    if (_restoringUserId != null &&
        (event.kind == DriverAuthEventKind.initialSession ||
            event.kind == DriverAuthEventKind.tokenRefreshed)) {
      final restored = _identity();
      if (_valid() &&
          restored != null &&
          restored == event.userId &&
          restored == _restoringUserId) {
        _restoringUserId = null;
        _epoch = ++_clock;
        _userId = restored;
      } else if (restored != null && restored != _restoringUserId) {
        revoke();
      }
      return;
    }
    // A delayed event cannot re-admit a revoked user, even when the SDK has
    // since installed that user's session. Refresh only preserves a live owner.
    if (_userId != null &&
        (event.userId != _userId || _identity() != _userId)) {
      revoke();
    }
    if (_userId != null &&
        _suspended &&
        _valid() &&
        event.kind == DriverAuthEventKind.tokenRefreshed) {
      _epoch = ++_clock;
      _suspended = false;
    }
  }

  Future<void> dispose() {
    if (_disposal != null) return _disposal!;
    revoke();
    _disposed = true;
    return _disposal = _subscription.cancel();
  }
}
