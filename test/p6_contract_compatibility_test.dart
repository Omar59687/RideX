import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/driver_completion_recovery.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/mock_trip.dart' show TripStatus;
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/card_payment_repository.dart';
import 'package:ridex/core/repositories/fare_repository.dart';
import 'package:ridex/core/repositories/payment_repository.dart';
import 'package:ridex/core/services/driver_completion/pending_completion_store.dart'
    as legacy;
import 'package:ridex/core/services/trips/driver_completion_command_store.dart';
import 'package:ridex/core/services/trips/file_driver_completion_command_store.dart';
import 'package:ridex/features/auth/presentation/widgets/admin_sanitized_payment_card.dart';
import 'package:ridex/features/booking/presentation/providers/rider_payment_selection_provider.dart';
import 'package:ridex/features/history/presentation/models/rider_payment_presentation.dart';
import 'package:ridex/features/history/presentation/providers/rider_payment_providers.dart';
import 'package:ridex/features/history/presentation/widgets/rider_payment_record_card.dart';
import 'package:ridex/features/history/presentation/widgets/rider_payment_status_card.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'helpers/p6_compatibility/fixtures.dart';

// Foundation compatibility only. Explicit synthetic backend/session fixtures
// do not establish hosted RLS, payment truth, production wiring or crash safety.
const _rider = AppUser(
  id: 'rider-fixture',
  name: 'Fixture rider',
  email: 'rider@example.invalid',
  role: RideRole.rider,
);

RiderPaymentTripEvidence _completedEvidence() => const RiderPaymentTripEvidence(
      paymentId: paymentId,
      tripId: tripId,
      bookingRequestId: bookingId,
      tripStatus: TripStatus.completed,
    );

