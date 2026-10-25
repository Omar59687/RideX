import 'dart:math';

import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/repositories/driver_eligibility_repository.dart';
import 'package:ridex/core/services/supabase/auth_service.dart';
import 'package:ridex/core/services/supabase/supabase_initialization_provenance.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum DriverCashContextFailure { authorizationLost, unavailable, changed }

final class DriverCashContextException implements Exception {
  const DriverCashContextException(this.failure);
  final DriverCashContextFailure failure;
}

/// Discovers the active Trip from canonical availability, never a screen ID.
/// Pins the application owner, SDK Session and initial Trip/version. Re-reading
/// a changed Trip cannot silently create a replacement completion intent.
final class SupabaseDriverCompletionSource
    implements CanonicalDriverCompletionSource {
  SupabaseDriverCompletionSource({
    required VerifiedSupabaseDriverAccess access,
    required SupabaseDriverAuthorityBinding authority,
  })  : _access = access,
        _authority = authority,
        _owner = authority.currentOwner,
        _session = access.client?.auth.currentSession;

  final VerifiedSupabaseDriverAccess _access;
  final SupabaseDriverAuthorityBinding _authority;
  final DriverAuthorityOwner _owner;
  final Session? _session;
  CanonicalDriverCompletionContext? _context;
  bool _disposed = false;
  DriverCashContextFailure? lastFailure;

  bool get isCurrent =>
      !_disposed &&
      _session != null &&
      !_session.isExpired &&
      _owner.isUsable &&
      identical(_access.backend, _owner.backend) &&
      identical(_access.client?.auth.currentSession, _session) &&
      _authority.currentOwner.isUsable &&
      _owner.sameOwner(_authority.currentOwner);

  void dispose() => _disposed = true;

  Never _fail(DriverCashContextFailure failure) {
    lastFailure = failure;
    throw DriverCashContextException(failure);
  }

  void _requireCurrent() {
    if (!isCurrent) _fail(DriverCashContextFailure.authorizationLost);
  }

  Future<DriverCompletionSessionSnapshot> readSession() async {
    _requireCurrent();
    final result = await DriverEligibilityRepository(_authority).validate();
    _requireCurrent();
    if (result is! DriverEligible || !_owner.sameOwner(result.owner)) {
      _fail(result is DriverIneligible &&
              result.failure == DriverEligibilityFailure.transportUnavailable
          ? DriverCashContextFailure.unavailable
          : DriverCashContextFailure.authorizationLost);
    }
    return DriverCompletionSessionSnapshot(
        driverId: _owner.driverId, epoch: _owner.epoch, isApprovedDriver: true);
  }

  Future<Map<String, dynamic>?> _availability() async {
    _requireCurrent();
    final row = await _access.client!
        .from('driver_availability')
        .select('driver_id,state,active_trip_id')
        .eq('driver_id', _owner.driverId!)
        .maybeSingle();
    _requireCurrent();
    return row;
  }

  @override
  Future<CanonicalDriverCompletionContext?> load() async {
    try {
      await readSession();
      final availability = await _availability();
      if (availability == null || availability['state'] != 'onTrip') {
        return null;
      }
      if (availability['driver_id'] != _owner.driverId) {
        _fail(DriverCashContextFailure.authorizationLost);
      }
      final tripId = availability['active_trip_id'];
      if (tripId is! String || !isCanonicalTripId(tripId)) return null;
      final row = await _access.client!
          .from('trips')
          .select('id,driver_id,status,version,payment_method')
          .eq('id', tripId)
          .maybeSingle();
      _requireCurrent();
      if (row == null) return null;
      if (row['id'] != tripId || row['driver_id'] != _owner.driverId) {
        _fail(DriverCashContextFailure.authorizationLost);
      }
      final version = row['version'];
      if (row['status'] != 'inProgress' ||
          row['payment_method'] != 'cash' ||
          version is! int ||
          version <= 0) {
        return null;
      }
      // Detect active-Trip replacement and eligibility loss during the reads.
      final current = await _availability();
      await readSession();
      if (current?['driver_id'] != _owner.driverId ||
          current?['state'] != 'onTrip' ||
          current?['active_trip_id'] != tripId) {
        _fail(DriverCashContextFailure.changed);
      }
      final previous = _context;
      if (previous != null) {
        if (previous.command.tripId != tripId ||
            previous.command.expectedTripVersion != version) {
          _fail(DriverCashContextFailure.changed);
        }
        return previous;
      }
      final random = Random.secure();
      final key = List.generate(
              32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
      return _context = CanonicalDriverCompletionContext(
          driverId: _owner.driverId!,
          command: DriverCompleteTripCommand(
              tripId: tripId,
              expectedTripVersion: version,
              idempotencyKey: key));
    } on DriverCashContextException {
      rethrow;
    } on Object {
      _fail(isCurrent
          ? DriverCashContextFailure.unavailable
          : DriverCashContextFailure.authorizationLost);
    }
  }
}
