import 'package:flutter_test/flutter_test.dart';
import 'helpers/test_app.dart';

void main() {
  testWidgets('role selection updates and signs into driver demo',
      (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Driver'));
    await tester.pumpAndSettle();

    expect(find.text('Continue as Demo Driver'), findsOneWidget);

    await tester.tap(find.text('Continue as Demo Driver'));
    await tester.pumpAndSettle();

    expect(find.text('Driver mode'), findsOneWidget);
  });
}
