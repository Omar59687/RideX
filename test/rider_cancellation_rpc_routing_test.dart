import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_booking_cancellation.dart';
import 'package:ridex/core/models/rider_trip_cancellation.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/supabase_rider_booking_search_repository.dart';
import 'package:ridex/core/repositories/supabase_rider_trip_cancellation_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/fake_rider_trip_tracking_repository.dart';

void main() {
  test('pending Booking and assigned Trip use separate canonical RPCs',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <(String, Uri, Map<String, dynamic>?)>[];
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'local-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    server.listen((request) async {
      final raw = await utf8.decoder.bind(request).join();
      Map<String, dynamic>? body;
      if (raw.isNotEmpty) body = jsonDecode(raw) as Map<String, dynamic>;
      requests.add((request.method, request.uri, body));
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/rest/v1/users') {
        request.response.write(jsonEncode([
          {'id': riderIdFixture, 'role': 'rider', 'is_blocked': false}
        ]));
      } else if (request.uri.path == '/rest/v1/rpc/rider_cancel_booking') {
        request.response.write(jsonEncode({
          'id': riderBookingIdFixture,
          'rider_id': riderIdFixture,
          'payment_method': 'cash',
          'status': 'cancelled',
          'version': 4,
        }));
      } else if (request.uri.path == '/rest/v1/rpc/rider_cancel_trip') {
        request.response.write(jsonEncode({
          'id': riderTripIdFixture,
          'rider_id': riderIdFixture,
          'payment_method': 'cash',
          'version': 4,
        }));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('{}');
      }
      await request.response.close();
    });
    addTearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({'exp': expiry, 'sub': riderIdFixture})))
        .replaceAll('=', '');
    await client.auth.setInitialSession(jsonEncode({
      'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.signature',
      'refresh_token': 'local-refresh-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': riderIdFixture,
        'app_metadata': <String, Object?>{},
        'user_metadata': <String, Object?>{},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }));
    // Use the same immutable Rider context as the test client; the provider
    // container itself is not used to authorize either repository.
    final session = SessionState.fromUser(const AppUser(
      id: riderIdFixture,
      name: 'Rider',
      email: 'rider@example.test',
      role: RideRole.rider,
    ));

    final bookingRepository = SupabaseRiderBookingCancellationRepository(
      client,
      readSession: () => session,
    );
    final bookingResult = await bookingRepository.cancelBooking(
      bookingRequestId: riderBookingIdFixture,
      expectedVersion: 3,
      reasonCode: 'Changed my mind',
    );
    expect(bookingResult, isA<RiderBookingCancellationAccepted>());
    expect(requests.last.$2.path, '/rest/v1/rpc/rider_cancel_booking');
    expect(requests.last.$3, {
      'target_booking_request_id': riderBookingIdFixture,
      'expected_version': 3,
      'reason_code': 'Changed my mind',
    });

    final trips = FakeRiderTripTrackingRepository(
      trip: riderAssignedTripFixture(
        version: 4,
        status: DriverTripLifecycleStatus.cancelledByRider,
      ),
    );
    addTearDown(trips.close);
    final tripRepository = SupabaseRiderTripCancellationRepository(
      client,
      readSession: () => session,
      tripRepository: trips,
    );
    final tripResult = await tripRepository.cancelTrip(
      tripId: riderTripIdFixture,
      expectedVersion: 3,
      reasonCode: 'Changed my mind',
    );
    expect(tripResult, isA<RiderTripCancellationAccepted>());
    expect(requests.last.$2.path, '/rest/v1/rpc/rider_cancel_trip');
    expect(requests.last.$3, {
      'target_trip_id': riderTripIdFixture,
      'expected_version': 3,
      'reason_code': 'Changed my mind',
    });
  });
}
