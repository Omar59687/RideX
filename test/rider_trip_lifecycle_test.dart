import 'dart:async';

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
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/trips_repository.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/features/booking/presentation/screens/ride_request_searching_screen.dart';
import 'package:ridex/features/ratings/presentation/screens/rating_screen.dart';
import 'package:ridex/features/trips/presentation/screens/rider_active_trip_screen.dart';
import 'package:ridex/features/trips/presentation/screens/trip_completion_screen.dart';

void main() {
  testWidgets(
      'rapid search creation is coalesced and accepts before navigation',
      (tester) async {
    final repository = _DelayedTripsRepository();
    final container = ProviderContainer(
      overrides: [
        tripsRepositoryProvider.overrideWith((ref) => repository),
        bookingRepositoryProvider
            .overrideWith((ref) => MockBookingRepository()),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(
          path: '/search',
          builder: (_, __) => const RideRequestSearchingScreen(),
        ),
        GoRoute(
          path: '/rider/trip',
          builder: (_, __) => const _TripStateProbe(),
        ),
        GoRoute(
          path: '/rider/home',
          builder: (_, __) => const Text('Rider home'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_testApp(container, router));
    await tester.pump();
    expect(repository.createCalls, 1);

    final secondCreation =
        container.read(activeTripControllerProvider.notifier).createTrip();
    expect(repository.createCalls, 1);
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('driver-found-button')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('no-driver-button')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('cancel-search-button')))
          .onPressed,
      isNull,
    );

    repository.complete(_trip(status: TripStatus.searching));
    await secondCreation;
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.createCalls, 1);

    await tester.tap(find.byKey(const ValueKey('driver-found-button')));
    await tester.pumpAndSettle();
    expect(find.text('Navigated with accepted'), findsOneWidget);
    expect(
      container.read(activeTripControllerProvider)?.status,
      TripStatus.accepted,
    );
  });

  testWidgets('confirmed rider cancellation uses the valid status transition',
      (tester) async {
    await _setLargeTestSurface(tester);
    final container = ProviderContainer(
      overrides: [
        activeTripControllerProvider.overrideWith(
          () => _SeededActiveTripController(_trip()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/rider/trip',
      routes: [
        GoRoute(
          path: '/rider/trip',
          builder: (_, __) => const RiderActiveTripScreen(),
        ),
        GoRoute(
          path: '/rider/home',
          builder: (_, __) => const Scaffold(body: Text('Rider home')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(_testApp(container, router));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const ValueKey('cancel-active-trip-button')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Cancel this ride?'), findsOneWidget);
    await tester.tap(find.text('Cancel ride').last);
    await tester.pumpAndSettle();

    expect(
      container.read(activeTripControllerProvider)?.status,
      TripStatus.cancelledByRider,
    );
    expect(find.text('Rider home'), findsOneWidget);
  });

  testWidgets('active route renders every rider status from provider state',
      (tester) async {
    await _setLargeTestSurface(tester);
    final container = ProviderContainer(
      overrides: [
        activeTripControllerProvider.overrideWith(
          () => _SeededActiveTripController(_trip()),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const RiderActiveTripScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Driver assigned'), findsOneWidget);
    expect(find.text('Nadia'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('JOD 7.35'), findsOneWidget);

    final controller = container.read(activeTripControllerProvider.notifier);
    controller.setStatus(TripStatus.driverArriving);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Driver arriving'), findsWidgets);
    controller.setStatus(TripStatus.driverArrived);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Driver has arrived'), findsOneWidget);
    controller.setStatus(TripStatus.inProgress);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Trip in progress'), findsOneWidget);
  });

  testWidgets('rider completion uses active trip fare route driver and cash',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        activeTripControllerProvider.overrideWith(
          () => _SeededActiveTripController(
            _trip(status: TripStatus.completed),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const TripCompletionScreen(isDriverView: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('JOD 7.35'), findsNWidgets(2));
    expect(find.text('Payment: Cash'), findsOneWidget);
    expect(find.text('Campus gate'), findsOneWidget);
    expect(find.text('City centre'), findsOneWidget);
    expect(find.text('Nadia'), findsOneWidget);
  });

  testWidgets('rating identifies active trip driver and discloses demo storage',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        activeTripControllerProvider.overrideWith(
          () => _SeededActiveTripController(
            _trip(status: TripStatus.completed),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const RatingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('How was Nadia?'), findsOneWidget);
    expect(find.text('Omar'), findsNothing);
    expect(
      find.text(
          'Demo only: this rating stays in this session and is not saved.'),
      findsOneWidget,
    );
    expect(find.text('Submit demo rating'), findsOneWidget);
  });
}

Widget _testApp(ProviderContainer container, GoRouter router) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  );
}

Future<void> _setLargeTestSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

MockTrip _trip({TripStatus status = TripStatus.accepted}) {
  final booking = MockData.initialDraft().copyWith(
    pickup: const RideLocation(label: 'Pickup', address: 'Campus gate'),
    destination:
        const RideLocation(label: 'Destination', address: 'City centre'),
    vehicleType: MockData.vehicleTypes[1],
    estimatedFare: 7.35,
  );
  return MockTrip(
    id: 'lifecycle-trip',
    booking: booking,
    status: status,
    driver: const DriverSummary(
      name: 'Nadia',
      rating: 4.8,
      vehicleName: 'Kia K5',
      plate: '12-ABC',
      etaMinutes: 4,
    ),
    finalFare: 7.35,
  );
}

class _DelayedTripsRepository implements TripsRepository {
  final _tripCompleter = Completer<MockTrip>();
  int createCalls = 0;

  @override
  Future<MockTrip> createTrip(BookingDraft draft) {
    createCalls++;
    return _tripCompleter.future;
  }

  void complete(MockTrip trip) => _tripCompleter.complete(trip);

  @override
  Future<List<MockTrip>> getTripHistory() async => const [];

  @override
  Future<MockTrip?> getTripById(String id) async => null;
}

class _SeededActiveTripController extends ActiveTripController {
  _SeededActiveTripController(this.trip);

  final MockTrip trip;

  @override
  MockTrip build() => trip;
}

class _TripStateProbe extends ConsumerWidget {
  const _TripStateProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(activeTripControllerProvider)?.status;
    return Scaffold(body: Text('Navigated with ${status?.name}'));
  }
}
