import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/repositories/trips_repository.dart';
import 'package:ridex/features/history/presentation/screens/trip_details_screen.dart';
import 'package:ridex/features/history/presentation/screens/trip_history_screen.dart';

const _unavailableCardKey = ValueKey('rider-payment-status-unavailable');

void main() {
  final completed = MockData.history().first;
  final cancelled = MockData.history().last;

  group('Rider history payment integration', () {
    testWidgets(
      'completed trip shows the canonical trip fare and an unavailable '
      'payment state, never a demo card or receipt claim',
      (tester) async {
        await _setLargeTestSurface(tester);
        await tester.pumpWidget(_detailsApp(completed));
        await tester.pumpAndSettle();

        // Canonical trip-level information stays visible.
        expect(find.text('Trip details'), findsOneWidget);
        expect(find.text('Trip completed'), findsOneWidget);
        expect(find.text('Trip fare'), findsOneWidget);
        expect(find.text('Driver & vehicle'), findsOneWidget);
        expect(find.text('Omar'), findsOneWidget);

        // Missing payment linkage is presented as unavailable, not as paid.
        expect(find.text('Payment'), findsOneWidget);
        expect(find.byKey(_unavailableCardKey), findsOneWidget);
        expect(find.text('Payment record unavailable'), findsOneWidget);
        expect(
          find.textContaining('This is not a payment failure'),
          findsOneWidget,
        );

        // No fabricated financial or receipt claims.
        expect(find.textContaining('Demo payment record'), findsNothing);
        expect(find.textContaining('Visa'), findsNothing);
        expect(find.textContaining('2048'), findsNothing);
        expect(find.text('Fare breakdown'), findsNothing);
        expect(find.text('Base fare'), findsNothing);
        expect(find.text('Distance & time'), findsNothing);
        expect(find.text('Promotion'), findsNothing);
        expect(find.text('Total charged'), findsNothing);
        expect(find.text('Payment completed'), findsNothing);
        expect(find.text('Payment captured'), findsNothing);
        expect(find.text('Paid'), findsNothing);
        expect(find.textContaining('Receipt ID'), findsNothing);
        expect(find.textContaining('Receipt number'), findsNothing);
        expect(find.textContaining('Issued'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'cancelled trip keeps its non-payment status and shows no payment card',
      (tester) async {
        await _setLargeTestSurface(tester);
        await tester.pumpWidget(_detailsApp(cancelled));
        await tester.pumpAndSettle();

        expect(find.text('Trip details'), findsOneWidget);
        expect(find.text('Cancelled by rider'), findsOneWidget);
        expect(find.text('Cancellation summary'), findsOneWidget);
        expect(find.text('Trip fare (not charged)'), findsOneWidget);
        expect(
          find.text(
            'No driver, payment, or cancellation fee is recorded for this '
            'request.',
          ),
          findsOneWidget,
        );
        expect(find.text('Driver & vehicle'), findsNothing);
        expect(find.text('Payment'), findsNothing);
        expect(find.byKey(_unavailableCardKey), findsNothing);
        expect(find.text('Total charged'), findsNothing);
        expect(find.text('Fare breakdown'), findsNothing);
        expect(find.textContaining('Demo payment record'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('renders without overflow on a narrow screen', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_detailsApp(completed));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Trip fare'), findsOneWidget);
      expect(find.byKey(_unavailableCardKey), findsOneWidget);
    });
  });

  group('Rider history list payment integration', () {
    testWidgets(
      'still loads, shows trip data, and navigates to the selected trip',
      (tester) async {
        await tester.pumpWidget(_historyApp());
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('history-trip-trip-completed-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('history-trip-trip-cancelled-1')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Hashemite University, Zarqa, Jordan'),
          findsWidgets,
        );

        await tester.tap(
          find.byKey(const Key('history-trip-trip-completed-1')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Opened trip-completed-1'), findsOneWidget);
      },
    );

    testWidgets(
      'completed rows state payment is not confirmed and never claim a '
      'receipt',
      (tester) async {
        await tester.pumpWidget(_historyApp());
        await tester.pumpAndSettle();

        expect(find.text('Payment not confirmed'), findsOneWidget);
        expect(find.textContaining('Demo payment record'), findsNothing);
        expect(find.textContaining('Payment completed'), findsNothing);
        expect(find.textContaining('Visa'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'cancelled rows keep their status and make no payment claim',
      (tester) async {
        await tester.pumpWidget(_historyApp());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('history-filter-cancelled')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('history-trip-trip-cancelled-1')),
          findsOneWidget,
        );
        expect(find.text('Payment not confirmed'), findsNothing);
        expect(find.textContaining('No charge'), findsOneWidget);
        expect(find.textContaining('Demo payment record'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('renders without overflow on a narrow screen', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_historyApp());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Payment not confirmed'), findsOneWidget);
    });
  });
}

Widget _historyApp() {
  final repository = _TestTripsRepository(history: MockData.history());
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

Widget _detailsApp(MockTrip trip) {
  final repository = _TestTripsRepository(
    history: [trip],
    tripsById: {trip.id: trip},
  );
  final router = GoRouter(
    initialLocation: '/history/${trip.id}',
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
        builder: (_, __) => const Scaffold(body: Text('Vehicle route')),
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

class _TestTripsRepository implements TripsRepository {
  _TestTripsRepository({required this.history, this.tripsById = const {}});

  final List<MockTrip> history;
  final Map<String, MockTrip> tripsById;

  @override
  Future<MockTrip> createTrip(BookingDraft draft) async {
    throw UnimplementedError();
  }

  @override
  Future<MockTrip> completeTrip(MockTrip trip) async {
    throw UnimplementedError();
  }

  @override
  Future<List<MockTrip>> getTripHistory() async => history;

  @override
  Future<MockTrip?> getTripById(String id) async => tripsById[id];
}

Future<void> _setLargeTestSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
