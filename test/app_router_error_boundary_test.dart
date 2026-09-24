import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/router/app_router.dart';

import 'helpers/recording_error_reporter.dart';

void main() {
  testWidgets('navigation errors use fixed copy and report raw details once',
      (tester) async {
    final error = StateError(rawErrorCanary);
    final reporter = RecordingAppErrorReporter();

    await tester.pumpWidget(
      MaterialApp(
        home: NavigationErrorScreen(
          error: error,
          errorReporter: reporter,
        ),
      ),
    );

    expect(find.text("We couldn't open this page"), findsOneWidget);
    expect(
      find.text('Return to the previous screen and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining(rawErrorCanary), findsNothing);
    expect(reporter.reports, hasLength(1));
    expect(reporter.reports.single.error, same(error));

    await tester.pump();
    expect(reporter.reports, hasLength(1));
  });
}
