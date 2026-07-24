import 'package:flutter_test/flutter_test.dart';
import 'helpers/test_app.dart';

void main() {
  testWidgets('public demo remains Rider-only after selecting Driver',
      (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Driver'));
    await tester.pumpAndSettle();

    expect(find.text('Continue as Demo Rider'), findsOneWidget);

    await tester.tap(find.text('Continue as Demo Rider'));
    await tester.pumpAndSettle();

    expect(find.text('Good morning, Ahmed'), findsOneWidget);
  });
}
