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
    await tester.tap(find.text('Continue as Demo Rider'));
    await tester.pumpAndSettle();

    expect(find.text('Where are you going?'), findsOneWidget);
    await tester.tap(find.text('Where are you going?'));
    await tester.pumpAndSettle();
    expect(find.text('Choose pickup'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('My current location'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('My current location'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Abdali Mall'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Abdali Mall'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taxi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search for driver'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('Matching you with a nearby driver'), findsOneWidget);
    await tester.tap(find.text('Demo: Driver found'));
    await tester.pumpAndSettle();

    expect(find.text('Driver found'), findsOneWidget);
  });
}
