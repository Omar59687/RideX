import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/driver_completion_recovery.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';
import 'package:ridex/core/repositories/supabase_driver_trip_completion_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

Map<String, Object?> completionOk([String tripId = _tripId]) =>
    <String, Object?>{'trip_id': tripId, 'status': 'completed'};

Map<String, Object?> tripRow({
  String tripId = _tripId,
  String status = 'completed',
  Object? version = 5,
}) =>
    <String, Object?>{'id': tripId, 'status': status, 'version': version};

Map<String, Object?> receiptRow({
  String tripId = _tripId,
  Object? receiptNumber = 'RX-2026-0001',
}) =>
    <String, Object?>{
      'id': 'd7f00000-0000-0000-0000-000000000001',
      'receipt_number': receiptNumber,
      'trip_id': tripId,
      'amount_paid_fils': 850,
      'currency': 'JOD',
      'payment_method': 'cash',
      'card_brand': null,
      'card_last_four': null,
      'issued_at': '2026-10-16T00:00:00Z',
    };

/// Scripted backend transport: no hosted calls, fully deterministic.
class _ScriptedTransport {
  _ScriptedTransport({
    this.completionResponse = const <String, Object?>{},
    this.tripRow,
    this.receiptRows = const <Map<String, Object?>>[],
  });

  Object? completionResponse;
  Object? completionError;
  Map<String, Object?>? tripRow;
  Object? tripError;
  List<Map<String, Object?>> receiptRows;
  Object? receiptError;

  final List<Map<String, Object?>> rpcCalls = [];
  final List<String> tripReads = [];
  final List<String> receiptReads = [];

  Future<Object?> rpc({
    required String name,
    required Map<String, Object?> params,
  }) async {
    rpcCalls.add(<String, Object?>{'name': name, ...params});
    final error = completionError;
    if (error != null) throw error;
    return completionResponse;
  }

  Future<Map<String, Object?>?> readTripRow(String tripId) async {
    tripReads.add(tripId);
    final error = tripError;
    if (error != null) throw error;
    return tripRow;
  }

  Future<List<Map<String, Object?>>> readReceiptRows(String tripId) async {
    receiptReads.add(tripId);
    final error = receiptError;
    if (error != null) throw error;
    return receiptRows;
  }

  SupabaseDriverTripCompletionRepository get repository =>
      SupabaseDriverTripCompletionRepository(
        rpc: rpc,
        readTripRow: readTripRow,
        readReceiptRows: readReceiptRows,
      );
}

_ScriptedTransport _successTransport({
  Map<String, Object?>? tripRowOverride,
  List<Map<String, Object?>> receiptRows = const <Map<String, Object?>>[],
}) {
  return _ScriptedTransport(
    completionResponse: completionOk(),
    tripRow: tripRowOverride ?? tripRow(),
    receiptRows: receiptRows,
  );
}

Future<void> expectCompletionFailure(
  Future<DriverCompleteTripResult> Function() run,
  DriverCompletionFailure expected,
) async {
  try {
    await run();
  } on DriverTripCompletionException catch (error) {
    expect(error.failure, expected);
    return;
  }
  fail('Expected DriverTripCompletionException($expected)');
}

