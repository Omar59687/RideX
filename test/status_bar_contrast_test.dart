import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness scaffold applies contrasting status-bar icons',
        (tester) async {
      _configureStatusBar(tester);

      await tester.pumpWidget(_app(brightness));
      await tester.pumpAndSettle();

      _expectStatusBar(brightness);
      expect(find.text('Choose destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('status-bar appearance updates when the active theme changes',
      (tester) async {
    _configureStatusBar(tester);

    for (final brightness in [
      Brightness.light,
      Brightness.dark,
      Brightness.light,
    ]) {
      await tester.pumpWidget(_app(brightness));
      await tester.pumpAndSettle();

      _expectStatusBar(brightness);
      expect(tester.takeException(), isNull);
    }
  });
}

void _configureStatusBar(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 900);
  tester.view.padding = const FakeViewPadding(top: 24);
  tester.view.viewPadding = const FakeViewPadding(top: 24);
  addTearDown(tester.view.reset);
}

Widget _app(Brightness brightness) {
  return MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    home: const AppScaffold(
      title: 'Choose destination',
      body: Text('Rider content'),
    ),
  );
}

void _expectStatusBar(Brightness brightness) {
  final style = SystemChrome.latestStyle;
  expect(style, isNotNull);
  expect(
    style!.statusBarIconBrightness,
    brightness == Brightness.light ? Brightness.dark : Brightness.light,
  );
  expect(style.statusBarBrightness, brightness);
  expect(style.statusBarColor, Colors.transparent);
}
