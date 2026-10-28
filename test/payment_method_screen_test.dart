import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/services/fare/pending_fare_lock_store.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/features/booking/presentation/providers/rider_payment_selection_provider.dart';
import 'package:ridex/features/booking/presentation/screens/payment_method_screen.dart';

class _MemoryLockStore implements PendingFareLockStore {
  @override
  Future<void> clearForRider(String riderId) async {}

  @override
  Future<PendingFareLock?> loadForRider(String riderId) async => null;

  @override
  Future<PendingFareLockSlot> inspectForRider(String riderId) async =>
      const PendingFareLockSlot.absent();

  @override
  Future<void> save(PendingFareLock command) async {}
}

FareQuote _quote() => FareQuote(
      id: 'quote-r08',
      bookingRequestId: 'booking-r08',
      quoteVersion: 1,
      pricingVersion: 1,
      fixedFareFils: 2150,
      breakdown: const FareBreakdown(
        baseFareFils: 500,
        distanceFils: 1200,
        durationFils: 300,
        stopsFils: 150,
        subtotalFils: 2150,
        minimumFareFils: 1000,
        roundingIncrementFils: 50,
        fixedFareFils: 2150,
      ),
      status: FareQuoteStatus.locked,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );

void main() {
  testWidgets('session-local Cash cannot authorize missing canonical handoff',
      (tester) async {
    final container = ProviderContainer(overrides: [
      pendingFareLockStoreProvider.overrideWithValue(_MemoryLockStore()),
    ]);
    addTearDown(container.dispose);
    await container.read(sessionControllerProvider.notifier).refreshSession();
    await container.read(sessionControllerProvider.notifier).continueAsDemo();
    final riderId = container.read(sessionControllerProvider).user!.id;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: PaymentMethodScreen(
          data: PaymentMethodRouteData(quote: _quote(), riderId: riderId),
        ),
      ),
    ));

    expect(find.text('Payment Method'), findsOneWidget);
    expect(find.text('Currently unavailable'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('JOD 2.15'), findsNothing);
    expect(find.text('Illustrative values'), findsNothing);
    expect(find.text('Payment method unavailable'), findsOneWidget);
    expect(
      tester.widget<AppButton>(find.byType(AppButton).first).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Card stays unavailable and cannot continue', (tester) async {
    final container = ProviderContainer(overrides: [
      pendingFareLockStoreProvider.overrideWithValue(_MemoryLockStore()),
    ]);
    addTearDown(container.dispose);
    await container.read(sessionControllerProvider.notifier).refreshSession();
    await container.read(sessionControllerProvider.notifier).continueAsDemo();
    final riderId = container.read(sessionControllerProvider).user!.id;
    container.read(riderPaymentSelectionProvider.notifier).selectCard();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: PaymentMethodScreen(
          data: PaymentMethodRouteData(quote: _quote(), riderId: riderId),
        ),
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.text('Payment method unavailable'), findsOneWidget);
    expect(find.text('Currently unavailable'), findsOneWidget);
    expect(
        find.textContaining('No card details are collected'), findsOneWidget);
    expect(
      tester.widget<AppButton>(find.byType(AppButton).first).onPressed,
      isNull,
    );
    expect(tester.widget<AppButton>(find.byType(AppButton).first).onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing fare handoff fails closed', (tester) async {
    final container = ProviderContainer(overrides: [
      pendingFareLockStoreProvider.overrideWithValue(_MemoryLockStore()),
    ]);
    addTearDown(container.dispose);
    await container.read(sessionControllerProvider.notifier).refreshSession();
    await container.read(sessionControllerProvider.notifier).continueAsDemo();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const PaymentMethodScreen(data: null),
      ),
    ));

    expect(
        find.textContaining('payment method, or Rider session is unavailable'),
        findsOneWidget);
    expect(
      tester.widget<AppButton>(find.byType(AppButton).first).onPressed,
      isNull,
    );
  });

  testWidgets('stale Rider identity disables continuation', (tester) async {
    final container = ProviderContainer(overrides: [
      pendingFareLockStoreProvider.overrideWithValue(_MemoryLockStore()),
    ]);
    addTearDown(container.dispose);
    await container.read(sessionControllerProvider.notifier).refreshSession();
    await container.read(sessionControllerProvider.notifier).continueAsDemo();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: PaymentMethodScreen(
          data: PaymentMethodRouteData(quote: _quote(), riderId: 'other-rider'),
        ),
      ),
    ));

    expect(find.textContaining('Rider session is unavailable'), findsOneWidget);
    expect(
      tester.widget<AppButton>(find.byType(AppButton).first).onPressed,
      isNull,
    );
  });

  testWidgets('fits the supported phone widths without layout exceptions',
      (tester) async {
    final container = ProviderContainer(overrides: [
      pendingFareLockStoreProvider.overrideWithValue(_MemoryLockStore()),
    ]);
    addTearDown(container.dispose);
    await container.read(sessionControllerProvider.notifier).refreshSession();
    await container.read(sessionControllerProvider.notifier).continueAsDemo();
    final riderId = container.read(sessionControllerProvider).user!.id;

    for (final size in const [
      Size(360, 800),
      Size(390, 844),
      Size(430, 932),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: PaymentMethodScreen(
            data: PaymentMethodRouteData(quote: _quote(), riderId: riderId),
          ),
        ),
      ));
      expect(tester.takeException(), isNull, reason: 'layout $size');
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
