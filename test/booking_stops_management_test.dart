import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/providers/session_providers.dart';

import 'helpers/fake_places.dart';

/// Covers ordered multi-stop management in [BookingController]:
/// add up to three stops, rejection of a fourth/invalid/duplicate stop,
/// removal, reorder, clear, estimate reset side-effects, and unchanged
/// routing-readiness semantics.
void main() {
  ProviderContainer createContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  RideLocation stopAt(double latitude, double longitude, [String label = '']) {
    return testLocation(
      latitude: latitude,
      longitude: longitude,
      label: label.isEmpty ? 'Stop $latitude,$longitude' : label,
    );
  }

  BookingController controllerOf(ProviderContainer container) {
    return container.read(bookingControllerProvider.notifier);
  }

  BookingDraft draftOf(ProviderContainer container) {
    return container.read(bookingControllerProvider);
  }

  test('adds up to three stops preserving list order', () {
    final container = createContainer();
    final controller = controllerOf(container);

    expect(controller.addStop(stopAt(31.90, 35.90, 'First')), isTrue);
    expect(controller.addStop(stopAt(31.91, 35.91, 'Second')), isTrue);
    expect(controller.addStop(stopAt(31.92, 35.92, 'Third')), isTrue);

    final stops = draftOf(container).stops;
    expect(stops.map((stop) => stop.label), ['First', 'Second', 'Third']);
  });

  test('rejects a fourth stop without changing state', () {
    final container = createContainer();
    final controller = controllerOf(container);

    controller.addStop(stopAt(31.90, 35.90, 'First'));
    controller.addStop(stopAt(31.91, 35.91, 'Second'));
    controller.addStop(stopAt(31.92, 35.92, 'Third'));
    final before = draftOf(container);

    expect(controller.addStop(stopAt(31.93, 35.93, 'Fourth')), isFalse);
    final after = draftOf(container);
    expect(after.stops, hasLength(BookingController.maxStops));
    expect(after.stops.map((stop) => stop.label), ['First', 'Second', 'Third']);
    expect(after, before);
  });

  test('maximum is exactly three', () {
    expect(BookingController.maxStops, 3);
  });

  test('invalid coordinates fail closed before reaching the draft', () {
    // The established invalid-coordinate definition (non-finite or
    // out-of-range latitude/longitude) is enforced by the LocationPoint
    // factory, so such points can never be wrapped in a RideLocation.
    // The controller additionally re-validates ranges defensively.
    expect(
      () => testLocation(latitude: double.nan, longitude: 35.90),
      throwsArgumentError,
    );
    expect(
      () => testLocation(latitude: 91, longitude: 35.90),
      throwsArgumentError,
    );
    expect(
      () => testLocation(latitude: 31.90, longitude: -181),
      throwsArgumentError,
    );

    // Boundary coordinates remain accepted by both the model and addStop.
    final container = createContainer();
    final controller = controllerOf(container);
    expect(controller.addStop(stopAt(-90, -180, 'Min corner')), isTrue);
    expect(controller.addStop(stopAt(90, 180, 'Max corner')), isTrue);
    expect(draftOf(container).stops, hasLength(2));
  });

  test('rejects duplicates of pickup, destination, and added stops', () {
    final container = createContainer();
    final controller = controllerOf(container);
    final pickup = testLocation(
      latitude: 31.95,
      longitude: 35.91,
      label: 'Pickup',
    );
    final destination = testLocation(
      latitude: 31.96,
      longitude: 35.92,
      label: 'Destination',
    );
    controller.setPickup(pickup);
    controller.setDestination(destination);

    // Same coordinates with a different label still count as duplicates.
    expect(
      controller.addStop(
        testLocation(
          latitude: 31.95,
          longitude: 35.91,
          label: 'Same as pickup',
        ),
      ),
      isFalse,
    );
    expect(
      controller.addStop(
        testLocation(
          latitude: 31.96,
          longitude: 35.92,
          label: 'Same as destination',
        ),
      ),
      isFalse,
    );
    expect(draftOf(container).stops, isEmpty);

    expect(controller.addStop(stopAt(31.97, 35.93, 'Stop')), isTrue);
    expect(
      controller.addStop(
        testLocation(
          latitude: 31.97,
          longitude: 35.93,
          label: 'Same as stop',
        ),
      ),
      isFalse,
    );
    expect(draftOf(container).stops, hasLength(1));
  });

  test('removeStopAt removes the indexed stop and keeps order', () {
    final container = createContainer();
    final controller = controllerOf(container);
    controller.addStop(stopAt(31.90, 35.90, 'First'));
    controller.addStop(stopAt(31.91, 35.91, 'Second'));
    controller.addStop(stopAt(31.92, 35.92, 'Third'));

    controller.removeStopAt(1);

    expect(
        draftOf(container).stops.map((stop) => stop.label), ['First', 'Third']);
  });

  test('removeStopAt ignores out-of-range indexes without side-effects', () {
    final container = createContainer();
    final controller = controllerOf(container);
    controller.addStop(stopAt(31.90, 35.90, 'Only'));
    controller.setVehicleType(MockData.vehicleTypes[1]);
    final before = draftOf(container);

    controller.removeStopAt(-1);
    controller.removeStopAt(1);
    controller.removeStopAt(99);

    expect(draftOf(container), before);
  });

  test('moveStop reorders stops', () {
    final container = createContainer();
    final controller = controllerOf(container);
    controller.addStop(stopAt(31.90, 35.90, 'First'));
    controller.addStop(stopAt(31.91, 35.91, 'Second'));
    controller.addStop(stopAt(31.92, 35.92, 'Third'));

    controller.moveStop(0, 2);
    expect(draftOf(container).stops.map((stop) => stop.label),
        ['Second', 'Third', 'First']);

    controller.moveStop(2, 0);
    expect(draftOf(container).stops.map((stop) => stop.label),
        ['First', 'Second', 'Third']);
  });

  test('moveStop ignores out-of-range or same-index moves', () {
    final container = createContainer();
    final controller = controllerOf(container);
    controller.addStop(stopAt(31.90, 35.90, 'First'));
    controller.addStop(stopAt(31.91, 35.91, 'Second'));
    controller.setVehicleType(MockData.vehicleTypes[1]);
    final before = draftOf(container);

    controller.moveStop(-1, 0);
    controller.moveStop(0, 2);
    controller.moveStop(0, -1);
    controller.moveStop(5, 0);
    controller.moveStop(0, 0);

    expect(draftOf(container), before);
  });

  test('clearStops empties the stop list', () {
    final container = createContainer();
    final controller = controllerOf(container);
    controller.addStop(stopAt(31.90, 35.90, 'First'));
    controller.addStop(stopAt(31.91, 35.91, 'Second'));

    controller.clearStops();

    expect(draftOf(container).stops, isEmpty);
  });

  test('empty stop list no-ops leave state untouched', () {
    final container = createContainer();
    final controller = controllerOf(container);
    controller.setVehicleType(MockData.vehicleTypes[1]);
    expect(draftOf(container).stops, isEmpty);

    var before = draftOf(container);
    controller.removeStopAt(0);
    expect(draftOf(container), before);
    controller.removeStopAt(-1);
    expect(draftOf(container), before);

    before = draftOf(container);
    controller.moveStop(0, 0);
    expect(draftOf(container), before);
    controller.moveStop(0, 1);
    expect(draftOf(container), before);
    controller.moveStop(-1, 0);
    expect(draftOf(container), before);
    controller.moveStop(5, 0);
    expect(draftOf(container), before);

    before = draftOf(container);
    controller.clearStops();
    expect(draftOf(container), before);
    expect(draftOf(container).stops, isEmpty);
  });

  test('stops mutations reset vehicle, fare, distance, and ETA', () {
    final container = createContainer();
    final controller = controllerOf(container);

    controller.setVehicleType(MockData.vehicleTypes[1]);
    controller.addStop(stopAt(31.90, 35.90, 'First'));
    var draft = draftOf(container);
    expect(draft.vehicleType, isNull);
    expect(draft.estimatedFare, 0);
    expect(draft.distanceKm, 0);
    expect(draft.etaMinutes, 0);

    controller.setVehicleType(MockData.vehicleTypes[2]);
    controller.addStop(stopAt(31.91, 35.91, 'Second'));
    controller.moveStop(0, 1);
    draft = draftOf(container);
    expect(draft.vehicleType, isNull);
    expect(draft.estimatedFare, 0);
    expect(draft.distanceKm, 0);
    expect(draft.etaMinutes, 0);
    expect(draft.stops.map((stop) => stop.label), ['Second', 'First']);

    controller.setVehicleType(MockData.vehicleTypes[0]);
    controller.removeStopAt(0);
    draft = draftOf(container);
    expect(draft.vehicleType, isNull);
    expect(draft.estimatedFare, 0);
    expect(draft.distanceKm, 0);
    expect(draft.etaMinutes, 0);

    controller.setVehicleType(MockData.vehicleTypes[0]);
    controller.clearStops();
    draft = draftOf(container);
    expect(draft.stops, isEmpty);
    expect(draft.vehicleType, isNull);
    expect(draft.estimatedFare, 0);
    expect(draft.distanceKm, 0);
    expect(draft.etaMinutes, 0);
  });

  test('routing readiness depends on pickup/destination only', () {
    final container = createContainer();
    final controller = controllerOf(container);

    expect(draftOf(container).isRoutingReady, isFalse);

    controller.addStop(stopAt(31.90, 35.90, 'Stop'));
    expect(draftOf(container).isRoutingReady, isFalse);

    controller.setPickup(
      testLocation(latitude: 31.95, longitude: 35.91, label: 'Pickup'),
    );
    expect(draftOf(container).isRoutingReady, isFalse);

    controller.setDestination(
      testLocation(latitude: 31.96, longitude: 35.92, label: 'Destination'),
    );
    expect(draftOf(container).isRoutingReady, isTrue);

    controller.addStop(stopAt(31.91, 35.91, 'Another'));
    controller.addStop(stopAt(31.92, 35.92, 'Third'));
    expect(draftOf(container).isRoutingReady, isTrue);

    controller.clearStops();
    expect(draftOf(container).isRoutingReady, isTrue);
  });
}
