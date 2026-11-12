import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/services/trips/file_driver_completion_command_store.dart';

/// Native at-most-once handoff barrier. Uses the existing journal I/O boundary.
/// Exclusive creation reserves across owners/processes BEFORE writing. Empty,
/// partial, unreadable or existing files deny replay forever; no automatic repair.
/// Acknowledgment requires flush, close and exact readback in private app support.
/// Assumes a local filesystem honoring exclusive creation and flush. As with the
/// existing completion journal, this does not promise universal power-loss safety
/// or survive app-data deletion/rollback. Preserve app data during recovery.
final class DriverOfferCommandJournal {
  DriverOfferCommandJournal(
      {this.directory, this.io = const NativeCompletionJournalIo()});
  final Directory? directory;
  final NativeCompletionJournalIo io;

  Future<void> reserve(DriverBackendIdentity backend, String driverId,
      String offerId, int version, String key, bool accept) async {
    if (!isCanonicalTripId(driverId) ||
        !isCanonicalTripId(offerId) ||
        version <= 0 ||
        key.isEmpty) {
      throw StateError('Invalid original decision.');
    }
    final root = directory ??
        Directory.fromUri((await getApplicationSupportDirectory())
            .uri
            .resolve('driver_offer_commands/'));
    final account = Directory.fromUri(root.uri
        .resolve('${backend.endpoint.host}/${driverId.toLowerCase()}/'));
    final path = await io.prepare(account);
    final file = File.fromUri(
        Directory(path).uri.resolve('${offerId.toLowerCase()}.json'));
    // Never delete this reservation, even when a subsequent step fails.
    await io.acquire(file);
    final bytes = utf8.encode(jsonEncode({
      'schema': 1,
      'backend': backend.endpoint.toString(),
      'driver': driverId,
      'offer': offerId,
      'version': version,
      'key': key,
      'decision': accept ? 'accept' : 'decline',
    }));
    final handle = await io.openAppend(file);
    try {
      await io.write(handle, bytes);
      await io.flush(handle);
    } finally {
      await io.close(handle);
    }
    final stored = await io.read(file);
    if (stored == null ||
        stored.length != bytes.length ||
        !Iterable<int>.generate(bytes.length)
            .every((i) => stored[i] == bytes[i])) {
      throw StateError('Original decision persistence unavailable.');
    }
  }
}
