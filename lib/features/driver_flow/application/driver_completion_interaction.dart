import 'package:flutter/foundation.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';
import '../data/canonical_driver_repository.dart';

/// Driver-owned presentation/dispatch checks; never a command or journal owner.
abstract interface class DriverCompletionInteraction implements Listenable {
  bool get isCurrent;
  Future<bool> verify({DriverCompleteTripCommand? expected});
  Future<bool> confirmCompleted(DriverCompleteTripCommand command);
}

/// Trusted integration configuration, not route arguments or account metadata.
/// No default backend/actor/vehicle approval is supplied by C02.
final class DriverCompletionInteractionConfiguration {
  const DriverCompletionInteractionConfiguration({
    required this.backend,
    required this.driverId,
    required this.vehicleId,
    required this.reviewedNonproduction,
    this.enabled = false,
  });
  final DriverBackendIdentity backend;
  final String driverId, vehicleId;
  final bool reviewedNonproduction, enabled;
}

/// Reuses C01 canonical reads. The host must borrow the same verified normal-user
/// SDK client as the existing completion source/repository and supply real
/// connection invalidations. A connection event is not assignment authority.
final class CanonicalDriverCompletionInteraction extends ChangeNotifier
    implements DriverCompletionInteraction {
  CanonicalDriverCompletionInteraction({
    required this.configuration,
    required CanonicalDriverPort port,
    required this.loadContext,
    required this.readVehicle,
    required this.connected,
    required this.sessionCurrent,
  })  : _port = port,
        _owner = port.currentOwner,
        _session = port.sessionIdentity,
        _repository = CanonicalDriverRepository(port) {
    connected.addListener(_connectionChanged);
  }
  final DriverCompletionInteractionConfiguration configuration;
  final CanonicalDriverPort _port;
  final DriverAuthorityOwner _owner;
  final Object? _session;
  final CanonicalDriverRepository _repository;
  final Future<CanonicalDriverCompletionContext?> Function() loadContext;
  final Future<Map<String, Object?>?> Function() readVehicle;
  final ValueListenable<bool> connected;
  final bool Function() sessionCurrent;
  bool _disposed = false;

  @override
  bool get isCurrent {
    try {
      final c = configuration;
      return !_disposed &&
          !kReleaseMode &&
          c.enabled &&
          c.reviewedNonproduction &&
          connected.value &&
          sessionCurrent() &&
          isCanonicalTripId(c.driverId) &&
          isCanonicalTripId(c.vehicleId) &&
          _owner.isUsable &&
          _owner.sameOwner(_port.currentOwner) &&
          identical(c.backend, _owner.backend) &&
          _session != null &&
          identical(_session, _port.sessionIdentity) &&
          c.driverId.toLowerCase() == _owner.driverId?.toLowerCase();
    } on Object {
      return false;
    }
  }

  void _connectionChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  Future<bool> verify({DriverCompleteTripCommand? expected}) async {
    if (!isCurrent) return false;
    try {
      final context = await loadContext();
      if (!isCurrent ||
          context == null ||
          context.driverId.toLowerCase() !=
              configuration.driverId.toLowerCase() ||
          (expected != null && !context.command.isExactReplayOf(expected))) {
        return false;
      }
      final result = await _repository.inspectTransition(
        tripId: context.command.tripId,
        expectedVersion: context.command.expectedTripVersion,
        requestedStatus: DriverTripLifecycleStatus.completed,
      );
      if (!isCurrent ||
          result.outcome != CanonicalDriverOutcome.observed ||
          result.trip?.vehicleId != configuration.vehicleId.toLowerCase()) {
        return false;
      }
      final vehicle = await readVehicle();
      return isCurrent &&
          result.outcome == CanonicalDriverOutcome.observed &&
          vehicle?['id'] == configuration.vehicleId.toLowerCase() &&
          vehicle?['driver_id'] == configuration.driverId.toLowerCase() &&
          vehicle?['is_active'] == true;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> confirmCompleted(DriverCompleteTripCommand command) async {
    if (!isCurrent) return false;
    try {
      final result = await _repository.readTrip(command.tripId);
      final trip = result.trip;
      return isCurrent &&
          result.outcome == CanonicalDriverOutcome.observed &&
          trip != null &&
          trip.id == command.tripId.toLowerCase() &&
          trip.driverId == configuration.driverId.toLowerCase() &&
          trip.vehicleId == configuration.vehicleId.toLowerCase() &&
          trip.status == DriverTripLifecycleStatus.completed &&
          trip.version > command.expectedTripVersion;
    } on Object {
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    connected.removeListener(_connectionChanged);
    _repository.dispose();
    super.dispose();
  }
}
