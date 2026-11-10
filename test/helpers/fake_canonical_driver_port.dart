import 'dart:async';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/features/driver_flow/data/canonical_driver_repository.dart';

const driverId = 'a7000000-0000-0000-0000-000000000001';
const otherId = 'a7000000-0000-0000-0000-000000000002';
const offerId = 'b7000000-0000-0000-0000-000000000001';
const bookingId = 'c7000000-0000-0000-0000-000000000001';
const quoteId = 'd7000000-0000-0000-0000-000000000001';
const vehicleId = 'e7000000-0000-0000-0000-000000000001';
const tripId = 'f7000000-0000-0000-0000-000000000001';
final now = DateTime.utc(2026, 11, 10, 12);
final backend = DriverBackendIdentity(
    endpoint: Uri.parse('https://authority.unit-test.invalid'),
    namespace: 'canonical-driver-test');
Map<String, Object?> availabilityRow() => {
      'driver_id': driverId,
      'state': 'reserved',
      'vehicle_id': vehicleId,
      'reserved_booking_request_id': bookingId,
      'active_trip_id': null,
      'version': 3
    };
Map<String, Object?> offerRow() => {
      'id': offerId,
      'driver_id': driverId,
      'booking_request_id': bookingId,
      'fare_quote_id': quoteId,
      'vehicle_id': vehicleId,
      'status': 'offered',
      'version': 1,
      'expires_at': now.add(const Duration(seconds: 15)).toIso8601String()
    };
Map<String, Object?> tripRow() => {
      'id': tripId,
      'driver_id': driverId,
      'rider_id': otherId,
      'booking_request_id': bookingId,
      'fare_quote_id': quoteId,
      'vehicle_id': vehicleId,
      'status': 'accepted',
      'version': 1,
      'payment_method': 'cash'
    };

class FakeCanonicalDriverPort implements CanonicalDriverPort {
  String? driver = driverId;
  int epoch = 1;
  bool valid = true;
  @override
  Object? sessionIdentity = Object();
  Map<String, Object?>? user = {
    'id': driverId,
    'role': 'driver',
    'is_blocked': false
  };
  Map<String, Object?>? profile = {
    'user_id': driverId,
    'approval_status': 'approved'
  };
  Map<String, Object?>? availability = availabilityRow();
  Map<String, Object?>? offer = offerRow();
  Map<String, Object?>? booking = {
    'id': bookingId,
    'fare_quote_id': quoteId,
    'status': 'searching',
    'payment_method': 'cash',
  };
  Map<String, Object?>? trip;
  Future<void> Function(String)? beforeRead;
  Future<Object?> Function(String)? onCommand;
  final calls = <(String, String, int, String)>[];
  final reads = <String>[];
  @override
  DriverAuthorityOwner get currentOwner => DriverAuthorityOwner(
      driverId: driver, backend: backend, epoch: epoch, hasValidSession: valid);
  Future<Map<String, Object?>?> read(
      String name, Map<String, Object?>? Function() value) async {
    reads.add(name);
    await beforeRead?.call(name);
    final row = value();
    return row == null ? null : Map.of(row);
  }

  @override
  Future<Map<String, Object?>?> readUser(String id) => read('user', () => user);
  @override
  Future<Map<String, Object?>?> readDriverProfile(String id) =>
      read('profile', () => profile);
  @override
  Future<Map<String, Object?>?> readAvailability() =>
      read('availability', () => availability);
  @override
  Future<Map<String, Object?>?> readOffer(String id) =>
      read('offer', () => offer);
  @override
  Future<Map<String, Object?>?> readBooking(String id) =>
      read('booking', () => booking);
  @override
  Future<Map<String, Object?>?> readTrip(String id) => read('trip', () => trip);
  @override
  Future<Map<String, Object?>?> readTripForBooking(String id) =>
      read('booking-trip', () => trip);
  @override
  Future<Object?> acceptOffer(String id, int version, String key) async {
    calls.add(('accept', id, version, key));
    return onCommand?.call('accept');
  }

  @override
  Future<Object?> declineOffer(String id, int version, String key) async {
    calls.add(('decline', id, version, key));
    return onCommand?.call('decline');
  }

  void accept() {
    offer = {...offer!, 'status': 'accepted', 'version': 2};
    trip = tripRow();
    availability = {
      ...availability!,
      'state': 'onTrip',
      'reserved_booking_request_id': null,
      'active_trip_id': tripId,
      'version': 4
    };
  }

  void decline() {
    offer = {...offer!, 'status': 'declined', 'version': 2};
    availability = {
      ...availability!,
      'state': 'available',
      'reserved_booking_request_id': null,
      'version': 4
    };
  }
}
