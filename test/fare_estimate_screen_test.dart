import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/fare_repository.dart';
import 'package:ridex/core/repositories/mock_place_repository.dart';
import 'package:ridex/core/repositories/mock_route_repository.dart';
import 'package:ridex/core/services/fare/pending_fare_lock_store.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/features/booking/presentation/screens/fare_estimate_screen.dart';

import 'helpers/recording_error_reporter.dart';

/// Provisional Phase 5 widget coverage for route-based fixed fares.
///
/// Flutter never calculates fares: the configured path displays the
/// backend-computed [FareQuote] (breakdown, total, quote version, expiry),
/// while the unconfigured path keeps the clearly marked deterministic demo
/// fare. Expiry never backs a total: expired quotes show a re-quote prompt.
///
/// Test-local doubles below model transport anomalies the shared fake does
/// not script: a commit whose response arrives unusable, and a lock RPC
/// that stays in flight until the test releases it.
class _CommitThenGarbleFareRepository implements FareRepository {
  _CommitThenGarbleFareRepository(this._delegate);

  final FakeFareRepository _delegate;
  bool _garbled = false;
  int? canonicalBookingVersion;
  FareQuote? linkedLock;
  final List<String> lockAttempts = [];

  // Models a later lifecycle update: its optimistic version advances while
  // the booking remains linked to the committed locked quote (migration 026).
  void advanceLinkedBookingVersion() {
    if (linkedLock == null) throw StateError('lock has not committed');
    canonicalBookingVersion = canonicalBookingVersion! + 1;
  }

  FakeFareRepository get delegate => _delegate;

  @override
  Future<FareBookingRef> createBookingDraft({
    required FareRouteLocation pickup,
    required FareRouteLocation destination,
    required String vehicleTypeCode,
    required String paymentMethod,
    List<FareStopInput> stops = const [],
  }) =>
      _delegate.createBookingDraft(
        pickup: pickup,
        destination: destination,
        vehicleTypeCode: vehicleTypeCode,
        paymentMethod: paymentMethod,
        stops: stops,
      );

  @override
  Future<FareBookingRef> updateBookingDraft({
    required String bookingRequestId,
    required int expectedBookingVersion,
    required FareRouteLocation pickup,
    required FareRouteLocation destination,
    required String vehicleTypeCode,
    required String paymentMethod,
    List<FareStopInput> stops = const [],
  }) =>
      _delegate.updateBookingDraft(
        bookingRequestId: bookingRequestId,
        expectedBookingVersion: expectedBookingVersion,
        pickup: pickup,
        destination: destination,
        vehicleTypeCode: vehicleTypeCode,
        paymentMethod: paymentMethod,
        stops: stops,
      );

  @override
  Future<FareQuote> fetchQuote({
    required String bookingRequestId,
    required int expectedBookingVersion,
    required int routeDistanceMeters,
    required int routeDurationSeconds,
  }) =>
      _delegate.fetchQuote(
        bookingRequestId: bookingRequestId,
        expectedBookingVersion: expectedBookingVersion,
        routeDistanceMeters: routeDistanceMeters,
        routeDurationSeconds: routeDurationSeconds,
      );

  @override
  Future<FareQuote> lockQuote({
    required String bookingRequestId,
    required String fareQuoteId,
    required int expectedBookingVersion,
    required int expectedQuoteVersion,
  }) async {
    lockAttempts.add('$bookingRequestId@$expectedBookingVersion '
        '$fareQuoteId@$expectedQuoteVersion');
    if (_garbled && canonicalBookingVersion != expectedBookingVersion + 1) {
      throw const FareException(FareFailure.versionConflict);
    }
    // The server commits, but the client receives an unusable response.
    final locked = await _delegate.lockQuote(
      bookingRequestId: bookingRequestId,
      fareQuoteId: fareQuoteId,
      expectedBookingVersion: expectedBookingVersion,
      expectedQuoteVersion: expectedQuoteVersion,
    );
    if (!_garbled) {
      _garbled = true;
      canonicalBookingVersion = expectedBookingVersion + 1;
      linkedLock = locked;
      throw const FareException(FareFailure.invalidResponse);
    }
    return locked;
  }
}

/// Models a lock RPC that stays in flight until the test releases [gate].
/// The delegate commits immediately; only the result delivery is withheld,
/// so completing the gate after disposal must be a safe no-op.
class _HangingLockFareRepository implements FareRepository {
  _HangingLockFareRepository(this._delegate);

  final FakeFareRepository _delegate;
  final Completer<void> gate = Completer<void>();
  Future<FareQuote>? _pending;

  @override
  Future<FareBookingRef> createBookingDraft({
    required FareRouteLocation pickup,
    required FareRouteLocation destination,
    required String vehicleTypeCode,
    required String paymentMethod,
    List<FareStopInput> stops = const [],
  }) =>
      _delegate.createBookingDraft(
        pickup: pickup,
        destination: destination,
        vehicleTypeCode: vehicleTypeCode,
        paymentMethod: paymentMethod,
        stops: stops,
      );

