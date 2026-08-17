import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/test_app.dart';

void main() {
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
