import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/app.dart';

void main() {
  testWidgets('shows a sanitized initialization failure', (tester) async {
    await tester.pumpWidget(const RideXInitializationFailureApp());

    expect(find.text('Unable to start RideX'), findsOneWidget);
    expect(
      find.text('RideX could not start safely. Please contact support.'),
      findsOneWidget,
    );
    expect(find.textContaining('SUPABASE'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });
}
