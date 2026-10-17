import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/fare_repository.dart';
import 'package:ridex/core/repositories/mock_place_repository.dart';
import 'package:ridex/core/repositories/mock_route_repository.dart';
import 'package:ridex/core/services/fare/pending_fare_lock_store.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/features/booking/presentation/providers/rider_payment_selection_provider.dart';
import 'package:ridex/features/booking/presentation/screens/fare_estimate_screen.dart';
import 'package:ridex/features/booking/presentation/screens/vehicle_type_selection_screen.dart';

/// P6-05: Rider payment method selection (Cash and Card).
///
/// Cash is the default. Card is selectable as a booking payment **method
/// only**: selection never authorizes, captures, or settles a payment. The
/// fare screen derives its display and draft calls from
/// [riderPaymentSelectionProvider] and dispatches the exact method that keyed
/// the in-flight request, so a toggle mid-request cannot mix values.
class _MemoryPendingFareLockStore implements PendingFareLockStore {
  PendingFareLock? slot;

  @override
  Future<void> save(PendingFareLock command) async {
    slot = command;
  }

  @override
  Future<PendingFareLock?> loadForRider(String riderId) async {
    final current = slot;
    return current?.riderId == riderId ? current : null;
  }

  @override
  Future<PendingFareLockSlot> inspectForRider(String riderId) async {
    final current = slot;
    if (current == null) return const PendingFareLockSlot.absent();
    if (current.riderId != riderId) {
      return const PendingFareLockSlot.corrupt('rider-mismatch');
    }
    return PendingFareLockSlot.valid(current);
  }

  @override
  Future<void> clearForRider(String riderId) async {
    if (slot?.riderId == riderId) slot = null;
  }
}

/// Records the `paymentMethod` argument of every draft call while
/// delegating behavior to a [FakeFareRepository].
class _RecordingMethodFareRepository implements FareRepository {
  _RecordingMethodFareRepository(this._delegate);

  final FakeFareRepository _delegate;
  final List<String> paymentMethods = [];

  /// When set, [createBookingDraft] waits on this before delegating so a test
  /// can toggle the payment method while the first draft call is in flight.
  Completer<void>? createGate;

  @override
  Future<FareBookingRef> createBookingDraft({
    required FareRouteLocation pickup,
    required FareRouteLocation destination,
    required String vehicleTypeCode,
    required String paymentMethod,
    List<FareStopInput> stops = const [],
  }) async {
    paymentMethods.add(paymentMethod);
    final gate = createGate;
    if (gate != null) {
      await gate.future;
    }
    return _delegate.createBookingDraft(
      pickup: pickup,
      destination: destination,
      vehicleTypeCode: vehicleTypeCode,
      paymentMethod: paymentMethod,
      stops: stops,
    );
  }

  @override
  Future<FareBookingRef> updateBookingDraft({
    required String bookingRequestId,
    required int expectedBookingVersion,
    required FareRouteLocation pickup,
    required FareRouteLocation destination,
    required String vehicleTypeCode,
    required String paymentMethod,
    List<FareStopInput> stops = const [],
  }) {
    paymentMethods.add(paymentMethod);
    return _delegate.updateBookingDraft(
      bookingRequestId: bookingRequestId,
      expectedBookingVersion: expectedBookingVersion,
      pickup: pickup,
      destination: destination,
      vehicleTypeCode: vehicleTypeCode,
      paymentMethod: paymentMethod,
      stops: stops,
    );
  }

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
  }) =>
      _delegate.lockQuote(
        bookingRequestId: bookingRequestId,
        fareQuoteId: fareQuoteId,
        expectedBookingVersion: expectedBookingVersion,
        expectedQuoteVersion: expectedQuoteVersion,
      );
}

