import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/errors/route_exception.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/route_models.dart';
import 'package:ridex/core/models/place_prediction.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/services/places/places_session_token.dart';
import 'package:ridex/core/repositories/mock_place_repository.dart';
import 'package:ridex/core/repositories/mock_route_repository.dart';
import 'package:ridex/core/repositories/route_repository.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/features/booking/presentation/screens/fare_estimate_screen.dart';
import 'package:ridex/features/booking/presentation/widgets/stops_section.dart';

import 'helpers/fake_places.dart';

/// Provisional Phase 5 widget coverage for multi-stop management.
///
/// All stop mutations go through the frozen [BookingController] API; these
/// tests drive the booking-flow UI surfaces only: ordered add/remove/
/// reorder/clear flows, max-3 and duplicate messaging, fare-screen stop
/// display from draft labels/addresses, and the honest not-ready route
/// presentation while stops are present.
///
/// The not-ready route case uses a dedicated stub that reports
/// [RouteFailure.unsupportedStops] (the pre-P5-2 contract), so the honest
/// failure presentation is verified deterministically regardless of the
/// parallel P5-2 route-with-stops work sharing this worktree.
class _UnsupportedStopsRouteRepository implements RouteRepository {
  const _UnsupportedStopsRouteRepository();

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    throw const RouteException(RouteFailure.unsupportedStops);
  }
}

