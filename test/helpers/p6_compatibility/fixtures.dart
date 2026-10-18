import 'dart:async';
import 'dart:io';

import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/card_payment_repository.dart';
import 'package:ridex/core/repositories/driver_trip_completion_repository.dart';
import 'package:ridex/core/repositories/payment_repository.dart';
import 'package:ridex/core/repositories/supabase_driver_trip_completion_repository.dart';
import 'package:ridex/core/services/trips/driver_completion_command_store.dart';
import 'package:ridex/core/services/trips/file_driver_completion_command_store.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/types.dart';

// Explicit test-only backend-shaped fixtures, never a production read source.
const driverId = 'a7000000-0000-0000-0000-000000000001';
const otherDriverId = 'a7000000-0000-0000-0000-000000000002';
const tripId = 'c7000000-0000-0000-0000-000000000001';
const otherTripId = 'c7000000-0000-0000-0000-000000000002';
const bookingId = 'b7000000-0000-0000-0000-000000000001';
const paymentId = 'd7000000-0000-0000-0000-000000000001';
const backendNamespace = 'p6-offline-fixture';

DriverCompleteTripCommand completionCommand({String key = 'original-key'}) =>
    DriverCompleteTripCommand(
      tripId: tripId,
      expectedTripVersion: 4,
      idempotencyKey: key,
    );

CashPayment cashFixture(CashPaymentStatus status) => CashPayment(
      paymentId: paymentId,
      bookingRequestId: bookingId,
      tripId: tripId,
      amountFils: 7350,
      status: status,
      version: 13,
    );

CardPayment cardFixture(CardPaymentStatus status, {String brand = 'visa'}) =>
    CardPayment(
      paymentId: paymentId,
      bookingRequestId: bookingId,
      tripId: tripId,
      amountFils: 7350,
      status: status,
      version: 17,
      cardBrand: brand,
      cardLastFour: '4242',
    );

/// No noSuchMethod fallback: adding a mutation to either production interface
/// breaks conformance at compile time. All successful reads use existing fakes.
class CashReader implements PaymentRepository {
  CashReader(this.delegate);
  final FakePaymentRepository delegate;
  final reads = <String>[];
  Completer<void>? gate;
  final entered = Completer<void>();

  @override
  Future<CashPayment> readCashPayment({required String paymentId}) async {
    reads.add(paymentId);
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    return delegate.readCashPayment(paymentId: paymentId);
  }
}

class CardReader implements CardPaymentRepository {
  CardReader(this.delegate);
  final FakeCardPaymentRepository delegate;
  final reads = <String>[];

  @override
  Future<CardPayment> readCardPayment({required String paymentId}) {
    reads.add(paymentId);
    return delegate.readCardPayment(paymentId: paymentId);
  }
}

/// Injected identity only; real Rider providers still enforce role/status and
/// generation checks. This does not simulate JWT validation or hosted RLS.
class FixtureSession extends SessionController {
  FixtureSession(this.initial);
  final SessionState initial;
  @override
  SessionState build() => initial;
  void publish(SessionState next) => state = next;
}

class NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Network is forbidden in the P6 compatibility harness.');
  }
}

/// Observes the actual async preferences plugin boundary. Completion must not
/// write or remove anything through the inactive SharedPreferences store.
final class PreferencesProbe extends InMemorySharedPreferencesAsync {
  PreferencesProbe(String legacyKey)
      : super.withData({legacyKey: 'untouched-legacy-evidence'});
  int writes = 0;
  int clears = 0;

  @override
  Future<bool> setString(
      String key, String value, SharedPreferencesOptions options) {
    writes++;
    return super.setString(key, value, options);
  }

  @override
  Future<bool> clear(
      ClearPreferencesParameters parameters, SharedPreferencesOptions options) {
    clears++;
    return super.clear(parameters, options);
  }
}

/// All storage remains real disk I/O; only acknowledgement timing/failure is
/// injected. No timers, sleeps, SDK singleton, credentials or network clients.
class JournalIo extends NativeCompletionJournalIo {
  Completer<void>? flushGate;
  final flushEntered = Completer<void>();
  bool failFlush = false;
  @override
  Future<void> flush(RandomAccessFile handle) async {
    if (!flushEntered.isCompleted) flushEntered.complete();
    await flushGate?.future;
    if (failFlush) throw const FileSystemException('Injected flush failure.');
    await super.flush(handle);
  }
}

class FixtureSource implements CanonicalDriverCompletionSource {
  FixtureSource(this.context);
  final CanonicalDriverCompletionContext context;
  @override
  Future<CanonicalDriverCompletionContext?> load() async => context;
}

