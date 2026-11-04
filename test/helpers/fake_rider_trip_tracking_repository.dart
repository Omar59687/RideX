import 'dart:async';

import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/rider_assigned_trip.dart';
import 'package:ridex/core/models/rider_trip_tracking_event.dart';
import 'package:ridex/core/repositories/rider_trip_tracking_repository.dart';

const riderTripIdFixture = 'a1b2c3d4-e5f6-4a1b-8c2d-a1b2c3d4e5f6';
const riderBookingIdFixture = 'b1c2d3e4-f5a6-4b1c-8d2e-b1c2d3e4f5a6';
const riderIdFixture = '33333333-3333-4333-8333-333333333333';
const riderDriverIdFixture = '44444444-4444-4444-8444-444444444444';
const riderVehicleIdFixture = '55555555-5555-4555-8555-555555555555';
const secondaryRiderTripIdFixture = '66666666-6666-4666-8666-666666666666';
const secondaryRiderBookingIdFixture = '77777777-7777-4777-8777-777777777777';
const unrelatedRiderIdFixture = '88888888-8888-4888-8888-888888888888';

/// Deterministic in-memory fake for Rider Trip tracking.
///
/// [authenticatedRiderId] is a test fixture, not proof of a real authenticated
/// session. [emitForeignFor] deliberately bypasses normal Trip scoping for
/// negative tests. Normal [watch] streams are per-Trip and only include
/// currently accessible Trips.
///
/// Once [close] starts, lookups return `null`, new watches are empty, and
/// queued watch events are withheld. Emitting an event throws [StateError].
class FakeRiderTripTrackingRepository implements RiderTripTrackingRepository {
  FakeRiderTripTrackingRepository({
    this.trip,
    Iterable<RiderAssignedTrip> additionalTrips = const [],
    String authenticatedRiderId = riderIdFixture,
    DateTime Function()? clock,
  })  : _additionalTrips = List.unmodifiable(additionalTrips),
        authenticatedRiderId =
            _canonicalId(authenticatedRiderId, 'authenticatedRiderId'),
        _clock = clock ?? DateTime.now;

  RiderAssignedTrip? trip;
  final List<RiderAssignedTrip> _additionalTrips;
  final String authenticatedRiderId;
  Object? bookingLoadError;
  Object? tripLoadError;
  int bookingLoadCount = 0;
  int tripLoadCount = 0;
  int watchCount = 0;
  final List<String> requestedBookingIds = [];
  final List<String> requestedTripIds = [];
  final List<String> watchedTripIds = [];
  final DateTime Function() _clock;
  final StreamController<RiderTripTrackingEvent> _allEvents =
      StreamController<RiderTripTrackingEvent>.broadcast();
  final Map<String, StreamController<RiderTripTrackingEvent>> _eventsByTrip =
      {};
  bool _closed = false;
  Future<void>? _closeFuture;

  bool get isClosed => _closed;

  bool get hasListener =>
      _allEvents.hasListener ||
      _eventsByTrip.values.any((controller) => controller.hasListener);

  /// Raw test-only emission log; callers use [watch] for scoped delivery.
  Stream<RiderTripTrackingEvent> get events => _allEvents.stream;

  @override
  Future<RiderAssignedTrip?> findByBooking({
    required String bookingRequestId,
  }) async {
    final canonicalBookingId =
        _canonicalId(bookingRequestId, 'bookingRequestId').toLowerCase();
    bookingLoadCount++;
    requestedBookingIds.add(bookingRequestId);
    if (_closed) return null;
    final error = bookingLoadError;
    if (error != null) throw error;
    for (final candidate in _allTrips) {
      if (_isAuthenticatedRider(candidate.riderId) &&
          candidate.bookingRequestId.toLowerCase() == canonicalBookingId) {
        return candidate;
      }
    }
    return null;
  }

