import 'package:flutter_test/flutter_test.dart';
import 'helpers/test_app.dart';

void main() {
  testWidgets('public sign-in exposes only the Rider demo path',
      (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Continue as Demo Rider'), findsOneWidget);
    expect(find.text('Driver'), findsNothing);

    final demo = find.text('Continue as Demo Rider');
    await tester.ensureVisible(demo);
    await tester.tap(demo);
    await tester.pumpAndSettle();

    expect(find.text('Good morning, Ahmed'), findsOneWidget);
  });
}
