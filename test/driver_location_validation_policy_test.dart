import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/services/driver_location/driver_location_validation_policy.dart';

void main() {
  const policy = DriverLocationValidationPolicy();
  final now = DateTime.utc(2026, 9, 24, 12);

  test('rejects missing accuracy and readings outside the canonical window',
      () {
    expect(
      policy.rejectionFor(
        candidate: _fix(now, accuracyMeters: null),
        now: now,
      ),
      DriverLocationRejection.missingAccuracy,
    );
    expect(
      policy.rejectionFor(
        candidate: _fix(now.subtract(const Duration(minutes: 15, seconds: 1))),
        now: now,
      ),
      DriverLocationRejection.expired,
    );
    expect(
      policy.rejectionFor(
        candidate: _fix(now.add(const Duration(minutes: 5, seconds: 1))),
        now: now,
      ),
      DriverLocationRejection.futureDated,
    );
    expect(
      policy.rejectionFor(
        candidate: _fix(now.subtract(const Duration(minutes: 15))),
        now: now,
      ),
      isNull,
    );
    expect(
      policy.rejectionFor(
        candidate: _fix(now.add(const Duration(minutes: 5))),
        now: now,
      ),
      isNull,
    );
  });

  test('requires source timestamps to advance strictly', () {
    final previous = _fix(now.subtract(const Duration(seconds: 1)));

    expect(
      policy.rejectionFor(
          candidate: _fix(previous.recordedAt), now: now, previous: previous),
      DriverLocationRejection.outOfOrder,
    );
    expect(
      policy.rejectionFor(
        candidate:
            _fix(previous.recordedAt.subtract(const Duration(seconds: 1))),
        now: now,
        previous: previous,
      ),
      DriverLocationRejection.outOfOrder,
    );
  });

  test('rejects temporary uncertainty and accepts later accurate recovery', () {
    final previous = _fix(
      now.subtract(const Duration(minutes: 1)),
      accuracyMeters: 6,
    );
    final inaccurate = _fix(
      now.subtract(const Duration(seconds: 30)),
      latitude: 31.964158,
      accuracyMeters: 500,
    );
    final recovered = _fix(
      now,
      latitude: 31.964158,
      accuracyMeters: 6,
    );
    final clearlyMoved = _fix(
      now,
      latitude: 31.973158,
      accuracyMeters: 500,
    );

    expect(
      policy.rejectionFor(
        candidate: inaccurate,
        now: now,
        previous: previous,
      ),
      DriverLocationRejection.accuracyRegression,
    );
    expect(
      policy.rejectionFor(
        candidate: recovered,
        now: now,
        previous: previous,
      ),
      isNull,
    );
    expect(
      policy.rejectionFor(
        candidate: clearlyMoved,
        now: now,
        previous: previous,
      ),
      isNull,
    );
  });
}

DriverLocationFix _fix(
  DateTime recordedAt, {
  double latitude = 31.963158,
  double? accuracyMeters = 6,
}) =>
    DriverLocationFix(
      point: LocationPoint(
        latitude: latitude,
        longitude: 35.930359,
        accuracyMeters: accuracyMeters,
      ),
      recordedAt: recordedAt,
    );
