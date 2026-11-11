import 'dart:async';

import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_assigned_trip.dart';
import 'package:ridex/core/models/rider_trip_tracking_event.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/models/trip_realtime.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/rider_trip_tracking_repository.dart';
import 'package:ridex/core/services/trips/trip_realtime_adapter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Canonical Rider Trip details read plus D02 advisory notifications. Each
/// notification is followed by a full RLS read; no payload is projected into
/// Rider-visible Trip state.
final class SupabaseRiderTripTrackingRepository
    implements RiderTripTrackingRepository {
  SupabaseRiderTripTrackingRepository(
    this._client, {
    required TripRealtimeAdapter realtime,
    required SessionState Function() readSession,
  })  : _realtime = realtime,
        _readSession = readSession;

  final SupabaseClient _client;
  final TripRealtimeAdapter _realtime;
  final SessionState Function() _readSession;

  @override
  Future<RiderAssignedTrip?> findByBooking({
    required String bookingRequestId,
  }) async {
    if (!isCanonicalTripId(bookingRequestId)) {
      throw ArgumentError.value(bookingRequestId, 'bookingRequestId');
    }
    final owner = _captureOwner();
    try {
      await _verifyProfile(owner);
      final rows = await _client
          .from('trips')
          .select('id')
          .eq('booking_request_id', bookingRequestId)
          .eq('rider_id', owner.riderId)
          .limit(2);
      _requireCurrent(owner);
      if (rows.length > 1) throw const _TripReadFailure();
      if (rows.isEmpty) return null;
      final tripId = rows.single['id'];
      if (tripId is! String || !isCanonicalTripId(tripId)) {
        throw const _TripReadFailure();
      }
      final trip = await _readTrip(tripId, owner);
      if (trip?.bookingRequestId.toLowerCase() !=
          bookingRequestId.toLowerCase()) {
        return null;
      }
      return trip;
    } on _SessionReplaced {
      rethrow;
    } on Object {
      _requireCurrent(owner);
      rethrow;
    }
  }

  @override
  Future<RiderAssignedTrip?> findByTrip({required String tripId}) async {
    if (!isCanonicalTripId(tripId)) {
      throw ArgumentError.value(tripId, 'tripId');
    }
    final owner = _captureOwner();
    try {
      await _verifyProfile(owner);
      return await _readTrip(tripId, owner);
    } on _SessionReplaced {
      rethrow;
    } on Object {
      _requireCurrent(owner);
      rethrow;
    }
  }

  Future<RiderAssignedTrip?> _readTrip(
    String tripId,
    _TripReadOwner owner,
  ) async {
    _requireCurrent(owner);
    final row = await _client
        .from('trips')
        .select('*')
        .eq('id', tripId)
        .eq('rider_id', owner.riderId)
        .maybeSingle();
    _requireCurrent(owner);
    if (row == null) return null;
    if (row['id'] != tripId ||
        row['rider_id'] != owner.riderId ||
        row['payment_method'] != 'cash' ||
        row['version'] is! int ||
        row['driver_id'] is! String ||
        row['vehicle_id'] is! String) {
      throw const _TripReadFailure();
    }
    final canonicalDriverId = row['driver_id'] as String;
    final canonicalVehicleId = row['vehicle_id'] as String;
    if (!isCanonicalTripId(canonicalDriverId) ||
        !isCanonicalTripId(canonicalVehicleId)) {
      throw const _TripReadFailure();
    }

    final stopRows = await _client
        .from('trip_stops')
        .select('id,trip_id,sequence,location,label')
        .eq('trip_id', tripId)
        .order('sequence');
    _requireCurrent(owner);
    if (stopRows.length > 3) throw const _TripReadFailure();

    final vehicle = await _client
        .from('vehicles')
        .select('id,driver_id,make,model,color,registration_plate,seat_capacity')
        .eq('id', canonicalVehicleId)
        .eq('driver_id', canonicalDriverId)
        .maybeSingle();
    _requireCurrent(owner);
    if (vehicle == null ||
        vehicle['id'] != canonicalVehicleId ||
        vehicle['driver_id'] != canonicalDriverId) {
      throw const _TripReadFailure();
    }
    await _verifyProfile(owner);
    _requireCurrent(owner);
    try {
      return RiderAssignedTrip(
        tripId: row['id'] as String,
        bookingRequestId: _string(row, 'booking_request_id'),
        riderId: row['rider_id'] as String,
        version: row['version'] as int,
        status: DriverTripLifecycleStatus.fromBackendValue(
          _string(row, 'status'),
        ),
        paymentMethod: PaymentMethod.cash,
        pickup: _place(row['pickup']),
        destination: _place(row['destination']),
        stops: [for (final stop in stopRows) _stop(stop, tripId)],
        routeDistanceMeters: _integer(row, 'route_distance_meters'),
        routeDurationSeconds: _integer(row, 'route_duration_seconds'),
        routeGeometryReference: row['route_geometry_reference'] as String?,
        originalFareFils: _integer(row, 'original_fare_fils'),
        currentFareFils: _integer(row, 'current_fare_fils'),
        currency: _string(row, 'currency'),
        driver: RiderDriverSummary(driverId: canonicalDriverId),
        vehicle: RiderVehicleSummary(
          vehicleId: canonicalVehicleId,
          make: _string(vehicle, 'make'),
          model: _string(vehicle, 'model'),
          color: _string(vehicle, 'color'),
          registrationPlate: _string(vehicle, 'registration_plate'),
          seatCapacity: _integer(vehicle, 'seat_capacity'),
        ),
        acceptedAt: _date(row, 'accepted_at'),
        updatedAt: _date(row, 'updated_at'),
      );
    } on Object {
      throw const _TripReadFailure();
    }
  }

  @override
  Stream<RiderTripTrackingEvent> watch({required String tripId}) =>
      Stream<RiderTripTrackingEvent>.multi((controller) {
        if (!isCanonicalTripId(tripId)) {
          controller.addError(ArgumentError.value(tripId, 'tripId'));
          unawaited(controller.close());
          return;
        }
        StreamSubscription<TripRealtimeUpdate>? subscription;
        var cancelled = false;
        controller.onCancel = () async {
          cancelled = true;
          await subscription?.cancel();
        };
        try {
          subscription = _realtime.watchTrip(tripId).listen((update) {
            if (cancelled) return;
            switch (update) {
              case VerifiedTripRealtimeEvent(:final trip):
                if (trip.tripId.toLowerCase() != tripId.toLowerCase()) return;
                unawaited(_emitCanonicalSnapshot(tripId, controller));
              case TripRealtimeConnectionUpdate(:final status):
                if (status == TripRealtimeChannelStatus.channelError ||
                    status == TripRealtimeChannelStatus.closed ||
                    status == TripRealtimeChannelStatus.timedOut) {
                  controller.add(RiderTripTrackingDisconnected(
                    tripId: tripId,
                    disconnectedAt: DateTime.now().toUtc(),
                  ));
                }
              case TripRealtimeVerificationUpdate():
                return;
            }
          }, onError: (Object error, StackTrace stackTrace) {
            if (!cancelled) controller.addError(error, stackTrace);
          }, onDone: () {
            if (!cancelled) unawaited(controller.close());
          });
        } on Object catch (error, stackTrace) {
          controller.addError(error, stackTrace);
          unawaited(controller.close());
        }
      }, isBroadcast: false);

  Future<void> _emitCanonicalSnapshot(
    String tripId,
    MultiStreamController<RiderTripTrackingEvent> controller,
  ) async {
    try {
      final trip = await findByTrip(tripId: tripId);
      if (trip != null) controller.add(RiderTripSnapshot(trip));
    } on Object {
      // A lost/foreign or unreadable row is not surfaced from a Realtime hint.
      // The lifecycle owner remains stale until a later canonical reread.
    }
  }

  _TripReadOwner _captureOwner() {
    final session = _readSession();
    final riderId = session.user?.id;
    final sdkSession = _client.auth.currentSession;
    if (session.status != SessionStatus.authenticated ||
        session.role != RideRole.rider ||
        session.user == null ||
        session.user!.isBlocked ||
        riderId == null ||
        !isCanonicalTripId(riderId) ||
        _client.auth.currentUser?.id != riderId ||
        sdkSession == null ||
        sdkSession.isExpired) {
      throw const _SessionReplaced();
    }
    return _TripReadOwner(session, riderId, sdkSession);
  }

  bool _isCurrent(_TripReadOwner owner) =>
      identical(_readSession(), owner.session) &&
      _client.auth.currentUser?.id == owner.riderId &&
      identical(_client.auth.currentSession, owner.sdkSession);

  void _requireCurrent(_TripReadOwner owner) {
    if (!_isCurrent(owner)) throw const _SessionReplaced();
  }

  Future<void> _verifyProfile(_TripReadOwner owner) async {
    _requireCurrent(owner);
    final profile = await _client
        .from('users')
        .select('id,role,is_blocked')
        .eq('id', owner.riderId)
        .maybeSingle();
    _requireCurrent(owner);
    if (profile == null ||
        profile['id'] != owner.riderId ||
        profile['role'] != 'rider' ||
        profile['is_blocked'] != false) {
      throw const _SessionReplaced();
    }
  }
}

