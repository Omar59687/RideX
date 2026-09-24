import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/errors/place_exception.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/place_prediction.dart';
import 'package:ridex/core/models/place_selection_state.dart';
import 'package:ridex/core/providers/place_providers.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/providers/location_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/booking/presentation/screens/vehicle_type_selection_screen.dart';
import 'package:ridex/features/booking/presentation/widgets/location_search_panel.dart';

import 'helpers/fake_places.dart';
import 'helpers/fake_location.dart';
import 'helpers/recording_error_reporter.dart';

void main() {
  const predictionA = PlacePrediction(
    placeId: 'a',
    primaryText: 'Abdali',
    secondaryText: 'Amman',
  );
  const predictionB = PlacePrediction(
    placeId: 'b',
    primaryText: 'Airport',
    secondaryText: 'Jordan',
  );

  test('empty and short queries issue no autocomplete request', () async {
    final fake = FakePlaceRepository();
    final container = _container(fake);
    addTearDown(container.dispose);
    final controller = container.read(
      placeSelectionControllerProvider(LocationEndpoint.destination).notifier,
    );

    controller.search('');
    controller.search('ab');
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(fake.autocompleteCalls, 0);
    expect(
      container
          .read(placeSelectionControllerProvider(LocationEndpoint.destination))
          .status,
      PlaceSearchStatus.idle,
    );
  });

  test('debounces rapid queries and sends only the newest value', () async {
    final fake = FakePlaceRepository()..predictions = const [predictionB];
    final container = _container(fake);
    addTearDown(container.dispose);
    final provider =
        placeSelectionControllerProvider(LocationEndpoint.destination);
    final controller = container.read(provider.notifier);
    container.listen(provider, (_, __) {});

    controller.search('Abd');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    controller.search('Airport');
    await Future<void>.delayed(const Duration(milliseconds: 380));

    expect(fake.queries, ['Airport']);
    expect(container.read(provider).predictions, const [predictionB]);
  });

  test('stale autocomplete response cannot replace newer query', () async {
    final first = Completer<List<PlacePrediction>>();
    final second = Completer<List<PlacePrediction>>();
    final fake = _QueuedAutocompleteRepository([first.future, second.future]);
    final container = _container(fake);
    addTearDown(container.dispose);
    final provider =
        placeSelectionControllerProvider(LocationEndpoint.destination);
    container.listen(provider, (_, __) {});
    final controller = container.read(provider.notifier);

    controller.search('Abdali');
    await Future<void>.delayed(const Duration(milliseconds: 370));
    controller.search('Airport');
    await Future<void>.delayed(const Duration(milliseconds: 370));
    second.complete(const [predictionB]);
    await Future<void>.delayed(Duration.zero);
    first.complete(const [predictionA]);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(provider).predictions, const [predictionB]);
  });

  test('pickup and destination prediction selections stay independent',
      () async {
    final fake = FakePlaceRepository();
    final pickup = testLocation(latitude: 31.95, longitude: 35.91);
    final destination = testLocation(latitude: 31.96, longitude: 35.92);
    final container = _container(fake);
    addTearDown(container.dispose);

    fake.resolvedPrediction = destination;
    await container
        .read(placeSelectionControllerProvider(LocationEndpoint.destination)
            .notifier)
        .selectPrediction(predictionA);
    fake.resolvedPrediction = pickup;
    await container
        .read(
            placeSelectionControllerProvider(LocationEndpoint.pickup).notifier)
        .selectPrediction(predictionB);

    final draft = container.read(bookingControllerProvider);
    expect(draft.pickup?.point, pickup.point);
    expect(draft.destination?.point, destination.point);
    expect(draft.isRoutingReady, isTrue);
  });

  test('forward geocoding success selects canonical coordinate', () async {
    final selected = testLocation(latitude: 31.95, longitude: 35.91);
    final fake = FakePlaceRepository()..forwardResults = [selected];
    final container = _container(fake);
    addTearDown(container.dispose);
    final provider = placeSelectionControllerProvider(LocationEndpoint.pickup);
    container.listen(provider, (_, __) {});
    final controller = container.read(provider.notifier);

    controller.search('Amman address');
    await controller.submitAddress();

    expect(container.read(bookingControllerProvider).pickup?.point,
        selected.point);
    expect(container.read(provider).status, PlaceSearchStatus.selected);
  });

  test('provider failures are sanitized', () async {
    final fake = FakePlaceRepository()
      ..autocompleteError = const PlaceException(PlaceFailure.unavailable);
    final container = _container(fake);
    addTearDown(container.dispose);
    final provider =
        placeSelectionControllerProvider(LocationEndpoint.destination);
    container.listen(provider, (_, __) {});
    container.read(provider.notifier).search('Abdali');
    await Future<void>.delayed(const Duration(milliseconds: 370));

    expect(container.read(provider).status, PlaceSearchStatus.failure);
    expect(container.read(provider).message, contains('unavailable'));
  });

  test('unexpected place errors are reported but never exposed in state',
      () async {
    final error = StateError(rawErrorCanary);
    final reporter = RecordingAppErrorReporter();
    final fake = FakePlaceRepository()..autocompleteError = error;
    final container = _container(fake, reporter: reporter);
    addTearDown(container.dispose);
    final provider =
        placeSelectionControllerProvider(LocationEndpoint.destination);
    container.listen(provider, (_, __) {});

    container.read(provider.notifier).search('Abdali');
    await Future<void>.delayed(const Duration(milliseconds: 370));

    final state = container.read(provider);
    expect(state.status, PlaceSearchStatus.failure);
    expect(
      state.message,
      'Place search is unavailable right now. Please try again.',
    );
    expect(state.toString(), isNot(contains(rawErrorCanary)));
    expect(reporter.reports.single.error, same(error));
  });

  testWidgets('place failure panel contains only fixed RideX copy',
      (tester) async {
    final searchController = TextEditingController(text: 'Abdali');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationSearchPanel(
            endpoint: LocationEndpoint.destination,
            state: const PlaceSelectionState(
              query: 'Abdali',
              status: PlaceSearchStatus.failure,
              message:
                  'Place search is unavailable right now. Please try again.',
            ),
            controller: searchController,
            onChanged: (_) {},
            onSubmitted: () {},
            onPredictionSelected: (_) {},
            onRetry: () {},
            onRetryAddress: () {},
          ),
        ),
      ),
    );
    expect(find.textContaining(rawErrorCanary), findsNothing);
    await tester.pumpWidget(const SizedBox());
    searchController.dispose();
  });

  test('late place failures remain reportable after auto-dispose', () async {
    final reporter = RecordingAppErrorReporter();
    final result = Completer<List<PlacePrediction>>();
    final error = StateError(rawErrorCanary);
    final fake = FakePlaceRepository()..autocompleteResult = result.future;
    final container = _container(fake, reporter: reporter);
    final provider =
        placeSelectionControllerProvider(LocationEndpoint.destination);
    final subscription = container.listen(provider, (_, __) {});
    container.read(provider.notifier).search('Abdali');
    await Future<void>.delayed(const Duration(milliseconds: 370));

    subscription.close();
    container.dispose();
    result.completeError(error, StackTrace.fromString(rawErrorCanary));
    await Future<void>.delayed(Duration.zero);

    expect(reporter.reports.single.error, same(error));
  });

  test('editing a confirmed endpoint makes the selection uncommitted', () {
    final fake = FakePlaceRepository();
    final container = _container(fake);
    addTearDown(container.dispose);
    final provider = placeSelectionControllerProvider(LocationEndpoint.pickup);
    final controller = container.read(provider.notifier);

    controller.search('New pickup');

    expect(container.read(provider).hasUncommittedQuery, isTrue);
    expect(container.read(provider).status, PlaceSearchStatus.debouncing);
  });

  test('map point remains canonical when reverse geocoding fails', () async {
    final fake = FakePlaceRepository()
      ..reverseError = const PlaceException(PlaceFailure.unavailable);
    final container = _container(fake);
    addTearDown(container.dispose);
    final point = LocationPoint(latitude: 31.95, longitude: 35.91);
    final provider = placeSelectionControllerProvider(LocationEndpoint.pickup);
    container.listen(provider, (_, __) {});

    await container.read(provider.notifier).selectPoint(
          point,
          source: LocationSelectionSource.map,
        );

    expect(container.read(bookingControllerProvider).pickup?.point, point);
    expect(container.read(provider).status, PlaceSearchStatus.selected);
    expect(container.read(provider).message, contains('still valid'));
  });

  for (final endpoint in LocationEndpoint.values) {
    test('$endpoint keeps routing blocked until reverse geocoding settles',
        () async {
      final reverse = Completer<RideLocation?>();
      final fake = _QueuedReverseRepository([reverse.future]);
      final container = _container(fake);
      addTearDown(container.dispose);
      container.read(bookingControllerProvider.notifier)
        ..setPickup(testLocation(latitude: 31.95, longitude: 35.91))
        ..setDestination(testLocation(latitude: 31.96, longitude: 35.92));
      final provider = placeSelectionControllerProvider(endpoint);
      container.listen(provider, (_, __) {});
      final point = endpoint == LocationEndpoint.pickup
          ? LocationPoint(latitude: 31.94, longitude: 35.90)
          : LocationPoint(latitude: 31.97, longitude: 35.93);

      final operation = container.read(provider.notifier).selectPoint(
            point,
            source: LocationSelectionSource.map,
          );

      final resolvingDraft = container.read(bookingControllerProvider);
      expect(
        endpoint == LocationEndpoint.pickup
            ? resolvingDraft.pickup
            : resolvingDraft.destination,
        isNull,
      );
      expect(resolvingDraft.isRoutingReady, isFalse);
      expect(container.read(provider).status, PlaceSearchStatus.resolving);
      expect(container.read(provider).selected?.point, point);

      reverse.complete(testLocation(
        latitude: point.latitude,
        longitude: point.longitude,
        source: LocationSelectionSource.map,
      ));
      await operation;

      final settledDraft = container.read(bookingControllerProvider);
      expect(settledDraft.isRoutingReady, isTrue);
      expect(
        endpoint == LocationEndpoint.pickup
            ? settledDraft.pickup?.point
            : settledDraft.destination?.point,
        point,
      );
    });
  }

  testWidgets(
      'direct vehicle selection stays blocked while an endpoint resolves',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final reverse = Completer<RideLocation?>();
    final fake = _QueuedReverseRepository([reverse.future]);
    final container = _container(fake);
    addTearDown(container.dispose);
    final booking = container.read(bookingControllerProvider.notifier)
      ..setPickup(testLocation(latitude: 31.95, longitude: 35.91))
      ..setDestination(testLocation(latitude: 31.96, longitude: 35.92));
    final provider =
        placeSelectionControllerProvider(LocationEndpoint.destination);
    container.listen(provider, (_, __) {});
    final point = LocationPoint(latitude: 31.97, longitude: 35.93);

    final operation = container.read(provider.notifier).selectPoint(
          point,
          source: LocationSelectionSource.map,
        );
    final vehicle = MockData.vehicleTypes.first;
    booking.setVehicleType(vehicle);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const VehicleTypeSelectionScreen(),
        ),
      ),
    );

    ElevatedButton chooseButton() => tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Choose ${vehicle.name}'),
        );

    expect(chooseButton().onPressed, isNull);

    reverse.complete(testLocation(
      latitude: point.latitude,
      longitude: point.longitude,
      source: LocationSelectionSource.map,
    ));
    await operation;
    booking.setVehicleType(vehicle);
    await tester.pump();

    expect(chooseButton().onPressed, isNotNull);
  });

  for (final endpoint in LocationEndpoint.values) {
    test('$endpoint keeps routing blocked until prediction details settle',
        () async {
      final details = Completer<RideLocation>();
      final fake = FakePlaceRepository()..resolveResult = details.future;
      final container = _container(fake);
      addTearDown(container.dispose);
      container.read(bookingControllerProvider.notifier)
        ..setPickup(testLocation(latitude: 31.95, longitude: 35.91))
        ..setDestination(testLocation(latitude: 31.96, longitude: 35.92));
      final provider = placeSelectionControllerProvider(endpoint);
      container.listen(provider, (_, __) {});
      final replacement = endpoint == LocationEndpoint.pickup
          ? testLocation(latitude: 31.94, longitude: 35.90)
          : testLocation(latitude: 31.97, longitude: 35.93);

      final operation =
          container.read(provider.notifier).selectPrediction(predictionA);

      final resolvingDraft = container.read(bookingControllerProvider);
      expect(
        endpoint == LocationEndpoint.pickup
            ? resolvingDraft.pickup
            : resolvingDraft.destination,
        isNull,
      );
      expect(resolvingDraft.isRoutingReady, isFalse);
      expect(container.read(provider).status, PlaceSearchStatus.resolving);

      details.complete(replacement);
      await operation;

      final settledDraft = container.read(bookingControllerProvider);
      expect(settledDraft.isRoutingReady, isTrue);
      expect(
        endpoint == LocationEndpoint.pickup
            ? settledDraft.pickup
            : settledDraft.destination,
        replacement,
      );
    });

    test('$endpoint keeps routing blocked until forward geocoding settles',
        () async {
      final forward = Completer<List<RideLocation>>();
      final fake = FakePlaceRepository()..forwardResult = forward.future;
      final container = _container(fake);
      addTearDown(container.dispose);
      container.read(bookingControllerProvider.notifier)
        ..setPickup(testLocation(latitude: 31.95, longitude: 35.91))
        ..setDestination(testLocation(latitude: 31.96, longitude: 35.92));
      final provider = placeSelectionControllerProvider(endpoint);
      container.listen(provider, (_, __) {});
      final controller = container.read(provider.notifier);
      final replacement = endpoint == LocationEndpoint.pickup
          ? testLocation(latitude: 31.94, longitude: 35.90)
          : testLocation(latitude: 31.97, longitude: 35.93);
      controller.search('Replacement address');

      final operation = controller.submitAddress();

      final resolvingDraft = container.read(bookingControllerProvider);
      expect(
        endpoint == LocationEndpoint.pickup
            ? resolvingDraft.pickup
            : resolvingDraft.destination,
        isNull,
      );
      expect(resolvingDraft.isRoutingReady, isFalse);
      expect(container.read(provider).status, PlaceSearchStatus.resolving);

      forward.complete([replacement]);
      await operation;

      final settledDraft = container.read(bookingControllerProvider);
      expect(settledDraft.isRoutingReady, isTrue);
      expect(
        endpoint == LocationEndpoint.pickup
            ? settledDraft.pickup
            : settledDraft.destination,
        replacement,
      );
    });
  }

  for (final usePrediction in [true, false]) {
    testWidgets(
        'direct vehicle selection stays blocked during ${usePrediction ? 'prediction details' : 'forward geocoding'}',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final details = Completer<RideLocation>();
      final forward = Completer<List<RideLocation>>();
      final fake = FakePlaceRepository()
        ..resolveResult = details.future
        ..forwardResult = forward.future;
      final container = _container(fake);
      addTearDown(container.dispose);
      container.listen(currentLocationControllerProvider, (_, __) {});
      final booking = container.read(bookingControllerProvider.notifier)
        ..setPickup(testLocation(latitude: 31.95, longitude: 35.91))
        ..setDestination(testLocation(latitude: 31.96, longitude: 35.92));
      final provider =
          placeSelectionControllerProvider(LocationEndpoint.destination);
      container.listen(provider, (_, __) {});
      final controller = container.read(provider.notifier);
      if (!usePrediction) controller.search('Replacement address');

      final operation = usePrediction
          ? controller.selectPrediction(predictionA)
          : controller.submitAddress();
      final vehicle = MockData.vehicleTypes.first;
      booking.setVehicleType(vehicle);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const VehicleTypeSelectionScreen(),
          ),
        ),
      );

      ElevatedButton chooseButton() => tester.widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Choose ${vehicle.name}'),
          );

      expect(chooseButton().onPressed, isNull);

      final replacement = testLocation(latitude: 31.97, longitude: 35.93);
      if (usePrediction) {
        details.complete(replacement);
      } else {
        forward.complete([replacement]);
      }
      await operation;
      booking.setVehicleType(vehicle);
      await tester.pump();

      expect(chooseButton().onPressed, isNotNull);
    });
  }

  test('failed prediction replacement leaves endpoint uncommitted', () async {
    final details = Completer<RideLocation>();
    final fake = FakePlaceRepository()..resolveResult = details.future;
    final container = _container(fake);
    addTearDown(container.dispose);
    container.read(bookingControllerProvider.notifier)
      ..setPickup(testLocation(latitude: 31.95, longitude: 35.91))
      ..setDestination(testLocation(latitude: 31.96, longitude: 35.92));
    final provider =
        placeSelectionControllerProvider(LocationEndpoint.destination);
    container.listen(provider, (_, __) {});

    final operation =
        container.read(provider.notifier).selectPrediction(predictionA);
    details.completeError(const PlaceException(PlaceFailure.unavailable));
    await operation;

    expect(container.read(bookingControllerProvider).destination, isNull);
    expect(container.read(bookingControllerProvider).isRoutingReady, isFalse);
    expect(container.read(provider).status, PlaceSearchStatus.failure);
  });

  test('empty forward-geocode replacement leaves endpoint uncommitted',
      () async {
    final forward = Completer<List<RideLocation>>();
    final fake = FakePlaceRepository()..forwardResult = forward.future;
    final container = _container(fake);
    addTearDown(container.dispose);
    container.read(bookingControllerProvider.notifier)
      ..setPickup(testLocation(latitude: 31.95, longitude: 35.91))
      ..setDestination(testLocation(latitude: 31.96, longitude: 35.92));
    final provider =
        placeSelectionControllerProvider(LocationEndpoint.destination);
    container.listen(provider, (_, __) {});
    final controller = container.read(provider.notifier)
      ..search('Replacement address');

    final operation = controller.submitAddress();
    forward.complete(const []);
    await operation;

    expect(container.read(bookingControllerProvider).destination, isNull);
    expect(container.read(bookingControllerProvider).isRoutingReady, isFalse);
    expect(container.read(provider).status, PlaceSearchStatus.empty);
  });

  test('stale reverse response cannot attach to a newer coordinate', () async {
    final first = Completer<RideLocation?>();
    final second = Completer<RideLocation?>();
    final fake = _QueuedReverseRepository([first.future, second.future]);
    final container = _container(fake);
    addTearDown(container.dispose);
    final provider = placeSelectionControllerProvider(LocationEndpoint.pickup);
    container.listen(provider, (_, __) {});
    final controller = container.read(provider.notifier);
    final pointA = LocationPoint(latitude: 31.95, longitude: 35.91);
    final pointB = LocationPoint(latitude: 31.96, longitude: 35.92);

    final operationA = controller.selectPoint(
      pointA,
      source: LocationSelectionSource.map,
    );
    final operationB = controller.selectPoint(
      pointB,
      source: LocationSelectionSource.map,
    );
    second.complete(testLocation(latitude: 31.96, longitude: 35.92));
    await operationB;
    first.complete(testLocation(
      latitude: 31.95,
      longitude: 35.91,
      address: 'Stale address',
    ));
    await operationA;

    expect(container.read(bookingControllerProvider).pickup?.point, pointB);
    expect(
      container.read(bookingControllerProvider).pickup?.address,
      isNot('Stale address'),
    );
  });

  test('stale prediction details cannot replace a newer map selection',
      () async {
    final details = Completer<RideLocation>();
    final fake = FakePlaceRepository()..resolveResult = details.future;
    final container = _container(fake);
    addTearDown(container.dispose);
    final provider = placeSelectionControllerProvider(LocationEndpoint.pickup);
    container.listen(provider, (_, __) {});
    final controller = container.read(provider.notifier);
    final mapPoint = LocationPoint(latitude: 31.96, longitude: 35.92);

    final selection = controller.selectPrediction(predictionA);
    final mapSelection = controller.selectPoint(
      mapPoint,
      source: LocationSelectionSource.map,
    );
    details.complete(testLocation(latitude: 31.95, longitude: 35.91));
    await selection;
    await mapSelection;

    expect(container.read(bookingControllerProvider).pickup?.point, mapPoint);
  });

  test('stale forward geocode cannot replace a newer map selection', () async {
    final forward = Completer<List<RideLocation>>();
    final fake = FakePlaceRepository()..forwardResult = forward.future;
    final container = _container(fake);
    addTearDown(container.dispose);
    final provider = placeSelectionControllerProvider(LocationEndpoint.pickup);
    container.listen(provider, (_, __) {});
    final controller = container.read(provider.notifier);
    final mapPoint = LocationPoint(latitude: 31.96, longitude: 35.92);

    controller.search('Typed address');
    final geocode = controller.submitAddress();
    final mapSelection = controller.selectPoint(
      mapPoint,
      source: LocationSelectionSource.map,
    );
    forward.complete([testLocation(latitude: 31.95, longitude: 35.91)]);
    await geocode;
    await mapSelection;

    expect(container.read(bookingControllerProvider).pickup?.point, mapPoint);
  });

  test('GPS point can become pickup', () async {
    final point = LocationPoint(latitude: 31.95, longitude: 35.91);
    final fake = FakePlaceRepository()
      ..reversedLocation = testLocation(
        latitude: 31.95,
        longitude: 35.91,
        source: LocationSelectionSource.gps,
      );
    final container = _container(fake);
    addTearDown(container.dispose);

    await container
        .read(
            placeSelectionControllerProvider(LocationEndpoint.pickup).notifier)
        .selectPoint(point, source: LocationSelectionSource.gps);

    expect(container.read(bookingControllerProvider).pickup?.point, point);
    expect(
      container.read(bookingControllerProvider).pickup?.source,
      LocationSelectionSource.gps,
    );
  });
}

ProviderContainer _container(
  FakePlaceRepository fake, {
  RecordingAppErrorReporter? reporter,
}) {
  return ProviderContainer(
    overrides: [
      placeRepositoryProvider.overrideWithValue(fake),
      locationRepositoryProvider.overrideWithValue(FakeLocationRepository()),
      if (reporter != null)
        appErrorReporterProvider.overrideWithValue(reporter),
    ],
  );
}

class _QueuedAutocompleteRepository extends FakePlaceRepository {
  _QueuedAutocompleteRepository(this.results);

  final List<Future<List<PlacePrediction>>> results;
  var index = 0;

  @override
  Future<List<PlacePrediction>> autocomplete({
    required String query,
    required String sessionToken,
    LocationPoint? bias,
  }) {
    return results[index++];
  }
}

class _QueuedReverseRepository extends FakePlaceRepository {
  _QueuedReverseRepository(this.results);

  final List<Future<RideLocation?>> results;
  var index = 0;

  @override
  Future<RideLocation?> reverseGeocode({
    required LocationPoint point,
    required LocationSelectionSource source,
  }) {
    return results[index++];
  }
}
