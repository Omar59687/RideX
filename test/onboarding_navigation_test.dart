import 'package:flutter_test/flutter_test.dart';
import 'helpers/test_app.dart';

void main() {
  testWidgets('onboarding Continue opens the shared sign-in flow',
      (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Track every moment'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Built for reliable demos'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('onboarding Skip opens the shared sign-in flow', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
  });
}
