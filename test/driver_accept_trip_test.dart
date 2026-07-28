import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/test_app.dart';

void main() {
  testWidgets('driver completes the preserved mock trip flow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    });

    await tester.pumpWidget(buildTestApp());
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'driver@ridex.app',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('driver-demo-request-button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('driver-demo-request-button')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -250));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('driver-accept-request-button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Pickup in progress'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Mark arrived'));
    await tester.pump();
    expect(find.text('You have arrived at pickup'), findsOneWidget);
    await tester.tap(find.text('Start trip'));
    await tester.pumpAndSettle();
    expect(find.text('Drive to destination'), findsOneWidget);

    await tester.tap(find.text('Complete trip'));
    await tester.pumpAndSettle();
    expect(find.text('Ride finished successfully'), findsOneWidget);

    await tester.tap(find.text('Open trip history'));
    await tester.pumpAndSettle();
    expect(find.text('Trip history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