void main() {
  ProviderContainer createContainer({FareRepository? fareRepository}) {
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
        pendingFareLockStoreProvider.overrideWithValue(
          _MemoryPendingFareLockStore(),
        ),
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

  Future<void> pumpVehicleScreen(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const VehicleTypeSelectionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpFareScreen(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
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

  /// Signs in the demo rider without re-signing on every screen pump, so a
  /// Card selection made before pumping the fare screen is not reset by a
  /// session change.
  Future<void> signInDemoRider(ProviderContainer container) async {
    await container.read(sessionControllerProvider.notifier).refreshSession();
    await container.read(sessionControllerProvider.notifier).continueAsDemo();
  }

  /// Pumps the fare screen on an already-established session (see
  /// [signInDemoRider]); does not touch sessions, so a prior Card selection
  /// survives.
  Future<void> pumpFareScreenRaw(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
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

  test('cash is selected by default with the canonical backend value', () {
    final container = createContainer();
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.cash,
    );
    expect(
      container.read(riderPaymentSelectionProvider).backendValue,
      'cash',
    );
  });

  test('cash and card selection are exposed and idempotent', () {
    final container = createContainer();
    final notifier = container.read(riderPaymentSelectionProvider.notifier);
    expect(notifier, isA<RiderPaymentSelectionController>());
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.cash,
    );
    notifier.selectCash();
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.cash,
    );
    // Card is selectable as a method only; repeated calls are no-ops.
    notifier.selectCard();
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.card,
    );
    expect(
      container.read(riderPaymentSelectionProvider).backendValue,
      'card',
    );
    notifier.selectCard();
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.card,
    );
    notifier.select(PaymentMethod.cash);
    expect(
      container.read(riderPaymentSelectionProvider).backendValue,
      'cash',
    );
  });

  test('payment selection resets to cash across rider sessions', () async {
    final container = createContainer();
    // Initialize the provider so its session listener is active.
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.cash,
    );
    // Rider A signs in via demo and selects Card.
    await container.read(sessionControllerProvider.notifier).continueAsDemo();
    expect(container.read(sessionControllerProvider).user?.id, 'rider-1');
    container.read(riderPaymentSelectionProvider.notifier).selectCard();
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.card,
    );
    // Session ends: selection returns to Cash (never carried over).
    await container.read(sessionControllerProvider.notifier).signOut();
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.cash,
    );
    // A different rider identity starts from Cash.
    await container.read(sessionControllerProvider.notifier).signUp(
          name: 'Second',
          email: 'second@ridex.app',
          password: '123456',
        );
    expect(
      container.read(sessionControllerProvider).user?.id,
      isNot('rider-1'),
    );
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.cash,
    );
  });

  testWidgets('vehicle screen shows Cash as selected by default',
      (tester) async {
    final container = createContainer();

    await pumpVehicleScreen(tester, container);

    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Selected'), findsOneWidget);
    expect(find.text('Card'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping Cash keeps the cash selection', (tester) async {
    final container = createContainer();

    await pumpVehicleScreen(tester, container);

    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();

    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.cash,
    );
    expect(find.text('Selected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping Card selects the card method with selected semantics',
      (tester) async {
    final container = createContainer();

    await pumpVehicleScreen(tester, container);
    await tester.scrollUntilVisible(
      find.text('Card'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.text('Card'));
    await tester.pumpAndSettle();

    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.card,
    );
    // No Coming Soon dialog gates the selection any more.
    expect(find.text('Coming soon'), findsNothing);
    expect(find.text('Selected'), findsOneWidget);
    final semantics = tester.widget<Semantics>(
      find.byKey(const ValueKey('card-payment-option')),
    );
    expect(semantics.properties.selected, isTrue);
    expect(semantics.properties.label, 'Card, selected payment method');
    // The UI clearly distinguishes method selection from real card capture.
    expect(
      find.textContaining('Real card payment processing is not available'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switching Card back to Cash updates selection and semantics',
      (tester) async {
    final container = createContainer();

    await pumpVehicleScreen(tester, container);
    await tester.scrollUntilVisible(
      find.text('Card'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Card'));
    await tester.pumpAndSettle();
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.card,
    );

    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();

    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.cash,
    );
    final cash = tester.widget<Semantics>(
      find.byKey(const ValueKey('cash-payment-option')),
    );
    expect(cash.properties.selected, isTrue);
    expect(find.text('Selected'), findsOneWidget);
    expect(
      find.textContaining('Real card payment processing is not available'),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('card selection dispatches the canonical card backend value',
      (tester) async {
    final recording = _RecordingMethodFareRepository(FakeFareRepository());
    final container = createContainer(fareRepository: recording);
    readyDraft(container);
    await signInDemoRider(container);

    await pumpVehicleScreen(tester, container);
    // The vehicle screen itself never touches the fare repository.
    expect(recording.paymentMethods, isEmpty);
    await tester.scrollUntilVisible(
      find.text('Card'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.text('Card'));
    await tester.pumpAndSettle();
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.card,
    );

    // The fare step creates drafts with the canonical card value only.
    await pumpFareScreenRaw(tester, container);
    await tester.scrollUntilVisible(
      find.text('Upfront fare'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Upfront fare'), findsOneWidget);
    expect(recording.paymentMethods, isNotEmpty);
    expect(
      recording.paymentMethods,
      everyElement(PaymentMethod.card.backendValue),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'dispatched method matches the request key across an in-flight '
      'toggle', (tester) async {
    final recording = _RecordingMethodFareRepository(FakeFareRepository());
    final container = createContainer(fareRepository: recording);
    readyDraft(container);
    await signInDemoRider(container);

    // Gate the very first (create) call so we can toggle while it is in
    // flight and prove the captured method, not the live one, is dispatched.
    recording.createGate = Completer<void>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const FareEstimateScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      recording.paymentMethods,
      [PaymentMethod.cash.backendValue],
    );
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.cash,
    );

    // Toggle to Card while the cash-created request is still in flight.
    container.read(riderPaymentSelectionProvider.notifier).selectCard();
    await tester.pump();

    // The in-flight request keeps its captured cash value; no new dispatch.
    expect(
      recording.paymentMethods,
      [PaymentMethod.cash.backendValue],
    );
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.card,
    );

    // Release the create: the screen re-quotes with the new Card method.
    recording.createGate!.complete();
    await tester.pumpAndSettle();

    // Each dispatched value equals the method that keyed its request: the
    // create was cash-keyed/cash-sent, the follow-up update is card.
    expect(recording.paymentMethods, [
      PaymentMethod.cash.backendValue,
      PaymentMethod.card.backendValue,
    ]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('payment selection survives vehicle-to-fare navigation',
      (tester) async {
    final container = createContainer(fareRepository: FakeFareRepository());
    readyDraft(container);

    // Vehicle step: default Cash is shown as selected.
    await pumpVehicleScreen(tester, container);
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.cash,
    );
    await tester.scrollUntilVisible(
      find.text('Cash'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Selected'), findsOneWidget);

    // Same ProviderContainer navigates to the fare step: selection
    // survives normal Rider booking navigation (no reset, still Cash).
    await pumpFareScreen(tester, container);
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.cash,
    );
    await tester.scrollUntilVisible(
      find.text('Upfront fare'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Payment'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fare screen displays the selected cash method', (tester) async {
    final container = createContainer(fareRepository: FakeFareRepository());
    readyDraft(container);

    await pumpFareScreen(tester, container);

    await tester.scrollUntilVisible(
      find.text('Upfront fare'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Upfront fare'), findsOneWidget);
    // The payment summary row derives from selection state, not a
    // hardcoded display value.
    expect(find.text('Payment'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Card'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('booking-draft calls use the canonical cash value',
      (tester) async {
    final recording = _RecordingMethodFareRepository(FakeFareRepository());
    final container = createContainer(fareRepository: recording);
    readyDraft(container);

    await pumpFareScreen(tester, container);

    await tester.scrollUntilVisible(
      find.text('Upfront fare'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Upfront fare'), findsOneWidget);
    expect(recording.paymentMethods, isNotEmpty);
    expect(
      recording.paymentMethods,
      everyElement(PaymentMethod.cash.backendValue),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('demo mode keeps the demo fare with cash selected',
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
    expect(find.text('Cash'), findsOneWidget);
    expect(container.read(pendingFareLockControllerProvider), isNull);
    await tester.scrollUntilVisible(
      find.text('Confirm & find a driver'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<AppButton>(
            find.widgetWithText(AppButton, 'Confirm & find a driver'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fare lock still works with the selected cash method',
      (tester) async {
    final container = createContainer(fareRepository: FakeFareRepository());
    readyDraft(container);

    await pumpFareScreen(tester, container);

    await tester.scrollUntilVisible(
      find.text('Lock fare'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Lock fare'));
    await tester.pumpAndSettle();

    expect(find.text('Fare locked'), findsOneWidget);
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.cash,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cash selection causes no extra draft mutation while unresolved',
      (tester) async {
    // Findings 3/5: the Cash-only invariant means the quote-key value and
    // the dispatched draft value are both always 'cash', so an idempotent
    // Cash selection can never invalidate the committed lock lineage.
    final fake = FakeFareRepository();
    final recording = _RecordingMethodFareRepository(fake);
    final container = createContainer(fareRepository: recording);
    readyDraft(container);

    await pumpFareScreen(tester, container);

    await tester.scrollUntilVisible(
      find.text('Lock fare'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final draftCallsBeforeLock = recording.paymentMethods.length;
    expect(recording.paymentMethods, isNotEmpty);

    // Ambiguous lock failure: the commit outcome is unknown and the
    // lineage must replay with its original identifiers and versions.
    fake.failNext(const FareException(FareFailure.networkFailure));
    await tester.tap(find.text('Lock fare'));
    await tester.pumpAndSettle();

    expect(find.text('Retry fare lock'), findsOneWidget);
    // The failed lock issued no draft update behind the rider.
    expect(recording.paymentMethods.length, draftCallsBeforeLock);
    final repoCallsWhileUnresolved = fake.calls.length;

    // Idempotent Cash selection while unresolved: no re-quote, no draft
    // mutation, lineage preserved.
    container.read(riderPaymentSelectionProvider.notifier).selectCash();
    await tester.pumpAndSettle();

    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.cash,
    );
    expect(recording.paymentMethods.length, draftCallsBeforeLock);
    expect(fake.calls.length, repoCallsWhileUnresolved);
    expect(find.text('Retry fare lock'), findsOneWidget);

    // The original lineage still replays exactly.
    await tester.tap(find.text('Retry fare lock'));
    await tester.pumpAndSettle();

    expect(find.text('Fare locked'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cash selection exposes selected semantics', (tester) async {
    final container = createContainer();

    await pumpVehicleScreen(tester, container);
    await tester.scrollUntilVisible(
      find.text('Cash'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    final semantics = tester.widget<Semantics>(
      find.byKey(const ValueKey('cash-payment-option')),
    );
    expect(semantics.properties.selected, isTrue);
    expect(
      semantics.properties.label,
      'Cash, selected payment method',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fare screen displays the selected card method distinctly',
      (tester) async {
    final container = createContainer(fareRepository: FakeFareRepository());
    readyDraft(container);
    await signInDemoRider(container);
    container.read(riderPaymentSelectionProvider.notifier).selectCard();

    await pumpFareScreenRaw(tester, container);
    await tester.scrollUntilVisible(
      find.text('Upfront fare'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Upfront fare'), findsOneWidget);
    expect(find.text('Payment'), findsOneWidget);
    expect(find.text('Card'), findsOneWidget);
    expect(find.text('Cash'), findsNothing);
    // The note makes clear this is method selection, not a processed charge.
    expect(
      find.textContaining('No card payment is processed'),
      findsOneWidget,
    );
    // Never presents Card as a completed payment state.
    expect(find.textContaining('Succeeded'), findsNothing);
    expect(find.textContaining('Authorized'), findsNothing);
    expect(find.textContaining('Paid'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('card selection survives a quote failure and retries',
      (tester) async {
    final fake = FakeFareRepository();
    final recording = _RecordingMethodFareRepository(fake);
    final container = createContainer(fareRepository: recording);
    readyDraft(container);
    await signInDemoRider(container);
    container.read(riderPaymentSelectionProvider.notifier).selectCard();

    fake.failNext(const FareException(FareFailure.pricingUnavailable));
    await pumpFareScreenRaw(tester, container);

    await tester.scrollUntilVisible(
      find.text('Retry fare request'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Fares are unavailable right now.'), findsOneWidget);
    // The selection is untouched by a backend failure.
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.card,
    );

    await tester.ensureVisible(find.text('Retry fare request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry fare request'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Upfront fare'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Upfront fare'), findsOneWidget);
    expect(
      recording.paymentMethods,
      everyElement(PaymentMethod.card.backendValue),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('card selection replays an ambiguous lock failure and locks',
      (tester) async {
    final fake = FakeFareRepository();
    final recording = _RecordingMethodFareRepository(fake);
    final container = createContainer(fareRepository: recording);
    readyDraft(container);
    await signInDemoRider(container);
    container.read(riderPaymentSelectionProvider.notifier).selectCard();
    await pumpFareScreenRaw(tester, container);

    await tester.scrollUntilVisible(
      find.text('Lock fare'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final draftCallsBeforeLock = recording.paymentMethods.length;

    fake.failNext(const FareException(FareFailure.networkFailure));
    await tester.tap(find.text('Lock fare'));
    await tester.pumpAndSettle();

    expect(find.text('Retry fare lock'), findsOneWidget);
    // The ambiguous failure issued no draft update behind the rider.
    expect(recording.paymentMethods.length, draftCallsBeforeLock);

    await tester.tap(find.text('Retry fare lock'));
    await tester.pumpAndSettle();

    expect(find.text('Fare locked'), findsOneWidget);
    expect(
      container.read(riderPaymentSelectionProvider),
      PaymentMethod.card,
    );
    expect(
      recording.paymentMethods,
      everyElement(PaymentMethod.card.backendValue),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