  @override
  Future<FareBookingRef> updateBookingDraft({
    required String bookingRequestId,
    required int expectedBookingVersion,
    required FareRouteLocation pickup,
    required FareRouteLocation destination,
    required String vehicleTypeCode,
    required String paymentMethod,
    List<FareStopInput> stops = const [],
  }) =>
      _delegate.updateBookingDraft(
        bookingRequestId: bookingRequestId,
        expectedBookingVersion: expectedBookingVersion,
        pickup: pickup,
        destination: destination,
        vehicleTypeCode: vehicleTypeCode,
        paymentMethod: paymentMethod,
        stops: stops,
      );

  @override
  Future<FareQuote> fetchQuote({
    required String bookingRequestId,
    required int expectedBookingVersion,
    required int routeDistanceMeters,
    required int routeDurationSeconds,
  }) =>
      _delegate.fetchQuote(
        bookingRequestId: bookingRequestId,
        expectedBookingVersion: expectedBookingVersion,
        routeDistanceMeters: routeDistanceMeters,
        routeDurationSeconds: routeDurationSeconds,
      );

  @override
  Future<FareQuote> lockQuote({
    required String bookingRequestId,
    required String fareQuoteId,
    required int expectedBookingVersion,
    required int expectedQuoteVersion,
  }) {
    _pending ??= _delegate.lockQuote(
      bookingRequestId: bookingRequestId,
      fareQuoteId: fareQuoteId,
      expectedBookingVersion: expectedBookingVersion,
      expectedQuoteVersion: expectedQuoteVersion,
    );
    return gate.future.then((_) => _pending!);
  }
}

