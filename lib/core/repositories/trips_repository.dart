import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/mock_trip.dart';

abstract class TripsRepository {
  Future<MockTrip> createTrip(BookingDraft draft);
  Future<List<MockTrip>> getTripHistory();
  Future<MockTrip?> getTripById(String id);
}
