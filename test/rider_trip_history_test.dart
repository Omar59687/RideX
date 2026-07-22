import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/trips_repository.dart';
import 'package:ridex/features/history/presentation/screens/trip_details_screen.dart';
import 'package:ridex/features/history/presentation/screens/trip_history_screen.dart';

void main() {
  testWidgets('history shows loading, empty, and retryable error states',
      (tester) async {
    final completer = Completer<List<MockTrip>>();
    final repository = _TestTripsRepository(historyResult: completer.future);
    await tester.pumpWidget(_historyApp(repository));

    expect(find.byKey(const Key('history-loading')), findsOneWidget);
    completer.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('No rides yet'), findsOneWidget);

    final errorCompleter = Completer<List<MockTrip>>();
    repository.historyResult = errorCompleter.future;
    await tester.pumpWidget(_historyApp(repository));
    await tester.pump();
    errorCompleter.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Trips could not be loaded'), findsOneWidget);

    repository.historyResult = Future.value(MockData.history());
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('history-trip-trip-completed-1')), findsOneWidget);
  });

  testWidgets('history filters rides and opens the selected trip',
      (tester) async {
    final repository = _TestTripsRepository(
      historyResult: Future.value(MockData.history()),
    );
    await tester.pumpWidget(_historyApp(repository));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('history-trip-trip-completed-1')), findsOneWidget);
    expect(
        find.byKey(const Key('history-trip-trip-cancelled-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('history-filter-cancelled')));
    await tester.pump();
    expect(
        find.byKey(const Key('history-trip-trip-completed-1')), findsNothing);
    expect(
        find.byKey(const Key('history-trip-trip-cancelled-1')), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('history-trip-trip-cancelled-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Opened trip-cancelled-1'), findsOneWidget);
  });

  testWidgets('completed details show demo receipt and seed rebooking',
      (tester) async {
    await _setLargeTestSurface(tester);
    final completed = MockData.history().first;
    final repository = _TestTripsRepository(
      historyResult: Future.value(MockData.history()),
      tripsById: {completed.id: completed},
    );
    final container = ProviderContainer(
      overrides: [
        tripsRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_detailsApp(container, completed.id));
    await tester.pumpAndSettle();

    expect(find.text('Driver & vehicle'), findsOneWidget);
    expect(find.text('Demo payment record | Visa 2048'), findsOneWidget);
    expect(find.text('Omar'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('rebook-route')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('rebook-route')));
    await tester.pumpAndSettle();
    expect(find.text('Rebooking Hashemite University'), findsOneWidget);
    expect(
      container.read(bookingControllerProvider).destination?.address,
      'Abdali Boulevard',
    );
  });

  testWidgets('cancelled details avoid driver and payment claims and rebook',
      (tester) async {
    await _setLargeTestSurface(tester);
    final cancelled = MockData.history().last;
    final repository = _TestTripsRepository(
      historyResult: Future.value(MockData.history()),
      tripsById: {cancelled.id: cancelled},
    );
    final container = ProviderContainer(
      overrides: [
        tripsRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_detailsApp(container, cancelled.id));
    await tester.pumpAndSettle();

    expect(find.text('Cancellation summary'), findsOneWidget);
    expect(find.text('Driver & vehicle'), findsNothing);
    expect(find.textContaining('Demo payment record'), findsNothing);
    expect(
      find.text(
        'No driver, payment, or cancellation fee is recorded for this request.',
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('rebook-route')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('rebook-route')));
    await tester.pumpAndSettle();
    expect(find.text('Rebooking Hashemite University'), findsOneWidget);
  });

  testWidgets('missing trip offers a route back to history', (tester) async {
    final repository = _TestTripsRepository(
      historyResult: Future.value(const []),
    );
    final container = ProviderContainer(
      overrides: [
        tripsRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_detailsApp(container, 'missing'));
    await tester.pumpAndSettle();

    expect(find.text('Trip not found'), findsOneWidget);
    await tester.tap(find.text('Back to ride history'));
    await tester.pumpAndSettle();
    expect(find.text('History route'), findsOneWidget);
  });

  testWidgets('driver can still access the existing shared history view',
      (tester) async {
    final repository = _TestTripsRepository(
      historyResult: Future.value(MockData.history()),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripsRepositoryProvider.overrideWith((ref) => repository),
          authRepositoryProvider.overrideWith((ref) => _DriverAuthRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const TripHistoryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trip history'), findsOneWidget);
    expect(find.textContaining('Hashemite University -> Abdali Boulevard'),
        findsWidgets);
    expect(find.byKey(const Key('history-filter-all')), findsNothing);
  });
}

Widget _historyApp(_TestTripsRepository repository) {
  final router = GoRouter(
    initialLocation: '/history',
    routes: [
      GoRoute(
        path: '/history',
        builder: (_, __) => const TripHistoryScreen(),
      ),
      GoRoute(
        path: '/history/:tripId',
        builder: (_, state) => Scaffold(
          body: Text('Opened ${state.pathParameters['tripId']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: [
      tripsRepositoryProvider.overrideWith((ref) => repository),
      authRepositoryProvider.overrideWith((ref) => MockAuthRepository()),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: router,
    ),
  );
}

Widget _detailsApp(ProviderContainer container, String tripId) {
  final router = GoRouter(
    initialLocation: '/history/$tripId',
    routes: [
      GoRoute(
        path: '/history',
        builder: (_, __) => const Scaffold(body: Text('History route')),
      ),
      GoRoute(
        path: '/history/:tripId',
        builder: (_, state) => TripDetailsScreen(
          tripId: state.pathParameters['tripId']!,
        ),
      ),
      GoRoute(
        path: '/rider/vehicle',
        builder: (_, __) => const _BookingProbe(),
      ),
    ],
  );
  addTearDown(router.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: router,
    ),
  );
}

class _BookingProbe extends ConsumerWidget {
  const _BookingProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(bookingControllerProvider);
    return Scaffold(body: Text('Rebooking ${booking.pickup?.address}'));
  }
}

class _TestTripsRepository implements TripsRepository {
  _TestTripsRepository({
    required this.historyResult,
    this.tripsById = const {},
  });

  Future<List<MockTrip>> historyResult;
  final Map<String, MockTrip> tripsById;

  @override
  Future<MockTrip> createTrip(BookingDraft draft) async {
    throw UnimplementedError();
  }

  @override
  Future<List<MockTrip>> getTripHistory() => historyResult;

  @override
  Future<MockTrip?> getTripById(String id) async => tripsById[id];
}

class _DriverAuthRepository extends MockAuthRepository {
  @override
  Future<AppUser?> restoreSession() async => MockData.demoDriver;
}

Future<void> _setLargeTestSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
