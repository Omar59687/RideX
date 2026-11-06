import 'dart:ui' show SemanticsAction;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/providers/driver_cash_completion_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';
import 'package:ridex/features/driver_flow/presentation/screens/driver_trip_preview_screen.dart';
import 'driver_trip_presentation_controller_test.dart'
    show TripHarness, previewTrip;
import 'driver_trip_preview_screen_test.dart' show reveal;
import 'helpers/fake_driver_flow_repository.dart';

const _stopKey = ValueKey('driver-cash-completion-stop');

void main() {
  Future<void> mount(WidgetTester tester, TripHarness h,
      {bool canonicalFlag = false}) async {
    await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: ProviderScope(
            overrides: [
              driverCashRuntimeEnabledProvider.overrideWithValue(canonicalFlag),
              driverCashCompletionProvider.overrideWith((ref) =>
                  throw StateError(
                      'Preview must not mount canonical completion')),
            ],
            child: MaterialApp(
                theme: AppTheme.light(),
                home: const DriverTripPreviewScreen()))));
    await tester.pump();
  }

  testWidgets('B06 explicit stop gate exists in preview', (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    await h.settle();
    await mount(tester, h);
    await tester.drag(find.byType(Scrollable), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.byKey(_stopKey), findsOneWidget);
    expect(h.repository.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  for (final status in DriverTripLifecycleStatus.values) {
    testWidgets(
        'B06 $status shows disabled completion without payment or receipt success',
        (tester) async {
      final h = TripHarness();
      addTearDown(h.dispose);
      h.repository.current =
          driverFlowSnapshot(trip: previewTrip(status: status));
      await h.settle();
      await mount(tester, h);
      await reveal(tester, find.byKey(_stopKey));
      expect(tester.widget<OutlinedButton>(find.byKey(_stopKey)).onPressed,
          isNull);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(_stopKey));
      }
      await tester.pump();
      expect(h.repository.commands, isEmpty);
      expect(find.text('Cash settlement: not verified.'), findsOneWidget);
      expect(find.text('Payment confirmation: not verified.'), findsOneWidget);
      expect(find.text('Receipt issuance: not verified.'), findsOneWidget);
      expect(find.text('Payment successful'), findsNothing);
      expect(find.text('Receipt verified'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('B06 completion explanation is accessible with gate identifiers',
      (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    await h.settle();
    await mount(tester, h);
    final semantics = tester.ensureSemantics();
    await reveal(tester, find.byKey(_stopKey));
    expect(
        tester
            .getSemantics(find.byKey(_stopKey))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse);
    expect(
        find.textContaining('P6-R01, P6-R02, P6-R03, P6-R07'), findsOneWidget);
    expect(
        find.textContaining('Real completion remains blocked'), findsOneWidget);
    expect(h.repository.commands, isEmpty);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('B06 canonical test flag cannot activate preview completion',
      (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    await h.settle();
    await mount(tester, h, canonicalFlag: true);
    await reveal(tester, find.byKey(_stopKey));
    expect(
        tester.widget<OutlinedButton>(find.byKey(_stopKey)).onPressed, isNull);
    expect(h.repository.commands, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('B06 remount resume and refresh never replay completion',
      (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    await h.settle();
    await mount(tester, h);
    await reveal(tester, find.byKey(_stopKey));
    await tester.tap(find.byKey(_stopKey));
    await tester.pumpWidget(const SizedBox());
    await mount(tester, h);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await h.controller.refresh();
    await tester.pump();
    expect(h.repository.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'B06 completion stop preserves exact integer-fils locked Cash fare',
      (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    await h.settle();
    await mount(tester, h);
    expect(find.text('Locked Cash fare: JOD 1.990'), findsOneWidget);
    await reveal(tester, find.byKey(_stopKey));
    expect(h.repository.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'B06 authorization loss hides summary and open route without completion',
      (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    await h.settle();
    await mount(tester, h);
    await reveal(tester, find.text('View route preview'));
    await tester.tap(find.text('View route preview'));
    await tester.pumpAndSettle();
    expect(find.byType(MapPlaceholder), findsOneWidget);
    h.session.replace(const SessionState.unauthenticated());
    await tester.pump();
    expect(find.byType(MapPlaceholder), findsNothing);
    expect(find.text('Pickup: Pickup', skipOffstage: false), findsNothing);
    expect(h.repository.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('B06 narrow large-text explanation renders without overflow',
      (tester) async {
    final h = TripHarness();
    addTearDown(h.dispose);
    await h.settle();
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: child!),
            home: const DriverTripPreviewScreen())));
    await tester.pump();
    await reveal(tester, find.byKey(_stopKey));
    expect(tester.takeException(), isNull);
    expect(h.repository.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