/// Provisional Phase 5 widget coverage for multi-stop management.
///
/// All stop mutations go through the frozen [BookingController] API; these
/// tests drive the booking-flow UI surfaces only: ordered add/remove/
/// reorder/clear flows, max-3 and duplicate messaging, fare-screen stop
/// display from draft labels/addresses, and the honest not-ready route
/// presentation while stops are present (routing with stops is P5-2 work).
void main() {
  ProviderContainer createContainer({RouteRepository? routeRepository}) {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => MockAuthRepository()),
        bookingRepositoryProvider.overrideWith(
          (ref) => MockBookingRepository(),
        ),
        placeRepositoryProvider.overrideWith((ref) => MockPlaceRepository()),
        routeRepositoryProvider.overrideWithValue(
          routeRepository ?? const MockRouteRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpStopsSection(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(child: StopsSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> searchForStop(WidgetTester tester, String query) async {
    await tester.enterText(
      find.byKey(const ValueKey('stop-search-field')),
      query,
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> addStopViaPrediction(
    WidgetTester tester,
    String query,
  ) async {
    await searchForStop(tester, query);
    await tapVisible(tester, find.byKey(const ValueKey('stop-prediction-0')));
  }

  BookingController controllerOf(ProviderContainer container) {
    return container.read(bookingControllerProvider.notifier);
  }

  List<String> stopLabelsOf(ProviderContainer container) {
    return container
        .read(bookingControllerProvider)
        .stops
        .map((stop) => stop.label)
        .toList(growable: false);
  }

  testWidgets('adds stops through search predictions in order', (
    tester,
  ) async {
    final container = createContainer();
    await pumpStopsSection(tester, container);

    await addStopViaPrediction(tester, 'Abdali');
    await addStopViaPrediction(tester, 'Queen');

    expect(
      stopLabelsOf(container),
      ['Abdali Mall', 'Queen Alia Airport'],
    );
    expect(find.text('Abdali Mall'), findsOneWidget);
    expect(find.text('Queen Alia Airport'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets('adds a stop by submitting a typed address', (tester) async {
    final container = createContainer();
    await pumpStopsSection(tester, container);

    await tester.enterText(
      find.byKey(const ValueKey('stop-search-field')),
      'Hashemite',
    );
    await tester.pump();
    await tapVisible(
      tester,
      find.byKey(const ValueKey('stop-search-submit')),
    );

    expect(stopLabelsOf(container), ['Hashemite University']);
    expect(find.byKey(const ValueKey('stop-card-0')), findsOneWidget);
  });

  testWidgets('removes a stop and keeps order', (tester) async {
    final container = createContainer();
    final controller = controllerOf(container);
    expect(
      controller.addStop(
        testLocation(latitude: 31.90, longitude: 35.90, label: 'First'),
      ),
      isTrue,
    );
    expect(
      controller.addStop(
        testLocation(latitude: 31.91, longitude: 35.91, label: 'Second'),
      ),
      isTrue,
    );
    expect(
      controller.addStop(
        testLocation(latitude: 31.92, longitude: 35.92, label: 'Third'),
      ),
      isTrue,
    );
    await pumpStopsSection(tester, container);

    await tapVisible(tester, find.byKey(const ValueKey('stop-remove-1')));

    expect(stopLabelsOf(container), ['First', 'Third']);
    expect(find.text('Second'), findsNothing);
  });

  testWidgets('reorders stops with move controls', (tester) async {
    final container = createContainer();
    final controller = controllerOf(container);
    expect(
      controller.addStop(
        testLocation(latitude: 31.90, longitude: 35.90, label: 'First'),
      ),
      isTrue,
    );
    expect(
      controller.addStop(
        testLocation(latitude: 31.91, longitude: 35.91, label: 'Second'),
      ),
      isTrue,
    );
    await pumpStopsSection(tester, container);

    await tapVisible(tester, find.byKey(const ValueKey('stop-move-down-0')));
    expect(stopLabelsOf(container), ['Second', 'First']);

    await tapVisible(tester, find.byKey(const ValueKey('stop-move-up-1')));
    expect(stopLabelsOf(container), ['First', 'Second']);
  });

  testWidgets('clears all stops', (tester) async {
    final container = createContainer();
    final controller = controllerOf(container);
    expect(
      controller.addStop(
        testLocation(latitude: 31.90, longitude: 35.90, label: 'First'),
      ),
      isTrue,
    );
    expect(
      controller.addStop(
        testLocation(latitude: 31.91, longitude: 35.91, label: 'Second'),
      ),
      isTrue,
    );
    await pumpStopsSection(tester, container);

    await tapVisible(tester, find.byKey(const ValueKey('stops-clear')));

    expect(container.read(bookingControllerProvider).stops, isEmpty);
    expect(find.byKey(const ValueKey('stops-empty')), findsOneWidget);
    expect(find.text('0/3'), findsOneWidget);
  });

  testWidgets('rejects a fourth stop with honest max messaging', (
    tester,
  ) async {
    final container = createContainer();
    final controller = controllerOf(container);
    controller.setPickup(MockData.locations[0]);
    controller.setDestination(MockData.locations[1]);
    expect(controller.addStop(MockData.locations[2]), isTrue);
    expect(controller.addStop(MockData.locations[3]), isTrue);
    expect(
      controller.addStop(
        testLocation(latitude: 31.90, longitude: 35.90, label: 'Third'),
      ),
      isTrue,
    );
    await pumpStopsSection(tester, container);

    await searchForStop(tester, 'Hashemite');
    await tapVisible(
      tester,
      find.byKey(const ValueKey('stop-prediction-0')),
    );

    expect(container.read(bookingControllerProvider).stops, hasLength(3));
    expect(find.byKey(const ValueKey('stops-feedback')), findsOneWidget);
    expect(
      find.text(
        'You can add up to 3 stops. Remove one to add another.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('stops-route-note')), findsOneWidget);
  });

  testWidgets('rejects duplicate stops with honest messaging', (
    tester,
  ) async {
    final container = createContainer();
    await pumpStopsSection(tester, container);

    await addStopViaPrediction(tester, 'Abdali');
    await addStopViaPrediction(tester, 'Abdali');

    expect(container.read(bookingControllerProvider).stops, hasLength(1));
    expect(
      find.text(
        'This stop is already in your route. Choose a different location.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'fare screen presents the honest not-ready route surface with stops',
    (tester) async {
      final container = createContainer(
        routeRepository: const _UnsupportedStopsRouteRepository(),
      );
      final controller = controllerOf(container);
      controller.setPickup(MockData.locations[0]);
      controller.setDestination(MockData.locations[1]);
      expect(
        controller.addStop(
          testLocation(
            latitude: 31.70,
            longitude: 35.99,
            label: 'Coffee stop',
            address: 'Coffee address',
          ),
        ),
        isTrue,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const FareEstimateScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ordered stops come from draft labels/addresses only.
      expect(find.text('Coffee address'), findsOneWidget);
      expect(find.text('Coffee stop'), findsOneWidget);

      // Honest not-ready presentation: no fabricated route result, the
      // existing failure surface names the limitation, and confirmation
      // stays unavailable.
      expect(
        find.text('Intermediate stops are not available yet.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('route-ready')), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Confirm & find a driver'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final confirm = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Confirm & find a driver'),
      );
      expect(confirm.onPressed, isNull);
    },
  );

  testWidgets(
    'fare screen lists ordered stops without a selected vehicle',
    (tester) async {
      final container = createContainer();
      final controller = controllerOf(container);
      controller.setPickup(MockData.locations[0]);
      controller.setDestination(MockData.locations[1]);
      expect(
        controller.addStop(
          testLocation(
            latitude: 31.70,
            longitude: 35.99,
            label: 'Coffee stop',
            address: 'Coffee address',
          ),
        ),
        isTrue,
      );
      expect(
        controller.addStop(
          testLocation(
            latitude: 31.71,
            longitude: 35.98,
            label: 'Pharmacy stop',
            address: 'Pharmacy address',
          ),
        ),
        isTrue,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const FareEstimateScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ordered stops come from draft labels/addresses only; stopping
      // clears the selected vehicle, so confirmation stays unavailable
      // without inventing a fare.
      expect(find.text('Coffee address'), findsOneWidget);
      expect(find.text('Coffee stop'), findsOneWidget);
      expect(find.text('Pharmacy address'), findsOneWidget);
      expect(find.text('Pharmacy stop'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Confirm & find a driver'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final confirm = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Confirm & find a driver'),
      );
      expect(confirm.onPressed, isNull);
    },
  );

  testWidgets('stop management works on a small 320x568 screen', (
    tester,
  ) async {
    final container = createContainer();
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpStopsSection(tester, container);
    await addStopViaPrediction(tester, 'Abdali');

    expect(stopLabelsOf(container), ['Abdali Mall']);
    expect(find.byKey(const ValueKey('stop-remove-0')), findsOneWidget);
  });

  testWidgets(
      'stop autocomplete and details reuse one valid token and rotate across sequential sessions',
      (tester) async {
    final fake = FakePlaceRepository()
      ..predictions = const [
        PlacePrediction(
          placeId: 'stop-a',
          primaryText: 'Stop A',
          secondaryText: 'Address A',
        ),
      ]
      ..resolvedPrediction = testLocation(
        latitude: 31.90,
        longitude: 35.90,
        label: 'Stop A',
      );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => MockAuthRepository()),
        bookingRepositoryProvider.overrideWith(
          (ref) => MockBookingRepository(),
        ),
        placeRepositoryProvider.overrideWithValue(fake),
        routeRepositoryProvider.overrideWithValue(
          const MockRouteRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await pumpStopsSection(tester, container);

    await searchForStop(tester, 'Stop A');
    await tapVisible(tester, find.byKey(const ValueKey('stop-prediction-0')));

    expect(stopLabelsOf(container), ['Stop A']);
    expect(fake.sessionTokens, hasLength(2));
    for (final token in fake.sessionTokens) {
      expect(placesSessionTokenRegExp.hasMatch(token), isTrue);
    }
    expect(fake.sessionTokens[1], fake.sessionTokens[0]);
    final firstSessionToken = fake.sessionTokens.first;

    fake.predictions = const [
      PlacePrediction(
        placeId: 'stop-b',
        primaryText: 'Stop B',
        secondaryText: 'Address B',
      ),
    ];
    fake.resolvedPrediction = testLocation(
      latitude: 31.91,
      longitude: 35.91,
      label: 'Stop B',
    );

    await searchForStop(tester, 'Stop B');
    await tapVisible(tester, find.byKey(const ValueKey('stop-prediction-0')));

    expect(stopLabelsOf(container), ['Stop A', 'Stop B']);
    expect(fake.sessionTokens, hasLength(4));
    for (final token in fake.sessionTokens) {
      expect(placesSessionTokenRegExp.hasMatch(token), isTrue);
    }
    expect(fake.sessionTokens[2], isNot(firstSessionToken));
    expect(fake.sessionTokens[3], fake.sessionTokens[2]);
  });

  testWidgets('typed address submission terminates the stop autocomplete token',
      (tester) async {
    final fake = FakePlaceRepository()
      ..predictions = const [
        PlacePrediction(
          placeId: 'stop-a',
          primaryText: 'Stop A',
          secondaryText: 'Address A',
        ),
      ]
      ..resolvedPrediction = testLocation(
        latitude: 31.90,
        longitude: 35.90,
        label: 'Stop A',
      )
      ..forwardResults = [
        testLocation(
          latitude: 31.91,
          longitude: 35.91,
          label: 'Typed Stop',
        ),
      ];
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => MockAuthRepository()),
        bookingRepositoryProvider.overrideWith(
          (ref) => MockBookingRepository(),
        ),
        placeRepositoryProvider.overrideWithValue(fake),
        routeRepositoryProvider.overrideWithValue(
          const MockRouteRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await pumpStopsSection(tester, container);

    await searchForStop(tester, 'Stop A');
    expect(fake.sessionTokens, hasLength(1));
    final autocompleteToken = fake.sessionTokens.single;
    expect(placesSessionTokenRegExp.hasMatch(autocompleteToken), isTrue);

    await tester.enterText(
      find.byKey(const ValueKey('stop-search-field')),
      'Typed address',
    );
    await tester.pump();
    await tapVisible(
      tester,
      find.byKey(const ValueKey('stop-search-submit')),
    );

    expect(stopLabelsOf(container), ['Typed Stop']);
    // Forward geocoding consumes no session token.
    expect(fake.sessionTokens, hasLength(1));

    fake.predictions = const [
      PlacePrediction(
        placeId: 'stop-b',
        primaryText: 'Stop B',
        secondaryText: 'Address B',
      ),
    ];
    fake.resolvedPrediction = testLocation(
      latitude: 31.92,
      longitude: 35.92,
      label: 'Stop B',
    );

    await searchForStop(tester, 'Stop B');
    expect(fake.sessionTokens, hasLength(2));
    expect(fake.sessionTokens.last, isNot(autocompleteToken));
    expect(
      placesSessionTokenRegExp.hasMatch(fake.sessionTokens.last),
      isTrue,
    );

    await tapVisible(tester, find.byKey(const ValueKey('stop-prediction-0')));
    expect(stopLabelsOf(container), ['Typed Stop', 'Stop B']);
    expect(fake.sessionTokens, hasLength(3));
    expect(fake.sessionTokens[1], fake.sessionTokens[2]);
    for (final token in fake.sessionTokens) {
      expect(placesSessionTokenRegExp.hasMatch(token), isTrue);
    }
  });

  testWidgets(
      'rejected duplicate consumes predictions and next session uses a fresh token',
      (tester) async {
    final fake = FakePlaceRepository()
      ..predictions = const [
        PlacePrediction(
          placeId: 'dup-a',
          primaryText: 'Dup A',
          secondaryText: 'Address A',
        ),
      ]
      ..resolvedPrediction = testLocation(
        latitude: 31.90,
        longitude: 35.90,
        label: 'Dup A',
      );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => MockAuthRepository()),
        bookingRepositoryProvider.overrideWith(
          (ref) => MockBookingRepository(),
        ),
        placeRepositoryProvider.overrideWithValue(fake),
        routeRepositoryProvider.overrideWithValue(
          const MockRouteRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await pumpStopsSection(tester, container);

    await searchForStop(tester, 'Dup A');
    await tapVisible(tester, find.byKey(const ValueKey('stop-prediction-0')));
    expect(stopLabelsOf(container), ['Dup A']);
    expect(fake.sessionTokens, hasLength(2));
    final firstSession = fake.sessionTokens.first;

    await searchForStop(tester, 'Dup A');
    expect(find.byKey(const ValueKey('stop-prediction-0')), findsOneWidget);
    await tapVisible(tester, find.byKey(const ValueKey('stop-prediction-0')));

    expect(stopLabelsOf(container), hasLength(1));
    expect(
      find.text(
        'This stop is already in your route. Choose a different location.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('stop-prediction-0')), findsNothing);
    expect(fake.sessionTokens, hasLength(4));
    expect(fake.sessionTokens[2], isNot(firstSession));
    expect(fake.sessionTokens[3], fake.sessionTokens[2]);

    fake.predictions = const [
      PlacePrediction(
        placeId: 'stop-b',
        primaryText: 'Stop B',
        secondaryText: 'Address B',
      ),
    ];
    fake.resolvedPrediction = testLocation(
      latitude: 31.91,
      longitude: 35.91,
      label: 'Stop B',
    );
    await searchForStop(tester, 'Stop B');
    expect(fake.sessionTokens, hasLength(5));
    expect(fake.sessionTokens.last, isNot(fake.sessionTokens[3]));
    expect(
      placesSessionTokenRegExp.hasMatch(fake.sessionTokens.last),
      isTrue,
    );
  });
}
