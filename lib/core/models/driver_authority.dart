import 'package:ridex/core/models/driver_trip_completion.dart';

/// Nonsecret environment identity. Registry entries are trusted deployment
/// configuration, never values obtained from a screen, account or auth token.
final class DriverBackendIdentity {
  DriverBackendIdentity({required this.endpoint, required this.namespace}) {
    if (endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        endpoint.path.isNotEmpty ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:\-]{0,63}$').hasMatch(namespace)) {
      throw ArgumentError('Invalid Driver backend identity.');
    }
  }

  final Uri endpoint;
  final String namespace;
}

/// Explicit allowlist owned by integration composition. No default production
/// mapping is invented here. Unknown endpoints and ambiguous registries fail.
final class DriverBackendRegistry {
  DriverBackendRegistry(Iterable<DriverBackendIdentity> approved)
      : _approved = List.unmodifiable(approved) {
    if (_approved.map((e) => e.endpoint).toSet().length != _approved.length ||
        _approved.map((e) => e.namespace).toSet().length != _approved.length) {
      throw ArgumentError('Ambiguous Driver backend registry.');
    }
  }

  final List<DriverBackendIdentity> _approved;

  DriverBackendIdentity? resolve(Uri endpoint) {
    for (final identity in _approved) {
      if (identity.endpoint == endpoint) return identity;
    }
    return null;
  }
}

/// Injected by Slice B; Slice A never creates or advances a production epoch.
/// Revoke synchronously before logout/login/replacement awaits, observe A-B-A,
/// and never reuse an epoch while an old operation can still complete.
final class DriverAuthorityLifecycle {
  const DriverAuthorityLifecycle({
    required this.epoch,
    required this.isActive,
  });
  final int epoch;
  final bool isActive;
}

typedef DriverAuthorityLifecycleReader = DriverAuthorityLifecycle Function();

/// Captured SDK identity plus binding and injected lifecycle, not UI approval.
final class DriverAuthorityOwner {
  const DriverAuthorityOwner({
    required this.driverId,
    required this.backend,
    required this.epoch,
    required this.hasValidSession,
  });
  final String? driverId;
  final DriverBackendIdentity backend;
  final int epoch;
  final bool hasValidSession;

  bool get isUsable =>
      hasValidSession &&
      epoch >= 0 &&
      driverId != null &&
      isCanonicalTripId(driverId!);

  bool sameOwner(DriverAuthorityOwner other) =>
      driverId?.toLowerCase() == other.driverId?.toLowerCase() &&
      identical(backend, other.backend) &&
      epoch == other.epoch &&
      hasValidSession == other.hasValidSession;
}

enum DriverEligibilityFailure {
  sessionInvalidated,
  profileMissing,
  malformedProfile,
  foreignIdentity,
  notDriver,
  blocked,
  notApproved,
  authorizationDenied,
  transportUnavailable,
}

sealed class DriverEligibilityOutcome {
  const DriverEligibilityOutcome();
}

/// Point-in-time eligibility only. Not a lease, instant remote-revocation
/// guarantee, dispatch permission, or proof of payment/receipt success.
final class DriverEligible extends DriverEligibilityOutcome {
  const DriverEligible(this.owner);
  final DriverAuthorityOwner owner;
}

final class DriverIneligible extends DriverEligibilityOutcome {
  const DriverIneligible(this.failure);
  final DriverEligibilityFailure failure;
}

enum DriverAuthEventKind {
  initialSession,
  signedIn,
  signedOut,
  tokenRefreshed,
  userUpdated,
  passwordRecovery,
  mfaChallengeVerified,
  unknown,
}

/// Ordered observation only, containing no token, key, metadata or SDK type.
/// Asynchronous delivery is NOT synchronous pre-await logout revocation.
final class DriverAuthEvent {
  const DriverAuthEvent(this.kind, this.userId);
  final DriverAuthEventKind kind;
  final String? userId;
}