void main() {
  group('RPC invocation', () {
    test('sends the fixed completed transition with the exact triple',
        () async {
      final transport = _successTransport(
        receiptRows: [receiptRow()],
      );
      await transport.repository.completeTrip(command());

      expect(transport.rpcCalls, hasLength(1));
      expect(
        transport.rpcCalls.single,
        {
          'name': 'driver_transition_trip',
          'target_id': _tripId,
          'requested_status': 'completed',
          'expected_version': 4,
          'idempotency_key': 'complete-key-1',
        },
      );
    });

    test('passes caller idempotency keys through byte-identically', () async {
      final transport = _successTransport();
      await transport.repository.completeTrip(
        command(idempotencyKey: 'key-alpha-9'),
      );
      await transport.repository.completeTrip(
        command(idempotencyKey: 'key-beta-7'),
      );

      expect(transport.rpcCalls, hasLength(2));
      expect(transport.rpcCalls[0]['idempotency_key'], 'key-alpha-9');
      expect(transport.rpcCalls[1]['idempotency_key'], 'key-beta-7');
    });
  });

  group('success and rereads', () {
    test('attaches canonical version and verified receipt', () async {
      final transport = _successTransport(
        receiptRows: [receiptRow()],
      );
      final result = await transport.repository.completeTrip(command());

      expect(result.tripId, _tripId);
      expect(result.isCompleted, isTrue);
      expect(result.backendVersion, 5);
      expect(result.receiptVerified, isTrue);
      expect(result.receiptNumber, 'RX-2026-0001');
      expect(transport.tripReads, [_tripId]);
      expect(transport.receiptReads, [_tripId]);
    });

    test('accepts the backend-bumped version without conflict', () async {
      final transport = _successTransport(
        tripRowOverride: tripRow(version: 7),
      );
      final result = await transport.repository.completeTrip(
        command(expectedTripVersion: 4),
      );

      expect(result.backendVersion, 7);
      expect(result.receiptVerified, isFalse);
    });

    test('returns an unverified version-only result without receipt', () async {
      final transport = _successTransport();
      final result = await transport.repository.completeTrip(command());

      expect(result.isCompleted, isTrue);
      expect(result.backendVersion, 5);
      expect(result.receiptVerified, isFalse);
      expect(result.receiptNumber, isNull);
    });

    test('rejects receipt rows belonging to another trip', () async {
      final transport = _successTransport(
        receiptRows: [receiptRow(tripId: _otherTripId)],
      );
      final error = await _attemptFailure(transport);
      expect(error.cause, DriverCompletionFailure.malformedResponse);
      expect(error.confirmedTrip?.backendVersion, 5);
    });
  });

  group('backend rejections', () {
    test('maps known SQLSTATE codes to typed failures', () async {
      const expectations = {
        '42501': DriverCompletionFailure.unauthorized,
        'P0002': DriverCompletionFailure.tripNotFound,
        '40001': DriverCompletionFailure.staleVersion,
        '55000': DriverCompletionFailure.invalidTransition,
        '22023': DriverCompletionFailure.invalidTransition,
      };
      for (final entry in expectations.entries) {
        final transport = _successTransport()
          ..completionError = PostgrestException(
            message: 'rejected',
            code: entry.key,
          );
        await expectCompletionFailure(
          () => transport.repository.completeTrip(command()),
          entry.value,
        );
      }
    });

    test('maps the idempotency mismatch shape to a conflict', () async {
      final transport = _successTransport()
        ..completionResponse = <String, Object?>{
          'error': 'idempotency_payload_mismatch',
        };
      await expectCompletionFailure(
        () => transport.repository.completeTrip(command()),
        DriverCompletionFailure.idempotencyConflict,
      );
    });

    test('maps unknown codes and transport loss to unknownResult', () async {
      final errors = <Object>[
        const PostgrestException(message: 'other', code: 'XX000'),
        const PostgrestException(message: 'blank', code: ''),
        const PostgrestException(message: 'no code'),
        TimeoutException('deadline', const Duration(seconds: 1)),
        const SocketException('unreachable'),
      ];
      for (final error in errors) {
        final transport = _successTransport()..completionError = error;
        await expectCompletionFailure(
          () => transport.repository.completeTrip(command()),
          DriverCompletionFailure.unknownResult,
        );
      }
    });
  });

  group('malformed and fail-closed outcomes', () {
    test('maps garbled RPC payloads to malformedResponse', () async {
      final payloads = <Object?>[
        ['not', 'a', 'map'],
        null,
        42,
        <String, Object?>{'status': 'completed'},
        <String, Object?>{},
        <String, Object?>{'trip_id': _tripId},
        <String, Object?>{'trip_id': _tripId, 'status': 'bogus'},
        <String, Object?>{'trip_id': 'trip-1', 'status': 'completed'},
        <String, Object?>{'trip_id': 42, 'status': 'completed'},
        <String, Object?>{'error': 'something-else'},
        <String, Object?>{
          'error': 'idempotency_payload_mismatch',
          'trip_id': _tripId,
        },
      ];
      for (final payload in payloads) {
        final transport = _successTransport()..completionResponse = payload;
        await expectCompletionFailure(
          () => transport.repository.completeTrip(command()),
          DriverCompletionFailure.malformedResponse,
        );
      }
    });

    test('fails closed on a non-completed RPC status', () async {
      final transport = _successTransport()
        ..completionResponse = <String, Object?>{
          'trip_id': _tripId,
          'status': 'inProgress',
        };
      await expectCompletionFailure(
        () => transport.repository.completeTrip(command()),
        DriverCompletionFailure.malformedResponse,
      );
    });

    test('retains acknowledged completion when the canonical row is hidden',
        () async {
      final transport = _successTransport()
        ..tripRow = null
        ..receiptRows = [receiptRow()];
      await expectCompletionFailure(
        () => transport.repository.completeTrip(command()),
        DriverCompletionFailure.unknownResult,
      );
    });

    test('fails closed on unparsable canonical rows', () async {
      final rows = <Map<String, Object?>>[
        tripRow(status: 'inProgress'),
        tripRow(status: 'bogus'),
        tripRow(version: 0),
        tripRow(version: -2),
        tripRow(version: '5'),
        tripRow(version: null),
        tripRow(version: 5.0),
        tripRow()..remove('status'),
      ];
      for (final row in rows) {
        final transport = _successTransport(tripRowOverride: row);
        await expectCompletionFailure(
          () => transport.repository.completeTrip(command()),
          DriverCompletionFailure.unknownResult,
        );
      }
    });

    test('never returns partial success when rereads fail', () async {
      final errors = <Object>[
        const PostgrestException(message: 'denied', code: '42501'),
        const PostgrestException(message: 'lost', code: 'XX000'),
        TimeoutException('deadline', const Duration(seconds: 1)),
        const SocketException('unreachable'),
      ];
      for (final error in errors) {
        final asTripError = _successTransport()..tripError = error;
        await expectCompletionFailure(
          () => asTripError.repository.completeTrip(command()),
          DriverCompletionFailure.unknownResult,
        );
        final asReceiptError = _successTransport()..receiptError = error;
        await expectCompletionFailure(
          () => asReceiptError.repository.completeTrip(command()),
          DriverCompletionFailure.unknownResult,
        );
      }
    });

    test('fails closed on a receipt row without a number', () async {
      final transport = _successTransport(
        receiptRows: [receiptRow(receiptNumber: '   ')],
      );
      await expectCompletionFailure(
        () => transport.repository.completeTrip(command()),
        DriverCompletionFailure.unknownResult,
      );
    });
  });
  boundaryTests();
}

