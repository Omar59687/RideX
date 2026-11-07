import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_booking_cancellation.dart';
import 'package:ridex/core/models/rider_booking_search.dart';
import 'package:ridex/core/providers/rider_cancellation_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/rider_trip_tracking_repository.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart';

import 'helpers/fake_rider_booking_cancellation_repository.dart';
import 'helpers/fake_rider_booking_search_repository.dart';
import 'helpers/fake_rider_trip_tracking_repository.dart';

const _rider = AppUser(
  id: riderIdFixture,
  name: 'Test Rider',
  email: 'rider@example.com',
  role: RideRole.rider,
);

const _cancelKey = ValueKey('canonical-search-cancel');
const _retryKey = ValueKey('canonical-search-retry');

class _SessionForTest extends SessionController {
  _SessionForTest(this.initial);

  final SessionState initial;

  @override
  SessionState build() => initial;

  void publish(SessionState next) => state = next;
}

ProviderContainer _container(
  SessionState session, {
  FakeRiderBookingCancellationRepository? cancellationRepository,
}) =>
    ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(() => _SessionForTest(session)),
        riderCancellationRepositoryProvider.overrideWithValue(
          cancellationRepository ?? FakeRiderBookingCancellationRepository(),
        ),
      ],
    );

Future<void> _pumpScreen(
  WidgetTester tester,
  ProviderContainer container, {
  required FakeRiderBookingSearchRepository repository,
  RiderTripTrackingRepository? tripTrackingRepository,
  GlobalKey<NavigatorState>? navigatorKey,
  Duration softTimeout = const Duration(seconds: 90),
  Duration readDeadline = const Duration(seconds: 15),
}) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      navigatorKey: navigatorKey,
      home: CanonicalRideSearchingScreen(
        bookingRequestId: riderBookingIdFixture,
        repository: repository,
        tripTrackingRepository: tripTrackingRepository,
        softTimeout: softTimeout,
        readDeadline: readDeadline,
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

FakeRiderBookingSearchRepository _reads({
  RiderBookingSearchStatus status = RiderBookingSearchStatus.searching,
  int version = 3,
}) {
  return FakeRiderBookingSearchRepository(
    authenticatedRiderId: riderIdFixture,
    booking: riderBookingSearchFixture(status: status, version: version),
  );
}

AppButton _cancelButton(WidgetTester tester) =>
    tester.widget<AppButton>(find.byKey(_cancelKey));

Finder _dialogConfirm() => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Cancel booking'),
    );

