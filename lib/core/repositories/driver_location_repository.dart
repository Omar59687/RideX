import 'package:ridex/core/errors/driver_location_exception.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/services/driver_location/driver_location_service.dart';

abstract interface class DriverLocationRepository {
  Future<DriverAvailability?> fetchAvailability();

  Future<SavedDriverLocation?> fetchLatestLocation();

  Future<SavedDriverLocation> publish(DriverLocationSample sample);
}

class ServiceDriverLocationRepository implements DriverLocationRepository {
  const ServiceDriverLocationRepository(this._service);

  final DriverLocationService _service;

  @override
  Future<DriverAvailability?> fetchAvailability() =>
      _service.fetchAvailability();

  @override
  Future<SavedDriverLocation?> fetchLatestLocation() =>
      _service.fetchLatestLocation();

  @override
  Future<SavedDriverLocation> publish(DriverLocationSample sample) async {
    final availability = await _service.fetchAvailability();
    if (availability == null || !availability.canShareLocation) {
      throw const DriverLocationException(DriverLocationFailure.ineligible);
    }
    if (availability.state == DriverAvailabilityState.onTrip) {
      if (sample.tripId != availability.activeTripId) {
        throw const DriverLocationException(DriverLocationFailure.ineligible);
      }
    } else if (sample.tripId != null) {
      throw const DriverLocationException(DriverLocationFailure.ineligible);
    }
    return _service.recordLocation(sample);
  }
}
