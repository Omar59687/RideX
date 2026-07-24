import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_text_styles.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/widgets/ride_x_bottom_navigation.dart';

import 'helpers/test_app.dart';

void main() {
  test('light and dark themes expose the RideX semantic extension', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.extension<RideXTheme>(), isNotNull);
    expect(dark.extension<RideXTheme>(), isNotNull);
    expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
    expect(light.scaffoldBackgroundColor, const Color(0xFFF8F5F0));
    expect(light.colorScheme.surface, const Color(0xFFFFFFFF));
    expect(light.colorScheme.onSurface, const Color(0xFF242233));
    expect(light.colorScheme.onSurfaceVariant, const Color(0xFF6F6B7D));
    expect(light.colorScheme.outline, const Color(0xFFE2DEEB));
    expect(
        light.extension<RideXTheme>()!.brandedPanel, const Color(0xFF19162B));
  });

  testWidgets('RideX remains light when the device requests dark mode',
      (tester) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );

    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
  });

  testWidgets('themes resolve bundled Plus Jakarta Sans weights',
      (tester) async {
    const fontAssets = {
      'assets/fonts/PlusJakartaSans-Regular.ttf': FontWeight.w400,
      'assets/fonts/PlusJakartaSans-Medium.ttf': FontWeight.w500,
      'assets/fonts/PlusJakartaSans-SemiBold.ttf': FontWeight.w600,
      'assets/fonts/PlusJakartaSans-Bold.ttf': FontWeight.w700,
      'assets/fonts/PlusJakartaSans-ExtraBold.ttf': FontWeight.w800,
    };

    for (final asset in [...fontAssets.keys, 'assets/fonts/OFL.txt']) {
      expect((await rootBundle.load(asset)).lengthInBytes, greaterThan(0));
    }

    final textTheme = AppTheme.light().textTheme;
    final representativeStyles = {
      textTheme.bodyMedium: FontWeight.w400,
      textTheme.bodyLarge: FontWeight.w500,
      textTheme.titleMedium: FontWeight.w600,
      textTheme.headlineLarge: FontWeight.w700,
      textTheme.displayLarge: FontWeight.w800,
    };
    for (final entry in representativeStyles.entries) {
      expect(entry.key?.fontFamily, AppTextStyles.fontFamily);
      expect(entry.key?.fontWeight, entry.value);
    }
  });

  testWidgets(
      'rider core flow fits compact large-text reduced-motion presentation',
      (tester) async {
    await _configureView(
      tester,
      size: const Size(390, 844),
      textScaleFactor: 1.3,
      disableAnimations: true,
    );
    await tester.pumpWidget(buildTestApp());
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Skip'));
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continue as Demo Rider'));
    await tester.tap(find.text('Continue as Demo Rider'));
    await tester.pumpAndSettle();

    expect(find.text('Where to?'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Where to?'));
    await tester.pumpAndSettle();
    expect(find.text('Plan your route'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('Abdali Mall').first,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Abdali Mall').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'pickup screen');
    await tester.ensureVisible(find.text('Confirm pickup point'));
    await tester.tap(find.text('Confirm pickup point'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'vehicle screen');
    await tester.ensureVisible(find.text('Standard'));
    await tester.tap(find.text('Standard'));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('vehicle-standard')))
          .hasFlag(SemanticsFlag.isSelected),
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.text('Choose Standard'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Choose Standard'));
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -80),
    );
    await tester.pump();
    await tester.tap(find.text('Choose Standard'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'fare screen');
    await tester.scrollUntilVisible(
      find.text('Confirm & find a driver'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Confirm & find a driver'));
    await tester.tap(find.text('Confirm & find a driver'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull, reason: 'searching screen');
    await tester.ensureVisible(find.text('Demo: Driver found'));
    await tester.tap(find.text('Demo: Driver found'));
    await tester.pumpAndSettle();

    expect(find.text('Driver found'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'active trip screen');
  });

  testWidgets('rider tab screens remain light at 430x932 in dark mode',
      (tester) async {
    await _configureView(tester, size: const Size(430, 932));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(
      tester.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    await tester.pumpWidget(buildTestApp());
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Skip'));
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue as Demo Rider'));
    await tester.pumpAndSettle();

    expect(Theme.of(tester.element(find.text('Where to?'))).brightness,
        Brightness.light);
    for (final label in ['History', 'Profile', 'Settings', 'Home']) {
      await tester.tap(
        find.widgetWithText(NavigationDestination, label),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label tab');
    }

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'notifications screen');
  });

  testWidgets('rider bottom navigation has selected semantics and 44px targets',
      (tester) async {
    await _configureView(tester, size: const Size(430, 932));
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            bottomNavigationBar: RideXBottomNavigation(currentIndex: 1),
          ),
        ),
        for (final path in [
          '/rider/home',
          '/history',
          '/rider/profile',
          '/settings',
        ])
          GoRoute(path: path, builder: (_, __) => Text(path)),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
    await tester.pumpAndSettle();

    final semantics = tester.getSemantics(find.text('History'));
    expect(semantics.hasFlag(SemanticsFlag.isSelected), isTrue);
    for (final label in ['Home', 'History', 'Profile', 'Settings']) {
      final destination = find.ancestor(
        of: find.text(label),
        matching: find.byType(NavigationDestination),
      );
      expect(destination, findsOneWidget, reason: label);
      final target = tester.getSize(destination);
      expect(target.width, greaterThanOrEqualTo(44), reason: label);
      expect(target.height, greaterThanOrEqualTo(44), reason: label);
    }

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('/settings'), findsOneWidget);
  });
}

Future<void> _configureView(
  WidgetTester tester, {
  required Size size,
  double textScaleFactor = 1,
  bool disableAnimations = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: disableAnimations);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
  });
}
