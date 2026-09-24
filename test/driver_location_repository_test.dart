import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/errors/driver_location_exception.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/repositories/driver_location_repository.dart';
import 'package:ridex/core/repositories/mock_driver_location_repository.dart';
import 'package:ridex/core/services/driver_location/driver_location_service.dart';
import 'package:ridex/core/services/driver_location/supabase_driver_location_service.dart';

void main() {
  final point = LocationPoint(
    latitude: 31.963158,
    longitude: 35.930359,
    accuracyMeters: 6,
  );
  final recordedAt = DateTime.utc(2026, 9, 17, 10);

  test('maps strict canonical availability and saved location rows', () {
    final availability = SupabaseDriverLocationService.availabilityFromRow({
      'state': 'onTrip',
      'active_trip_id': 'trip-1',
    });
    final saved = SupabaseDriverLocationService.savedLocationFromRow({
      'trip_id': 'trip-1',
      'sequence': 4,
      'latitude': 31.963158,
      'longitude': 35.930359,
      'accuracy_meters': 6.0,
      'heading_degrees': 90.0,
      'speed_meters_per_second': 4.5,
      'recorded_at': '2026-09-17T10:00:00.000Z',
      'received_at': '2026-09-17T10:00:01.000Z',
    });

    expect(availability.state, DriverAvailabilityState.onTrip);
    expect(availability.activeTripId, 'trip-1');
    expect(saved.sequence, 4);
    expect(saved.point, point);
    expect(saved.receivedAt, DateTime.utc(2026, 9, 17, 10, 0, 1));
  });

  test('rejects malformed availability, timestamps, and sequences', () {
    expect(
      () => SupabaseDriverLocationService.availabilityFromRow({
        'state': 'available',
        'active_trip_id': 'unexpected',
      }),
      throwsA(isA<DriverLocationException>()),
    );
    expect(
      () => SupabaseDriverLocationService.savedLocationFromRow({
        'sequence': 1.0,
        'latitude': 1,
        'longitude': 1,
        'accuracy_meters': 1,
        'recorded_at': 'not-a-timestamp',
        'received_at': '2026-09-17T10:00:01.000Z',
      }),
      throwsA(isA<DriverLocationException>()),
    );
  });

  test('only publishes samples eligible for canonical availability', () async {
    final service = _FakeDriverLocationService(
      const DriverAvailability(state: DriverAvailabilityState.available),
    );
    final repository = ServiceDriverLocationRepository(service);

    await repository.publish(_sample(point, recordedAt));
    expect(service.publishCount, 1);

    service.availability = const DriverAvailability(
      state: DriverAvailabilityState.onTrip,
      activeTripId: 'trip-1',
    );
    await expectLater(
      repository.publish(_sample(point, recordedAt, tripId: 'another-trip')),
      throwsA(
        isA<DriverLocationException>().having(
          (error) => error.failure,
          'failure',
          DriverLocationFailure.ineligible,
        ),
      ),
    );
    expect(service.publishCount, 1);
  });

  test('mock returns the highest-sequence saved location deterministically',
      () async {
    final repository = MockDriverLocationRepository(
      locations: [
        _saved(point, 2, recordedAt),
        _saved(point, 8, recordedAt.add(const Duration(seconds: 1))),
      ],
    );

    expect((await repository.fetchLatestLocation())!.sequence, 8);
  });

  test('builds only the approved location RPC payload', () {
    final sample = _sample(
      point,
      recordedAt,
      tripId: 'trip-1',
      headingDegrees: 90,
      speedMetersPerSecond: 4.5,
    );

    expect(SupabaseDriverLocationService.rpcPayload(sample), {
      'requested_trip_id': 'trip-1',
      'requested_sequence': 1,
      'requested_latitude': 31.963158,
      'requested_longitude': 35.930359,
      'requested_accuracy_meters': 6.0,
      'requested_heading_degrees': 90.0,
      'requested_speed_meters_per_second': 4.5,
      'requested_recorded_at': '2026-09-17T10:00:00.000Z',
    });
  });

  test('surfaces a Supabase failure without Mock fallback', () async {
    final repository = ServiceDriverLocationRepository(
      _FailingDriverLocationService(),
    );

    await expectLater(
      repository.publish(_sample(point, recordedAt)),
      throwsA(
        isA<DriverLocationException>().having(
          (error) => error.failure,
          'failure',
          DriverLocationFailure.networkFailure,
        ),
      ),
    );
  });
}

DriverLocationSample _sample(
  LocationPoint point,
  DateTime recordedAt, {
  String? tripId,
  double? headingDegrees,
  double? speedMetersPerSecond,
}) =>
    DriverLocationSample(
      point: point,
      sequence: 1,
      recordedAt: recordedAt,
      tripId: tripId,
      headingDegrees: headingDegrees,
      speedMetersPerSecond: speedMetersPerSecond,
    );

SavedDriverLocation _saved(LocationPoint point, int sequence, DateTime time) =>
    SavedDriverLocation(
      point: point,
      sequence: sequence,
      recordedAt: time,
      receivedAt: time,
    );

class _FakeDriverLocationService implements DriverLocationService {
  _FakeDriverLocationService(this.availability);

  DriverAvailability? availability;
  int publishCount = 0;

  @override
  Future<DriverAvailability?> fetchAvailability() async => availability;

  @override
  Future<SavedDriverLocation?> fetchLatestLocation() async => null;

  @override
  Future<SavedDriverLocation> recordLocation(
      DriverLocationSample sample) async {
    publishCount++;
    return _saved(sample.point, sample.sequence, sample.recordedAt);
  }
}

class _FailingDriverLocationService implements DriverLocationService {
  @override
  Future<DriverAvailability?> fetchAvailability() {
    throw const DriverLocationException(DriverLocationFailure.networkFailure);
  }

  @override
  Future<SavedDriverLocation?> fetchLatestLocation() async => null;

  @override
  Future<SavedDriverLocation> recordLocation(DriverLocationSample sample) {
    throw UnimplementedError();
  }
}
