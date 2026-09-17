import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';

abstract interface class DriverLocationService {
  Future<DriverAvailability?> fetchAvailability();

  Future<SavedDriverLocation?> fetchLatestLocation();

  Future<SavedDriverLocation> recordLocation(DriverLocationSample sample);
}