Future<DriverCompletionAttemptException> _attemptFailure(
  _ScriptedTransport transport,
) async {
  final original = command();
  try {
    await transport.repository.completeTrip(original);
  } on DriverCompletionAttemptException catch (error) {
    expect(identical(error.command, original), isTrue);
    expect(error.toString(), isNot(contains(original.idempotencyKey)));
    expect(transport.rpcCalls, hasLength(1));
    expect(transport.rpcCalls.single['expected_version'],
        original.expectedTripVersion);
    expect(
        transport.rpcCalls.single['idempotency_key'], original.idempotencyKey);
    return error;
  }
  throw StateError('Expected typed attempt failure');
}

class _CanonicalSource implements CanonicalDriverCompletionSource {
  @override
  Future<CanonicalDriverCompletionContext?> load() async =>
      CanonicalDriverCompletionContext(
        driverId: 'a7000000-0000-0000-0000-000000000001',
        command: command(),
      );
}

class _StagingGateway implements DriverCompletionStagingGateway {
  final commands = <DriverCompleteTripCommand>[];
  @override
  Future<CoordinatorStagingDecision> stage(
      CanonicalDriverCompletionContext context) async {
    commands.add(context.command);
    return commands.length == 1
        ? StagingNewlyCreated(context.command)
        : StagingExistingEvidence(commands.first);
  }
}

DriverCompletionCoordinator _coordinator(
  _ScriptedTransport transport,
  _StagingGateway gateway,
) =>
    DriverCompletionCoordinator(
      canonicalSource: _CanonicalSource(),
      stagingGateway: gateway,
      repository: transport.repository,
      sessionReader: () async => const DriverCompletionSessionSnapshot(
        driverId: 'a7000000-0000-0000-0000-000000000001',
        epoch: 1,
        isApprovedDriver: true,
      ),
    );

