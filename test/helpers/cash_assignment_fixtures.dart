import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/booking_handoff.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/repositories/cash_booking_assignment_repository.dart';

String id(int n) => 'a7050000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final bId = id(1),
    qId = id(2),
    rId = id(3),
    dId = id(4),
    vId = id(5),
    oId = id(6),
    tId = id(7);
const point = {'latitude': 31.95, 'longitude': 35.93};
Map<String, dynamic> quote() => {
      'id': qId,
      'booking_request_id': bId,
      'rider_id': rId,
      'status': 'locked',
      'quote_version': 1,
      'pricing_version': 1,
      'currency': 'JOD',
      'fixed_fare_fils': 2000,
      'breakdown': {
        'base_fare_fils': 500,
        'distance_fils': 1200,
        'duration_fils': 300,
        'stops_fils': 0,
        'subtotal_fils': 2000,
        'minimum_fare_fils': 1000,
        'rounding_increment_fils': 50,
        'fixed_fare_fils': 2000
      },
      'created_at': '2026-11-04T10:00:00Z',
      'expires_at': '2026-11-04T10:10:00Z',
      'locked_at': '2026-11-04T10:01:00Z',
      'route_distance_meters': 5400,
      'route_duration_seconds': 720,
      'route_geometry_reference': 'route-a',
      'pickup': point,
      'destination': point,
      'vehicle_type_code': 'economy',
      'ordered_stops': [
        {'location': point, 'label': 'First'},
        {'location': point, 'label': 'Second', 'rider_note': 'Gate B'}
      ],
    };
ConfirmedBookingReference reference() => ConfirmedBookingReference(
    command: PendingFareLock(
        bookingRequestId: bId,
        expectedBookingVersion: 1,
        fareQuoteId: qId,
        expectedQuoteVersion: 1,
        riderId: rId,
        status: PendingLockRecoveryStatus.uncertain,
        createdAt: DateTime.utc(2026, 11, 4)),
    quote: FareQuote.fromJson(quote()));
Map<String, dynamic> booking() => {
      'id': bId,
      'rider_id': rId,
      'payment_method': 'cash',
      'status': 'matched',
      'version': 5,
      'fare_quote_id': qId,
      'matched_driver_id': dId,
      'matched_vehicle_id': vId,
      'pickup': point,
      'destination': point,
      'vehicle_type_code': 'economy',
      'fare_quotes': [quote()],
      'booking_stops': [
        {'sequence': 1, 'location': point, 'label': 'First'},
        {
          'sequence': 2,
          'location': point,
          'label': 'Second',
          'rider_note': 'Gate B'
        }
      ],
      'driver_match_offers': [
        {
          'id': oId,
          'booking_request_id': bId,
          'fare_quote_id': qId,
          'driver_id': dId,
          'vehicle_id': vId,
          'status': 'accepted'
        }
      ],
      'trips': [
        {
          'id': tId,
          'booking_request_id': bId,
          'fare_quote_id': qId,
          'rider_id': rId,
          'driver_id': dId,
          'vehicle_id': vId,
          'version': 1,
          'status': 'accepted',
          'payment_method': 'cash',
          'currency': 'JOD',
          'original_fare_fils': 2000,
          'pickup': point,
          'destination': point,
          'route_distance_meters': 5400,
          'route_duration_seconds': 720,
          'route_geometry_reference': 'route-a',
          'trip_stops': [
            {
              'sequence': 2,
              'location': point,
              'label': 'Second',
              'rider_note': 'Gate B'
            },
            {'sequence': 1, 'location': point, 'label': 'First'}
          ]
        }
      ],
    };

class Fake implements CashAssignmentReadTransport {
  @override
  RiderAssignmentOwner owner = RiderAssignmentOwner(rId, 'local', 0, Object());
  Map<String, dynamic>? value = booking();
  Future<void> Function()? before;
  @override
  Future<Map<String, dynamic>?> readOwnedBooking(String bookingId) async {
    await before?.call();
    return value == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }
}

Map<String, dynamic> trip(Fake p) =>
    (p.value!['trips'] as List).single as Map<String, dynamic>;
Map<String, dynamic> fare(Fake p) =>
    (p.value!['fare_quotes'] as List).single as Map<String, dynamic>;
Future<AssignedCashTrip?> run(Fake p) =>
    CashBookingAssignmentRepository(p).read(reference());
Matcher failure(CashAssignmentFailure f) =>
    isA<CashAssignmentException>().having((e) => e.failure, 'failure', f);
