import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/driver_flow/application/driver_completion_handoff_controller.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_completion_handoff_provider.dart';
import 'package:ridex/features/driver_flow/presentation/screens/driver_completion_status_screen.dart';

import 'helpers/fake_driver_completion_handoff_reader.dart';
import 'helpers/fake_canonical_driver_port.dart' as f;

final class _ApprovedDriverSession extends SessionController {
  @override
  SessionState build() => SessionState.fromUser(
        const AppUser(
          id: f.driverId,
          name: 'Synthetic Driver',
          email: 'driver@example.invalid',
          role: RideRole.driver,
          driverApprovalStatus: DriverApprovalStatus.approved,
        ),
      );
}

void main() {
  testWidgets('missing read owner never shows hard-coded success or fare', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionControllerProvider.overrideWith(_ApprovedDriverSession.new)],
        child: const MaterialApp(
          home: DriverCompletionStatusScreen(tripId: f.tripId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Trip completion details are unavailable or unverified.'),
      findsOneWidget,
    );
    expect(find.text('Ride finished successfully'), findsNothing);
    expect(find.textContaining('JOD'), findsNothing);
    expect(find.textContaining('1.99'), findsNothing);
    expect(find.textContaining('Verified receipt:'), findsNothing);
  });

  testWidgets('Trip completion does not promote unknown Payment or Receipt', (
    tester,
  ) async {
    final reader = FakeDriverCompletionHandoffReader()
      ..paymentState = DriverHandoffReadState.unknown
      ..receiptState = DriverHandoffReadState.unknown;
    final connected = ValueNotifier(true);
    final invalidations = ValueNotifier(0);
    final controller = DriverCompletionHandoffController(
      tripId: f.tripId,
      reader: reader,
      connected: connected,
      authorityInvalidations: invalidations,
    );
    addTearDown(controller.dispose);
    addTearDown(connected.dispose);
    addTearDown(invalidations.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(_ApprovedDriverSession.new),
          driverCompletionStatusProvider(f.tripId)
              .overrideWith((ref) => controller),
        ],
        child: const MaterialApp(
          home: DriverCompletionStatusScreen(tripId: f.tripId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trip completion verified.'), findsOneWidget);
    expect(find.text('Payment status is unavailable or unverified.'),
        findsOneWidget);
    expect(find.text('Receipt status is unavailable or unverified.'),
        findsOneWidget);
    expect(find.textContaining('Verified receipt:'), findsNothing);
    expect(find.textContaining('JOD'), findsNothing);
  });

  testWidgets('only an independent verified receipt number is shown', (
    tester,
  ) async {
    final reader = FakeDriverCompletionHandoffReader()
      ..receiptState = DriverHandoffReadState.verified;
    final connected = ValueNotifier(true);
    final invalidations = ValueNotifier(0);
    final controller = DriverCompletionHandoffController(
      tripId: f.tripId,
      reader: reader,
      connected: connected,
      authorityInvalidations: invalidations,
    );
    addTearDown(controller.dispose);
    addTearDown(connected.dispose);
    addTearDown(invalidations.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(_ApprovedDriverSession.new),
          driverCompletionStatusProvider(f.tripId)
              .overrideWith((ref) => controller),
        ],
        child: const MaterialApp(
          home: DriverCompletionStatusScreen(tripId: f.tripId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Verified receipt: R-005'), findsOneWidget);
    expect(find.text('Cash payment status: cashSelected.'), findsOneWidget);
    expect(find.text('Ride finished successfully'), findsNothing);
  });

  testWidgets('route Trip locator must match the injected authority owner', (
    tester,
  ) async {
    final reader = FakeDriverCompletionHandoffReader();
    final connected = ValueNotifier(true);
    final invalidations = ValueNotifier(0);
    final controller = DriverCompletionHandoffController(
      tripId: f.tripId,
      reader: reader,
      connected: connected,
      authorityInvalidations: invalidations,
    );
    addTearDown(controller.dispose);
    addTearDown(connected.dispose);
    addTearDown(invalidations.dispose);
    const foreignTrip = 'a9000000-0000-4000-8000-000000000099';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(_ApprovedDriverSession.new),
          driverCompletionStatusProvider(foreignTrip)
              .overrideWith((ref) => controller),
        ],
        child: const MaterialApp(
          home: DriverCompletionStatusScreen(tripId: foreignTrip),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Trip completion details are unavailable or unverified.'),
      findsOneWidget,
    );
    expect(find.text('Trip completion verified.'), findsNothing);
    expect(reader.calls, isEmpty);
  });
}