RiderTripPlace _place(Object? value) {
  if (value is! Map) throw const _TripReadFailure();
  final latitude = value['latitude'];
  final longitude = value['longitude'];
  if (latitude is! num || longitude is! num) throw const _TripReadFailure();
  final label = value['label'];
  return RiderTripPlace(
    point: LocationPoint(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
    ),
    label: label is String ? label : null,
  );
}

RiderTripPlace _stop(Map<String, dynamic> row, String tripId) {
  if (row['trip_id'] != tripId || row['sequence'] is! int) {
    throw const _TripReadFailure();
  }
  final place = _place(row['location']);
  final label = row['label'];
  return RiderTripPlace(point: place.point, label: label is String ? label : null);
}

String _string(Map<String, dynamic> row, String field) {
  final value = row[field];
  if (value is! String || value.isEmpty) throw const _TripReadFailure();
  return value;
}

int _integer(Map<String, dynamic> row, String field) {
  final value = row[field];
  if (value is! int) throw const _TripReadFailure();
  return value;
}

DateTime _date(Map<String, dynamic> row, String field) {
  final value = row[field];
  final date = value is String ? DateTime.tryParse(value) : null;
  if (date == null) throw const _TripReadFailure();
  return date.toUtc();
}

final class _TripReadOwner {
  const _TripReadOwner(this.session, this.riderId, this.sdkSession);
  final SessionState session;
  final String riderId;
  final Session sdkSession;
}

final class _TripReadFailure implements Exception {
  const _TripReadFailure();
}

final class _SessionReplaced implements Exception {
  const _SessionReplaced();
}
