import 'package:ridex/core/services/trips/driver_completion_command_store.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';

/// The namespace/Driver are captured from verified composition, not UI input.
/// A new coordinator cannot dispatch an existing journal record.
final class JournalDriverCompletionStagingGateway
    implements DriverCompletionStagingGateway {
  JournalDriverCompletionStagingGateway(
      {required this.backendNamespace,
      required this.driverId,
      required this.openStore});
  final String backendNamespace;
  final String driverId;
  final Future<DriverCompletionCommandStore> Function() openStore;

  @override
  Future<CoordinatorStagingDecision> stage(
      CanonicalDriverCompletionContext context) async {
    if (context.driverId != driverId ||
        !isCompletionJournalIdentityValid(
            backendNamespace: backendNamespace,
            driverId: driverId,
            tripId: context.command.tripId)) {
      return const StagingBlocked(StagingBlockReason.invalidIdentity);
    }
    try {
      final store = await openStore();
      final result = await store.stage(
          backendNamespace: backendNamespace,
          driverId: driverId,
          command: context.command);
      return switch (result) {
        CompletionCreated(:final command) => StagingNewlyCreated(command),
        CompletionExisting(:final command) => StagingExistingEvidence(command),
        CompletionConflict() => const StagingConflict(),
        CompletionBlocked(:final issue) => StagingBlocked(switch (issue) {
            CompletionJournalIssue.invalidIdentity ||
            CompletionJournalIssue.ownershipMismatch =>
              StagingBlockReason.invalidIdentity,
            CompletionJournalIssue.storageUnavailable ||
            CompletionJournalIssue.synchronizationUnavailable =>
              StagingBlockReason.storageUnavailable,
            CompletionJournalIssue.persistenceUncertain =>
              StagingBlockReason.persistenceUncertain,
            _ => StagingBlockReason.corruptEvidence,
          }),
      };
    } on Object {
      return const StagingBlocked(StagingBlockReason.storageUnavailable);
    }
  }
}
