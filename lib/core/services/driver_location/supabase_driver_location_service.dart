import 'package:ridex/core/errors/driver_location_exception.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/services/driver_location/driver_location_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseDriverLocationService implements DriverLocationService {
  const SupabaseDriverLocationService(this._client);

  final SupabaseClient _client;

  @override
  Future<DriverAvailability?> fetchAvailability() async {
    try {
      final row = await _client
          .from('driver_availability')
          .select('state, active_trip_id')
          .eq('driver_id', _driverId)
          .maybeSingle();
      return row == null ? null : availabilityFromRow(row);
    } on DriverLocationException {
      rethrow;
    } on Object catch (error) {
      throw DriverLocationException(_failureFor(error));
    }
  }

  @override
  Future<SavedDriverLocation?> fetchLatestLocation() async {
    try {
      final row = await _client
          .from('driver_locations')
          .select(
            'trip_id, sequence, latitude, longitude, accuracy_meters, '
            'heading_degrees, speed_meters_per_second, recorded_at, received_at',
          )
          .eq('driver_id', _driverId)
          .order('sequence', ascending: false)
          .limit(1)
          .maybeSingle();
      return row == null ? null : savedLocationFromRow(row);
    } on DriverLocationException {
      rethrow;
    } on Object catch (error) {
      throw DriverLocationException(_failureFor(error));
    }
  }

  @override
  Future<SavedDriverLocation> recordLocation(
      DriverLocationSample sample) async {
    try {
      final row = await _client.rpc(
        'driver_record_location',
        params: rpcPayload(sample),
      );
      if (row is! Map) {
        throw const DriverLocationException(DriverLocationFailure.invalidData);
      }
      return savedLocationFromRow(row);
    } on DriverLocationException {
      rethrow;
    } on Object catch (error) {
      throw DriverLocationException(_failureFor(error));
    }
  }

  String get _driverId {
    final id = _client.auth.currentUser?.id;
    if (id == null || id.isEmpty) {
      throw const DriverLocationException(DriverLocationFailure.unauthorized);
    }
    return id;
  }

  static DriverAvailability availabilityFromRow(Map<String, dynamic> row) {
    final state = row['state'];
    final activeTripId = _nullableId(row['active_trip_id']);
    if (state is! String) {
      throw const DriverLocationException(DriverLocationFailure.invalidData);
    }
    try {
      final parsedState = DriverAvailabilityStateX.fromDatabase(state);
      if (parsedState == DriverAvailabilityState.onTrip
          ? activeTripId == null
          : activeTripId != null) {
        throw const DriverLocationException(DriverLocationFailure.invalidData);
      }
      return DriverAvailability(
        state: parsedState,
        activeTripId: activeTripId,
      );
    } on DriverLocationException {
      rethrow;
    } on ArgumentError {
      throw const DriverLocationException(DriverLocationFailure.invalidData);
    }
  }

  static Map<String, dynamic> rpcPayload(DriverLocationSample sample) => {
        'requested_trip_id': sample.tripId,
        'requested_sequence': sample.sequence,
        'requested_latitude': sample.point.latitude,
        'requested_longitude': sample.point.longitude,
        'requested_accuracy_meters': sample.point.accuracyMeters,
        'requested_heading_degrees': sample.headingDegrees,
        'requested_speed_meters_per_second': sample.speedMetersPerSecond,
        'requested_recorded_at': sample.recordedAt.toIso8601String(),
      };

  static SavedDriverLocation savedLocationFromRow(Map<dynamic, dynamic> row) {
    try {
      final sequence = row['sequence'];
      final latitude = row['latitude'];
      final longitude = row['longitude'];
      final accuracy = row['accuracy_meters'];
      if (sequence is! int ||
          latitude is! num ||
          longitude is! num ||
          accuracy is! num) {
        throw const FormatException();
      }
      return SavedDriverLocation(
        point: LocationPoint(
          latitude: latitude.toDouble(),
          longitude: longitude.toDouble(),
          accuracyMeters: accuracy.toDouble(),
        ),
        sequence: sequence,
        recordedAt: _timestamp(row['recorded_at']),
        receivedAt: _timestamp(row['received_at']),
        tripId: _nullableId(row['trip_id']),
        headingDegrees: _nullableFiniteNumber(row['heading_degrees']),
        speedMetersPerSecond: _nullableFiniteNumber(
          row['speed_meters_per_second'],
        ),
      );
    } on DriverLocationException {
      rethrow;
    } on Object {
      throw const DriverLocationException(DriverLocationFailure.invalidData);
    }
  }

  static DateTime _timestamp(Object? value) {
    if (value is! String) throw const FormatException();
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw const FormatException();
    return parsed.toUtc();
  }

  static String? _nullableId(Object? value) {
    if (value == null) return null;
    if (value is! String || value.isEmpty) throw const FormatException();
    return value;
  }

  static double? _nullableFiniteNumber(Object? value) {
    if (value == null) return null;
    if (value is! num || !value.isFinite) throw const FormatException();
    return value.toDouble();
  }

  static DriverLocationFailure _failureFor(Object error) {
    if (error is PostgrestException) {
      return switch (error.code) {
        '42501' || 'PGRST301' => DriverLocationFailure.unauthorized,
        '23505' => DriverLocationFailure.staleSequence,
        '22023' || '55000' => DriverLocationFailure.ineligible,
        _ => DriverLocationFailure.unavailable,
      };
    }
    return DriverLocationFailure.unavailable;
  }
}