ProviderContainer _riderContainer({
  SessionState? session,
  CashReader? cash,
  CardReader? card,
}) {
  final container = ProviderContainer(overrides: [
    sessionControllerProvider.overrideWith(
      () => FixtureSession(session ?? SessionState.fromUser(_rider)),
    ),
    if (cash != null)
      riderCashPaymentRepositoryProvider.overrideWithValue(cash),
    if (card != null)
      riderCardPaymentRepositoryProvider.overrideWithValue(card),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<CompletionHarness> _harness() async {
  final harness = await CompletionHarness.create();
  addTearDown(harness.dispose);
  return harness;
}

Future<void> _expectOriginal(CompletionHarness harness) async {
  final slot = await harness.inspect();
  expect(slot, isA<CompletionValid>());
  expect((slot as CompletionValid).command.isExactReplayOf(completionCommand()),
      isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NoNetwork network;
  late PreferencesProbe preferences;
  final legacyKey =
      legacy.SharedPreferencesCompletionCommandStore.keyForDriver(driverId);
  setUp(() {
    final previousNetwork = HttpOverrides.current;
    final previousPreferences = SharedPreferencesAsyncPlatform.instance;
    network = NoNetwork();
    preferences = PreferencesProbe(legacyKey);
    HttpOverrides.global = network;
    SharedPreferencesAsyncPlatform.instance = preferences;
    addTearDown(() async {
      try {
        expect(network.attempts, 0,
            reason: 'No network/hosted calls permitted.');
        expect(preferences.writes, 0,
            reason: 'Inactive completion store must not receive dual writes.');
        expect(preferences.clears, 0,
            reason: 'Legacy evidence must not be retired.');
        expect(await SharedPreferencesAsync().getString(legacyKey),
            'untouched-legacy-evidence');
      } finally {
        SharedPreferencesAsyncPlatform.instance = previousPreferences;
        HttpOverrides.global = previousNetwork;
      }
    });
  });

  group('P6-09 Driver compatibility', () {
    test(
        'A1 journal command reaches adapter unchanged and canonical version is reread',
        () async {
      final h = await _harness();
      final outcome = await h.coordinator().complete() as CoordinatorCompleted;
      expect(h.backend.calls.single, {
        'name': 'driver_transition_trip',
        'target_id': tripId,
        'requested_status': 'completed',
        'expected_version': 4,
        'idempotency_key': 'original-key',
      });
      expect(h.events, ['journal-CompletionCreated', 'rpc']);
      expect(h.backend.tripReads, [tripId]);
      expect(h.backend.receiptReads, [tripId]);
      expect(outcome.result.tripId, tripId);
      expect(outcome.result.backendVersion,
          9); // Injected canonical value, not 4+1.
      expect(outcome.result.receiptVerified, isFalse);
      expect(outcome.result.receiptNumber, isNull);
      await _expectOriginal(h);
    });

    test(
        'B1 flush acknowledgement precedes RPC and concurrent taps share one flight',
        () async {
      final h = await _harness();
      final gate = Completer<void>();
      h.io.flushGate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final coordinator = h.coordinator();
      final first = coordinator.complete();
      final second = coordinator.complete();
      expect(first, same(second));
      await h.io.flushEntered.future;
      expect(h.backend.calls, isEmpty);
      expect(h.events, isEmpty);
      gate.complete();
      expect(await first, isA<CoordinatorCompleted>());
      await second;
      expect(h.backend.calls, hasLength(1));
      expect(h.events, ['journal-CompletionCreated', 'rpc']);
      await _expectOriginal(h);
    });

    test(
        'B2 uncertain staging blocks dispatch and preserves evidence on recreation',
        () async {
      final h = await _harness();
      h.io.failFlush = true;
      expect(await h.coordinator().complete(), isA<CoordinatorBlocked>());
      expect(h.backend.calls, isEmpty);
      h.io.failFlush = false;
      // Real bytes may exist despite lost acknowledgement. Inspection proves
      // bounded persistence, never permission for a new coordinator to replay.
      await _expectOriginal(h);
      final recreated =
          FileDriverCompletionCommandStore(directory: h.directory);
      expect(await h.coordinator(journal: recreated).complete(),
          isA<CoordinatorUnresolved>());
      expect(h.backend.calls, isEmpty);
    });

    test('B3 conflicting command cannot replace Journal evidence or dispatch',
        () async {
      final h = await _harness();
      await h.store.stage(
          backendNamespace: backendNamespace,
          driverId: driverId,
          command: completionCommand());
      final outcome = await h
          .coordinator(command: completionCommand(key: 'rotated-key'))
          .complete();
      expect(outcome, isA<CoordinatorConflict>());
      expect(h.backend.calls, isEmpty);
      await _expectOriginal(h);
    });

    test(
        'B4 timeout preserves original command and recreated coordinator never blindly replays',
        () async {
      final h = await _harness();
      h.backend.rpcError = TimeoutException('scripted response loss');
      final coordinator = h.coordinator();
      final result = await coordinator.complete() as CoordinatorUnresolved;
      expect(result.stagedCommand.isExactReplayOf(completionCommand()), isTrue);
      final attempt = h.repository.attempt!;
      expect(attempt.command.isExactReplayOf(result.stagedCommand), isTrue);
      expect(attempt.writeEvidence, DriverCompletionWriteEvidence.unknown);
      expect(CompletionRecovery.fromAttempt(attempt),
          isA<CanonicalRereadRequired>());
      await coordinator.complete();
      final recreated =
          FileDriverCompletionCommandStore(directory: h.directory);
      expect(await h.coordinator(journal: recreated).complete(),
          isA<CoordinatorUnresolved>());
      expect(h.backend.calls, hasLength(1));
      expect(h.backend.tripReads, isEmpty);
      await _expectOriginal(h);
    });

    test(
        'B5 two coordinators sharing the real Journal dispatch only its newly staged intent',
        () async {
      final h = await _harness();
      final gate = Completer<void>();
      h.backend.rpcGate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final first = h.coordinator().complete();
      await h.backend.rpcEntered.future;
      expect(await h.coordinator().complete(), isA<CoordinatorUnresolved>());
      expect(h.backend.calls, hasLength(1));
      gate.complete();
      expect(await first, isA<CoordinatorCompleted>());
      await _expectOriginal(h);
    });

    for (final boundary in ['RPC', 'canonical']) {
      test(
          'C1 wrong $boundary Trip identity fails closed across adapter and coordinator',
          () async {
        final h = await _harness();
        if (boundary == 'RPC') {
          h.backend.rpcTripId = otherTripId;
        } else {
          h.backend.rowTripId = otherTripId;
        }
        expect(await h.coordinator().complete(), isA<CoordinatorUnresolved>());
        final attempt = h.repository.attempt!;
        expect(attempt.cause, DriverCompletionFailure.malformedResponse);
        expect(attempt.confirmedTrip, isNull);
        expect(CompletionRecovery.fromAttempt(attempt),
            isA<CanonicalRereadRequired>());
        expect(h.backend.receiptReads, isEmpty);
        expect(h.backend.tripReads, boundary == 'RPC' ? isEmpty : [tripId]);
        await _expectOriginal(h);
      });
    }

    test(
        'C2 RPC rejection and post-acknowledgement denial have different recovery evidence',
        () async {
      final rejected = await _harness();
      rejected.backend.rpcError =
          const PostgrestException(message: 'denied', code: '42501');
      expect(await rejected.coordinator().complete(),
          isA<CoordinatorUnresolved>());
      expect(rejected.repository.attempt!.writeEvidence,
          DriverCompletionWriteEvidence.rejected);
      expect(CompletionRecovery.fromAttempt(rejected.repository.attempt!),
          isA<RejectionConfirmed>());
      await _expectOriginal(rejected);

      final acknowledged = await _harness();
      acknowledged.backend.tripError =
          const PostgrestException(message: 'denied', code: '42501');
      final outcome =
          await acknowledged.coordinator().complete() as CoordinatorUnresolved;
      expect(outcome.failure, DriverCompletionFailure.unknownResult);
      expect(acknowledged.repository.attempt!.writeEvidence,
          DriverCompletionWriteEvidence.acknowledged);
      expect(CompletionRecovery.fromAttempt(acknowledged.repository.attempt!),
          isA<CanonicalRereadRequired>());
      await _expectOriginal(acknowledged);
    });

    test(
        'C3 receipt denial retains canonical completed Trip without confirming a receipt',
        () async {
      final h = await _harness();
      h.backend.receiptError =
          const PostgrestException(message: 'denied', code: '42501');
      expect(await h.coordinator().complete(), isA<CoordinatorUnresolved>());
      final attempt = h.repository.attempt!;
      final directive =
          CompletionRecovery.fromAttempt(attempt) as ReceiptRereadRequired;
      expect(attempt.stage, DriverCompletionAttemptStage.receiptReread);
      expect(attempt.cause, DriverCompletionFailure.unauthorized);
      expect(directive.result.tripId, tripId);
      expect(directive.result.backendVersion, 9);
      expect(directive.result.receiptVerified, isFalse);
      expect(directive.result.receiptNumber, isNull);
      expect(attempt.command.isExactReplayOf(completionCommand()), isTrue);
      await _expectOriginal(h);
    });

    test(
        'C4 missing receipt preserves Trip completion and never settles Cash or captures Card',
        () async {
      final h = await _harness();
      h.backend.receiptError =
          const PostgrestException(message: 'receipt absent', code: 'P0002');
      final outcome = await h.coordinator().complete() as CoordinatorCompleted;
      expect(outcome.result.backendVersion, 9);
      expect(outcome.result.receiptVerified, isFalse);
      expect(outcome.result.receiptNumber, isNull);
      final cash = FakePaymentRepository()
        ..seedCashPayment(cashFixture(CashPaymentStatus.cashSelected));
      final card = FakeCardPaymentRepository()
        ..seedCardPayment(cardFixture(CardPaymentStatus.cardPaymentAuthorized));
      final cashRecord = await cash.readCashPayment(paymentId: paymentId);
      final cardRecord = await card.readCardPayment(paymentId: paymentId);
      expect(
          RiderPaymentPresentation.fromCash(cashRecord,
                  tripEvidence: _completedEvidence())
              .canDescribeAsPaid,
          isFalse);
      final display = RiderPaymentPresentation.fromCard(cardRecord,
          tripEvidence: _completedEvidence());
      expect(display.canDescribeAsPaid, isFalse);
      expect(display.statusLabel, 'Authorized (not captured)');
      expect(display.issuedReceiptExists, isNull);
      expect(h.backend.calls, hasLength(1));
      await _expectOriginal(h);
    });

    test('E1 another Driver cannot consume the original Driver command',
        () async {
      final h = await _harness();
      await h.store.stage(
          backendNamespace: backendNamespace,
          driverId: driverId,
          command: completionCommand());
      h.session = const DriverCompletionSessionSnapshot(
          driverId: otherDriverId, epoch: 2, isApprovedDriver: true);
      expect(await h.coordinator(owner: driverId).complete(),
          isA<CoordinatorSessionInvalid>());
      expect(h.backend.calls, isEmpty);
      expect(await h.inspect(owner: otherDriverId), isA<CompletionAbsent>());
      await _expectOriginal(h);
    });

    for (final approved in [false, true]) {
      test(
          'E2 ${approved ? 'signed-out' : 'unapproved'} Driver cannot stage or dispatch',
          () async {
        final h = await _harness();
        h.session = DriverCompletionSessionSnapshot(
          driverId: approved ? null : driverId,
          epoch: 2,
          isApprovedDriver: approved,
        );
        expect(
            await h.coordinator().complete(), isA<CoordinatorSessionInvalid>());
        expect(h.events, isEmpty);
        expect(h.backend.calls, isEmpty);
        expect(await h.inspect(), isA<CompletionAbsent>());
      });
    }

    test(
        'E3 session changes during staging prevent dispatch without erasing evidence',
        () async {
      final h = await _harness();
      final gate = Completer<void>();
      h.io.flushGate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final pending = h.coordinator().complete();
      await h.io.flushEntered.future;
      h.session = const DriverCompletionSessionSnapshot(
          driverId: otherDriverId, epoch: 2, isApprovedDriver: true);
      gate.complete();
      expect(await pending, isA<CoordinatorInvalidated>());
      expect(h.backend.calls, isEmpty);
      await _expectOriginal(h);
    });

    test('E4 A-B-A session epoch prevents late adapter success publication',
        () async {
      final h = await _harness();
      final gate = Completer<void>();
      h.backend.receiptGate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final coordinator = h.coordinator();
      final pending = coordinator.complete();
      await h.backend.receiptEntered.future;
      h.session = const DriverCompletionSessionSnapshot(
          driverId: otherDriverId, epoch: 2, isApprovedDriver: true);
      h.session = const DriverCompletionSessionSnapshot(
          driverId: driverId, epoch: 3, isApprovedDriver: true);
      gate.complete();
      final result = await pending as CoordinatorInvalidated;
      expect(coordinator.current, isNull);
      expect(
          result.stagedCommand!.isExactReplayOf(completionCommand()), isTrue);
      expect(h.backend.calls, hasLength(1));
      await _expectOriginal(h);
    });
  });

  group('P6-09 payment consumers', () {
    test('D1 selection reaches draft RPC as method only and creates no Payment',
        () async {
      final container = _riderContainer();
      final cash = FakePaymentRepository();
      final card = FakeCardPaymentRepository();
      final calls = <Map<String, dynamic>>[];
      final repository = SupabaseFareRepository(
        bookingMutationGate: (dispatch) =>
            dispatch(), // Gate itself is not under test here.
        rpc: ({required name, required params}) async {
          calls.add({'name': name, ...params});
          return {'id': bookingId, 'version': calls.length == 1 ? 37 : 38};
        },
        quoteEdge: (_) async => throw StateError('No quote request expected.'),
      );
      const pickup = FareRouteLocation(latitude: 31.95, longitude: 35.91);
      const destination = FareRouteLocation(latitude: 31.96, longitude: 35.92);
      final selection = container.read(riderPaymentSelectionProvider.notifier);
      selection.selectCash();
      final booking = await repository.createBookingDraft(
        pickup: pickup,
        destination: destination,
        vehicleTypeCode: 'economy',
        paymentMethod:
            container.read(riderPaymentSelectionProvider).backendValue,
      );
      selection.selectCard();
      final updated = await repository.updateBookingDraft(
        bookingRequestId: booking.bookingRequestId,
        expectedBookingVersion: booking.version,
        pickup: pickup,
        destination: destination,
        vehicleTypeCode: 'economy',
        paymentMethod:
            container.read(riderPaymentSelectionProvider).backendValue,
      );
      expect(calls.map((c) => c['name']),
          ['rider_create_booking_draft', 'rider_update_booking_draft']);
      expect(calls.map((c) => c['requested_payment_method']), ['cash', 'card']);
      expect(calls.last['expected_version'], 37);
      expect(updated.version, 38);
      await expectLater(cash.readCashPayment(paymentId: paymentId),
          throwsA(isA<PaymentException>()));
      await expectLater(card.readCardPayment(paymentId: paymentId),
          throwsA(isA<PaymentException>()));
    });

    for (final status in CashPaymentStatus.values) {
      test(
          'D2 Cash ${status.name} crosses repository and Rider-Admin mappers without invented receipts',
          () async {
        final fixture = cashFixture(status);
        final fake = FakePaymentRepository()..seedCashPayment(fixture);
        final reader = CashReader(fake);
        final container = _riderContainer(cash: reader);
        await container
            .read(riderPaymentReadControllerProvider.notifier)
            .readPayment(paymentId: paymentId, method: PaymentMethod.cash);
        final ready = container.read(riderPaymentReadControllerProvider)
            as RiderPaymentReady;
        final record = await fake.readCashPayment(paymentId: paymentId);
        final admin = AdminSanitizedPayment.fromCash(record);
        expect(record, same(fixture));
        expect(record.version, 13);
        expect(record.bookingRequestId, bookingId);
        expect(reader.reads, [paymentId]);
        expect(ready.presentation.canDescribeAsPaid, isFalse);
        expect(ready.presentation.issuedReceiptExists, isNull);
        expect(admin.methodLabel, ready.presentation.methodLabel);
        expect(admin.amountDisplay, ready.presentation.formattedAmount);
        expect(admin.statusLabel == 'Paid', status == CashPaymentStatus.paid);
        expect(RiderPaymentStatusDisplay.failClosed(ready.presentation).title,
            isNot('Payment completed'));
      });
    }

    for (final status in CardPaymentStatus.values) {
      test(
          'D3 Card ${status.name} crosses repository and Rider-Admin mappers without inferring capture',
          () async {
        final fixture = cardFixture(status);
        final fake = FakeCardPaymentRepository()..seedCardPayment(fixture);
        final reader = CardReader(fake);
        final container = _riderContainer(card: reader);
        await container
            .read(riderPaymentReadControllerProvider.notifier)
            .readPayment(paymentId: paymentId, method: PaymentMethod.card);
        final ready = container.read(riderPaymentReadControllerProvider)
            as RiderPaymentReady;
        final record = await fake.readCardPayment(paymentId: paymentId);
        final admin = AdminSanitizedPayment.fromCard(record);
        expect(record, same(fixture));
        expect(record.version, 17);
        expect(record.bookingRequestId, bookingId);
        expect(reader.reads, [paymentId]);
        expect(ready.presentation.canDescribeAsPaid, isFalse);
        expect(ready.presentation.issuedReceiptExists, isNull);
        expect(admin.methodLabel, ready.presentation.methodLabel);
        expect(admin.amountDisplay, ready.presentation.formattedAmount);
        expect(admin.statusLabel == 'Succeeded',
            status == CardPaymentStatus.cardPaymentSucceeded);
        expect(RiderPaymentStatusDisplay.failClosed(ready.presentation).title,
            isNot('Payment captured'));
        if (status == CardPaymentStatus.cardPaymentAuthorized) {
          expect(ready.presentation.statusLabel, 'Authorized (not captured)');
          expect(admin.statusLabel, 'Authorized');
        }
      });
    }

    testWidgets(
        'D4 caller-built completed evidence cannot render confirmed payment or invented receipt',
        (tester) async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final fake = FakeCardPaymentRepository()
          ..seedCardPayment(cardFixture(CardPaymentStatus.cardPaymentSucceeded,
              brand: 'private-provider-marker'));
        final record = await fake.readCardPayment(paymentId: paymentId);
        await tester.pumpWidget(MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
                body: SingleChildScrollView(
                    child: Column(children: [
              RiderPaymentRecordCard.fromCard(record,
                  tripEvidence: _completedEvidence()),
              AdminSanitizedPaymentCard(
                  payment: AdminSanitizedPayment.fromCard(record)),
            ])))));
        expect(find.text('Payment captured'), findsNothing);
        expect(find.text('Payment completed'), findsNothing);
        expect(find.text('Payment status unverified'), findsOneWidget);
        expect(find.text('Unavailable'), findsOneWidget);
        expect(find.textContaining('private-provider-marker'), findsNothing);
        expect(find.textContaining(paymentId), findsNothing);
        expect(find.textContaining(bookingId), findsNothing);
        expect(find.textContaining(tripId), findsNothing);
        expect(find.textContaining('4242'), findsNWidgets(2));
      }, network);
    });

    testWidgets(
        'D5 unconfigured production readers render unavailable without paid or receipt claims',
        (tester) async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final container = _riderContainer();
        await container
            .read(riderPaymentReadControllerProvider.notifier)
            .readPayment(paymentId: paymentId, method: PaymentMethod.cash);
        final state = container.read(riderPaymentReadControllerProvider);
        expect(state, isA<RiderPaymentUnavailable>());
        await tester.pumpWidget(MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: RiderPaymentStatusCard(readState: state))));
        expect(find.text('Payment record unavailable'), findsOneWidget);
        expect(find.text('Payment completed'), findsNothing);
        expect(find.text('Payment captured'), findsNothing);
      }, network);
    });

    test(
        'E5 incomplete payment fixtures are rejected rather than filling booking identity or version',
        () {
      final cash = CashPayment(
          paymentId: paymentId,
          tripId: tripId,
          amountFils: 7350,
          status: CashPaymentStatus.cashSelected,
          version: 13);
      final card = CardPayment(
          paymentId: paymentId,
          tripId: tripId,
          amountFils: 7350,
          status: CardPaymentStatus.cardPaymentPending,
          version: 17);
      expect(() => FakePaymentRepository().seedCashPayment(cash),
          throwsA(isA<PaymentException>()));
      expect(() => FakeCardPaymentRepository().seedCardPayment(card),
          throwsA(isA<PaymentException>()));
      expect(cash.bookingRequestId, isNull);
      expect(card.bookingRequestId, isNull);
    });

    for (final session in [
      const SessionState.unauthenticated(),
      SessionState.fromUser(const AppUser(
          id: 'blocked-rider',
          name: 'Blocked',
          email: 'blocked@example.invalid',
          role: RideRole.rider,
          isBlocked: true)),
      SessionState.fromUser(const AppUser(
          id: 'admin-fixture',
          name: 'Admin',
          email: 'admin@example.invalid',
          role: RideRole.admin)),
    ]) {
      test(
          'E6 ${session.status.name}-${session.role?.name} cannot bypass Rider read authorization',
          () async {
        final cash = CashReader(FakePaymentRepository()
          ..seedCashPayment(cashFixture(CashPaymentStatus.paid)));
        final card = CardReader(FakeCardPaymentRepository()
          ..seedCardPayment(
              cardFixture(CardPaymentStatus.cardPaymentSucceeded)));
        final container =
            _riderContainer(session: session, cash: cash, card: card);
        for (final method in PaymentMethod.values) {
          await container
              .read(riderPaymentReadControllerProvider.notifier)
              .readPayment(paymentId: paymentId, method: method);
          expect(container.read(riderPaymentReadControllerProvider),
              isA<RiderPaymentUnavailable>());
        }
        expect(cash.reads, isEmpty);
        expect(card.reads, isEmpty);
      });
    }

    test(
        'E7 Rider logout resets selection and discards an in-flight payment result',
        () async {
      final reader = CashReader(FakePaymentRepository()
        ..seedCashPayment(cashFixture(CashPaymentStatus.paid)));
      final gate = Completer<void>();
      reader.gate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final container = _riderContainer(cash: reader);
      container.read(riderPaymentSelectionProvider.notifier).selectCard();
      final pending = container
          .read(riderPaymentReadControllerProvider.notifier)
          .readPayment(paymentId: paymentId, method: PaymentMethod.cash);
      await reader.entered.future;
      (container.read(sessionControllerProvider.notifier) as FixtureSession)
          .publish(const SessionState.unauthenticated());
      gate.complete();
      await pending;
      expect(container.read(riderPaymentSelectionProvider), PaymentMethod.cash);
      expect(container.read(riderPaymentReadControllerProvider),
          isA<RiderPaymentUnavailable>());
    });

    test(
        'E8 completion adapter retains injectable-only IO without direct SDK or finance access',
        () {
      final source = File(
              'lib/core/repositories/supabase_driver_trip_completion_repository.dart')
          .readAsStringSync();
      final code = source.replaceAll(RegExp(r'//[^\n]*|/\*[\s\S]*?\*/'), '');
      // Structural boundary supplements actual invocation assertions above.
      // Concrete SDK access would bypass the harness's injected/read-safe seams.
      final sdkCalls = RegExp(r'(\w+)\s*\.\s*(from|rpc|invoke)\s*\(')
          .allMatches(code)
          .where((match) =>
              !(match.group(1) == 'DriverCompletionAttemptException' &&
                  match.group(2) == 'rpc'));
      expect(sdkCalls, isEmpty);
      expect(code, isNot(contains('Supabase.instance')));
      expect(code, isNot(contains('SupabaseClient(')));
    });
  });
}
