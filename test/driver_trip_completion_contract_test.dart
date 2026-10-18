import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/repositories/driver_trip_completion_repository.dart';

const _tripId = 'c7f00000-0000-0000-0000-000000000001';
const _otherTripId = 'c7f00000-0000-0000-0000-000000000002';

DriverCompleteTripCommand command({
  String tripId = _tripId,
  int expectedTripVersion = 4,
  String idempotencyKey = 'complete-key-1',
}) =>
    DriverCompleteTripCommand(
      tripId: tripId,
      expectedTripVersion: expectedTripVersion,
      idempotencyKey: idempotencyKey,
    );

Matcher completionFailure(DriverCompletionFailure failure) =>
    isA<DriverTripCompletionException>()
        .having((error) => error.failure, 'failure', failure);

void main() {
  group('additive attempt evidence contract', () {
    test('post-write errors remain catchable as legacy unknown-result failures',
        () {
      final original = command();
      final DriverTripCompletionException error =
          DriverCompletionAttemptException.tripReread(
              original, DriverCompletionFailure.tripNotFound);
      expect(error.failure, DriverCompletionFailure.unknownResult);
      final attempt = error as DriverCompletionAttemptException;
      expect(attempt.command, same(original));
      expect(attempt.writeEvidence, DriverCompletionWriteEvidence.acknowledged);
      expect(attempt.confirmedTrip, isNull);
      expect(attempt.toString(), isNot(contains(original.idempotencyKey)));
      expect(attempt.toString(), isNot(contains(original.tripId)));
    });
    test('receipt recovery rejects mismatched or unverified canonical evidence',
        () {
      final invalid = <DriverCompleteTripResult>[
        DriverCompleteTripResult(
            tripId: _otherTripId,
            status: DriverTripLifecycleStatus.completed,
            backendVersion: 5),
        DriverCompleteTripResult(
            tripId: _tripId,
            status: DriverTripLifecycleStatus.inProgress,
            backendVersion: 5),
        DriverCompleteTripResult(
            tripId: _tripId, status: DriverTripLifecycleStatus.completed),
        DriverCompleteTripResult(
            tripId: _tripId,
            status: DriverTripLifecycleStatus.completed,
            backendVersion: 5,
            receiptVerified: true,
            receiptNumber: 'RX-PRIVATE'),
      ];
      for (final trip in invalid) {
        expect(
            () => DriverCompletionAttemptException.receiptReread(
                  command(),
                  DriverCompletionFailure.unknownResult,
                  trip,
                ),
            throwsArgumentError);
      }
    });
    test(
        'receipt-read failure retains canonical result without leaking it in logs',
        () {
      final original = command();
      final trip = DriverCompleteTripResult(
          tripId: _tripId,
          status: DriverTripLifecycleStatus.completed,
          backendVersion: 8);
      final error = DriverCompletionAttemptException.receiptReread(
        original,
        DriverCompletionFailure.unauthorized,
        trip,
      );
      expect(error.confirmedTrip, same(trip));
      expect(error.failure, DriverCompletionFailure.unknownResult);
      expect(error.cause, DriverCompletionFailure.unauthorized);
      expect(error.writeEvidence, DriverCompletionWriteEvidence.verified);
      expect(error.toString(), isNot(contains(original.tripId)));
    });
  });
  group('DriverCompleteTripCommand validation', () {
    test('accepts a canonical UUID with positive version and key', () {
      final value = command();
      expect(value.tripId, _tripId);
      expect(value.expectedTripVersion, 4);
      expect(value.idempotencyKey, 'complete-key-1');
    });

    test('rejects mock and malformed trip identifiers', () {
      for (final id in [
        'trip-1',
        '',
        '   ',
        'not-a-uuid',
        'c7f00000-0000-0000-0000-00000000000',
        'c7f00000-0000-0000-0000-000000000001-extra',
        '00000000-0000-0000-0000-00000000000g',
      ]) {
        expect(() => command(tripId: id), throwsArgumentError);
      }
    });

    test('rejects non-positive expected versions', () {
      expect(() => command(expectedTripVersion: 0), throwsArgumentError);
      expect(() => command(expectedTripVersion: -2), throwsArgumentError);
    });

    test('rejects blank or over-long idempotency keys', () {
      expect(() => command(idempotencyKey: ''), throwsArgumentError);
      expect(() => command(idempotencyKey: '   '), throwsArgumentError);
      expect(
        () => command(idempotencyKey: List.filled(129, 'k').join()),
        throwsArgumentError,
      );
    });

    test('accepts a 128-character key and trims surrounding whitespace', () {
      final key = List.filled(128, 'k').join();
      final value = command(idempotencyKey: '  $key  ');
      expect(value.idempotencyKey, key);
      expect(value.idempotencyKey.length, 128);
    });

    test('trims the trip identifier', () {
      final value = command(tripId: '  $_tripId  ');
      expect(value.tripId, _tripId);
    });

    test('isCanonicalTripId matches backend UUID shape only', () {
      expect(isCanonicalTripId(_tripId), isTrue);
      expect(isCanonicalTripId('trip-1'), isFalse);
      expect(isCanonicalTripId(''), isFalse);
    });
  });

  group('DriverTripLifecycleStatus vocabulary', () {
    test('round-trips all nine canonical backend values', () {
      expect(
        DriverTripLifecycleStatus.values.map((status) => status.backendValue),
        [
          'accepted',
          'driverArriving',
          'driverArrived',
          'inProgress',
          'completed',
          'cancelledByRider',
          'cancelledByDriver',
          'cancelledByAdmin',
          'failed',
        ],
      );
      for (final status in DriverTripLifecycleStatus.values) {
        expect(
          DriverTripLifecycleStatus.fromBackendValue(status.backendValue),
          status,
        );
      }
    });

    test('rejects mock-only and unknown statuses', () {
      for (final value in [
        'requested',
        'searching',
        'noDriverFound',
        'Completed',
        '',
      ]) {
        expect(
          () => DriverTripLifecycleStatus.fromBackendValue(value),
          throwsArgumentError,
        );
      }
    });
  });

  group('DriverCompleteTripResult boundaries', () {
    test('unverified completion carries no version or receipt', () {
      final result = DriverCompleteTripResult(
        tripId: _tripId,
        status: DriverTripLifecycleStatus.completed,
      );
      expect(result.isCompleted, isTrue);
      expect(result.backendVersion, isNull);
      expect(result.receiptVerified, isFalse);
      expect(result.receiptNumber, isNull);
    });

    test('completion alone never implies payment success', () {
      final result = DriverCompleteTripResult(
        tripId: _tripId,
        status: DriverTripLifecycleStatus.completed,
      );
      // There is no payment field on the result; verified receipt state
      // requires a separate authorized reread.
      expect(result.isCompleted, isTrue);
      expect(result.receiptVerified, isFalse);
    });

    test('non-completed canonical status is preserved without receipt', () {
      final result = DriverCompleteTripResult(
        tripId: _tripId,
        status: DriverTripLifecycleStatus.inProgress,
      );
      expect(result.isCompleted, isFalse);
      expect(result.receiptVerified, isFalse);
    });

    test('accepts verified receipt with version from authorized reread', () {
      final result = DriverCompleteTripResult(
        tripId: _tripId,
        status: DriverTripLifecycleStatus.completed,
        backendVersion: 5,
        receiptVerified: true,
        receiptNumber: 'RDX-20261016-ABCDEF12',
      );
      expect(result.backendVersion, 5);
      expect(result.receiptVerified, isTrue);
      expect(result.receiptNumber, 'RDX-20261016-ABCDEF12');
    });

    test('rejects verified result without receipt number', () {
      expect(
        () => DriverCompleteTripResult(
          tripId: _tripId,
          status: DriverTripLifecycleStatus.completed,
          receiptVerified: true,
        ),
        throwsArgumentError,
      );
    });

    test('rejects unverified result carrying receipt data', () {
      expect(
        () => DriverCompleteTripResult(
          tripId: _tripId,
          status: DriverTripLifecycleStatus.completed,
          receiptNumber: 'RDX-20261016-ABCDEF12',
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-positive backend versions and bad trip ids', () {
      expect(
        () => DriverCompleteTripResult(
          tripId: _tripId,
          status: DriverTripLifecycleStatus.completed,
          backendVersion: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => DriverCompleteTripResult(
          tripId: 'trip-1',
          status: DriverTripLifecycleStatus.completed,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Backend response parsing', () {
    test('parses a valid completion response without fabrication', () {
      final result = DriverCompletionParsing.parseCompletionResponse({
        'trip_id': _tripId,
        'status': 'completed',
      });
      expect(result.tripId, _tripId);
      expect(result.status, DriverTripLifecycleStatus.completed);
      expect(result.backendVersion, isNull);
      expect(result.receiptVerified, isFalse);
      expect(result.receiptNumber, isNull);
    });

    test('parses non-completed canonical status instead of failing', () {
      final result = DriverCompletionParsing.parseCompletionResponse({
        'trip_id': _tripId,
        'status': 'inProgress',
      });
      expect(result.isCompleted, isFalse);
    });

    test('maps the idempotency mismatch shape to a typed conflict', () {
      expect(
        () => DriverCompletionParsing.parseCompletionResponse({
          'error': 'idempotency_payload_mismatch',
        }),
        throwsA(
          completionFailure(DriverCompletionFailure.idempotencyConflict),
        ),
      );
    });

    test('rejects malformed backend payloads', () {
      final payloads = <Map<String, Object?>>[
        {},
        {'trip_id': _tripId},
        {'status': 'completed'},
        {'trip_id': '', 'status': 'completed'},
        {'trip_id': 'trip-1', 'status': 'completed'},
        {'trip_id': _tripId, 'status': 'bogus'},
        {'trip_id': _tripId, 'status': 'searching'},
        {'trip_id': _tripId, 'status': ''},
        {'error': 'something-else'},
        {'error': 'idempotency_payload_mismatch', 'trip_id': _tripId},
      ];
      for (final payload in payloads) {
        expect(
          () => DriverCompletionParsing.parseCompletionResponse(payload),
          throwsA(
            completionFailure(DriverCompletionFailure.malformedResponse),
          ),
          reason: payload.toString(),
        );
      }
    });

    test('rejects incorrect JSON types', () {
      final payloads = <Map<String, Object?>>[
        {'trip_id': 42, 'status': 'completed'},
        {'trip_id': _tripId, 'status': 42},
        {'trip_id': null, 'status': 'completed'},
        {
          'trip_id': [_tripId],
          'status': 'completed'
        },
      ];
      for (final payload in payloads) {
        expect(
          () => DriverCompletionParsing.parseCompletionResponse(payload),
          throwsA(
            completionFailure(DriverCompletionFailure.malformedResponse),
          ),
          reason: payload.toString(),
        );
      }
    });
  });

  group('FakeDriverTripCompletionRepository', () {
    test('returns unverified success by default and records the call',
        () async {
      final fake = FakeDriverTripCompletionRepository();
      final result = await fake.completeTrip(command());
      expect(result.tripId, _tripId);
      expect(result.isCompleted, isTrue);
      expect(result.backendVersion, isNull);
      expect(result.receiptVerified, isFalse);
      expect(result.receiptNumber, isNull);
      expect(fake.callCount, 1);
      expect(fake.calls.single.isExactReplayOf(command()), isTrue);
    });

    test('returns the scripted success result for the requested trip',
        () async {
      final scripted = DriverCompleteTripResult(
        tripId: _tripId,
        status: DriverTripLifecycleStatus.completed,
        backendVersion: 5,
        receiptVerified: true,
        receiptNumber: 'RDX-20261016-ABCDEF12',
      );
      final fake = FakeDriverTripCompletionRepository(
        successResult: scripted,
      );
      expect(await fake.completeTrip(command()), scripted);
    });

    test('rejects a scripted success result for another trip', () async {
      final fake = FakeDriverTripCompletionRepository(
        successResult: DriverCompleteTripResult(
          tripId: _otherTripId,
          status: DriverTripLifecycleStatus.completed,
        ),
      );
      await expectLater(
        fake.completeTrip(command()),
        throwsA(
          completionFailure(DriverCompletionFailure.malformedResponse),
        ),
      );
    });

    test('covers every failure category deterministically', () async {
      const expectations = {
        FakeCompletionScenario.unauthorized:
            DriverCompletionFailure.unauthorized,
        FakeCompletionScenario.tripNotFound:
            DriverCompletionFailure.tripNotFound,
        FakeCompletionScenario.staleVersion:
            DriverCompletionFailure.staleVersion,
        FakeCompletionScenario.invalidTransition:
            DriverCompletionFailure.invalidTransition,
        FakeCompletionScenario.idempotencyConflict:
            DriverCompletionFailure.idempotencyConflict,
        FakeCompletionScenario.unknownResult:
            DriverCompletionFailure.unknownResult,
        FakeCompletionScenario.malformedResponse:
            DriverCompletionFailure.malformedResponse,
      };
      for (final entry in expectations.entries) {
        final fake = FakeDriverTripCompletionRepository(
          scenario: entry.key,
        );
        await expectLater(
          fake.completeTrip(command()),
          throwsA(completionFailure(entry.value)),
          reason: entry.key.name,
        );
        expect(fake.callCount, 1);
      }
    });

    test('records exact replay identity across retries', () async {
      final fake = FakeDriverTripCompletionRepository();
      final first = command();
      final replay = command();
      await fake.completeTrip(first);
      await fake.completeTrip(replay);
      expect(fake.callCount, 2);
      expect(fake.calls[0].isExactReplayOf(fake.calls[1]), isTrue);
      expect(fake.calls[0], fake.calls[1]);
    });

    test('distinguishes a bumped version from an exact replay', () async {
      final fake = FakeDriverTripCompletionRepository();
      final first = command(expectedTripVersion: 4);
      final bumped = command(expectedTripVersion: 5);
      await fake.completeTrip(first);
      await fake.completeTrip(bumped);
      expect(first.isExactReplayOf(bumped), isFalse);
      expect(fake.calls[0].isExactReplayOf(fake.calls[1]), isFalse);
    });

    test('simulates no settlement: success never verifies payment', () async {
      final fake = FakeDriverTripCompletionRepository();
      final result = await fake.completeTrip(command());
      expect(result.receiptVerified, isFalse);
      expect(result.receiptNumber, isNull);
    });
  });
}
