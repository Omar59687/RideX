import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/test_app.dart';
import 'package:ridex/features/rider_home/presentation/screens/rider_home_screen.dart';

void main() {
  for (final entry in ['Where to?', 'View all', 'Abdali Mall']) {
    testWidgets('system Back from $entry booking entry returns to Rider home',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildTestApp());
      await tester.pump(const Duration(milliseconds: 950));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue as Demo Rider'));
      await tester.tap(find.text('Continue as Demo Rider'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(entry));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry));
      await tester.pumpAndSettle();
      expect(
          find.text(
              entry == 'Abdali Mall' ? 'Choose pickup' : 'Choose destination'),
          findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(RiderHomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('rider can move through mock booking flow', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    final demo = find.text('Continue as Demo Rider');
    await tester.ensureVisible(demo);
    await tester.tap(demo);
    await tester.pumpAndSettle();

    expect(find.text('Where to?'), findsOneWidget);
    await tester.tap(find.text('Where to?'));
    await tester.pumpAndSettle();
    expect(find.text('Choose destination'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('destination-search-field')),
      'Abdali',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Abdali Mall').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Choose pickup'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Choose pickup'));
    await tester.pumpAndSettle();
    expect(find.text('Choose pickup'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('pickup-search-field')),
      'Hashemite',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Hashemite University').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Confirm pickup point'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Confirm pickup point'));
    await tester.pumpAndSettle();
    expect(find.text('Economy'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Premium'), findsOneWidget);
    await tester.tap(find.text('Standard'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Choose Standard'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Choose Standard'));
    await tester.pumpAndSettle();
    expect(find.text('Review booking'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Confirm & find a driver'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Confirm & find a driver'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('Matching you with a nearby driver'), findsOneWidget);
    await tester.tap(find.text('Demo: Driver found'));
    await tester.pumpAndSettle();

    expect(find.text('Driver found'), findsOneWidget);
  });
}