Future<void> _confirmDialog(WidgetTester tester, {String? reason}) async {
  await tester.pumpAndSettle();
  if (reason != null) {
    await tester.tap(find.byKey(ValueKey('cancellation-reason-$reason')));
    await tester.pump();
  }
  await tester.tap(_dialogConfirm());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cancel control follows verified status and phase',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final repository = _reads();

    for (final (status, enabled) in [
      (RiderBookingSearchStatus.confirmed, true),
      (RiderBookingSearchStatus.searching, true),
      (RiderBookingSearchStatus.matched, false),
      (RiderBookingSearchStatus.cancelled, false),
      (RiderBookingSearchStatus.expired, false),
      (RiderBookingSearchStatus.failed, false),
      (RiderBookingSearchStatus.draft, false),
    ]) {
      repository.booking = riderBookingSearchFixture(status: status);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpScreen(tester, container, repository: repository);
      expect(
        _cancelButton(tester).onPressed != null,
        enabled,
        reason: status.name,
      );
    }

    repository.booking = riderBookingSearchFixture();
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpScreen(
      tester,
      container,
      repository: repository,
      softTimeout: const Duration(seconds: 2),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Taking longer than expected'), findsOneWidget);
    expect(_cancelButton(tester).onPressed, isNotNull);
  });

  testWidgets('reason dialog dispatches exactly one typed cancellation',
      (tester) async {
    final cancels = FakeRiderBookingCancellationRepository(
      result: RiderBookingCancellationAccepted(
        riderBookingSearchFixture(
          version: 4,
          status: RiderBookingSearchStatus.cancelled,
        ),
      ),
    );
    final container = _container(
      SessionState.fromUser(_rider),
      cancellationRepository: cancels,
    );
    addTearDown(container.dispose);
    await _pumpScreen(
      tester,
      container,
      repository: _reads(),
    );

    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this booking?'), findsOneWidget);
    expect(
      find.text('Choose a reason for cancelling this booking.'),
      findsOneWidget,
    );
    expect(find.textContaining('Your Driver will be told'), findsNothing);
    expect(find.text('Keep booking'), findsOneWidget);
    expect(
      tester
          .widget<RadioListTile<String>>(
            find.byKey(
              const ValueKey('cancellation-reason-Changed my mind'),
            ),
          )
          .groupValue,
      'Changed my mind',
    );

    await _confirmDialog(tester, reason: 'Booked by mistake');

    expect(cancels.cancelCount, 1);
    expect(cancels.requests.single.expectedVersion, 3);
    expect(cancels.requests.single.reasonCode, 'Booked by mistake');
    expect(find.text('Booking cancelled'), findsOneWidget);
    expect(find.text('Cancellation outcome unknown'), findsNothing);
    expect(_cancelButton(tester).onPressed, isNull);
  });

  testWidgets('Keep booking dismisses without dispatch', (tester) async {
    final cancels = FakeRiderBookingCancellationRepository(
      result: RiderBookingCancellationAccepted(
        riderBookingSearchFixture(
          version: 4,
          status: RiderBookingSearchStatus.cancelled,
        ),
      ),
    );
    final container = _container(
      SessionState.fromUser(_rider),
      cancellationRepository: cancels,
    );
    addTearDown(container.dispose);
    await _pumpScreen(
      tester,
      container,
      repository: _reads(),
    );

    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep booking'));
    await tester.pumpAndSettle();

    expect(cancels.cancelCount, 0);
    expect(find.text('Searching for a driver'), findsOneWidget);
    expect(_cancelButton(tester).onPressed, isNotNull);
  });

  testWidgets('unknown outcome never claims success and stays blocked',
      (tester) async {
    final container = _container(
      SessionState.fromUser(_rider),
      cancellationRepository: FakeRiderBookingCancellationRepository(
        result: const RiderBookingCancellationUnknown(),
      ),
    );
    addTearDown(container.dispose);
    final repository = _reads();
    await _pumpScreen(
      tester,
      container,
      repository: repository,
    );

    await tester.tap(find.byKey(_cancelKey));
    await _confirmDialog(tester);

    expect(find.text('Cancellation outcome unknown'), findsOneWidget);
    expect(find.text('Booking cancelled'), findsNothing);
    expect(_cancelButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(_retryKey));
    await tester.pump();
    await tester.pump();

    expect(find.text('Searching for a driver'), findsOneWidget);
    expect(find.text('Cancellation outcome unknown'), findsOneWidget);
    expect(find.text('Booking cancelled'), findsNothing);
    expect(_cancelButton(tester).onPressed, isNull);
  });

  testWidgets('stale rejection rereads and permits one user retry',
      (tester) async {
    final repository = _reads();
    final cancels = FakeRiderBookingCancellationRepository(
      result: const RiderBookingCancellationRejected(
        RiderCancellationRejection.staleVersion,
      ),
    );
    final container = _container(
      SessionState.fromUser(_rider),
      cancellationRepository: cancels,
    );
    addTearDown(container.dispose);
    await _pumpScreen(
      tester,
      container,
      repository: repository,
    );

    repository.booking = riderBookingSearchFixture(version: 6);
    await tester.tap(find.byKey(_cancelKey));
    await _confirmDialog(tester);

    expect(find.text('Cancellation not sent'), findsOneWidget);
    expect(find.text('Searching for a driver'), findsOneWidget);
    expect(repository.readCount, 2);
    expect(cancels.cancelCount, 1);
    expect(_cancelButton(tester).onPressed, isNotNull);

    cancels.result = RiderBookingCancellationAccepted(
      riderBookingSearchFixture(
        version: 7,
        status: RiderBookingSearchStatus.cancelled,
      ),
    );
    await tester.tap(find.byKey(_cancelKey));
    await _confirmDialog(tester);

    expect(cancels.cancelCount, 2);
    expect(cancels.requests.last.expectedVersion, 6);
    expect(find.text('Booking cancelled'), findsOneWidget);
  });

  testWidgets('controller replacement keeps one pending cancellation',
      (tester) async {
    final gate = Completer<RiderBookingCancellationResult>();
    final cancels = FakeRiderBookingCancellationRepository(
      onCancel: (_) => gate.future,
    );
    final container = _container(
      SessionState.fromUser(_rider),
      cancellationRepository: cancels,
    );
    addTearDown(container.dispose);
    await _pumpScreen(
      tester,
      container,
      repository: _reads(),
    );

    await tester.tap(find.byKey(_cancelKey));
    await _confirmDialog(tester);
    expect(find.text('Cancelling booking'), findsOneWidget);

    final replacement = _reads();
    await _pumpScreen(
      tester,
      container,
      repository: replacement,
    );
    await tester.pump();

    expect(find.text('Cancelling booking'), findsOneWidget);
    expect(_cancelButton(tester).onPressed, isNull);
    expect(cancels.cancelCount, 1);
    expect(replacement.readCount, 0);

    gate.complete(RiderBookingCancellationAccepted(
      riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.cancelled,
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Booking cancelled'), findsOneWidget);
    expect(cancels.cancelCount, 1);
  });

  testWidgets('independent remounts and same-Rider refresh retain ownership',
      (tester) async {
    final gate = Completer<RiderBookingCancellationResult>();
    final cancels = FakeRiderBookingCancellationRepository(
      onCancel: (_) => gate.future,
    );
    final container = _container(
      SessionState.fromUser(_rider),
      cancellationRepository: cancels,
    );
    addTearDown(container.dispose);
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    final reads = _reads();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, shown, __) => shown
              ? CanonicalRideSearchingScreen(
                  bookingRequestId: riderBookingIdFixture,
                  repository: reads,
                )
              : const Scaffold(body: Text('Screen retired')),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(_cancelKey));
    await _confirmDialog(tester);
    expect(cancels.cancelCount, 1);

    for (var i = 0; i < 2; i++) {
      visible.value = false;
      await tester.pump();
      expect(find.text('Screen retired'), findsOneWidget);
      visible.value = true;
      await tester.pump();
      expect(find.text('Cancelling booking'), findsOneWidget);
      expect(_cancelButton(tester).onPressed, isNull);
      (container.read(sessionControllerProvider.notifier) as _SessionForTest)
          .publish(SessionState.fromUser(_rider));
      await tester.pump();
      expect(find.text('Cancelling booking'), findsOneWidget);
      expect(cancels.cancelCount, 1);
    }

    gate.complete(RiderBookingCancellationAccepted(
      riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.cancelled,
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Booking cancelled'), findsOneWidget);
    expect(cancels.cancelCount, 1);
  });

  testWidgets('controller replacement dismisses its open dialog',
      (tester) async {
    final cancels = FakeRiderBookingCancellationRepository();
    final container = _container(
      SessionState.fromUser(_rider),
      cancellationRepository: cancels,
    );
    addTearDown(container.dispose);
    await _pumpScreen(tester, container, repository: _reads());

    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await _pumpScreen(tester, container, repository: _reads());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(cancels.cancelCount, 0);
  });

  testWidgets('session change removes only its dialog below another route',
      (tester) async {
    final cancels = FakeRiderBookingCancellationRepository();
    final container = _container(
      SessionState.fromUser(_rider),
      cancellationRepository: cancels,
    );
    addTearDown(container.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();
    await _pumpScreen(
      tester,
      container,
      repository: _reads(),
      navigatorKey: navigatorKey,
    );

    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Unrelated route')),
    ));
    await tester.pumpAndSettle();

    (container.read(sessionControllerProvider.notifier) as _SessionForTest)
        .publish(const SessionState.unauthenticated());
    await tester.pumpAndSettle();

    expect(find.text('Unrelated route'), findsOneWidget);
    expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
    expect(cancels.cancelCount, 0);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Booking status unresolved'), findsOneWidget);
  });

  testWidgets('screen disposal removes its open dialog without dispatch',
      (tester) async {
    final cancels = FakeRiderBookingCancellationRepository();
    final container = _container(
      SessionState.fromUser(_rider),
      cancellationRepository: cancels,
    );
    addTearDown(container.dispose);
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, shown, __) => shown
              ? CanonicalRideSearchingScreen(
                  bookingRequestId: riderBookingIdFixture,
                  repository: _reads(),
                )
              : const Scaffold(body: Text('Screen retired')),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    visible.value = false;
    await tester.pumpAndSettle();

    expect(find.text('Screen retired'), findsOneWidget);
    expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
    expect(cancels.cancelCount, 0);
  });

  testWidgets('same-Rider session replacement dismisses an open dialog',
      (tester) async {
    final cancels = FakeRiderBookingCancellationRepository();
    final container = _container(
      SessionState.fromUser(_rider),
      cancellationRepository: cancels,
    );
    addTearDown(container.dispose);
    await _pumpScreen(
      tester,
      container,
      repository: _reads(),
    );

    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    (container.read(sessionControllerProvider.notifier) as _SessionForTest)
        .publish(SessionState.fromUser(_rider));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(cancels.cancelCount, 0);
    expect(find.text('Searching for a driver'), findsOneWidget);
  });

  testWidgets('logout dismisses an open dialog without dispatch',
      (tester) async {
    final cancels = FakeRiderBookingCancellationRepository();
    final container = _container(
      SessionState.fromUser(_rider),
      cancellationRepository: cancels,
    );
    addTearDown(container.dispose);
    await _pumpScreen(
      tester,
      container,
      repository: _reads(),
    );

    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    (container.read(sessionControllerProvider.notifier) as _SessionForTest)
        .publish(const SessionState.unauthenticated());
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(cancels.cancelCount, 0);
    expect(find.text('Booking status unresolved'), findsOneWidget);
  });

  testWidgets('verified assignment never exposes Driver details',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    await _pumpScreen(
      tester,
      container,
      repository: _reads(
        status: RiderBookingSearchStatus.matched,
        version: 4,
      ),
      tripTrackingRepository:
          FakeRiderTripTrackingRepository(trip: riderAssignedTripFixture()),
    );

    expect(find.text('Match reported'), findsOneWidget);
    expect(
      find.text(
        'An assigned Trip was verified for this original booking. '
        'Driver details are not displayed in this slice.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'An assigned Trip has not been verified. Driver details are unavailable.',
      ),
      findsNothing,
    );
    expect(
      find.text(
        'Assignment verified. Driver details are not displayed in this slice.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Test Make'), findsNothing);
    expect(find.textContaining('Test pickup'), findsNothing);
  });

  testWidgets('failed assignment verification is reported as unavailable',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final trips = FakeRiderTripTrackingRepository()
      ..bookingLoadError = StateError('assignment read failed');
    await _pumpScreen(
      tester,
      container,
      repository: _reads(status: RiderBookingSearchStatus.matched),
      tripTrackingRepository: trips,
    );

    expect(find.text('Assignment verification unavailable'), findsOneWidget);
  });

  testWidgets('session change during cancellation drops the late result',
      (tester) async {
    final gate = Completer<RiderBookingCancellationResult>();
    final container = _container(
      SessionState.fromUser(_rider),
      cancellationRepository: FakeRiderBookingCancellationRepository(
        onCancel: (_) => gate.future,
      ),
    );
    addTearDown(container.dispose);
    await _pumpScreen(
      tester,
      container,
      repository: _reads(),
    );

    await tester.tap(find.byKey(_cancelKey));
    await _confirmDialog(tester);
    expect(find.text('Cancelling booking'), findsOneWidget);

    (container.read(sessionControllerProvider.notifier) as _SessionForTest)
        .publish(const SessionState.unauthenticated());
    await tester.pump();
    expect(find.text('Booking status unresolved'), findsOneWidget);

    gate.complete(RiderBookingCancellationAccepted(
      riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.cancelled,
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Booking cancelled'), findsNothing);
    expect(find.text('Booking status unresolved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
