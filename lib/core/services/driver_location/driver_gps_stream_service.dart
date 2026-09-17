import 'package:ridex/core/models/driver_location.dart';

abstract interface class DriverGpsStreamService {
  Stream<DriverLocationFix> foregroundFixes();
}
