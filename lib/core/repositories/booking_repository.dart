import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/vehicle_type.dart';

abstract class BookingRepository {
  Future<List<RideLocation>> getSavedLocations();
  Future<List<VehicleType>> getVehicleTypes();
  Future<double> estimateFare(BookingDraft draft);
}
