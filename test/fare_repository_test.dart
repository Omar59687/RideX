import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/repositories/fare_repository.dart';

const _pickup = FareRouteLocation(
  latitude: 31.95,
  longitude: 35.92,
  label: 'Pickup',
);
const _destination = FareRouteLocation(
  latitude: 32.08,
  longitude: 36.1,
  label: 'Destination',
);

Map<String, dynamic> _quoteRow({
  String bookingId = 'booking-1',
  int quoteVersion = 1,
  String status = 'calculated',
  String expiresAt = '2026-10-04T12:10:00.000Z',
}) {
  return {
    'id': 'aaaaaaaa-bbbb-4ccc-9ddd-eeeeeeeeeeee',
    'booking_request_id': bookingId,
    'quote_version': quoteVersion,
    'pricing_version': 3,
    'fixed_fare_fils': 2050,
    'breakdown': {
      'base_fare_fils': 500,
      'distance_fils': 1200,
      'duration_fils': 300,
      'stops_fils': 0,
      'subtotal_fils': 2000,
      'minimum_fare_fils': 1000,
      'rounding_increment_fils': 50,
      'fixed_fare_fils': 2050,
    },
    'currency': 'JOD',
    'status': status,
    'expires_at': expiresAt,
    'created_at': '2026-10-04T12:00:00.000Z',
    'route_distance_meters': 5400,
    'route_duration_seconds': 720,
  };
}

