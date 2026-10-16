import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_completion_recovery.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';

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

const _closedDebugCodes = ClassifiedCompletionFailure.closedDebugCodes;

void main() {
  group('SQLSTATE classification', () {
    test('maps every known completion-path code', () {
      const expectations = {
        '42501': DriverCompletionFailure.unauthorized,
        'P0002': DriverCompletionFailure.tripNotFound,
        '40001': DriverCompletionFailure.staleVersion,
        '55000': DriverCompletionFailure.invalidTransition,
        '22023': DriverCompletionFailure.invalidTransition,
      };
      for (final entry in expectations.entries) {
        final classified = DriverCompletionErrorMapping.fromSqlState(entry.key);
        expect(classified.failure, entry.value, reason: entry.key);
        expect(classified.debugCode, entry.key);
      }
    });

    test('normalizes padding and letter case before matching', () {
      expect(
        DriverCompletionErrorMapping.fromSqlState(' p0002 ').failure,
        DriverCompletionFailure.tripNotFound,
      );
      expect(
        DriverCompletionErrorMapping.fromSqlState(' 42501').debugCode,
        '42501',
      );
    });

    test('treats unknown or absent codes as unknown, never as confirmed', () {
      for (final code in ['54000', '23505', 'XX000', '', '   ']) {
        final classified = DriverCompletionErrorMapping.fromSqlState(code);
        expect(
          classified.failure,
          DriverCompletionFailure.unknownResult,
          reason: 'code: "$code"',
        );
        expect(classified.debugCode, 'unknown-sqlstate');
      }
    });

    test('does not misread the accept-path 54000 code as a trip outcome', () {
      final classified = DriverCompletionErrorMapping.fromSqlState('54000');
      expect(classified.failure, isNot(DriverCompletionFailure.tripNotFound));
      expect(classified.failure, isNot(DriverCompletionFailure.staleVersion));
      expect(
        classified.failure,
        isNot(DriverCompletionFailure.invalidTransition),
      );
      expect(classified.failure, DriverCompletionFailure.unknownResult);
    });

    test('keeps the authoritative vocabulary fixed to ten safe codes', () {
      expect(
        ClassifiedCompletionFailure.closedDebugCodes,
        {
          '42501',
          'P0002',
          '40001',
          '55000',
          '22023',
          'unknown-sqlstate',
          'idempotency-mismatch',
          'timeout',
          'transport-disconnect',
          'malformed-payload',
        },
      );
    });

    test('keeps every debug code inside the closed vocabulary', () {
      final inputs = [
        '42501',
        'P0002',
        '40001',
        '55000',
        '22023',
        '54000',
        'XX000',
        '',
        'p0002',
      ];
      for (final input in inputs) {
        expect(
          _closedDebugCodes,
          contains(
            DriverCompletionErrorMapping.fromSqlState(input).debugCode,
          ),
          reason: 'input: "$input"',
        );
      }
      expect(
        _closedDebugCodes,
        contains(
          DriverCompletionErrorMapping.idempotencyMismatch().debugCode,
        ),
      );
      expect(
        _closedDebugCodes,
        contains(
          DriverCompletionErrorMapping.transportLoss(
            TransportLossKind.timeout,
          ).debugCode,
        ),
      );
      expect(
        _closedDebugCodes,
        contains(
          DriverCompletionErrorMapping.transportLoss(
            TransportLossKind.disconnect,
          ).debugCode,
        ),
      );
      expect(
        _closedDebugCodes,
        contains(
          DriverCompletionErrorMapping.malformedPayload().debugCode,
        ),
      );
    });
  });

  group('Transport and payload classification', () {
    test('maps timeout and disconnect to unknown with distinct codes', () {
      final timeout = DriverCompletionErrorMapping.transportLoss(
        TransportLossKind.timeout,
      );
      final disconnect = DriverCompletionErrorMapping.transportLoss(
        TransportLossKind.disconnect,
      );
      expect(timeout.failure, DriverCompletionFailure.unknownResult);
      expect(disconnect.failure, DriverCompletionFailure.unknownResult);
      expect(timeout.debugCode, 'timeout');
      expect(disconnect.debugCode, 'transport-disconnect');
    });

    test('maps the mismatch shape to a typed conflict', () {
      final classified = DriverCompletionErrorMapping.idempotencyMismatch();
      expect(
        classified.failure,
        DriverCompletionFailure.idempotencyConflict,
      );
      expect(classified.debugCode, 'idempotency-mismatch');
    });

    test('maps unparsable payloads to malformed without raw content', () {
      final classified = DriverCompletionErrorMapping.malformedPayload();
      expect(classified.failure, DriverCompletionFailure.malformedResponse);
      expect(classified.debugCode, 'malformed-payload');
    });
  });

  group('SQL recovery directives', () {
    test('routes recognized rejections to RejectionConfirmed', () {
      const expectations = {
        '42501': DriverCompletionFailure.unauthorized,
        'P0002': DriverCompletionFailure.tripNotFound,
        '40001': DriverCompletionFailure.staleVersion,
        '55000': DriverCompletionFailure.invalidTransition,
        '22023': DriverCompletionFailure.invalidTransition,
      };
      for (final entry in expectations.entries) {
        final directive = CompletionRecovery.fromSqlState(entry.key);
        expect(directive, isA<RejectionConfirmed>(), reason: entry.key);
        expect(
          (directive as RejectionConfirmed).error.failure,
          entry.value,
        );
      }
    });

    test('routes unknown codes to canonical reread, not rejection', () {
      for (final code in ['54000', 'XX000', '']) {
        final directive = CompletionRecovery.fromSqlState(code);
        expect(
          directive,
          isA<CanonicalRereadRequired>(),
          reason: 'code: "$code"',
        );
        expect(
          (directive as CanonicalRereadRequired).error.failure,
          DriverCompletionFailure.unknownResult,
        );
      }
    });
  });

  group('JSON recovery directives', () {
    test('routes a valid completion to receipt reread without fabrication', () {
      final directive = CompletionRecovery.fromJsonResponse({
        'trip_id': _tripId,
        'status': 'completed',
      });
      expect(directive, isA<ReceiptRereadRequired>());
      final result = (directive as ReceiptRereadRequired).result;
      expect(result.tripId, _tripId);
      expect(result.isCompleted, isTrue);
      expect(result.backendVersion, isNull);
      expect(result.receiptVerified, isFalse);
      expect(result.receiptNumber, isNull);
    });

    test('completion directive never implies payment success', () {
      final directive = CompletionRecovery.fromJsonResponse({
        'trip_id': _tripId,
        'status': 'completed',
      });
      final result = (directive as ReceiptRereadRequired).result;
      expect(result.isCompleted, isTrue);
      expect(result.receiptVerified, isFalse);
    });

    test('routes a non-completed status to canonical reread as malformed', () {
      for (final status in [
        'accepted',
        'driverArriving',
        'inProgress',
        'cancelledByDriver',
        'failed',
      ]) {
        final directive = CompletionRecovery.fromJsonResponse({
          'trip_id': _tripId,
          'status': status,
        });
        expect(
          directive,
          isA<CanonicalRereadRequired>(),
          reason: 'status: $status',
        );
        expect(
          (directive as CanonicalRereadRequired).error.failure,
          DriverCompletionFailure.malformedResponse,
        );
      }
    });

    test('permits receipt reread only for confirmed completion', () {
      for (final status in DriverTripLifecycleStatus.values) {
        final directive = CompletionRecovery.fromJsonResponse({
          'trip_id': _tripId,
          'status': status.backendValue,
        });
        if (status == DriverTripLifecycleStatus.completed) {
          expect(directive, isA<ReceiptRereadRequired>());
        } else {
          expect(directive, isA<CanonicalRereadRequired>());
        }
      }
    });

    test('routes the mismatch shape to rejection with conflict', () {
      final directive = CompletionRecovery.fromJsonResponse({
        'error': 'idempotency_payload_mismatch',
      });
      expect(directive, isA<RejectionConfirmed>());
      expect(
        (directive as RejectionConfirmed).error.failure,
        DriverCompletionFailure.idempotencyConflict,
      );
    });

    test('routes garbled payloads to canonical reread as malformed', () {
      final payloads = <Map<String, Object?>>[
        {},
        {'trip_id': _tripId},
        {'trip_id': 'trip-1', 'status': 'completed'},
        {'trip_id': _tripId, 'status': 'bogus'},
        {'error': 'something-else'},
        {'trip_id': 42, 'status': 'completed'},
      ];
      for (final payload in payloads) {
        final directive = CompletionRecovery.fromJsonResponse(payload);
        expect(
          directive,
          isA<CanonicalRereadRequired>(),
          reason: payload.toString(),
        );
        expect(
          (directive as CanonicalRereadRequired).error.failure,
          DriverCompletionFailure.malformedResponse,
        );
      }
    });
  });

  group('Transport recovery directives', () {
    test('routes timeout and disconnect to canonical reread', () {
      for (final kind in TransportLossKind.values) {
        final directive = CompletionRecovery.fromTransportLoss(kind);
        expect(directive, isA<CanonicalRereadRequired>());
        expect(
          (directive as CanonicalRereadRequired).error.failure,
          DriverCompletionFailure.unknownResult,
        );
      }
    });
  });

  group('Replay validation', () {
    test('accepts the identical triple as an exact replay', () {
      expect(
        validateCompletionReplay(command(), command()),
        ReplayValidity.exactReplay,
      );
    });

    test('rejects a bumped version', () {
      expect(
        validateCompletionReplay(
          command(expectedTripVersion: 4),
          command(expectedTripVersion: 5),
        ),
        ReplayValidity.versionChanged,
      );
    });

    test('rejects a rotated idempotency key', () {
      expect(
        validateCompletionReplay(
          command(idempotencyKey: 'complete-key-1'),
          command(idempotencyKey: 'complete-key-2'),
        ),
        ReplayValidity.keyChanged,
      );
    });

    test('rejects a different trip', () {
      expect(
        validateCompletionReplay(
          command(tripId: _tripId),
          command(tripId: _otherTripId),
        ),
        ReplayValidity.tripChanged,
      );
    });

    test('applies deterministic priority when several fields differ', () {
      final original = command();
      final allChanged = command(
        tripId: _otherTripId,
        expectedTripVersion: 9,
        idempotencyKey: 'another-key',
      );
      expect(
        validateCompletionReplay(original, allChanged),
        ReplayValidity.tripChanged,
      );
      expect(
        validateCompletionReplay(
          original,
          command(expectedTripVersion: 9, idempotencyKey: 'another-key'),
        ),
        ReplayValidity.versionChanged,
      );
    });

    test('matches isExactReplayOf in both directions', () {
      final pairs = [
        (command(), command()),
        (
          command(expectedTripVersion: 4),
          command(expectedTripVersion: 5),
        ),
        (
          command(idempotencyKey: 'complete-key-1'),
          command(idempotencyKey: 'complete-key-2'),
        ),
        (
          command(tripId: _tripId),
          command(tripId: _otherTripId),
        ),
      ];
      for (final pair in pairs) {
        expect(
          validateCompletionReplay(pair.$1, pair.$2) ==
              ReplayValidity.exactReplay,
          pair.$1.isExactReplayOf(pair.$2),
          reason: '${pair.$1} vs ${pair.$2}',
        );
      }
    });

    test('classification is deterministic across repeated calls', () {
      expect(
        DriverCompletionErrorMapping.fromSqlState('40001'),
        DriverCompletionErrorMapping.fromSqlState('40001'),
      );
      expect(
        CompletionRecovery.fromTransportLoss(TransportLossKind.timeout),
        CompletionRecovery.fromTransportLoss(TransportLossKind.timeout),
      );
      expect(
        validateCompletionReplay(command(), command()),
        validateCompletionReplay(command(), command()),
      );
    });
  });
}
