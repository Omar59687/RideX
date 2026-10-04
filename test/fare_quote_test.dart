import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/fare_quote.dart';

Map<String, dynamic> quoteJson({Map<String, dynamic>? overrides}) {
  return {
    'id': 'aaaaaaaa-bbbb-4ccc-9ddd-eeeeeeeeeeee',
    'booking_request_id': '7f9c9c9c-1234-4abc-9def-0123456789ab',
    'quote_version': 2,
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
    'status': 'calculated',
    'expires_at': '2026-10-04T12:10:00.000Z',
    'created_at': '2026-10-04T12:00:00.000Z',
    'route_distance_meters': 5400,
    'route_duration_seconds': 720,
    ...?overrides,
  };
}

void main() {
  group('FareQuote mapping', () {
    test('maps the backend quote row including all breakdown keys', () {
      final quote = FareQuote.fromJson(quoteJson());

      expect(quote.id, 'aaaaaaaa-bbbb-4ccc-9ddd-eeeeeeeeeeee');
      expect(quote.bookingRequestId, '7f9c9c9c-1234-4abc-9def-0123456789ab');
      expect(quote.quoteVersion, 2);
      expect(quote.pricingVersion, 3);
      expect(quote.fixedFareFils, 2050);
      expect(quote.currency, 'JOD');
      expect(quote.status, FareQuoteStatus.calculated);
      expect(quote.routeDistanceMeters, 5400);
      expect(quote.routeDurationSeconds, 720);
      expect(
        quote.breakdown,
        const FareBreakdown(
          baseFareFils: 500,
          distanceFils: 1200,
          durationFils: 300,
          stopsFils: 0,
          subtotalFils: 2000,
          minimumFareFils: 1000,
          roundingIncrementFils: 50,
          fixedFareFils: 2050,
        ),
      );
    });

    test('round-trips through toJson', () {
      final quote = FareQuote.fromJson(quoteJson());
      expect(FareQuote.fromJson(quote.toJson()), quote);
    });

    test('rejects non-JOD currency, unknown status, and bad amounts', () {
      final invalid = [
        quoteJson(overrides: {'currency': 'USD'}),
        quoteJson(overrides: {'status': 'pending'}),
        quoteJson(overrides: {'fixed_fare_fils': -1}),
        quoteJson(overrides: {'quote_version': 0}),
        quoteJson(overrides: {'expires_at': 'not-a-date'}),
        {
          ...quoteJson(),
          'breakdown': {'base_fare_fils': 1},
        },
        {
          ...quoteJson(),
          'breakdown': {
            ...(quoteJson()['breakdown'] as Map<String, dynamic>),
            'rounding_increment_fils': 0,
          },
        },
      ];
      for (final json in invalid) {
        expect(
          () => FareQuote.fromJson(json),
          throwsA(
            isA<FareException>().having(
              (error) => error.failure,
              'failure',
              FareFailure.invalidResponse,
            ),
          ),
        );
      }
    });

    test('detects minimum-fare application from backend numbers', () {
      final applied = FareQuote.fromJson(
        quoteJson(
          overrides: {
            'breakdown': {
              'base_fare_fils': 500,
              'distance_fils': 100,
              'duration_fils': 50,
              'stops_fils': 0,
              'subtotal_fils': 650,
              'minimum_fare_fils': 1000,
              'rounding_increment_fils': 50,
              'fixed_fare_fils': 1000,
            },
          },
        ),
      );
      expect(applied.breakdown.minimumApplied, isTrue);

      final notApplied = FareQuote.fromJson(quoteJson());
      expect(notApplied.breakdown.minimumApplied, isFalse);
    });
  });

  group('FareQuote expiry', () {
    test('usable only when calculated and unexpired', () {
      final now = DateTime.utc(2026, 10, 4, 12, 5);
      final usable = FareQuote.fromJson(quoteJson());
      expect(usable.isUsableAt(now), isTrue);
      expect(usable.isExpiredAt(now), isFalse);

      final expiredByTime = FareQuote.fromJson(
        quoteJson(overrides: {'expires_at': '2026-10-04T12:04:00.000Z'}),
      );
      expect(expiredByTime.isExpiredAt(now), isTrue);
      expect(expiredByTime.isUsableAt(now), isFalse);

      final expiredByStatus = FareQuote.fromJson(
        quoteJson(overrides: {'status': 'expired'}),
      );
      expect(expiredByStatus.isExpiredAt(now), isTrue);
      expect(expiredByStatus.isUsableAt(now), isFalse);

      final superseded = FareQuote.fromJson(
        quoteJson(overrides: {'status': 'superseded'}),
      );
      expect(superseded.isUsableAt(now), isFalse);
    });
  });

  group('formatFareFils', () {
    test('formats integer fils as JOD with integer arithmetic only', () {
      expect(formatFareFils(0), 'JOD 0.00');
      expect(formatFareFils(4), 'JOD 0.00');
      expect(formatFareFils(5), 'JOD 0.01');
      expect(formatFareFils(1000), 'JOD 1.00');
      expect(formatFareFils(1500), 'JOD 1.50');
      expect(formatFareFils(1999), 'JOD 2.00');
      expect(formatFareFils(2000), 'JOD 2.00');
      expect(formatFareFils(2050), 'JOD 2.05');
    });

    test('rejects negative fils', () {
      expect(() => formatFareFils(-1), throwsArgumentError);
    });
  });
}
