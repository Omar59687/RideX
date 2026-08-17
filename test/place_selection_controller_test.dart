import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/errors/place_exception.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/place_prediction.dart';
import 'package:ridex/core/models/place_selection_state.dart';
import 'package:ridex/core/providers/place_providers.dart';
import 'package:ridex/core/providers/location_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';

import 'helpers/fake_places.dart';
import 'helpers/fake_location.dart';

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

ProviderContainer _container(FakePlaceRepository fake) {
  return ProviderContainer(
    overrides: [
      placeRepositoryProvider.overrideWithValue(fake),
      locationRepositoryProvider.overrideWithValue(FakeLocationRepository()),
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
