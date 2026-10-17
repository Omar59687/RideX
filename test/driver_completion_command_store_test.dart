import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/services/trips/driver_completion_command_store.dart';

const driver = 'a7000000-0000-0000-0000-000000000001';
const trip = 'c7000000-0000-0000-0000-000000000001';

void main() {
  test('preserves the contract-normalized command, including Unicode key', () {
    final command = DriverCompleteTripCommand(
        tripId: ' $trip ', expectedTripVersion: 7, idempotencyKey: ' مفتاح🔑 ');
    final valid = CompletionValid(command);
    expect(valid.command.tripId, trip);
    expect(valid.command.expectedTripVersion, 7);
    expect(valid.command.idempotencyKey, 'مفتاح🔑');
    expect(CompletionCreated(command).command, same(command));
    expect(CompletionExisting(command).command, same(command));
  });

  test('inspection and staging expose closed, separate result categories', () {
    expect(const CompletionAbsent(), isA<CompletionSlot>());
    expect(const CompletionCorrupt(CompletionJournalIssue.invalidFrame).issue,
        CompletionJournalIssue.invalidFrame);
    expect(
        const CompletionUnavailable(CompletionJournalIssue.storageUnavailable)
            .issue,
        CompletionJournalIssue.storageUnavailable);
    expect(
        const CompletionBlocked(CompletionJournalIssue.persistenceUncertain)
            .issue,
        CompletionJournalIssue.persistenceUncertain);
    expect(const CompletionConflict(CompletionConflictKind.keyReused).kind,
        CompletionConflictKind.keyReused);
  });

  for (final namespace in ['prod', 'project:prod', 'A.b_c-d', 'a' * 64]) {
    test('accepts explicit safe namespace $namespace', () {
      expect(
          isCompletionJournalIdentityValid(
              backendNamespace: namespace, driverId: driver, tripId: trip),
          isTrue);
    });
  }
  for (final namespace in [
    '',
    '..',
    '../prod',
    r'prod\test',
    '/prod',
    ' prod',
    'prod ',
    'https://project',
    'a' * 65,
    'منتج',
    'prod\n'
  ]) {
    test('rejects unsafe namespace ${namespace.codeUnits}', () {
      expect(
          isCompletionJournalIdentityValid(
              backendNamespace: namespace, driverId: driver, tripId: trip),
          isFalse);
    });
  }

  test('rejects mock, padded and traversal identities before I/O', () {
    for (final invalid in [
      'trip-1',
      '../$driver',
      ' $driver',
      '$driver ',
      ''
    ]) {
      expect(
          isCompletionJournalIdentityValid(
              backendNamespace: 'prod', driverId: invalid, tripId: trip),
          isFalse);
      expect(
          isCompletionJournalIdentityValid(
              backendNamespace: 'prod', driverId: driver, tripId: invalid),
          isFalse);
    }
  });

  test('UUID casing is accepted without rewriting a command triple', () {
    final command = DriverCompleteTripCommand(
        tripId: trip.toUpperCase(),
        expectedTripVersion: 7,
        idempotencyKey: 'k');
    expect(command.tripId, trip.toUpperCase());
    expect(
        isCompletionJournalIdentityValid(
            backendNamespace: 'prod',
            driverId: driver.toUpperCase(),
            tripId: command.tripId),
        isTrue);
    expect(
        command.isExactReplayOf(DriverCompleteTripCommand(
            tripId: trip, expectedTripVersion: 7, idempotencyKey: 'k')),
        isFalse);
  });
}
