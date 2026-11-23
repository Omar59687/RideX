// Child-process fixture only. Uses a caller-created temporary journal and a
// local marker instead of any SDK/backend. exit() intentionally skips cleanup.
import 'dart:io';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/repositories/driver_trip_completion_repository.dart';
import 'package:ridex/core/services/trips/driver_completion_staging_gateway.dart';
import 'package:ridex/core/services/trips/file_driver_completion_command_store.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';

const driver = 'a7000000-0000-0000-0000-000000000001';
final command = DriverCompleteTripCommand(
    tripId: 'c7000000-0000-0000-0000-000000000001',
    expectedTripVersion: 4,
    idempotencyKey: 'original-key');

class _Source implements CanonicalDriverCompletionSource {
  @override
  Future<CanonicalDriverCompletionContext?> load() async =>
      CanonicalDriverCompletionContext(driverId: driver, command: command);
}

class _FlushExit extends NativeCompletionJournalIo {
  @override
  Future<void> flush(RandomAccessFile handle) async {
    await super.flush(handle);
    exit(74);
  }
}

class _Gateway implements DriverCompletionStagingGateway {
  _Gateway(this.delegate, this.mode);
  final JournalDriverCompletionStagingGateway delegate;
  final String mode;
  @override
  Future<CoordinatorStagingDecision> stage(
      CanonicalDriverCompletionContext context) async {
    final result = await delegate.stage(context);
    if (result is StagingNewlyCreated && mode == 'staged-exit') exit(73);
    return result;
  }
}

class _Repo implements DriverTripCompletionRepository {
  _Repo(this.directory);
  final Directory directory;
  @override
  Future<DriverCompleteTripResult> completeTrip(
      DriverCompleteTripCommand command) async {
    await File.fromUri(directory.uri.resolve('fake-dispatch.marker')).writeAsString(
        '${command.tripId}|${command.expectedTripVersion}|${command.idempotencyKey}',
        flush: true);
    throw const DriverTripCompletionException(
        DriverCompletionFailure.unknownResult);
  }
}

Future<void> main(List<String> args) async {
  final directory = Directory(args[0]);
  final mode = args[1];
  final store = FileDriverCompletionCommandStore(
      directory: directory,
      io: mode == 'flush-exit'
          ? _FlushExit()
          : const NativeCompletionJournalIo());
  final coordinator = DriverCompletionCoordinator(
      canonicalSource: _Source(),
      stagingGateway: _Gateway(
          JournalDriverCompletionStagingGateway(
              backendNamespace: 'ridex-test',
              driverId: driver,
              openStore: () async => store),
          mode),
      repository: _Repo(directory),
      sessionReader: () async => const DriverCompletionSessionSnapshot(
          driverId: driver, epoch: 1, isApprovedDriver: true));
  final result = await coordinator.complete();
  exit(result is CoordinatorUnresolved ? 75 : 76);
}