  @override
  Future<RiderAssignedTrip?> findByTrip({required String tripId}) async {
    final canonicalTripId = _canonicalId(tripId, 'tripId');
    tripLoadCount++;
    requestedTripIds.add(tripId);
    if (_closed) return null;
    final error = tripLoadError;
    if (error != null) throw error;
    final current = _findTrip(canonicalTripId);
    if (current == null || !_isAuthenticatedRider(current.riderId)) {
      return null;
    }
    return current;
  }

  @override
  Stream<RiderTripTrackingEvent> watch({required String tripId}) {
    final canonicalTripId = _canonicalId(tripId, 'tripId');
    watchCount++;
    watchedTripIds.add(tripId);
    if (_closed) return Stream<RiderTripTrackingEvent>.empty();
    final current = _findTrip(canonicalTripId);
    if (current == null || !_isAuthenticatedRider(current.riderId)) {
      return Stream<RiderTripTrackingEvent>.empty();
    }
    return _controllerFor(canonicalTripId)
        .stream
        .where((_) => !_closed && _ownsTrip(canonicalTripId));
  }

  /// Emits an event without deduplication or reordering.
  ///
  /// Duplicate, stale, and out-of-order events are intentionally preserved for
  /// downstream reconciliation tests. Delivery remains scoped to
  /// [RiderTripTrackingEvent.tripId].
  void emit(RiderTripTrackingEvent event) {
    if (_closed) {
      throw StateError('Fake repository is closed.');
    }
    _allEvents.add(event);
    final current = _findTrip(event.tripId);
    if (current != null &&
        _ownsTrip(event.tripId) &&
        (event is! RiderTripSnapshot ||
            _isAuthenticatedRider(event.trip.riderId))) {
      _eventsByTrip[event.tripId.toLowerCase()]?.add(event);
    }
  }

  /// Injects [event] into [watchedTripId]'s listener even when the event
  /// belongs to another Trip. Use only for foreign-event rejection tests.
  void emitForeignFor({
    required String watchedTripId,
    required RiderTripTrackingEvent event,
  }) {
    if (_closed) {
      throw StateError('Fake repository is closed.');
    }
    final canonicalWatchedTripId = _canonicalId(watchedTripId, 'watchedTripId');
    if (event.tripId.toLowerCase() == canonicalWatchedTripId.toLowerCase()) {
      throw ArgumentError.value(
        event,
        'event',
        'Must target a different Trip.',
      );
    }
    final controller = _eventsByTrip[canonicalWatchedTripId.toLowerCase()];
    if (controller == null || !controller.hasListener) {
      throw StateError('No active listener for Trip $watchedTripId.');
    }
    controller.add(event);
    _allEvents.add(event);
  }

  void emitSnapshot([RiderAssignedTrip? next]) {
    final current = next ?? trip;
    if (current == null) {
      throw StateError('No assigned trip is seeded.');
    }
    emit(RiderTripSnapshot(current));
  }

  void emitStatus({
    required int tripVersion,
    required int eventSequence,
    required DriverTripLifecycleStatus status,
    DateTime? occurredAt,
  }) {
    final current = trip;
    if (current == null) {
      throw StateError('No assigned trip is seeded.');
    }
    emit(
      RiderTripStatusChanged(
        tripId: current.tripId,
        tripVersion: tripVersion,
        eventSequence: eventSequence,
        status: status,
        occurredAt: occurredAt ?? _clock(),
      ),
    );
  }

  void emitLocation({
    required DriverLocationSample sample,
    DateTime? receivedAt,
  }) {
    final current = trip;
    if (current == null) {
      throw StateError('No assigned trip is seeded.');
    }
    emit(
      RiderTripLocationChanged(
        tripId: current.tripId,
        sample: sample,
        receivedAt: receivedAt ?? _clock(),
      ),
    );
  }

  void emitDisconnected({String? reason, DateTime? disconnectedAt}) {
    final current = trip;
    if (current == null) {
      throw StateError('No assigned trip is seeded.');
    }
    emit(
      RiderTripTrackingDisconnected(
        tripId: current.tripId,
        disconnectedAt: disconnectedAt ?? _clock(),
        reason: reason,
      ),
    );
  }

