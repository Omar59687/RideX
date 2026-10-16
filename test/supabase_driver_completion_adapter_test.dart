import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
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

    test('ignores receipt rows belonging to another trip', () async {
      final transport = _successTransport(
        receiptRows: [receiptRow(tripId: _otherTripId)],
      );
      final result = await transport.repository.completeTrip(command());

      expect(result.receiptVerified, isFalse);
      expect(result.receiptNumber, isNull);
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

    test('fails closed as unauthorized when the canonical row is hidden',
        () async {
      final transport = _successTransport()
        ..tripRow = null
        ..receiptRows = [receiptRow()];
      await expectCompletionFailure(
        () => transport.repository.completeTrip(command()),
        DriverCompletionFailure.unauthorized,
      );
    });

    test('fails closed on unparsable canonical rows', () async {
      final rows = <Map<String, Object?>>[
        tripRow(status: 'inProgress'),
        tripRow(status: 'bogus'),
        tripRow(version: 0),
        tripRow(version: -2),
        tripRow(version: '5'),
      ];
      for (final row in rows) {
        final transport = _successTransport(tripRowOverride: row);
        await expectCompletionFailure(
          () => transport.repository.completeTrip(command()),
          DriverCompletionFailure.malformedResponse,
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
          error is PostgrestException && error.code == '42501'
              ? DriverCompletionFailure.unauthorized
              : DriverCompletionFailure.unknownResult,
        );
        final asReceiptError = _successTransport()..receiptError = error;
        await expectCompletionFailure(
          () => asReceiptError.repository.completeTrip(command()),
          error is PostgrestException && error.code == '42501'
              ? DriverCompletionFailure.unauthorized
              : DriverCompletionFailure.unknownResult,
        );
      }
    });

    test('fails closed on a receipt row without a number', () async {
      final transport = _successTransport(
        receiptRows: [receiptRow(receiptNumber: '   ')],
      );
      await expectCompletionFailure(
        () => transport.repository.completeTrip(command()),
        DriverCompletionFailure.malformedResponse,
      );
    });
  });
}