/// Test-only bridge. It translates actual Journal outcomes; it adds no retry,
/// replacement, expiry, clearing, or production provider composition.
class JournalGateway implements DriverCompletionStagingGateway {
  JournalGateway(this.store, this.events);
  final FileDriverCompletionCommandStore store;
  final List<String> events;
  @override
  Future<CoordinatorStagingDecision> stage(
      CanonicalDriverCompletionContext context) async {
    final result = await store.stage(
      backendNamespace: backendNamespace,
      driverId: context.driverId,
      command: context.command,
    );
    events.add('journal-${result.runtimeType}');
    return switch (result) {
      CompletionCreated(:final command) => StagingNewlyCreated(command),
      CompletionExisting(:final command) => StagingExistingEvidence(command),
      CompletionConflict() => const StagingConflict(),
      CompletionBlocked() =>
        const StagingBlocked(StagingBlockReason.persistenceUncertain),
    };
  }
}

class ScriptedBackend {
  ScriptedBackend(this.events);
  final List<String> events;
  final calls = <Map<String, Object?>>[];
  final tripReads = <String>[];
  final receiptReads = <String>[];
  Object? rpcError;
  Object? tripError;
  Object? receiptError;
  String rpcTripId = tripId;
  String rowTripId = tripId;
  Completer<void>? rpcGate;
  Completer<void>? receiptGate;
  final rpcEntered = Completer<void>();
  final receiptEntered = Completer<void>();

  SupabaseDriverTripCompletionRepository get adapter =>
      SupabaseDriverTripCompletionRepository(
        rpc: ({required name, required params}) async {
          events.add('rpc');
          calls.add({'name': name, ...params});
          if (!rpcEntered.isCompleted) rpcEntered.complete();
          await rpcGate?.future;
          if (rpcError != null) throw rpcError!;
          return {'trip_id': rpcTripId, 'status': 'completed'};
        },
        readTripRow: (id) async {
          tripReads.add(id);
          if (tripError != null) throw tripError!;
          return {'id': rowTripId, 'status': 'completed', 'version': 9};
        },
        readReceiptRows: (id) async {
          receiptReads.add(id);
          if (!receiptEntered.isCompleted) receiptEntered.complete();
          await receiptGate?.future;
          if (receiptError != null) throw receiptError!;
          return [];
        },
      );
}

class ObservedCompletion implements DriverTripCompletionRepository {
  ObservedCompletion(this.delegate);
  final DriverTripCompletionRepository delegate;
  DriverCompletionAttemptException? attempt;
  @override
  Future<DriverCompleteTripResult> completeTrip(
      DriverCompleteTripCommand command) async {
    try {
      return await delegate.completeTrip(command);
    } on DriverCompletionAttemptException catch (error) {
      attempt = error;
      rethrow;
    }
  }
}

class CompletionHarness {
  CompletionHarness._(this.directory, this.io) {
    store = FileDriverCompletionCommandStore(directory: directory, io: io);
    backend = ScriptedBackend(events);
    repository = ObservedCompletion(backend.adapter);
  }

  static Future<CompletionHarness> create() async => CompletionHarness._(
        await Directory.systemTemp.createTemp('ridex-p6-compatibility-'),
        JournalIo(),
      );
  final Directory directory;
  final JournalIo io;
  final events = <String>[];
  late final FileDriverCompletionCommandStore store;
  late final ScriptedBackend backend;
  late final ObservedCompletion repository;
  DriverCompletionSessionSnapshot session =
      const DriverCompletionSessionSnapshot(
    driverId: driverId,
    epoch: 1,
    isApprovedDriver: true,
  );

  DriverCompletionCoordinator coordinator({
    DriverCompleteTripCommand? command,
    String owner = driverId,
    FileDriverCompletionCommandStore? journal,
  }) =>
      DriverCompletionCoordinator(
        canonicalSource: FixtureSource(CanonicalDriverCompletionContext(
          driverId: owner,
          command: command ?? completionCommand(),
        )),
        stagingGateway: JournalGateway(journal ?? store, events),
        repository: repository,
        sessionReader: () async => session,
      );

  Future<CompletionSlot> inspect({String owner = driverId}) =>
      FileDriverCompletionCommandStore(directory: directory).inspect(
        backendNamespace: backendNamespace,
        driverId: owner,
        tripId: tripId,
      );

  Future<void> dispose() async {
    // Delete only this harness's newly-created directory, never existing data.
    final root = await Directory.systemTemp.resolveSymbolicLinks();
    final target = await directory.resolveSymbolicLinks();
    if (!target.startsWith('$root${Platform.pathSeparator}') ||
        !directory.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .startsWith('ridex-p6-compatibility-')) {
      throw StateError(
          'Refusing cleanup outside the harness temporary directory.');
    }
    await directory.delete(recursive: true);
  }
}
