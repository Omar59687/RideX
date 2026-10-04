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
        routeRepositoryProvider.overrideWithValue(
          const MockRouteRepository(),
        ),
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
    return tester.widget<AppButton>(
      find.widgetWithText(AppButton, label),
    );
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
}
