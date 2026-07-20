import 'package:flutter_test/flutter_test.dart';
import 'helpers/test_app.dart';

void main() {
  testWidgets('app launches from splash into onboarding', (tester) async {
    await tester.pumpWidget(buildTestApp());

    expect(find.text('RideX'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    expect(find.text('Book rides in seconds'), findsOneWidget);
  });
}