  /// A paused listener may delay completion, but not shutdown of other Trips.
  Future<void> close() => _closeFuture ??= _closeAll();

  Future<void> _closeAll() async {
    _closed = true;
    final closures = [
      for (final controller in _eventsByTrip.values) controller.close(),
      _allEvents.close(),
    ];
    await Future.wait(closures);
    _eventsByTrip.clear();
  }

  Iterable<RiderAssignedTrip> get _allTrips sync* {
    final current = trip;
    if (current != null) yield current;
    yield* _additionalTrips;
  }

  RiderAssignedTrip? _findTrip(String tripId) {
    final canonicalTripId = tripId.toLowerCase();
    for (final candidate in _allTrips) {
      if (candidate.tripId.toLowerCase() == canonicalTripId) {
        return candidate;
      }
    }
    return null;
  }

  bool _isAuthenticatedRider(String riderId) =>
      riderId.toLowerCase() == authenticatedRiderId.toLowerCase();

  bool _ownsTrip(String tripId) {
    final current = _findTrip(tripId);
    return current != null && _isAuthenticatedRider(current.riderId);
  }

  StreamController<RiderTripTrackingEvent> _controllerFor(String tripId) {
    return _eventsByTrip.putIfAbsent(
      tripId.toLowerCase(),
      () => StreamController<RiderTripTrackingEvent>.broadcast(),
    );
  }
}

String _canonicalId(String value, String name) {
  if (!isCanonicalTripId(value)) {
    throw ArgumentError.value(value, name, 'Must be a canonical UUID.');
  }
  return value;
}

RiderAssignedTrip riderAssignedTripFixture({
  String tripId = riderTripIdFixture,
  String bookingRequestId = riderBookingIdFixture,
  String riderId = riderIdFixture,
  String driverId = riderDriverIdFixture,
  String vehicleId = riderVehicleIdFixture,
  int version = 3,
  DriverTripLifecycleStatus status = DriverTripLifecycleStatus.accepted,
  PaymentMethod paymentMethod = PaymentMethod.cash,
  String? driverDisplayName,
  bool includeVehicleDetails = true,
  String? routeGeometryReference = 'test-route',
  List<RiderTripPlace>? stops,
  RiderTripPlace? pickup,
  RiderTripPlace? destination,
  int routeDistanceMeters = 1240,
  int routeDurationSeconds = 420,
  int originalFareFils = 7350,
  int currentFareFils = 7350,
  String currency = 'JOD',
}) {
  return RiderAssignedTrip(
    tripId: tripId,
    bookingRequestId: bookingRequestId,
    riderId: riderId,
    version: version,
    status: status,
    paymentMethod: paymentMethod,
    pickup: pickup ??
        RiderTripPlace(
          point: LocationPoint(
            latitude: 31.9539,
            longitude: 35.9106,
            accuracyMeters: 8,
          ),
          label: 'Test pickup',
        ),
    destination: destination ??
        RiderTripPlace(
          point: LocationPoint(
            latitude: 31.97,
            longitude: 35.93,
            accuracyMeters: 8,
          ),
          label: 'Test destination',
        ),
    stops: stops ?? const [],
    routeDistanceMeters: routeDistanceMeters,
    routeDurationSeconds: routeDurationSeconds,
    routeGeometryReference: routeGeometryReference,
    originalFareFils: originalFareFils,
    currentFareFils: currentFareFils,
    currency: currency,
    driver: RiderDriverSummary(
      driverId: driverId,
      displayName: driverDisplayName,
    ),
    vehicle: RiderVehicleSummary(
      vehicleId: vehicleId,
      make: includeVehicleDetails ? 'Test Make' : null,
      model: includeVehicleDetails ? 'Test Model' : null,
      color: includeVehicleDetails ? 'Test Color' : null,
      registrationPlate: includeVehicleDetails ? 'TEST 123' : null,
      seatCapacity: includeVehicleDetails ? 4 : null,
    ),
    acceptedAt: DateTime.utc(2026, 11, 4, 8),
    updatedAt: DateTime.utc(2026, 11, 4, 8, 5),
  );
}