void boundaryTests() {
  group('identity boundaries', () {
    for (final identity in <Object?>[_otherTripId, null, 42, 'trip-1']) {
      test('RPC identity $identity cannot complete caller Trip', () async {
        final transport = _successTransport()
          ..completionResponse = {'trip_id': identity, 'status': 'completed'};
        final error = await _attemptFailure(transport);
        expect(error.stage, DriverCompletionAttemptStage.rpc);
        expect(error.writeEvidence, DriverCompletionWriteEvidence.unknown);
        expect(error.failure, DriverCompletionFailure.malformedResponse);
        expect(error.confirmedTrip, isNull);
        expect(transport.tripReads, isEmpty);
        expect(transport.receiptReads, isEmpty);
      });
      test('canonical identity $identity cannot complete caller Trip',
          () async {
        final transport = _successTransport()
          ..tripRow = {
            'id': identity,
            'status': 'completed',
            'version': 5,
          };
        final error = await _attemptFailure(transport);
        expect(error.stage, DriverCompletionAttemptStage.tripReread);
        expect(error.writeEvidence, DriverCompletionWriteEvidence.acknowledged);
        expect(error.failure, DriverCompletionFailure.unknownResult);
        expect(error.cause, DriverCompletionFailure.malformedResponse);
        expect(error.confirmedTrip, isNull);
        expect(transport.receiptReads, isEmpty);
      });
    }
    test('canonical reread must include id', () async {
      final transport = _successTransport()
        ..tripRow = (tripRow()..remove('id'));
      final error = await _attemptFailure(transport);
      expect(error.cause, DriverCompletionFailure.malformedResponse);
      expect(transport.receiptReads, isEmpty);
    });
    test('UUID case equivalence retains backend row identity', () async {
      final transport = _successTransport(
          tripRowOverride: tripRow(tripId: _tripId.toUpperCase()))
        ..completionResponse = completionOk(_tripId.toUpperCase());
      final result = await transport.repository.completeTrip(command());
      expect(result.tripId, _tripId.toUpperCase());
      expect(result.backendVersion, 5);
    });
  });

  group('attempt stages', () {
    test('successful guard runs before the single RPC', () async {
      final transport = _successTransport();
      final original = command();
      final repository = SupabaseDriverTripCompletionRepository(
        rpc: transport.rpc,
        readTripRow: transport.readTripRow,
        readReceiptRows: transport.readReceiptRows,
        beforeDispatch: (c) async {
          expect(c, same(original));
          expect(transport.rpcCalls, isEmpty);
        },
      );
      expect((await repository.completeTrip(original)).backendVersion, 5);
      expect(transport.rpcCalls, hasLength(1));
    });
    test('unknown guard failure remains not-dispatched without leaking details',
        () async {
      final transport = _successTransport();
      final repository = SupabaseDriverTripCompletionRepository(
        rpc: transport.rpc,
        readTripRow: transport.readTripRow,
        readReceiptRows: transport.readReceiptRows,
        beforeDispatch: (_) async => throw StateError('PRIVATE_GUARD_DETAIL'),
      );
      try {
        await repository.completeTrip(command());
        fail('Expected blocked dispatch');
      } on DriverCompletionAttemptException catch (error) {
        expect(
            error.writeEvidence, DriverCompletionWriteEvidence.notDispatched);
        expect(error.failure, DriverCompletionFailure.unknownResult);
        expect(error.toString(), isNot(contains('PRIVATE_GUARD_DETAIL')));
      }
      expect(transport.rpcCalls, isEmpty);
    });
    test('pre-dispatch guard failure sends no RPC and sanitizes error',
        () async {
      final transport = _successTransport();
      final original = command();
      final repository = SupabaseDriverTripCompletionRepository(
        rpc: transport.rpc,
        readTripRow: transport.readTripRow,
        readReceiptRows: transport.readReceiptRows,
        beforeDispatch: (_) async => throw const DriverTripCompletionException(
          DriverCompletionFailure.unauthorized,
        ),
      );
      try {
        await repository.completeTrip(original);
        fail('Expected guard failure');
      } on DriverCompletionAttemptException catch (error) {
        expect(error.command, same(original));
        expect(error.stage, DriverCompletionAttemptStage.beforeDispatch);
        expect(
            error.writeEvidence, DriverCompletionWriteEvidence.notDispatched);
        expect(error.failure, DriverCompletionFailure.unauthorized);
      }
      expect(transport.rpcCalls, isEmpty);
      expect(transport.tripReads, isEmpty);
      expect(transport.receiptReads, isEmpty);
    });
    for (final code in ['42501', 'P0002', '40001', '55000', '22023']) {
      test('RPC SQL rejection $code is distinct from post-write read failure',
          () async {
        final transport = _successTransport()
          ..completionError = PostgrestException(
            message: 'PRIVATE_SERVER_DETAILS',
            code: code,
          );
        final error = await _attemptFailure(transport);
        expect(error.stage, DriverCompletionAttemptStage.rpc);
        expect(error.writeEvidence, DriverCompletionWriteEvidence.rejected);
        expect(
            CompletionRecovery.fromAttempt(error), isA<RejectionConfirmed>());
        expect(error.toString(), isNot(contains('PRIVATE_SERVER_DETAILS')));
        expect(transport.tripReads, isEmpty);
      });
      test('Trip read SQL $code preserves acknowledged completion', () async {
        final transport = _successTransport()
          ..tripError = PostgrestException(
            message: 'PRIVATE_SERVER_DETAILS',
            code: code,
          );
        final error = await _attemptFailure(transport);
        expect(error.stage, DriverCompletionAttemptStage.tripReread);
        expect(error.writeEvidence, DriverCompletionWriteEvidence.acknowledged);
        expect(error.failure, DriverCompletionFailure.unknownResult);
        expect(CompletionRecovery.fromAttempt(error),
            isA<CanonicalRereadRequired>());
        expect(error.toString(), isNot(contains('PRIVATE_SERVER_DETAILS')));
        expect(transport.receiptReads, isEmpty);
      });
    }
    for (final error in <Object>[
      TimeoutException('PRIVATE'),
      const SocketException('PRIVATE')
    ]) {
      test('RPC transport ${error.runtimeType} has unknown write evidence',
          () async {
        final transport = _successTransport()..completionError = error;
        final failure = await _attemptFailure(transport);
        expect(failure.writeEvidence, DriverCompletionWriteEvidence.unknown);
        expect(failure.failure, DriverCompletionFailure.unknownResult);
        expect(CompletionRecovery.fromAttempt(failure),
            isA<CanonicalRereadRequired>());
        expect(transport.tripReads, isEmpty);
      });
    }
    test('exact conflict envelope has known rejection evidence', () async {
      final transport = _successTransport()
        ..completionResponse = {
          'error': 'idempotency_payload_mismatch',
        };
      final error = await _attemptFailure(transport);
      expect(error.writeEvidence, DriverCompletionWriteEvidence.rejected);
      expect(error.failure, DriverCompletionFailure.idempotencyConflict);
    });
  });

  group('receipt boundaries', () {
    test(
        'malformed outer receipt payload retains verified Trip as recovery evidence',
        () async {
      final transport = _successTransport();
      final repository = SupabaseDriverTripCompletionRepository(
        rpc: transport.rpc,
        readTripRow: transport.readTripRow,
        readReceiptRows: (_) async => (null as dynamic),
      );
      try {
        await repository.completeTrip(command());
        fail('Expected malformed receipt read');
      } on DriverCompletionAttemptException catch (error) {
        expect(error.failure, DriverCompletionFailure.unknownResult);
        expect(error.cause, DriverCompletionFailure.malformedResponse);
        expect(error.confirmedTrip?.backendVersion, 5);
        expect(error.confirmedTrip?.receiptVerified, isFalse);
      }
      expect(transport.rpcCalls, hasLength(1));
    });
    test('receipt P0002 preserves completed Trip, never becomes tripNotFound',
        () async {
      final transport = _successTransport()
        ..receiptError = const PostgrestException(
          message: 'Receipt was not found.',
          code: 'P0002',
        );
      final result = await transport.repository.completeTrip(command());
      expect(result.isCompleted, isTrue);
      expect(result.backendVersion, 5);
      expect(result.receiptVerified, isFalse);
      expect(result.receiptNumber, isNull);
      expect(transport.rpcCalls, hasLength(1));
    });
    final failures = <String, Object>{
      'unauthorized':
          const PostgrestException(message: 'PRIVATE', code: '42501'),
      'unknown SQL':
          const PostgrestException(message: 'PRIVATE', code: 'XX000'),
      'timeout': TimeoutException('PRIVATE'),
      'disconnect': const SocketException('PRIVATE'),
    };
    for (final entry in failures.entries) {
      test(
          'receipt ${entry.key} retains canonical completion for reconciliation',
          () async {
        final transport = _successTransport()..receiptError = entry.value;
        final error = await _attemptFailure(transport);
        expect(error.stage, DriverCompletionAttemptStage.receiptReread);
        expect(error.writeEvidence, DriverCompletionWriteEvidence.verified);
        expect(error.failure, DriverCompletionFailure.unknownResult);
        expect(
            error.cause,
            entry.key == 'unauthorized'
                ? DriverCompletionFailure.unauthorized
                : DriverCompletionFailure.unknownResult);
        expect(error.confirmedTrip?.tripId, _tripId);
        expect(error.confirmedTrip?.backendVersion, 5);
        expect(error.confirmedTrip?.receiptVerified, isFalse);
        expect(error.confirmedTrip?.receiptNumber, isNull);
        final recovery =
            CompletionRecovery.fromAttempt(error) as ReceiptRereadRequired;
        expect(recovery.result, same(error.confirmedTrip));
        expect(error.toString(), isNot(contains('PRIVATE')));
      });
    }
    final malformedRows = <List<Map<String, Object?>>>[
      [receiptRow(tripId: _otherTripId)],
      [receiptRow()..remove('trip_id')],
      [receiptRow()..remove('id')],
      [receiptRow()..['id'] = 'not-a-receipt-uuid'],
      [receiptRow()..remove('receipt_number')],
      [receiptRow(receiptNumber: 42)],
      [receiptRow(receiptNumber: '')],
      [receiptRow(), receiptRow()],
    ];
    for (var i = 0; i < malformedRows.length; i++) {
      test('malformed receipt payload $i is not legitimate absence', () async {
        final error = await _attemptFailure(
            _successTransport(receiptRows: malformedRows[i]));
        expect(error.cause, DriverCompletionFailure.malformedResponse);
        expect(error.confirmedTrip?.backendVersion, 5);
        expect(error.confirmedTrip?.receiptVerified, isFalse);
      });
    }
  });

  group('unchanged coordinator compatibility', () {
    for (final receiptFailure in [false, true]) {
      test(
          'post-write ${receiptFailure ? "receipt" : "Trip"} error stays unresolved without replay',
          () async {
        final transport = _successTransport();
        if (receiptFailure) {
          transport.receiptError =
              const PostgrestException(message: 'denied', code: '42501');
        } else {
          transport.tripError =
              const PostgrestException(message: 'missing', code: 'P0002');
        }
        final gateway = _StagingGateway();
        final coordinator = _coordinator(transport, gateway);
        final outcome = await coordinator.complete() as CoordinatorUnresolved;
        expect(outcome.failure, DriverCompletionFailure.unknownResult);
        expect(outcome.stagedCommand.isExactReplayOf(command()), isTrue);
        await coordinator.complete();
        final recreated = _coordinator(transport, gateway);
        expect(await recreated.complete(), isA<CoordinatorUnresolved>());
        expect(transport.rpcCalls, hasLength(1));
        expect(gateway.commands.every((c) => c.isExactReplayOf(command())),
            isTrue);
      });
    }
    test(
        'legitimate receipt absence publishes completed Trip, not payment success',
        () async {
      final transport = _successTransport()
        ..receiptError = const PostgrestException(
          message: 'absent',
          code: 'P0002',
        );
      final coordinator = _coordinator(transport, _StagingGateway());
      final outcome = await coordinator.complete() as CoordinatorCompleted;
      expect(outcome.result.backendVersion, 5);
      expect(outcome.result.receiptVerified, isFalse);
      expect(outcome.result.receiptNumber, isNull);
      expect(outcome.stagedCommand.isExactReplayOf(command()), isTrue);
      expect(transport.rpcCalls, hasLength(1));
    });
  });
}
