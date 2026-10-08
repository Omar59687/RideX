import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/fare_repository.dart';
import 'package:ridex/core/repositories/mock_place_repository.dart';
import 'package:ridex/core/repositories/mock_route_repository.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/features/booking/presentation/screens/fare_estimate_screen.dart';

/// Provisional Phase 5 widget coverage for route-based fixed fares.
///
/// Flutter never calculates fares: the configured path displays the
/// backend-computed [FareQuote] (breakdown, total, quote version, expiry),
/// while the unconfigured path keeps the clearly marked deterministic demo
/// fare. Expiry never backs a total: expired quotes show a re-quote prompt.
void main() {
  ProviderContainer createContainer({FareRepository? fareRepository}) {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => MockAuthRepository()),
        bookingRepositoryProvider.overrideWith(
          (ref) => MockBookingRepository(),
        ),
        placeRepositoryProvider.overrideWith((ref) => MockPlaceRepository()),
        routeRepositoryProvider.overrideWithValue(const MockRouteRepository()),
        if (fareRepository != null)
          fareRepositoryProvider.overrideWith((ref) => fareRepository),
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

  AppButton confirmButton(
    WidgetTester tester, {
    String label = 'Confirm & find a driver',
  }) {
    return tester.widget<AppButton>(find.widgetWithText(AppButton, label));
  }

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
      final container = createContainer(fareRepository: FakeFareRepository());
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

  testWidgets('expired quotes show a re-quote prompt and never a stale total', (
    tester,
  ) async {
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
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
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
  });

  testWidgets('lost successful lock response replays the original request', (
    tester,
  ) async {
    final repository = _ControlledLockRepository(loseFirstResponse: true);
    final container = createContainer(fareRepository: repository);
    readyDraft(container);
    await pumpFareScreen(tester, container);
    await tester.scrollUntilVisible(
      find.text('Lock fare'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Lock fare'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Retry fare lock'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Fare lock not confirmed'), findsOneWidget);
    expect(find.text('Retry fare request'), findsNothing);
    expect(find.text('Fare locked'), findsNothing);
    await tester.tap(find.text('Retry fare lock'));
    await tester.pumpAndSettle();

    expect(repository.lockRequests, hasLength(2));
    expect(repository.lockRequests[1], repository.lockRequests[0]);
    expect(repository.calls.where((call) => call == 'create'), hasLength(1));
    expect(
      repository.calls.where((call) => call.startsWith('quote ')),
      hasLength(1),
    );
    expect(
      repository.calls.where((call) => call.startsWith('update ')),
      isEmpty,
    );
    await tester.scrollUntilVisible(
      find.text('Fare locked'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(confirmButton(tester, label: 'Fare locked').onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lock transport failure before commit can be retried', (
    tester,
  ) async {
    final repository = _ControlledLockRepository();
    final container = createContainer(fareRepository: repository);
    readyDraft(container);
    await pumpFareScreen(tester, container);
    repository.failNext(const FareException(FareFailure.networkFailure));
    await tester.scrollUntilVisible(
      find.text('Lock fare'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Lock fare'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Retry fare lock'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Retry fare lock'));
    await tester.pumpAndSettle();

    expect(repository.lockRequests, hasLength(2));
    expect(repository.lockRequests[1], repository.lockRequests[0]);
    expect(
      repository.quotesFor('booking-fake-1').single.status,
      FareQuoteStatus.locked,
    );
    expect(
      repository.calls.where((call) => call.startsWith('update ')),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rapid lock submissions make only one in-flight request', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repository = _ControlledLockRepository(lockGate: gate);
    final container = createContainer(fareRepository: repository);
    readyDraft(container);
    await pumpFareScreen(tester, container);
    await tester.scrollUntilVisible(
      find.text('Lock fare'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final submit = confirmButton(tester, label: 'Lock fare').onPressed!;
    submit();
    submit();
    await tester.pump();
    expect(repository.lockRequests, hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();
    expect(
      repository.quotesFor('booking-fake-1').single.status,
      FareQuoteStatus.locked,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('editing a locked fare updates with the post-lock version', (
    tester,
  ) async {
    final repository = _ControlledLockRepository();
    final container = createContainer(fareRepository: repository);
    readyDraft(container);
    await pumpFareScreen(tester, container);
    await tester.scrollUntilVisible(
      find.text('Lock fare'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Lock fare'));
    await tester.pumpAndSettle();

    container
        .read(bookingControllerProvider.notifier)
        .setVehicleType(MockData.vehicleTypes[1]);
    await tester.pumpAndSettle();
    expect(repository.calls, contains('update booking-fake-1@2'));
    expect(repository.calls.where((call) => call == 'create'), hasLength(1));
    expect(find.text('Fare unavailable'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Lock fare'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(confirmButton(tester, label: 'Lock fare').onPressed, isNotNull);
    await tester.tap(find.text('Lock fare'));
    await tester.pumpAndSettle();
    expect(repository.lockRequests.last['bookingVersion'], 3);
    expect(find.text('Fare locked'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an edit waits for the unresolved original lock to recover', (
    tester,
  ) async {
    final repository = _ControlledLockRepository(loseFirstResponse: true);
    final container = createContainer(fareRepository: repository);
    readyDraft(container);
    await pumpFareScreen(tester, container);
    await tester.scrollUntilVisible(
      find.text('Lock fare'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Lock fare'));
    await tester.pumpAndSettle();

    container
        .read(bookingControllerProvider.notifier)
        .setVehicleType(MockData.vehicleTypes[1]);
    await tester.pumpAndSettle();
    expect(
      repository.calls.where((call) => call.startsWith('update ')),
      isEmpty,
    );
    expect(
      repository.calls.where((call) => call.startsWith('quote ')),
      hasLength(1),
    );
    await tester.scrollUntilVisible(
      find.text('Retry fare lock'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Retry fare lock'));
    await tester.pumpAndSettle();

    expect(repository.lockRequests[1], repository.lockRequests[0]);
    expect(repository.calls, contains('update booking-fake-1@2'));
    expect(
      repository.calls.where((call) => call.startsWith('quote ')),
      hasLength(2),
    );
    expect(find.text('Fare lock not confirmed'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'version conflict cannot silently overwrite or reprice a booking',
    (tester) async {
      final repository = _ControlledLockRepository();
      final container = createContainer(fareRepository: repository);
      readyDraft(container);
      await pumpFareScreen(tester, container);
      repository.failNext(const FareException(FareFailure.versionConflict));
      await tester.scrollUntilVisible(
        find.text('Lock fare'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Lock fare'));
      await tester.pumpAndSettle();
      container
          .read(bookingControllerProvider.notifier)
          .setVehicleType(MockData.vehicleTypes[1]);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Fare lock not confirmed'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(
        find.text(
          'This booking changed elsewhere. '
          'Return home and start a new booking.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry fare lock'), findsNothing);
      expect(find.text('Retry fare request'), findsNothing);
      expect(repository.lockRequests, hasLength(1));
      expect(
        repository.calls.where((call) => call.startsWith('update ')),
        isEmpty,
      );
      expect(
        repository.calls.where((call) => call.startsWith('quote ')),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _ControlledLockRepository extends FakeFareRepository {
  _ControlledLockRepository({this.loseFirstResponse = false, this.lockGate});

  final bool loseFirstResponse;
  final Completer<void>? lockGate;
  final List<Map<String, Object>> lockRequests = [];

  @override
  Future<FareQuote> lockQuote({
    required String bookingRequestId,
    required String fareQuoteId,
    required int expectedBookingVersion,
    required int expectedQuoteVersion,
  }) async {
    lockRequests.add({
      'booking': bookingRequestId,
      'quote': fareQuoteId,
      'bookingVersion': expectedBookingVersion,
      'quoteVersion': expectedQuoteVersion,
    });
    await lockGate?.future;
    final locked = await super.lockQuote(
      bookingRequestId: bookingRequestId,
      fareQuoteId: fareQuoteId,
      expectedBookingVersion: expectedBookingVersion,
      expectedQuoteVersion: expectedQuoteVersion,
    );
    if (loseFirstResponse && lockRequests.length == 1) {
      throw const FareException(FareFailure.networkFailure);
    }
    return locked;
  }
}
