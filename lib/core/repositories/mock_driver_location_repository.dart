import 'package:ridex/core/errors/driver_location_exception.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/repositories/driver_location_repository.dart';

class MockDriverLocationRepository implements DriverLocationRepository {
  MockDriverLocationRepository({
    this.availability = const DriverAvailability(
      state: DriverAvailabilityState.available,
    ),
    List<SavedDriverLocation> locations = const [],
  }) : _locations = [...locations]
          ..sort((left, right) => right.sequence.compareTo(left.sequence));

  DriverAvailability availability;
  final List<SavedDriverLocation> _locations;

  @override
  Future<DriverAvailability?> fetchAvailability() async => availability;

  @override
  Future<SavedDriverLocation?> fetchLatestLocation() async =>
      _locations.isEmpty ? null : _locations.first;

  @override
  Future<SavedDriverLocation> publish(DriverLocationSample sample) async {
    if (!availability.canShareLocation ||
        (availability.state == DriverAvailabilityState.onTrip
            ? sample.tripId != availability.activeTripId
            : sample.tripId != null)) {
      throw const DriverLocationException(DriverLocationFailure.ineligible);
    }
    if (_locations.isNotEmpty && sample.sequence <= _locations.first.sequence) {
      throw const DriverLocationException(DriverLocationFailure.staleSequence);
    }
    final saved = SavedDriverLocation(
      point: sample.point,
      sequence: sample.sequence,
      recordedAt: sample.recordedAt,
      receivedAt: sample.recordedAt,
      tripId: sample.tripId,
      headingDegrees: sample.headingDegrees,
      speedMetersPerSecond: sample.speedMetersPerSecond,
    );
    _locations.insert(0, saved);
    return saved;
  }
}