void main() {
  group('SupabaseFareRepository', () {
    test('create sends the draft RPC shape and maps id/version', () async {
      String? rpcName;
      Map<String, dynamic>? rpcParams;
      final repository = SupabaseFareRepository(
        rpc: (
            {required String name,
            required Map<String, dynamic> params}) async {
          rpcName = name;
          rpcParams = params;
          return {'id': 'booking-1', 'version': 1};
        },
        quoteEdge: (_) async => throw StateError('unexpected edge call'),
      );

      final ref = await repository.createBookingDraft(
        pickup: _pickup,
        destination: _destination,
        vehicleTypeCode: 'economy',
        paymentMethod: 'cash',
        stops: const [
          FareStopInput(
            location: FareRouteLocation(latitude: 31.9, longitude: 35.9),
          ),
        ],
      );

      expect(ref.bookingRequestId, 'booking-1');
      expect(ref.version, 1);
      expect(rpcName, 'rider_create_booking_draft');
      expect(rpcParams!['requested_pickup'], {
        'latitude': 31.95,
        'longitude': 35.92,
        'label': 'Pickup',
      });
      expect(rpcParams!['requested_vehicle_type'], 'economy');
      expect(rpcParams!['requested_payment_method'], 'cash');
      expect((rpcParams!['requested_stops'] as List), hasLength(1));
    });

    test('update sends expected version and quote carries the new version',
        () async {
      final names = <String>[];
      final repository = SupabaseFareRepository(
        rpc: (
            {required String name,
            required Map<String, dynamic> params}) async {
          names.add(name);
          if (name == 'rider_update_booking_draft') {
            expect(params['target_booking_request_id'], 'booking-1');
            expect(params['expected_version'], 1);
            return {'id': 'booking-1', 'version': 2};
          }
          if (name == 'rider_lock_fare_quote') {
            expect(params, {
              'target_booking_request_id': 'booking-1',
              'target_fare_quote_id': 'aaaaaaaa-bbbb-4ccc-9ddd-eeeeeeeeeeee',
              'expected_booking_version': 2,
              'expected_quote_version': 2,
            });
            return _quoteRow(
              bookingId: 'booking-1',
              quoteVersion: 2,
              status: 'locked',
            );
          }
          throw StateError('unexpected rpc $name');
        },
        quoteEdge: (Map<String, dynamic> body) async {
          expect(body, {
            'operation': 'quote',
            'booking_request_id': 'booking-1',
            'expected_booking_version': 2,
          });
          return {
            'data': _quoteRow(bookingId: 'booking-1', quoteVersion: 2),
          };
        },
      );

      // Draft change supersedes server-side; the re-quote that follows
      // carries the bumped booking version and the new quote version.
      final updated = await repository.updateBookingDraft(
        bookingRequestId: 'booking-1',
        expectedBookingVersion: 1,
        pickup: _pickup,
        destination: _destination,
        vehicleTypeCode: 'economy',
        paymentMethod: 'cash',
      );
      expect(updated.version, 2);

      final quote = await repository.fetchQuote(
        bookingRequestId: updated.bookingRequestId,
        expectedBookingVersion: updated.version,
        routeDistanceMeters: 5400,
        routeDurationSeconds: 720,
      );
      expect(quote.quoteVersion, 2);
      expect(quote.fixedFareFils, 2050);

      final locked = await repository.lockQuote(
        bookingRequestId: updated.bookingRequestId,
        fareQuoteId: quote.id,
        expectedBookingVersion: updated.version,
        expectedQuoteVersion: quote.quoteVersion,
      );
      expect(locked.status, FareQuoteStatus.locked);
      expect(names, [
        'rider_update_booking_draft',
        'rider_lock_fare_quote',
      ]);
    });

    test('maps transport failures for draft and quote calls', () async {
      final cases = <FareTransportFailure, FareFailure>{
        const FareTransportFailure(code: '40001'): FareFailure.versionConflict,
        const FareTransportFailure(code: 'version_conflict'):
            FareFailure.versionConflict,
        const FareTransportFailure(code: 'P0002'): FareFailure.notFound,
        const FareTransportFailure(code: 'not_found'): FareFailure.notFound,
        const FareTransportFailure(code: '42501'): FareFailure.forbidden,
        const FareTransportFailure(code: 'forbidden'): FareFailure.forbidden,
        const FareTransportFailure(code: 'no_pricing_configuration'):
            FareFailure.pricingUnavailable,
        const FareTransportFailure(code: 'quote_expired'): FareFailure.expired,
        const FareTransportFailure(code: 'provider_timeout'):
            FareFailure.timedOut,
        const FareTransportFailure(status: 401): FareFailure.unauthorized,
        const FareTransportFailure(status: 403): FareFailure.forbidden,
        const FareTransportFailure(status: 404): FareFailure.notFound,
        const FareTransportFailure(status: 409): FareFailure.versionConflict,
        const FareTransportFailure(status: 410): FareFailure.expired,
        const FareTransportFailure(status: 504): FareFailure.timedOut,
        const FareTransportFailure(): FareFailure.networkFailure,
        const FareTransportFailure(status: 500): FareFailure.unavailable,
      };
      for (final entry in cases.entries) {
        final transport = entry.key;
        final expected = entry.value;
        final repository = SupabaseFareRepository(
          rpc: (
              {required String name,
              required Map<String, dynamic> params}) async {
            throw transport;
          },
          quoteEdge: (_) async {
            throw transport;
          },
        );
        await expectLater(
          repository.createBookingDraft(
            pickup: _pickup,
            destination: _destination,
            vehicleTypeCode: 'economy',
            paymentMethod: 'cash',
          ),
          throwsA(
            isA<FareException>().having(
              (error) => error.failure,
              'failure',
              expected,
            ),
          ),
          reason: 'create $transport',
        );
        await expectLater(
          repository.fetchQuote(
            bookingRequestId: 'booking-1',
            expectedBookingVersion: 1,
            routeDistanceMeters: 5400,
            routeDurationSeconds: 720,
          ),
          throwsA(
            isA<FareException>().having(
              (error) => error.failure,
              'failure',
              expected,
            ),
          ),
          reason: 'quote $transport',
        );
      }
    });

    test('maps malformed rows and envelopes to invalidResponse', () async {
      final malformedRpc = SupabaseFareRepository(
        rpc: (
                {required String name,
                required Map<String, dynamic> params}) async =>
            {'id': 'booking-1'},
        quoteEdge: (_) async => throw StateError('unexpected edge call'),
      );
      await expectLater(
        malformedRpc.createBookingDraft(
          pickup: _pickup,
          destination: _destination,
          vehicleTypeCode: 'economy',
          paymentMethod: 'cash',
        ),
        throwsA(
          isA<FareException>().having(
            (error) => error.failure,
            'failure',
            FareFailure.invalidResponse,
          ),
        ),
      );

      final malformedEdge = SupabaseFareRepository(
        rpc: (
                {required String name,
                required Map<String, dynamic> params}) async =>
            throw StateError('unexpected rpc call'),
        quoteEdge: (_) async => {
          'data': {'id': 'not-a-quote'},
        },
      );
      await expectLater(
        malformedEdge.fetchQuote(
          bookingRequestId: 'booking-1',
          expectedBookingVersion: 1,
          routeDistanceMeters: 5400,
          routeDurationSeconds: 720,
        ),
        throwsA(
          isA<FareException>().having(
            (error) => error.failure,
            'failure',
            FareFailure.invalidResponse,
          ),
        ),
      );
    });

    test('rejects quotes returned for a different booking', () async {
      final repository = SupabaseFareRepository(
        rpc: ({required String name, required Map<String, dynamic> params})
            async => throw StateError('unexpected rpc'),
        quoteEdge: (_) async => {'data': _quoteRow(bookingId: 'other-booking')},
      );
      await expectLater(
        repository.fetchQuote(
          bookingRequestId: 'booking-1',
          expectedBookingVersion: 1,
          routeDistanceMeters: 5400,
          routeDurationSeconds: 720,
        ),
        throwsA(isA<FareException>().having((e) => e.failure, 'failure',
            FareFailure.invalidResponse)),
      );
    });

    test('accepts an authoritative locked response after the quote deadline',
        () async {
      final repository = SupabaseFareRepository(
        rpc: (
            {required String name,
            required Map<String, dynamic> params}) async {
          expect(name, 'rider_lock_fare_quote');
          expect(params['expected_booking_version'], 1);
          return _quoteRow(status: 'locked', expiresAt: '2020-01-01T00:00:00Z');
        },
        quoteEdge: (_) async => throw StateError('unexpected edge call'),
      );
      final locked = await repository.lockQuote(
        bookingRequestId: 'booking-1',
        fareQuoteId: 'aaaaaaaa-bbbb-4ccc-9ddd-eeeeeeeeeeee',
        expectedBookingVersion: 1,
        expectedQuoteVersion: 1,
      );
      expect(locked.status, FareQuoteStatus.locked);
      expect(locked.isExpiredAt(DateTime.now()), isTrue);
    });

    test('a lock response must match the requested quote and locked status',
        () async {
      for (final wrongField in <Map<String, dynamic>>[
        {'id': 'other-quote'},
        {'booking_request_id': 'other-booking'},
        {'quote_version': 2},
        {'status': 'calculated'},
        {'status': 'superseded'},
      ]) {
        final repository = SupabaseFareRepository(
          rpc: ({required String name, required Map<String, dynamic> params})
              async => {..._quoteRow(status: 'locked'), ...wrongField},
          quoteEdge: (_) async => throw StateError('unexpected edge call'),
        );
        await expectLater(
          repository.lockQuote(
            bookingRequestId: 'booking-1',
            fareQuoteId: 'aaaaaaaa-bbbb-4ccc-9ddd-eeeeeeeeeeee',
            expectedBookingVersion: 1,
            expectedQuoteVersion: 1,
          ),
          throwsA(isA<FareException>().having((e) => e.failure, 'failure',
              FareFailure.invalidResponse)),
          reason: 'incorrect lock field $wrongField',
        );
      }
    });
  });

  group('FakeFareRepository', () {
    test('exact lock replay increments once and stale replay fails after edit',
        () async {
      final fake = FakeFareRepository();
      final booking = await fake.createBookingDraft(
        pickup: _pickup,
        destination: _destination,
        vehicleTypeCode: 'economy',
        paymentMethod: 'cash',
      );
      final quote = await fake.fetchQuote(
        bookingRequestId: booking.bookingRequestId,
        expectedBookingVersion: booking.version,
        routeDistanceMeters: 5400,
        routeDurationSeconds: 720,
      );
      Future<FareQuote> replay() => fake.lockQuote(
            bookingRequestId: booking.bookingRequestId,
            fareQuoteId: quote.id,
            expectedBookingVersion: booking.version,
            expectedQuoteVersion: quote.quoteVersion,
          );
      final locked = await replay();
      expect(await replay(), locked);
      final edited = await fake.updateBookingDraft(
        bookingRequestId: booking.bookingRequestId,
        expectedBookingVersion: 2,
        pickup: _pickup,
        destination: _destination,
        vehicleTypeCode: 'comfort',
        paymentMethod: 'cash',
      );
      expect(edited.version, 3);
      await expectLater(replay(), throwsA(isA<FareException>().having(
          (e) => e.failure, 'failure', FareFailure.versionConflict)));
    });

    test('supports create, superseding update, and re-quote', () async {
      final fake = FakeFareRepository();

      final created = await fake.createBookingDraft(
        pickup: _pickup,
        destination: _destination,
        vehicleTypeCode: 'economy',
        paymentMethod: 'cash',
      );
      final first = await fake.fetchQuote(
        bookingRequestId: created.bookingRequestId,
        expectedBookingVersion: created.version,
        routeDistanceMeters: 5400,
        routeDurationSeconds: 720,
      );
      expect(first.quoteVersion, 1);

      final updated = await fake.updateBookingDraft(
        bookingRequestId: created.bookingRequestId,
        expectedBookingVersion: created.version,
        pickup: _pickup,
        destination: _destination,
        vehicleTypeCode: 'economy',
        paymentMethod: 'cash',
      );
      expect(updated.version, 2);

      // The stale booking version can no longer re-quote.
      await expectLater(
        fake.fetchQuote(
          bookingRequestId: created.bookingRequestId,
          expectedBookingVersion: 1,
          routeDistanceMeters: 5400,
          routeDurationSeconds: 720,
        ),
        throwsA(
          isA<FareException>().having(
            (error) => error.failure,
            'failure',
            FareFailure.versionConflict,
          ),
        ),
      );

      final second = await fake.fetchQuote(
        bookingRequestId: updated.bookingRequestId,
        expectedBookingVersion: updated.version,
        routeDistanceMeters: 6100,
        routeDurationSeconds: 800,
      );
      expect(second.routeDistanceMeters, 6100);
      expect(
        fake.calls.where((call) => call.startsWith('quote')).length,
        greaterThanOrEqualTo(2),
      );
    });

    test('reports notFound, injected failures, and seeded expiry', () async {
      final fake = FakeFareRepository();
      await expectLater(
        fake.updateBookingDraft(
          bookingRequestId: 'missing',
          expectedBookingVersion: 1,
          pickup: _pickup,
          destination: _destination,
          vehicleTypeCode: 'economy',
          paymentMethod: 'cash',
        ),
        throwsA(
          isA<FareException>().having(
            (error) => error.failure,
            'failure',
            FareFailure.notFound,
          ),
        ),
      );

      fake.failNext(const FareException(FareFailure.pricingUnavailable));
      await expectLater(
        fake.createBookingDraft(
          pickup: _pickup,
          destination: _destination,
          vehicleTypeCode: 'economy',
          paymentMethod: 'cash',
        ),
        throwsA(
          isA<FareException>().having(
            (error) => error.failure,
            'failure',
            FareFailure.pricingUnavailable,
          ),
        ),
      );

      final created = await fake.createBookingDraft(
        pickup: _pickup,
        destination: _destination,
        vehicleTypeCode: 'economy',
        paymentMethod: 'cash',
      );
      fake.seedQuote(
        FareQuote(
          id: 'quote-expired',
          bookingRequestId: created.bookingRequestId,
          quoteVersion: 1,
          pricingVersion: 1,
          fixedFareFils: 2000,
          breakdown: const FareBreakdown(
            baseFareFils: 500,
            distanceFils: 1200,
            durationFils: 300,
            stopsFils: 0,
            subtotalFils: 2000,
            minimumFareFils: 1000,
            roundingIncrementFils: 50,
            fixedFareFils: 2000,
          ),
          status: FareQuoteStatus.calculated,
          expiresAt: DateTime.now().toUtc().subtract(
                const Duration(minutes: 1),
              ),
        ),
      );
      final quote = await fake.fetchQuote(
        bookingRequestId: created.bookingRequestId,
        expectedBookingVersion: created.version,
        routeDistanceMeters: 5400,
        routeDurationSeconds: 720,
      );
      expect(quote.id, 'quote-expired');
      expect(quote.isExpiredAt(DateTime.now().toUtc()), isTrue);
      expect(quote.isUsableAt(DateTime.now().toUtc()), isFalse);
    });
  });

  group('UnavailableFareRepository', () {
    test('throws unavailable for every operation', () async {
      const repository = UnavailableFareRepository();
      await expectLater(
        repository.createBookingDraft(
          pickup: _pickup,
          destination: _destination,
          vehicleTypeCode: 'economy',
          paymentMethod: 'cash',
        ),
        throwsA(
          isA<FareException>().having(
            (error) => error.failure,
            'failure',
            FareFailure.unavailable,
          ),
        ),
      );
      await expectLater(
        repository.fetchQuote(
          bookingRequestId: 'booking-1',
          expectedBookingVersion: 1,
          routeDistanceMeters: 1,
          routeDurationSeconds: 1,
        ),
        throwsA(
          isA<FareException>().having(
            (error) => error.failure,
            'failure',
            FareFailure.unavailable,
          ),
        ),
      );
    });
  });
}
