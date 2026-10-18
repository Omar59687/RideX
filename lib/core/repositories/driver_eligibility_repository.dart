import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';

/// Trusted, read-only injection boundary. Owner and reads must use the same
/// authenticated client. No cached UI session, mutation or persistence seam.
abstract interface class DriverEligibilityTransport {
  DriverAuthorityOwner get currentOwner;
  Future<Map<String, Object?>?> readUser(String driverId);
  Future<Map<String, Object?>?> readDriverProfile(String driverId);
}

/// Closed transport classification; never stores raw backend messages.
final class DriverEligibilityReadException implements Exception {
  const DriverEligibilityReadException(this.failure);
  final DriverEligibilityFailure failure;
}

final class DriverEligibilityRepository {
  DriverEligibilityRepository(this._transport);
  final DriverEligibilityTransport _transport;

  Future<DriverEligibilityOutcome> validate() async {
    final owner = _owner();
    if (owner == null || !owner.isUsable) return _invalidated;
    try {
      final user = await _transport.readUser(owner.driverId!);
      if (!_stillOwned(owner)) return _invalidated;
      if (user == null) return _failed(DriverEligibilityFailure.profileMissing);
      final identityFailure = _identity(user['id'], owner.driverId!);
      if (identityFailure != null) return _failed(identityFailure);
      final role = user['role'];
      final blocked = user['is_blocked'];
      if (role is! String || blocked is! bool) {
        return _failed(DriverEligibilityFailure.malformedProfile);
      }
      if (role == 'rider' || role == 'admin') {
        return _failed(DriverEligibilityFailure.notDriver);
      }
      if (role != 'driver') {
        return _failed(DriverEligibilityFailure.malformedProfile);
      }
      if (blocked) return _failed(DriverEligibilityFailure.blocked);
      final profile = await _transport.readDriverProfile(owner.driverId!);
      if (!_stillOwned(owner)) return _invalidated;
      if (profile == null) {
        return _failed(DriverEligibilityFailure.profileMissing);
      }
      final profileFailure = _identity(profile['user_id'], owner.driverId!);
      if (profileFailure != null) return _failed(profileFailure);
      final approval = profile['approval_status'];
      if (approval == 'pending' || approval == 'rejected') {
        return _failed(DriverEligibilityFailure.notApproved);
      }
      if (approval != 'approved') {
        return _failed(DriverEligibilityFailure.malformedProfile);
      }
      return DriverEligible(owner);
    } on Object catch (error) {
      if (!_stillOwned(owner)) return _invalidated;
      return _failed(error is DriverEligibilityReadException
          ? error.failure
          : DriverEligibilityFailure.transportUnavailable);
    }
  }

  DriverAuthorityOwner? _owner() {
    try {
      return _transport.currentOwner;
    } on Object {
      return null;
    }
  }

  bool _stillOwned(DriverAuthorityOwner owner) {
    final current = _owner();
    return current != null && current.isUsable && owner.sameOwner(current);
  }

  static DriverEligibilityFailure? _identity(Object? id, String expected) {
    if (id is! String || !isCanonicalTripId(id)) {
      return DriverEligibilityFailure.malformedProfile;
    }
    return id.toLowerCase() == expected.toLowerCase()
        ? null
        : DriverEligibilityFailure.foreignIdentity;
  }

  static const _invalidated =
      DriverIneligible(DriverEligibilityFailure.sessionInvalidated);
  static DriverIneligible _failed(DriverEligibilityFailure failure) =>
      DriverIneligible(failure);
}
