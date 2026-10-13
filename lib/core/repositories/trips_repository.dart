import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/mock_trip.dart';

abstract class TripsRepository {
  Future<MockTrip> createTrip(BookingDraft draft);
  Future<List<MockTrip>> getTripHistory();
  Future<MockTrip?> getTripById(String id);

  /// Provisional mock-only driver completion hook (P6-07 slice).
  ///
  /// The trusted backend operation is `driver_transition_trip` (target id,
  /// expected version, idempotency key); that signature needs P6-01/P6-02
  /// and is NOT represented here. [MockTrip] carries no version, so this
  /// slice passes the active trip and validates identity plus a legal
  /// transition to completed only. Never marks any payment state.
  Future<MockTrip> completeTrip(MockTrip trip);
}
