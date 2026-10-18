import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/main.dart' as app;

const _frame = Duration(milliseconds: 100);
const _waitLimit = Duration(seconds: 10);
const _routeWarning =
    'Unsupported route changes must be confirmed before requesting a driver.';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android Rider Demo reaches booking review without submitting',
      (tester) async {
    // Fail before bootstrap can initialize a hosted client. Exercise the
    // normal unconfigured app, without repository or session overrides.
    expect(defaultTargetPlatform, TargetPlatform.android);
    expect(
      EnvConfig.supabaseUrl.isEmpty &&
          EnvConfig.supabasePublishableKey.isEmpty &&
          !EnvConfig.hasMapsConfig,
      isTrue,
      reason: 'Run this smoke test without backend or Maps dart-defines.',
    );

    await app.main();
    await _waitFor(tester, find.text('Book rides in seconds'));
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await _capture(binding, tester, '01-onboarding');

    await _tap(tester, find.text('Next'));
    expect(find.text('Track every moment'), findsOneWidget);
    await _tap(tester, find.text('Next'));
    expect(find.text('Built for reliable demos'), findsOneWidget);
    await _tap(tester, find.text('Continue'));
    await _waitFor(tester, find.text('Continue as Demo Rider'));
    await _tap(tester, find.text('Continue as Demo Rider'));
    await _waitFor(tester, find.text('Where to?'));
    await _capture(binding, tester, '02-rider-home');

    await _tap(tester, find.text('Where to?'));
    expect(find.text('Choose destination'), findsOneWidget);
    final destination = find.byKey(const ValueKey('destination-search-field'));
    await _show(tester, _button('Choose pickup'));
    expect(_readButton(tester, 'Choose pickup').onPressed, isNull);
    await _show(tester, destination);
    await tester.enterText(destination, 'zzzznomatch987');
    final noResults = find.text('No matching places found.');
    await _waitFor(tester, noResults);
    await _capture(binding, tester, '03-no-results');

    await tester.enterText(destination, 'Abdali');
    final destinationResult =
        find.byKey(const ValueKey('destination-prediction-0'));
    await _waitFor(tester, destinationResult);
    expect(find.text('Abdali Mall'), findsOneWidget);
    await _tap(tester, destinationResult);
    FocusManager.instance.primaryFocus?.unfocus();
    await _settle(tester);
    expect(noResults, findsNothing);
    await _show(tester, _button('Choose pickup'));
    expect(_readButton(tester, 'Choose pickup').onPressed, isNotNull);
    await _tap(tester, _button('Choose pickup'));

    expect(find.text('Choose pickup'), findsOneWidget);
    await _show(tester, _button('Confirm pickup point'));
    expect(_readButton(tester, 'Confirm pickup point').onPressed, isNull);
    final pickup = find.byKey(const ValueKey('pickup-search-field'));
    await _show(tester, pickup);
    await tester.enterText(pickup, 'Hashemite');
    final pickupResult = find.byKey(const ValueKey('pickup-prediction-0'));
    await _waitFor(tester, pickupResult);
    expect(find.text('Hashemite University'), findsOneWidget);
    await _tap(tester, pickupResult);
    FocusManager.instance.primaryFocus?.unfocus();
    await _settle(tester);
    await _waitFor(tester, find.byKey(const ValueKey('route-ready')));
    await _show(tester, _button('Confirm pickup point'));
    expect(_readButton(tester, 'Confirm pickup point').onPressed, isNotNull);
    await _tap(tester, _button('Confirm pickup point'));

    expect(find.text('Choose your ride'), findsOneWidget);
    await _show(tester, _button('Choose a ride'));
    expect(_readButton(tester, 'Choose a ride').onPressed, isNull);
    await _tap(tester, find.byKey(const ValueKey('vehicle-economy')));
    await _show(tester, _button('Choose Economy'));
    expect(_readButton(tester, 'Choose Economy').onPressed, isNotNull);
    await _tap(tester, find.byKey(const ValueKey('vehicle-standard')));

    final cash = find.byKey(const ValueKey('cash-payment-option'));
    final card = find.byKey(const ValueKey('card-payment-option'));
    await _tap(tester, cash);
    _expectSelected(tester, cash, true);
    _expectSelected(tester, card, false);
    await _tap(tester, card);
    _expectSelected(tester, card, true);
    _expectSelected(tester, cash, false);
    expect(
      find.text('Card selected as a method only. Real card payment processing '
          'is not available yet.'),
      findsOneWidget,
    );
    await _capture(binding, tester, '04-card-selected');
    await _tap(tester, cash);
    _expectSelected(tester, cash, true);
    _expectSelected(tester, card, false);
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);

    await _tap(tester, _button('Choose Standard'));
    expect(find.text('Review booking'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Card'), findsNothing);
    expect(find.text('Demo fare'), findsOneWidget);
    expect(find.text('JOD 5.80'), findsOneWidget);
    expect(find.byKey(const ValueKey('route-ready')), findsOneWidget);
    expect(find.byKey(const ValueKey('route-unavailable')), findsNothing);
    expect(find.text(_routeWarning), findsNothing);

    final confirm = _button('Confirm & find a driver');
    await _show(tester, confirm);
    expect(_readButton(tester, 'Confirm & find a driver').onPressed, isNotNull);
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
    await _capture(binding, tester, '05-cash-booking-review');

    // Exercise back navigation through the real AppBar, retaining selection.
    await _tap(tester, find.byTooltip('Back'));
    expect(find.text('Choose your ride'), findsOneWidget);
    await _show(tester, cash);
    _expectSelected(tester, cash, true);
    await _tap(tester, _button('Choose Standard'));
    await _show(tester, confirm);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text(_routeWarning), findsNothing);
    expect(_readButton(tester, 'Confirm & find a driver').onPressed, isNotNull);
    expect(find.text('Matching you with a nearby driver'), findsNothing);
    _expectNoFlutterErrors(tester);

    binding.reportData!.addAll({
      'mode': 'demo',
      'vehicle': 'Standard',
      'payment': 'Cash',
      'tripSubmitted': false,
      'paymentExecuted': false,
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Finder _button(String label) => find.byWidgetPredicate(
      (widget) => widget is AppButton && widget.label == label,
      description: 'AppButton "$label"',
    );

AppButton _readButton(WidgetTester tester, String label) =>
    tester.widget<AppButton>(_button(label));

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  final deadline = tester.binding.clock.now().add(_waitLimit);
  while (finder.evaluate().isEmpty &&
      tester.binding.clock.now().isBefore(deadline)) {
    await tester.pump(_frame);
    _expectNoFlutterErrors(tester);
  }
  expect(finder, findsOneWidget, reason: 'Timed out waiting for $finder');
  await _settle(tester);
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    240,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 20,
  );
  await _settle(tester);
  expect(finder.hitTestable(), findsOneWidget);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _show(tester, finder);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
      _frame, EnginePhase.sendSemanticsUpdate, _waitLimit);
  _expectNoFlutterErrors(tester);
}

void _expectSelected(WidgetTester tester, Finder finder, bool selected) {
  expect(tester.widget<Semantics>(finder).properties.selected, selected);
}

void _expectNoFlutterErrors(WidgetTester tester) {
  expect(tester.takeException(), isNull, reason: 'Flutter framework error');
}

Future<void> _capture(IntegrationTestWidgetsFlutterBinding binding,
    WidgetTester tester, String name) async {
  await _settle(tester);
  expect(await binding.takeScreenshot(name), isNotEmpty);
  _expectNoFlutterErrors(tester);
}