void main() {
  ProviderContainer createContainer({
    FareRepository? fareRepository,
    PendingFareLockStore? pendingStore,
    RecordingAppErrorReporter? errorReporter,
  }) {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => MockAuthRepository()),
        bookingRepositoryProvider.overrideWith(
          (ref) => MockBookingRepository(),
        ),
        placeRepositoryProvider.overrideWith((ref) => MockPlaceRepository()),
        routeRepositoryProvider.overrideWithValue(
          const MockRouteRepository(),
        ),
        if (fareRepository != null)
          fareRepositoryProvider.overrideWith((ref) => fareRepository),
        // Persistence runs on every lock dispatch: tests use an offline
        // recording store unless they inject their own. Production keeps
        // the SharedPreferences-backed default.
        pendingFareLockStoreProvider.overrideWithValue(
          pendingStore ?? _RecordingPendingFareLockStore(),
        ),
        if (errorReporter != null)
          appErrorReporterProvider.overrideWithValue(errorReporter),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  void readyDraft(ProviderContainer container) {
    final controller = container.read(bookingControllerProvider.notifier);
    controller.setPickup(MockData.locations[0]);
    controller.setDestination(MockData.locations[1]);
    controller.setVehicleType(MockData.vehicleTypes.first);
  }

  Future<void> pumpFareScreen(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    // Live fare operations are scoped to an authenticated Rider, even when
    // their transport is replaced by an offline test double.
    await container.read(sessionControllerProvider.notifier).refreshSession();
    await container.read(sessionControllerProvider.notifier).continueAsDemo();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const FareEstimateScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<GlobalKey<NavigatorState>> pushFareScreen(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await container.read(sessionControllerProvider.notifier).refreshSession();
    await container.read(sessionControllerProvider.notifier).continueAsDemo();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: navigator,
        theme: AppTheme.light(),
        home: const Scaffold(body: Text('Previous route')),
      ),
    ));
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const FareEstimateScreen(),
    ));
    await tester.pumpAndSettle();
    return navigator;
  }

  AppButton confirmButton(
    WidgetTester tester, {
    String label = 'Confirm & find a driver',
  }) {
    return tester.widget<AppButton>(
      find.widgetWithText(AppButton, label),
    );
  }

  /// The screen builds `PopScope<Object>` (inferred from the pop-result
  /// callback), so `find.byType(PopScope)` — exact-type matching — misses
  /// it. A predicate matches every instantiation.
  PopScope farePopScope(WidgetTester tester) => tester.widget<PopScope>(
        find.byWidgetPredicate((widget) => widget is PopScope),
      );

  testWidgets(
    'unconfigured backend keeps the clearly marked deterministic demo fare',
    (tester) async {
      final container = createContainer();
      readyDraft(container);

      await pumpFareScreen(tester, container);

      await tester.scrollUntilVisible(
        find.text('Demo fare'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Demo fare'), findsOneWidget);
      expect(
        find.text(
          'Demo fare — a deterministic placeholder, not a backend quote. '
          'It stays fixed for the route shown.',
        ),
        findsOneWidget,
      );
      expect(find.text('JOD 4.20'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Confirm & find a driver'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(confirmButton(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'configured backend shows the authoritative breakdown and total',
    (tester) async {
      final container = createContainer(
        fareRepository: FakeFareRepository(),
      );
      readyDraft(container);

      await pumpFareScreen(tester, container);

      await tester.scrollUntilVisible(
        find.text('Upfront fare'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Upfront fare'), findsOneWidget);
      expect(find.text('Base fare'), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('Stops'), findsOneWidget);
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      // The fixture subtotal and total coincide (2000 fils after rounding).
      expect(find.text('JOD 2.00'), findsNWidgets(2));
      expect(find.textContaining('Quote v1'), findsOneWidget);
      expect(find.textContaining('Pricing v1'), findsOneWidget);
      expect(
        find.textContaining('Rounded to the nearest 50 fils.'),
        findsOneWidget,
      );
      // The demo fare path is gone in the configured mode.
      expect(find.text('Demo fare'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Lock fare'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(confirmButton(tester, label: 'Lock fare').onPressed, isNotNull);
      await tester.tap(find.text('Lock fare'));
      await tester.pumpAndSettle();
      expect(find.text('Fare locked'), findsOneWidget);
      expect(confirmButton(tester, label: 'Fare locked').onPressed, isNull);
      // No GoRouter is installed: a live lock must not navigate to mock search.
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'expired quotes show a re-quote prompt and never a stale total',
    (tester) async {
      final fareRepository = FakeFareRepository();
      fareRepository.seedQuote(
        FareQuote(
          id: 'quote-expired',
          bookingRequestId: 'booking-fake-1',
          quoteVersion: 1,
          pricingVersion: 1,
          fixedFareFils: 2000,
          breakdown: const FareBreakdown(
            baseFareFils: 500,
            distanceFils: 1200,
            durationFils: 300,
            stopsFils: 0,
            subtotalFils: 2000,
            minimumFareFils: 1000,
            roundingIncrementFils: 50,
            fixedFareFils: 2000,
          ),
          status: FareQuoteStatus.calculated,
          expiresAt: DateTime.now().toUtc().subtract(
                const Duration(minutes: 1),
              ),
        ),
      );
      final container = createContainer(fareRepository: fareRepository);
      readyDraft(container);

      await pumpFareScreen(tester, container);

      await tester.scrollUntilVisible(
        find.text('Fare quote expired'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Fare quote expired'), findsOneWidget);
      expect(find.text('Request a new fare'), findsOneWidget);
      expect(find.text('JOD 2.00'), findsNothing);
      expect(find.text('Upfront fare'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Lock fare'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(confirmButton(tester, label: 'Lock fare').onPressed, isNull);
    },
  );

  testWidgets(
    'repeated lock taps issue a single lock request',
    (tester) async {
      final fareRepository = FakeFareRepository();
      final container = createContainer(fareRepository: fareRepository);
      readyDraft(container);

      await pumpFareScreen(tester, container);

      await tester.scrollUntilVisible(
        find.text('Lock fare'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Lock fare'));
      await tester.tap(find.text('Lock fare'));
      await tester.pumpAndSettle();

      expect(
        fareRepository.calls.where((call) => call.startsWith('lock')),
        hasLength(1),
      );
      expect(find.text('Fare locked'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'an ambiguous lock failure replays without replacing the quote',
    (tester) async {
      final fareRepository = FakeFareRepository();
      final container = createContainer(fareRepository: fareRepository);
      readyDraft(container);

      await pumpFareScreen(tester, container);

      await tester.scrollUntilVisible(
        find.text('Lock fare'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final quoteCalls =
          fareRepository.calls.where((call) => call.startsWith('quote')).length;

      // Failure before commit: replay must also work for this ambiguity.
      fareRepository.failNext(const FareException(FareFailure.networkFailure));
      await tester.tap(find.text('Lock fare'));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not reach the fare service.'),
        findsOneWidget,
      );
      expect(find.text('Retry fare lock'), findsOneWidget);
      // No draft update or replacement quote was issued behind the rider.
      expect(
        fareRepository.calls.where((call) => call.startsWith('update')),
        isEmpty,
      );
      expect(
        fareRepository.calls.where((call) => call.startsWith('quote')).length,
        quoteCalls,
      );

      await tester.scrollUntilVisible(
        find.text('Retry fare lock'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Retry fare lock'));
      await tester.pumpAndSettle();

      expect(find.text('Fare locked'), findsOneWidget);
      final locks = fareRepository.calls
          .where((call) => call.startsWith('lock'))
          .toList();
      expect(locks, hasLength(2));
      // Both attempts carried the original identifiers and versions.
      expect(locks[0], locks[1]);
      expect(
        fareRepository.calls.where((call) => call.startsWith('quote')).length,
        quoteCalls,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a genuine version conflict blocks mutations without restarting',
    (tester) async {
      final fareRepository = FakeFareRepository();
      final container = createContainer(fareRepository: fareRepository);
      readyDraft(container);

      await pumpFareScreen(tester, container);

      await tester.scrollUntilVisible(
        find.text('Lock fare'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      // An external session advances the booking: the screen's lock now
      // carries genuinely stale versions.
      await fareRepository.updateBookingDraft(
        bookingRequestId: 'booking-fake-1',
        expectedBookingVersion: 1,
        pickup: const FareRouteLocation(latitude: 31.95, longitude: 35.92),
        destination: const FareRouteLocation(latitude: 32.08, longitude: 36.1),
        vehicleTypeCode: 'economy',
        paymentMethod: 'cash',
      );
      await tester.tap(find.text('Lock fare'));
      await tester.pumpAndSettle();

      // BLOCKED recovery: no replay, no re-quote with stale versions.
      expect(
        find.text('The booking changed. Fare recovery is paused.'),
        findsOneWidget,
      );
      expect(find.text('Fare recovery blocked'), findsOneWidget);
      expect(find.text('Restart fare request'), findsNothing);
      expect(find.text('Retry fare lock'), findsNothing);
      expect(find.text('Retry fare request'), findsNothing);

      final calls = List<String>.of(fareRepository.calls);
      container
          .read(bookingControllerProvider.notifier)
          .setVehicleType(MockData.vehicleTypes[1]);
      await tester.pumpAndSettle();
      expect(fareRepository.calls, calls);
      expect(confirmButton(tester, label: 'Lock fare').onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a refresh conflict also blocks further refreshes',
    (tester) async {
      final fareRepository = FakeFareRepository();
      final container = createContainer(fareRepository: fareRepository);
      readyDraft(container);

      await pumpFareScreen(tester, container);

      await tester.scrollUntilVisible(
        find.text('Lock fare'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      // External advancement, then a draft edit triggers a refresh whose
      // update carries the stale version.
      await fareRepository.updateBookingDraft(
        bookingRequestId: 'booking-fake-1',
        expectedBookingVersion: 1,
        pickup: const FareRouteLocation(latitude: 31.95, longitude: 35.92),
        destination: const FareRouteLocation(latitude: 32.08, longitude: 36.1),
        vehicleTypeCode: 'economy',
        paymentMethod: 'cash',
      );
      container
          .read(bookingControllerProvider.notifier)
          .setVehicleType(MockData.vehicleTypes[1]);
      await tester.pumpAndSettle();

      expect(
        find.text('The booking changed. Fare recovery is paused.'),
        findsOneWidget,
      );
      expect(find.text('Fare recovery blocked'), findsOneWidget);
      expect(find.text('Restart fare request'), findsNothing);
      final calls = List<String>.of(fareRepository.calls);
      container
          .read(bookingControllerProvider.notifier)
          .setVehicleType(MockData.vehicleTypes.first);
      await tester.pumpAndSettle();
      expect(fareRepository.calls, calls);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a committed lock with a garbled response stays replayable',
    (tester) async {
      final garbling = _CommitThenGarbleFareRepository(FakeFareRepository());
      final container = createContainer(fareRepository: garbling);
      readyDraft(container);

      await pumpFareScreen(tester, container);

      await tester.scrollUntilVisible(
        find.text('Lock fare'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final delegate = garbling.delegate;
      final quoteCalls =
          delegate.calls.where((call) => call.startsWith('quote')).length;

      // The server commits, but the client receives an unusable response.
      await tester.tap(find.text('Lock fare'));
      await tester.pumpAndSettle();

      expect(find.text('Fares are unavailable right now.'), findsOneWidget);
      expect(find.text('Retry fare lock'), findsOneWidget);
      expect(
        delegate.calls.where((call) => call.startsWith('update')),
        isEmpty,
      );
      expect(
        delegate.calls.where((call) => call.startsWith('quote')).length,
        quoteCalls,
      );

      await tester.tap(find.text('Retry fare lock'));
      await tester.pumpAndSettle();

      expect(find.text('Fare locked'), findsOneWidget);
      final locks =
          delegate.calls.where((call) => call.startsWith('lock')).toList();
      expect(locks, hasLength(2));
      expect(locks[0], locks[1]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a stale re-quote callback after a lock never discards it',
    (tester) async {
      final fareRepository = FakeFareRepository();
      final container = createContainer(fareRepository: fareRepository);
      readyDraft(container);

      await pumpFareScreen(tester, container);

      // Force a refresh failure to capture a re-quote retry callback.
      container
          .read(bookingControllerProvider.notifier)
          .setVehicleType(MockData.vehicleTypes[1]);
      fareRepository
          .failNext(const FareException(FareFailure.pricingUnavailable));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Retry fare request'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Fares are unavailable right now.'), findsOneWidget);
      final staleRetry = tester
          .widget<AppButton>(
            find.widgetWithText(AppButton, 'Retry fare request'),
          )
          .onPressed!;
      final callsBeforeRecovery = fareRepository.calls.length;

      // Recover through the live UI: re-quote, then lock.
      await tester.tap(find.text('Retry fare request'));
      await tester.pumpAndSettle();
      expect(find.text('Upfront fare'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Lock fare'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Lock fare'));
      await tester.pumpAndSettle();
      expect(find.text('Fare locked'), findsOneWidget);
      final callsAfterLock = fareRepository.calls.length;

      // The retained callback is now stale: invoking it must be a no-op.
      staleRetry();
      await tester.pumpAndSettle();

      expect(fareRepository.calls.length, callsAfterLock);
      expect(fareRepository.calls.length, greaterThan(callsBeforeRecovery));
      expect(find.text('Fare locked'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a stale replay callback after recovery issues nothing new',
    (tester) async {
      final fareRepository = FakeFareRepository();
      final container = createContainer(fareRepository: fareRepository);
      readyDraft(container);

      await pumpFareScreen(tester, container);

      await tester.scrollUntilVisible(
        find.text('Lock fare'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      fareRepository.failNext(const FareException(FareFailure.networkFailure));
      await tester.tap(find.text('Lock fare'));
      await tester.pumpAndSettle();
      expect(find.text('Retry fare lock'), findsOneWidget);

      // Retain the replay callback, then recover through the live button.
      final staleReplay = tester
          .widget<AppButton>(
            find.widgetWithText(AppButton, 'Retry fare lock'),
          )
          .onPressed!;
      await tester.tap(find.text('Retry fare lock'));
      await tester.pumpAndSettle();
      expect(find.text('Fare locked'), findsOneWidget);
      final locksAfterRecovery = fareRepository.calls
          .where((call) => call.startsWith('lock'))
          .toList();
      expect(locksAfterRecovery, hasLength(2));

      staleReplay();
      await tester.pumpAndSettle();

      expect(
        fareRepository.calls.where((call) => call.startsWith('lock')).length,
        2,
      );
      expect(find.text('Fare locked'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'draft changes while unresolved issue no update or quote',
    (tester) async {
      final fareRepository = FakeFareRepository();
      final container = createContainer(fareRepository: fareRepository);
      readyDraft(container);

      await pumpFareScreen(tester, container);

      await tester.scrollUntilVisible(
        find.text('Lock fare'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      fareRepository.failNext(const FareException(FareFailure.timedOut));
      await tester.tap(find.text('Lock fare'));
      await tester.pumpAndSettle();
      expect(find.text('Retry fare lock'), findsOneWidget);
      final updateCalls = fareRepository.calls
          .where((call) => call.startsWith('update'))
          .length;
      final quoteCalls =
          fareRepository.calls.where((call) => call.startsWith('quote')).length;

      // The rider edits the draft while the lock outcome is unknown.
      container
          .read(bookingControllerProvider.notifier)
          .setVehicleType(MockData.vehicleTypes[1]);
      await tester.pumpAndSettle();

      expect(
        fareRepository.calls.where((call) => call.startsWith('update')).length,
        updateCalls,
      );
      expect(
        fareRepository.calls.where((call) => call.startsWith('quote')).length,
        quoteCalls,
      );
      expect(find.text('Retry fare lock'), findsOneWidget);

      // Exact replay confirms the original fare; edited local selections
      // cannot authorize a replacement quote before handoff.
      await tester.scrollUntilVisible(
        find.text('Retry fare lock'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Retry fare lock'));
      await tester.pumpAndSettle();

      expect(find.text('Upfront fare'), findsOneWidget);
      expect(find.textContaining('Quote v1'), findsOneWidget);
      expect(
          fareRepository.calls
              .where((call) => call.startsWith('update'))
              .length,
          updateCalls);
      expect(
          fareRepository.calls.where((call) => call.startsWith('quote')).length,
          quoteCalls);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'back navigation is blocked only while a lock is unresolved',
    (tester) async {
      final fareRepository = FakeFareRepository();
      final container = createContainer(fareRepository: fareRepository);
      readyDraft(container);

      final navigator = await pushFareScreen(tester, container);
      expect(navigator.currentState!.canPop(), isTrue);
      expect(farePopScope(tester).canPop, isTrue);

      await tester.scrollUntilVisible(
        find.text('Lock fare'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      fareRepository.failNext(const FareException(FareFailure.networkFailure));
      await tester.tap(find.text('Lock fare'));
      await tester.pumpAndSettle();
      expect(find.text('Retry fare lock'), findsOneWidget);
      expect(farePopScope(tester).canPop, isFalse);

      // The system back button does not abandon the pending lock lineage.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Retry fare lock'), findsOneWidget);
      expect(
          find.text('Waiting for the fare lock to resolve…'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(FareEstimateScreen), findsOneWidget);

      await tester.tap(find.text('Retry fare lock'));
      await tester.pumpAndSettle();
      expect(find.text('Fare locked'), findsOneWidget);
      expect(farePopScope(tester).canPop, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(FareEstimateScreen), findsNothing);
      expect(find.text('Previous route'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a lock result arriving after disposal corrupts nothing',
    (tester) async {
      final hanging = _HangingLockFareRepository(FakeFareRepository());
      final container = createContainer(fareRepository: hanging);
      readyDraft(container);

      final navigator = await pushFareScreen(tester, container);

      await tester.scrollUntilVisible(
        find.text('Lock fare'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Lock fare'));
      await tester.pump();

      // Replacement bypasses PopScope. Persistence is deliberately not
      // implemented; this verifies only disposal and late-completion safety.
      navigator.currentState!.pushReplacement(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Replacement route')),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(FareEstimateScreen), findsNothing);
      hanging.gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Replacement route'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'edits after a replayed lock retain the original fare until handoff',
    (tester) async {
      final fareRepository = FakeFareRepository();
      final container = createContainer(fareRepository: fareRepository);
      readyDraft(container);

      await pumpFareScreen(tester, container);

      await tester.scrollUntilVisible(
        find.text('Lock fare'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      fareRepository.failNext(const FareException(FareFailure.timedOut));
      await tester.tap(find.text('Lock fare'));
      await tester.pumpAndSettle();
      expect(find.text('Retry fare lock'), findsOneWidget);

      await tester.tap(find.text('Retry fare lock'));
      await tester.pumpAndSettle();
      expect(find.text('Fare locked'), findsOneWidget);

      // A later local edit cannot discard the confirmed original fare.
      container
          .read(bookingControllerProvider.notifier)
          .setVehicleType(MockData.vehicleTypes[1]);
      await tester.pumpAndSettle();

      expect(
          find.text('The booking changed. Request a new fare.'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Fare locked'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Quote v1'), findsOneWidget);
      expect(confirmButton(tester, label: 'Fare locked').onPressed, isNull);
      expect(fareRepository.calls.where((call) => call.startsWith('update')),
          isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
      'committed lock plus lifecycle advance stays blocked without replacement',
      (tester) async {
    final repository = _CommitThenGarbleFareRepository(FakeFareRepository());
    final container = createContainer(fareRepository: repository);
    readyDraft(container);
    await pumpFareScreen(tester, container);
    await tester.scrollUntilVisible(find.text('Lock fare'), 300,
        scrollable: find.byType(Scrollable).first);
    final staleLock = confirmButton(tester, label: 'Lock fare').onPressed!;
    await tester.tap(find.text('Lock fare'));
    await tester.pumpAndSettle();
    expect(repository.linkedLock!.status, FareQuoteStatus.locked);
    final original = repository.lockAttempts.single;
    repository.advanceLinkedBookingVersion();
    expect(repository.canonicalBookingVersion, 3);
    final staleReplay = tester
        .widget<AppButton>(find.widgetWithText(AppButton, 'Retry fare lock'))
        .onPressed!;
    staleReplay();
    await tester.pumpAndSettle();
    expect(repository.lockAttempts, [original, original]);
    expect(find.text('Fare recovery blocked'), findsOneWidget);
    expect(find.text('Restart fare request'), findsNothing);
    expect(find.text('Retry fare lock'), findsNothing);
    expect(farePopScope(tester).canPop, isFalse);
    final calls = List<String>.of(repository.delegate.calls);
    staleReplay();
    staleLock();
    container
        .read(bookingControllerProvider.notifier)
        .setVehicleType(MockData.vehicleTypes[1]);
    await tester.pumpAndSettle();
    expect(repository.delegate.calls, calls);
    expect(repository.lockAttempts, [original, original]);
    expect(repository.delegate.calls.where((c) => c == 'create'), hasLength(1));
    expect(repository.delegate.calls.where((c) => c.startsWith('quote')),
        hasLength(1));
    expect(repository.linkedLock!.id,
        repository.delegate.quotesFor('booking-fake-1').single.id);
    await tester.pumpWidget(const SizedBox());
  });

  for (final rejection in [FareFailure.unauthorized, FareFailure.forbidden]) {
    testWidgets('an uncertain committed lock survives replay $rejection',
        (tester) async {
      final repository = _CommitThenGarbleFareRepository(FakeFareRepository());
      final container = createContainer(fareRepository: repository);
      readyDraft(container);
      await pumpFareScreen(tester, container);
      await tester.scrollUntilVisible(find.text('Lock fare'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Lock fare'));
      await tester.pumpAndSettle();
      final retry = tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Retry fare lock'))
          .onPressed!;
      repository.delegate.failNext(FareException(rejection));
      retry();
      await tester.pumpAndSettle();
      expect(repository.lockAttempts, hasLength(2));
      expect(repository.lockAttempts[0], repository.lockAttempts[1]);
      expect(find.text('Fare recovery blocked'), findsOneWidget);
      expect(find.text('Sign in again to see fares.'), findsOneWidget);
      expect(find.text('Retry fare lock'), findsNothing);
      expect(farePopScope(tester).canPop, isFalse);
      final calls = List<String>.of(repository.delegate.calls);
      retry();
      container
          .read(bookingControllerProvider.notifier)
          .setVehicleType(MockData.vehicleTypes[1]);
      await tester.pumpAndSettle();
      expect(repository.delegate.calls, calls);
      expect(
          repository.delegate.calls.where((c) => c == 'create'), hasLength(1));
      expect(repository.linkedLock!.status, FareQuoteStatus.locked);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('pending recovery remains visible without a route or vehicle',
      (tester) async {
    final repository = _CommitThenGarbleFareRepository(FakeFareRepository());
    final container = createContainer(fareRepository: repository);
    readyDraft(container);
    await pumpFareScreen(tester, container);
    await tester.scrollUntilVisible(find.text('Lock fare'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Lock fare'));
    await tester.pumpAndSettle();
    container.read(bookingControllerProvider.notifier).clearPickup();
    await tester.pumpAndSettle();
    expect(find.text('Fare lock pending'), findsOneWidget);
    expect(find.text('Retry fare lock'), findsOneWidget);
    expect(container.read(bookingControllerProvider).vehicleType, isNull);
    final calls = List<String>.of(repository.delegate.calls);
    await tester.scrollUntilVisible(find.text('Retry fare lock'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Retry fare lock'));
    await tester.pumpAndSettle();
    expect(repository.lockAttempts[0], repository.lockAttempts[1]);
    expect(repository.delegate.calls.length, calls.length + 1);
    expect(farePopScope(tester).canPop, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'stale expiry callback cannot replace a newer pending or locked quote',
      (tester) async {
    var clock = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    final fake = FakeFareRepository(clock: () => clock);
    final repository = _CommitThenGarbleFareRepository(fake);
    final container = createContainer(fareRepository: repository);
    readyDraft(container);
    await pumpFareScreen(tester, container);
    await tester.scrollUntilVisible(find.text('Request a new fare'), 300,
        scrollable: find.byType(Scrollable).first);
    final expiredRetry = tester
        .widget<AppButton>(find.widgetWithText(AppButton, 'Request a new fare'))
        .onPressed!;
    clock = DateTime.now().toUtc();
    expiredRetry();
    expiredRetry(); // Duplicate while the replacement request is loading.
    await tester.pumpAndSettle();
    expect(fake.calls.where((c) => c.startsWith('update')), hasLength(1));
    final callsForNewQuote = List<String>.of(fake.calls);
    expiredRetry(); // Old quote identity after the replacement arrived.
    await tester.pumpAndSettle();
    expect(fake.calls, callsForNewQuote);
    await tester.scrollUntilVisible(find.text('Lock fare'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Lock fare'));
    await tester.pumpAndSettle();
    final pendingCalls = List<String>.of(fake.calls);
    expiredRetry();
    await tester.pumpAndSettle();
    expect(fake.calls, pendingCalls);
    expect(find.text('Retry fare lock'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Retry fare lock'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Retry fare lock'));
    await tester.pumpAndSettle();
    expect(find.text('Fare locked'), findsOneWidget);
    final lockedCalls = List<String>.of(fake.calls);
    expiredRetry();
    await tester.pumpAndSettle();
    expect(fake.calls, lockedCalls);
    expect(find.text('Fare locked'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('another user cannot replay the original Rider lock',
      (tester) async {
    final repository = _CommitThenGarbleFareRepository(FakeFareRepository());
    final container = createContainer(fareRepository: repository);
    readyDraft(container);
    await pumpFareScreen(tester, container);
    await tester.scrollUntilVisible(find.text('Lock fare'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Lock fare'));
    await tester.pumpAndSettle();
    final retry = tester
        .widget<AppButton>(find.widgetWithText(AppButton, 'Retry fare lock'))
        .onPressed!;
    final calls = List<String>.of(repository.delegate.calls);
    await container.read(sessionControllerProvider.notifier).signUp(
        name: 'Another Rider', email: 'other@example.test', password: 'test');
    await tester.pumpAndSettle();
    retry();
    await tester.pumpAndSettle();
    expect(repository.delegate.calls, calls);
    expect(find.text('Retry fare lock'), findsNothing);
    expect(find.text('Fare recovery blocked'), findsOneWidget);
    expect(find.text('JOD 2.00'), findsNothing);
    expect(repository.lockAttempts, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('persistence failure prevents lock dispatch', (tester) async {
    final fareRepository = FakeFareRepository();
    final pendingStore = _RecordingPendingFareLockStore()
      ..failNextSave = StateError('disk unavailable');
    final errorReporter = RecordingAppErrorReporter();
    final container = createContainer(
      fareRepository: fareRepository,
      pendingStore: pendingStore,
      errorReporter: errorReporter,
    );
    readyDraft(container);
    await pumpFareScreen(tester, container);
    await tester.scrollUntilVisible(find.text('Lock fare'), 300,
        scrollable: find.byType(Scrollable).first);

    await tester.tap(find.text('Lock fare'));
    await tester.pumpAndSettle();

    // Nothing was ever sent: a persistence failure is a known non-commit.
    expect(
      fareRepository.calls.where((call) => call.startsWith('lock')),
      isEmpty,
    );
    expect(container.read(pendingFareLockControllerProvider), isNull);
    expect(await pendingStore.loadForRider('rider-1'), isNull);
    // The storage failure is diagnosed internally, never leaked or shown
    // as a fare error detail.
    expect(errorReporter.reports, hasLength(1));
    expect(errorReporter.reports.single.operation, contains('pending'));
    expect(find.text('Fares are unavailable right now.'), findsOneWidget);
    // Uncertainty is NOT recorded for a request that never left.
    expect(find.text('Retry fare lock'), findsNothing);
    expect(find.text('Retry fare request'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lock waits for storage completion before dispatch',
      (tester) async {
    final repository = FakeFareRepository();
    final store = _RecordingPendingFareLockStore();
    final container =
        createContainer(fareRepository: repository, pendingStore: store);
    readyDraft(container);
    await pumpFareScreen(tester, container);
    await tester.scrollUntilVisible(find.text('Lock fare'), 300,
        scrollable: find.byType(Scrollable).first);
    final gate = Completer<void>();
    store.saveGate = gate;
    await tester.tap(find.text('Lock fare'));
    await tester.pump();
    expect(store.saveGate, isNull); // The save is actually awaiting the gate.
    expect(repository.calls.where((call) => call.startsWith('lock')), isEmpty);
    gate.complete();
    await tester.pumpAndSettle();
    expect(repository.calls.where((call) => call.startsWith('lock')),
        hasLength(1));
    await tester.scrollUntilVisible(find.text('Fare locked'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Fare locked'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sign-out during storage prevents screen RPC dispatch',
      (tester) async {
    final repository = FakeFareRepository();
    final store = _RecordingPendingFareLockStore();
    final reporter = RecordingAppErrorReporter();
    final container = createContainer(
        fareRepository: repository,
        pendingStore: store,
        errorReporter: reporter);
    readyDraft(container);
    await pumpFareScreen(tester, container);
    await tester.scrollUntilVisible(find.text('Lock fare'), 300,
        scrollable: find.byType(Scrollable).first);
    final gate = Completer<void>();
    store.saveGate = gate;
    await tester.tap(find.text('Lock fare'));
    await tester.pump();
    expect(store.saveGate, isNull);
    await container.read(sessionControllerProvider.notifier).signOut();
    gate.complete();
    await tester.pumpAndSettle();
    expect(repository.calls.where((call) => call.startsWith('lock')), isEmpty);
    expect(container.read(pendingFareLockControllerProvider), isNull);
    expect(store.slots['rider-1'], isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('storage failure after screen disposal uses captured diagnostics',
      (tester) async {
    final repository = FakeFareRepository();
    final store = _RecordingPendingFareLockStore();
    final reporter = RecordingAppErrorReporter();
    final container = createContainer(
        fareRepository: repository,
        pendingStore: store,
        errorReporter: reporter);
    readyDraft(container);
    await pumpFareScreen(tester, container);
    await tester.scrollUntilVisible(find.text('Lock fare'), 300,
        scrollable: find.byType(Scrollable).first);
    final gate = Completer<void>();
    store.saveGate = gate;
    store.failNextSave = StateError('disk unavailable');
    await tester.tap(find.text('Lock fare'));
    await tester.pump();
    expect(store.saveGate, isNull);
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pumpAndSettle();
    expect(repository.calls.where((call) => call.startsWith('lock')), isEmpty);
    expect(reporter.reports, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a confirmed lock retains its durable protection command',
      (tester) async {
    final fareRepository = FakeFareRepository();
    final pendingStore = _RecordingPendingFareLockStore();
    final container = createContainer(
      fareRepository: fareRepository,
      pendingStore: pendingStore,
    );
    readyDraft(container);
    await pumpFareScreen(tester, container);
    await tester.scrollUntilVisible(find.text('Lock fare'), 300,
        scrollable: find.byType(Scrollable).first);

    await tester.tap(find.text('Lock fare'));
    await tester.pumpAndSettle();

    expect(find.text('Fare locked'), findsOneWidget);
    // The pre-dispatch staging carried the original identity...
    expect(pendingStore.saves, hasLength(1));
    expect(pendingStore.saves.single.bookingRequestId, 'booking-fake-1');
    expect(pendingStore.saves.single.expectedBookingVersion, 1);
    expect(pendingStore.saves.single.fareQuoteId, 'quote-fake-1');
    expect(pendingStore.saves.single.expectedQuoteVersion, 1);
    expect(pendingStore.saves.single.riderId, 'rider-1');
    // Success retains protection until the later booking handoff.
    expect(container.read(pendingFareLockControllerProvider),
        pendingStore.saves.single);
    expect(
        await pendingStore.loadForRider('rider-1'), pendingStore.saves.single);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an uncertain command survives screen disposal', (tester) async {
    final fareRepository = FakeFareRepository();
    final pendingStore = _RecordingPendingFareLockStore();
    final container = createContainer(
      fareRepository: fareRepository,
      pendingStore: pendingStore,
    );
    readyDraft(container);
    await pumpFareScreen(tester, container);
    await tester.scrollUntilVisible(find.text('Lock fare'), 300,
        scrollable: find.byType(Scrollable).first);

    fareRepository.failNext(const FareException(FareFailure.networkFailure));
    await tester.tap(find.text('Lock fare'));
    await tester.pumpAndSettle();
    expect(find.text('Retry fare lock'), findsOneWidget);

    final staged = container.read(pendingFareLockControllerProvider);
    expect(staged, isNotNull);
    expect(staged!.bookingRequestId, 'booking-fake-1');
    expect(staged.expectedBookingVersion, 1);
    expect(staged.fareQuoteId, 'quote-fake-1');
    expect(staged.expectedQuoteVersion, 1);
    expect(staged.riderId, 'rider-1');

    // Disposal (redirects, replacement, process-driven rebuilds) must not
    // lose booking-owned recovery identity.
    await tester.pumpWidget(const SizedBox());
    expect(container.read(pendingFareLockControllerProvider), staged);
    expect(await pendingStore.loadForRider('rider-1'), staged);
    expect(tester.takeException(), isNull);
  });

  testWidgets('demo mode never stages a pending command', (tester) async {
    final pendingStore = _RecordingPendingFareLockStore();
    final container = createContainer(pendingStore: pendingStore);
    readyDraft(container);
    await pumpFareScreen(tester, container);

    await tester.scrollUntilVisible(find.text('Demo fare'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Demo fare'), findsOneWidget);
    expect(pendingStore.saves, isEmpty);
    expect(container.read(pendingFareLockControllerProvider), isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

/// Recording store double: memory slots plus a save log and an optional
/// one-shot save failure for persistence-before-dispatch tests.
class _RecordingPendingFareLockStore implements PendingFareLockStore {
  final slots = <String, PendingFareLock>{};
  final saves = <PendingFareLock>[];
  Error? failNextSave;
  Completer<void>? saveGate;

  @override
  Future<void> save(PendingFareLock command) async {
    final gate = saveGate;
    if (gate != null) {
      saveGate = null;
      await gate.future;
    }
    final failure = failNextSave;
    if (failure != null) {
      failNextSave = null;
      throw failure;
    }
    saves.add(command);
    slots[command.riderId] = command;
  }

  @override
  Future<PendingFareLock?> loadForRider(String riderId) async {
    return (await inspectForRider(riderId)).command;
  }

  @override
  Future<PendingFareLockSlot> inspectForRider(String riderId) async {
    final stored = slots[riderId];
    if (stored == null) return const PendingFareLockSlot.absent();
    if (stored.riderId != riderId) {
      return const PendingFareLockSlot.corrupt('rider-mismatch');
    }
    return PendingFareLockSlot.valid(stored);
  }

  @override
  Future<void> clearForRider(String riderId) async {
    slots.remove(riderId);
  }
}
