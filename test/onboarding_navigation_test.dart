import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/features/onboarding/presentation/screens/onboarding_screen.dart';

import 'helpers/test_app.dart';

void main() {
  for (final height in [0.0, 20.0, 40.0, 800.0]) {
    testWidgets(
        'onboarding renders at $height logical pixels high without layout errors',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_onboardingAtHeight(height));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Book rides in seconds'), findsOneWidget);
    });
  }

  testWidgets('onboarding recovers from zero height and advances slides',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_onboardingAtHeight(0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_onboardingAtHeight(800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Track every moment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding Continue opens the shared sign-in flow',
      (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Track every moment'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Built for reliable demos'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('onboarding Skip opens the shared sign-in flow', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
  });
}

Widget _onboardingAtHeight(double height) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Center(
      child: SizedBox(
        width: 800,
        height: height,
        child: const OnboardingScreen(),
      ),
    ),
  );
}
