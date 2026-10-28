import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/app.dart';
import 'package:ridex/app/router/app_router.dart';
import 'package:ridex/app/theme/appearance_theme_mode_provider.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/features/booking/presentation/screens/payment_method_screen.dart';

import 'helpers/in_memory_appearance_preferences.dart';

void main() {
  testWidgets(
    'Payment Method follows Light, Dark, and System while failing closed',
    (tester) async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );

      final router = GoRouter(
        initialLocation: '/payment-method-test',
        routes: [
          GoRoute(
            path: '/payment-method-test',
            builder: (_, __) => const PaymentMethodScreen(data: null),
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          appearancePreferencesProvider.overrideWithValue(
            InMemoryAppearancePreferences(),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const RideXApp(),
        ),
      );
      await tester.pumpAndSettle();

      void expectPaymentMethodBrightness(Brightness brightness) {
        expect(
          Theme.of(tester.element(find.text('Payment Method'))).brightness,
          brightness,
        );
        expect(find.byType(PaymentMethodScreen), findsOneWidget);
        expect(find.text('Payment method unavailable'), findsOneWidget);
        expect(
          tester.widget<AppButton>(find.byType(AppButton).first).onPressed,
          isNull,
        );
      }

      expect(container.read(appearanceThemeModeProvider), ThemeMode.system);
      expectPaymentMethodBrightness(Brightness.light);

      final controller = container.read(appearanceThemeModeProvider.notifier);
      await controller.setThemeMode(ThemeMode.light);
      await tester.pumpAndSettle();
      expectPaymentMethodBrightness(Brightness.light);

      await controller.setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();
      expectPaymentMethodBrightness(Brightness.dark);

      await controller.setThemeMode(ThemeMode.system);
      await tester.pumpAndSettle();
      expectPaymentMethodBrightness(Brightness.light);

      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await tester.pumpAndSettle();
      expectPaymentMethodBrightness(Brightness.dark);
    },
  );
}
