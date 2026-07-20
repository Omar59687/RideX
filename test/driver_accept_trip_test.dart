import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/test_app.dart';

void main() {
  testWidgets('driver accepts a mock trip request', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Driver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue as Demo Driver'));
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
  });
}
