import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_booking_search.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/rider_trip_tracking_repository.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/features/booking/presentation/screens/canonical_ride_searching_screen.dart';

import 'helpers/fake_rider_booking_search_repository.dart';
import 'helpers/fake_rider_trip_tracking_repository.dart';

const _rider = AppUser(
  id: riderIdFixture,
  name: 'Test Rider',
  email: 'rider@example.com',
  role: RideRole.rider,
);

class _SessionForTest extends SessionController {
  _SessionForTest(this.initial);

  final SessionState initial;

  @override
  SessionState build() => initial;

  void publish(SessionState next) => state = next;
}

ProviderContainer _container(SessionState session) => ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(() => _SessionForTest(session)),
      ],
    );

Future<void> _pumpScreen(
  WidgetTester tester,
  ProviderContainer container, {
  required FakeRiderBookingSearchRepository repository,
  RiderTripTrackingRepository? tripTrackingRepository,
  String bookingId = riderBookingIdFixture,
  Duration softTimeout = const Duration(seconds: 90),
  Duration readDeadline = const Duration(seconds: 15),
}) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: CanonicalRideSearchingScreen(
        bookingRequestId: bookingId,
        repository: repository,
        tripTrackingRepository: tripTrackingRepository,
        softTimeout: softTimeout,
        readDeadline: readDeadline,
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets(
      'bounded assignment polling reads same booking, pauses in background and stops on disposal',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final repository = FakeRiderBookingSearchRepository(
        authenticatedRiderId: riderIdFixture,
        booking: riderBookingSearchFixture());
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: CanonicalRideSearchingScreen(
          bookingRequestId: riderBookingIdFixture,
          repository: repository,
          assignmentPollInterval: const Duration(seconds: 2),
          softTimeout: const Duration(seconds: 10),
        ))));
    await tester.pump();
    expect(repository.readCount, 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(repository.readCount, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 2));
    expect(repository.readCount, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(repository.readCount, 3);
    await tester.pump(const Duration(seconds: 5));
    expect(repository.readCount, 4);
    await tester.pump(const Duration(seconds: 4));
    expect(repository.readCount, 4);
    expect(find.text('Taking longer than expected'), findsOneWidget);
    expect(repository.requestedBookingIds.toSet(), {riderBookingIdFixture});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('missing original booking is unresolved, not a no-driver result',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final repository = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
    );
    await _pumpScreen(tester, container, repository: repository);
    await tester.pump();

    expect(find.text('Booking status unresolved'), findsOneWidget);
    expect(find.text('Booking: $riderBookingIdFixture'), findsNothing);
    expect(find.textContaining('No driver found'), findsNothing);
    expect(find.text('Driver assignment unavailable'), findsOneWidget);
    expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('canonical-search-cancel')),
            )
            .onPressed,
        isNull);
    expect(container.read(activeTripControllerProvider), isNull);

    repository.onRead = (_) async => throw StateError('read unavailable');
    await tester.tap(find.byKey(const ValueKey('canonical-search-retry')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Booking status unavailable'), findsOneWidget);
    expect(find.text('Booking status unresolved'), findsNothing);
    expect(find.textContaining('No driver found'), findsNothing);
    expect(repository.requestedBookingIds,
        [riderBookingIdFixture, riderBookingIdFixture]);
  });

  testWidgets('searching and matched without a Trip never assert no Driver',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final repository = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      booking: riderBookingSearchFixture(),
    );
    final trips = FakeRiderTripTrackingRepository();
    addTearDown(trips.close);
    await _pumpScreen(tester, container,
        repository: repository, tripTrackingRepository: trips);
    await tester.pump();

    expect(find.text('Searching for a driver'), findsOneWidget);
    expect(find.textContaining('Driver assignment is unverified.'),
        findsOneWidget);
    expect(find.text('Driver assignment unavailable'), findsOneWidget);
    expect(trips.bookingLoadCount, 0);
    expect(find.textContaining('No driver found'), findsNothing);

    repository.booking = riderBookingSearchFixture(
        status: RiderBookingSearchStatus.matched, version: 4);
    await tester.tap(find.byKey(const ValueKey('canonical-search-retry')));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Match reported'), findsOneWidget);
    expect(find.text('No verified assigned Trip yet'), findsOneWidget);
    expect(
        find.textContaining('Driver details are unavailable.'), findsOneWidget);
    expect(find.textContaining('No driver found'), findsNothing);
    expect(trips.requestedBookingIds, [riderBookingIdFixture]);
    expect(container.read(activeTripControllerProvider), isNull);
    expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('canonical-search-assignment')),
            )
            .onPressed,
        isNull);
  });

  testWidgets('local entry and exit preserve the original booking ID',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final repository = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      booking: riderBookingSearchFixture(),
    );
    final trips = FakeRiderTripTrackingRepository();
    addTearDown(trips.close);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => CanonicalRideSearchingScreen(
                  bookingRequestId: riderBookingIdFixture,
                  repository: repository,
                  tripTrackingRepository: trips,
                ),
              )),
              child: const Text('Open original booking'),
            ),
          );
        }),
      ),
    ));

    await tester.tap(find.text('Open original booking'));
    await tester.pumpAndSettle();
    expect(find.text('Booking: $riderBookingIdFixture'), findsOneWidget);
    expect(repository.requestedBookingIds, [riderBookingIdFixture]);
    final leave = tester
        .widget<AppButton>(
          find.byKey(const ValueKey('canonical-search-back')),
        )
        .onPressed!;

    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Unrelated route')),
    ));
    await tester.pumpAndSettle();
    leave(); // A cached action cannot pop a newer route.
    await tester.pumpAndSettle();
    expect(find.text('Unrelated route'), findsOneWidget);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('canonical-search-back')));
    await tester.pumpAndSettle();
    expect(find.text('Open original booking'), findsOneWidget);
    expect(container.read(activeTripControllerProvider), isNull);

    repository.booking = riderBookingSearchFixture(
        status: RiderBookingSearchStatus.matched, version: 4);
    await tester.tap(find.text('Open original booking'));
    await tester.pumpAndSettle();
    expect(find.text('Booking: $riderBookingIdFixture'), findsOneWidget);
    expect(find.text('Match reported'), findsOneWidget);
    expect(find.text('No verified assigned Trip yet'), findsOneWidget);
    expect(repository.requestedBookingIds,
        [riderBookingIdFixture, riderBookingIdFixture]);
    expect(trips.requestedBookingIds, [riderBookingIdFixture]);
    expect(container.read(activeTripControllerProvider), isNull);
    await tester.tap(find.byKey(const ValueKey('canonical-search-back')));
    await tester.pumpAndSettle();
    expect(find.text('Open original booking'), findsOneWidget);
  });

  testWidgets('confirmed and searching use the original booking only',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final repository = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      booking: riderBookingSearchFixture(
        status: RiderBookingSearchStatus.confirmed,
      ),
    );
    await _pumpScreen(tester, container, repository: repository);
    await tester.pump();

    expect(find.text('Waiting for matching'), findsOneWidget);
    expect(find.text('Verified booking status: confirmed'), findsOneWidget);
    expect(container.read(activeTripControllerProvider), isNull);
    final cancel = tester.widget<AppButton>(
      find.byKey(const ValueKey('canonical-search-cancel')),
    );
    expect(cancel.onPressed, isNotNull);
    repository.booking = riderBookingSearchFixture(version: 4);
    await tester.tap(find.byKey(const ValueKey('canonical-search-retry')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Searching for a driver'), findsOneWidget);
    expect(find.text('Verified booking status: searching'), findsOneWidget);
    expect(find.textContaining('No driver found'), findsNothing);
    expect(repository.requestedBookingIds,
        [riderBookingIdFixture, riderBookingIdFixture]);
    expect(container.read(activeTripControllerProvider), isNull);
  });

  testWidgets('soft timeout does not change booking status or create a request',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final repository = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      booking: riderBookingSearchFixture(),
    );
    await _pumpScreen(
      tester,
      container,
      repository: repository,
      softTimeout: const Duration(seconds: 5),
    );
    await tester.pump();
    expect(find.text('Searching for a driver'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Taking longer than expected'), findsOneWidget);
    expect(find.text('Verified booking status: searching'), findsOneWidget);
    expect(find.textContaining('No driver found'), findsNothing);
    expect(repository.readCount, 1);
    expect(container.read(activeTripControllerProvider), isNull);
  });

  testWidgets(
      'read deadline is separate from feedback timeout and permits retry',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final abandoned = Completer<RiderBookingSearchSnapshot?>();
    var calls = 0;
    final repository = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      onRead: (_) => ++calls == 1
          ? abandoned.future
          : Future.value(riderBookingSearchFixture()),
    );
    await _pumpScreen(
      tester,
      container,
      repository: repository,
      readDeadline: const Duration(seconds: 3),
      softTimeout: const Duration(seconds: 30),
    );
    expect(find.text('Checking your booking'), findsOneWidget);
    expect(find.text('Booking: $riderBookingIdFixture'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Booking status unavailable'), findsOneWidget);
    expect(find.textContaining('No driver found'), findsNothing);
    expect(repository.readCount, 1);

    await tester.tap(find.byKey(const ValueKey('canonical-search-retry')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Searching for a driver'), findsOneWidget);
    expect(repository.requestedBookingIds,
        [riderBookingIdFixture, riderBookingIdFixture]);
    abandoned.completeError(StateError('late abandoned error'));
    await tester.pump();
    expect(find.text('Searching for a driver'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated retry taps share one read and never create a Trip',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final gate = Completer<RiderBookingSearchSnapshot?>();
    var retrying = false;
    final repository = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      onRead: (_) =>
          retrying ? gate.future : Future.value(riderBookingSearchFixture()),
    );
    await _pumpScreen(tester, container, repository: repository);
    await tester.pump();
    retrying = true;
    final retry = tester
        .widget<AppButton>(
          find.byKey(const ValueKey('canonical-search-retry')),
        )
        .onPressed!;
    retry();
    retry();
    await tester.pump();
    expect(repository.readCount, 2);
    expect(find.text('Checking your booking'), findsOneWidget);
    gate.complete(riderBookingSearchFixture());
    await tester.pump();
    await tester.pump();
    expect(find.text('Searching for a driver'), findsOneWidget);
    expect(repository.requestedBookingIds,
        [riderBookingIdFixture, riderBookingIdFixture]);
    expect(container.read(activeTripControllerProvider), isNull);
  });

  testWidgets('network and malformed reads remain unresolved, not no-driver',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final repository = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      onRead: (_) async => throw StateError('network down'),
    );
    await _pumpScreen(tester, container, repository: repository);
    await tester.pump();
    expect(find.text('Booking status unavailable'), findsOneWidget);
    expect(find.textContaining('No driver found'), findsNothing);

    repository.onRead = (_) async => riderBookingSearchFixture(
          bookingRequestId: secondaryRiderBookingIdFixture,
        );
    await tester.tap(find.byKey(const ValueKey('canonical-search-retry')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Booking status unresolved'), findsOneWidget);
    expect(find.textContaining('No driver found'), findsNothing);
  });

  testWidgets('verified terminal and matched statuses do not claim assignment',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final repository = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      booking: riderBookingSearchFixture(
        status: RiderBookingSearchStatus.expired,
      ),
    );
    for (final (status, title) in [
      (RiderBookingSearchStatus.expired, 'Search expired'),
      (RiderBookingSearchStatus.failed, 'Search failed'),
      (RiderBookingSearchStatus.cancelled, 'Booking cancelled'),
      (RiderBookingSearchStatus.matched, 'Match reported'),
    ]) {
      repository.booking = riderBookingSearchFixture(status: status);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpScreen(tester, container, repository: repository);
      await tester.pump();
      expect(find.text(title), findsOneWidget);
      expect(find.text('Verified booking status: ${status.backendValue}'),
          findsOneWidget);
      final assignment = tester.widget<AppButton>(
        find.byKey(const ValueKey('canonical-search-assignment')),
      );
      expect(assignment.onPressed, isNull);
    }
    expect(find.text('Driver assignment pending verification'), findsOneWidget);
    expect(container.read(activeTripControllerProvider), isNull);
  });

  testWidgets('loading session starts a fresh read on Rider authentication',
      (tester) async {
    final container = _container(const SessionState.loading());
    addTearDown(container.dispose);
    final repository = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      booking: riderBookingSearchFixture(),
    );
    await _pumpScreen(tester, container, repository: repository);
    expect(find.text('Booking status unresolved'), findsOneWidget);
    expect(find.text('Booking: $riderBookingIdFixture'), findsNothing);
    expect(repository.readCount, 0);

    (container.read(sessionControllerProvider.notifier) as _SessionForTest)
        .publish(SessionState.fromUser(_rider));
    await tester.pump();
    await tester.pump();
    expect(find.text('Searching for a driver'), findsOneWidget);
    expect(find.text('Booking: $riderBookingIdFixture'), findsOneWidget);
    expect(repository.readCount, 1);
  });

  testWidgets('same-Rider refresh reverifies and discards the old result',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final oldRead = Completer<RiderBookingSearchSnapshot?>();
    final newRead = Completer<RiderBookingSearchSnapshot?>();
    var readCount = 0;
    final repository = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      onRead: (_) => ++readCount == 1 ? oldRead.future : newRead.future,
    );
    await _pumpScreen(tester, container, repository: repository);
    expect(repository.readCount, 1);
    final session =
        container.read(sessionControllerProvider.notifier) as _SessionForTest;
    session.publish(SessionState.fromUser(_rider));
    await tester.pump();
    expect(repository.readCount, 2);
    expect(find.text('Booking: $riderBookingIdFixture'), findsNothing);
    oldRead.complete(riderBookingSearchFixture(
      status: RiderBookingSearchStatus.failed,
    ));
    await tester.pump();
    expect(find.text('Search failed'), findsNothing);
    newRead.complete(riderBookingSearchFixture());
    await tester.pump();
    await tester.pump();
    expect(find.text('Searching for a driver'), findsOneWidget);
    expect(find.text('Booking: $riderBookingIdFixture'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('canonical-search-retry')),
          )
          .onPressed,
      isNotNull,
    );
    session.publish(const SessionState.unauthenticated());
    await tester.pump();
    expect(find.text('Booking status unresolved'), findsOneWidget);
    expect(find.text('Booking: $riderBookingIdFixture'), findsNothing);
    expect(repository.readCount, 2);

    session.publish(SessionState.fromUser(_rider));
    await tester.pump();
    await tester.pump();
    expect(find.text('Searching for a driver'), findsOneWidget);
    expect(repository.readCount, 3);
  });

  testWidgets('Rider switch clears an already displayed canonical booking',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final repository = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      booking: riderBookingSearchFixture(),
    );
    await _pumpScreen(tester, container, repository: repository);
    await tester.pump();
    expect(find.text('Verified booking status: searching'), findsOneWidget);
    expect(find.text('Booking: $riderBookingIdFixture'), findsOneWidget);

    (container.read(sessionControllerProvider.notifier) as _SessionForTest)
        .publish(SessionState.fromUser(const AppUser(
      id: unrelatedRiderIdFixture,
      name: 'Other Rider',
      email: 'other@example.com',
      role: RideRole.rider,
    )));
    await tester.pump();
    expect(find.text('Booking status unresolved'), findsOneWidget);
    expect(find.text('Verified booking status: searching'), findsNothing);
    expect(find.text('Booking: $riderBookingIdFixture'), findsNothing);
    expect(repository.readCount, 1);
  });

  testWidgets(
      'different Rider cannot attach while the original read is pending',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final oldRead = Completer<RiderBookingSearchSnapshot?>();
    final repository = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      onRead: (_) => oldRead.future,
    );
    await _pumpScreen(tester, container, repository: repository);
    expect(repository.readCount, 1);

    (container.read(sessionControllerProvider.notifier) as _SessionForTest)
        .publish(SessionState.fromUser(const AppUser(
      id: unrelatedRiderIdFixture,
      name: 'Other Rider',
      email: 'other@example.com',
      role: RideRole.rider,
    )));
    await tester.pump();
    oldRead.complete(riderBookingSearchFixture(
      version: 4,
      status: RiderBookingSearchStatus.matched,
    ));
    await tester.pump();
    await tester.pump();

    expect(repository.readCount, 1);
    expect(find.text('Booking status unresolved'), findsOneWidget);
    expect(find.text('Match reported'), findsNothing);
    expect(find.text('Booking: $riderBookingIdFixture'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocked and wrong-role sessions hide the previous locator',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final repository = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      booking: riderBookingSearchFixture(),
    );
    await _pumpScreen(tester, container, repository: repository);
    await tester.pump();
    expect(find.text('Booking: $riderBookingIdFixture'), findsOneWidget);
    final session =
        container.read(sessionControllerProvider.notifier) as _SessionForTest;
    for (final changed in [
      SessionState.fromUser(const AppUser(
        id: riderIdFixture,
        name: 'Blocked Rider',
        email: 'blocked@example.com',
        role: RideRole.rider,
        isBlocked: true,
      )),
      SessionState.fromUser(const AppUser(
        id: riderIdFixture,
        name: 'Driver',
        email: 'driver@example.com',
        role: RideRole.driver,
      )),
      const SessionState.unauthenticated(),
    ]) {
      session.publish(changed);
      await tester.pump();
      expect(find.text('Booking: $riderBookingIdFixture'), findsNothing);
      expect(find.text('Verified booking status: searching'), findsNothing);
      expect(repository.readCount, 1);
    }
  });

  testWidgets('feedback timeout is cancelled on invalidation and disposal',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final repository = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      booking: riderBookingSearchFixture(),
    );
    await _pumpScreen(tester, container,
        repository: repository, softTimeout: const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Searching for a driver'), findsOneWidget);
    (container.read(sessionControllerProvider.notifier) as _SessionForTest)
        .publish(const SessionState.unauthenticated());
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Booking status unresolved'), findsOneWidget);
    expect(find.text('Taking longer than expected'), findsNothing);

    (container.read(sessionControllerProvider.notifier) as _SessionForTest)
        .publish(SessionState.fromUser(_rider));
    await tester.pump();
    await tester.pump();
    expect(find.text('Searching for a driver'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('default standalone screen cannot fall back to mock data',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: CanonicalRideSearchingScreen(
          bookingRequestId: riderBookingIdFixture,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Booking status unavailable'), findsOneWidget);
    expect(container.read(activeTripControllerProvider), isNull);
  });

  testWidgets('booking switch and disposal ignore stale completions',
      (tester) async {
    final container = _container(SessionState.fromUser(_rider));
    addTearDown(container.dispose);
    final oldRead = Completer<RiderBookingSearchSnapshot?>();
    final repository = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      onRead: (id) => id == riderBookingIdFixture
          ? oldRead.future
          : Future.value(riderBookingSearchFixture(
              bookingRequestId: secondaryRiderBookingIdFixture,
              status: RiderBookingSearchStatus.confirmed,
            )),
    );
    await _pumpScreen(tester, container, repository: repository);
    expect(repository.readCount, 1);
    await _pumpScreen(
      tester,
      container,
      repository: repository,
      bookingId: secondaryRiderBookingIdFixture,
    );
    await tester.pump();
    oldRead.completeError(StateError('late old booking error'));
    await tester.pump();
    expect(find.text('Waiting for matching'), findsOneWidget);
    expect(find.text('Searching for a driver'), findsNothing);
    expect(tester.takeException(), isNull);

    final lateRead = Completer<RiderBookingSearchSnapshot?>();
    repository.onRead = (_) => lateRead.future;
    await tester.tap(find.byKey(const ValueKey('canonical-search-retry')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    lateRead.completeError(StateError('late disposal error'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(container.read(activeTripControllerProvider), isNull);
  });
}
