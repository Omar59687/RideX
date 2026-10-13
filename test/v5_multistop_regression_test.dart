import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/route_models.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/fare_repository.dart';

import 'helpers/fake_places.dart';

/// V5-03 offline multi-stop regression coverage.
///
/// Pins existing production behavior only: ordered stops survive unrelated
/// draft mutations, `requested_stops` keep their order through draft
/// create/update, `RouteRequest.fromDraft` stays null-safe when endpoints
/// are missing, and trip creation carries the ordered stops forward.
/// Recovery models ([PendingFareLock], [BookingHandoff]) deliberately carry
/// no stop surface — multi-stop durability lives in the draft and in each
/// draft mutation's `requested_stops` — so no recovery-stop test is
/// invented here. Widget/flow coverage lives in `booking_stops_flow_test`,
/// unit management in `booking_stops_management_test`, and route mapping in
/// `route_stops_test`; nothing here duplicates those cases.
///
/// This file does NOT replace physical-device evidence for the multi-stop
/// ride (map rendering, GPS legs, hosted draft/quote with stops).
void main() {
  ProviderContainer createContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  RideLocation stopAt(double latitude, double longitude, String label) {
    return testLocation(
      latitude: latitude,
      longitude: longitude,
      label: label,
    );
  }

  void seedEndpoints(BookingController controller) {
    controller.setPickup(
      testLocation(latitude: 31.95, longitude: 35.91, label: 'Pickup'),
    );
    controller.setDestination(
      testLocation(latitude: 31.96, longitude: 35.92, label: 'Destination'),
    );
  }

  void seedThreeStops(BookingController controller) {
    expect(controller.addStop(stopAt(31.90, 35.90, 'First')), isTrue);
    expect(controller.addStop(stopAt(31.91, 35.91, 'Second')), isTrue);
    expect(controller.addStop(stopAt(31.92, 35.92, 'Third')), isTrue);
  }

  List<String?> labelsOf(BookingDraft draft) =>
      [for (final stop in draft.stops) stop.label];

  test('endpoint and vehicle changes preserve ordered stops', () {
    final container = createContainer();
    final controller = container.read(bookingControllerProvider.notifier);
    seedEndpoints(controller);
    seedThreeStops(controller);

    controller.setVehicleType(MockData.vehicleTypes[1]);
    controller.setPickup(
      testLocation(latitude: 31.94, longitude: 35.90, label: 'New pickup'),
    );
    controller.setDestination(
      testLocation(latitude: 31.97, longitude: 35.93, label: 'New destination'),
    );

    final draft = container.read(bookingControllerProvider);
    expect(labelsOf(draft), ['First', 'Second', 'Third']);
    expect(draft.pickup!.label, 'New pickup');
    expect(draft.destination!.label, 'New destination');
    // Endpoint changes reset the vehicle and estimates (existing behavior)
    // but must never drop the ordered stops.
    expect(draft.vehicleType, isNull);
    expect(draft.estimatedFare, 0);
  });

  test('fare estimation preserves ordered stops', () async {
    final container = createContainer();
    final controller = container.read(bookingControllerProvider.notifier);
    seedEndpoints(controller);
    seedThreeStops(controller);
    controller.setVehicleType(MockData.vehicleTypes[0]);

    await controller.estimateFare();

    final draft = container.read(bookingControllerProvider);
    expect(draft.estimatedFare, MockData.vehicleTypes[0].baseFare);
    expect(labelsOf(draft), ['First', 'Second', 'Third']);
  });

  test('remove-then-add and move compose into the expected order', () {
    final container = createContainer();
    final controller = container.read(bookingControllerProvider.notifier);
    seedEndpoints(controller);
    seedThreeStops(controller);

    controller.removeStopAt(1);
    expect(
      controller.addStop(stopAt(31.93, 35.93, 'Fourth')),
      isTrue,
    );
    expect(labelsOf(container.read(bookingControllerProvider)),
        ['First', 'Third', 'Fourth']);

    controller.moveStop(2, 0);
    expect(labelsOf(container.read(bookingControllerProvider)),
        ['Fourth', 'First', 'Third']);

    final request =
        RouteRequest.fromDraft(container.read(bookingControllerProvider))!;
    expect(
      request.intermediatePoints.map((point) => point.latitude),
      [31.93, 31.90, 31.92],
    );
  });

  test('fromDraft stays null-safe when stops exist without endpoints', () {
    const withoutEndpoints = BookingDraft(
      stops: [],
    );
    expect(RouteRequest.fromDraft(withoutEndpoints), isNull);

    final pickupOnly = BookingDraft(
      pickup: testLocation(
        latitude: 31.95,
        longitude: 35.91,
        label: 'Pickup',
      ),
      stops: [
        testLocation(latitude: 31.90, longitude: 35.90, label: 'Stop'),
      ],
    );
    expect(RouteRequest.fromDraft(pickupOnly), isNull);
  });

  test('draft create and update send ordered requested_stops', () async {
    final paramsByCall = <Map<String, dynamic>>[];
    final repository = SupabaseFareRepository(
      bookingMutationGate: (dispatch) => dispatch(),
      rpc: (
          {required String name, required Map<String, dynamic> params}) async {
        paramsByCall.add({'name': name, ...params});
        return {'id': 'booking-1', 'version': paramsByCall.length};
      },
      quoteEdge: (_) async => throw StateError('unexpected edge call'),
    );
    const stops = [
      FareStopInput(
        location: FareRouteLocation(
          latitude: 31.90,
          longitude: 35.90,
          label: 'First',
        ),
        label: 'First',
      ),
      FareStopInput(
        location: FareRouteLocation(latitude: 31.91, longitude: 35.91),
        label: 'Second',
      ),
      FareStopInput(
        location: FareRouteLocation(
          latitude: 31.92,
          longitude: 35.92,
          label: 'Third',
        ),
        label: 'Third',
      ),
    ];

    await repository.createBookingDraft(
      pickup: const FareRouteLocation(
        latitude: 31.95,
        longitude: 35.92,
        label: 'Pickup',
      ),
      destination: const FareRouteLocation(
        latitude: 32.0,
        longitude: 35.95,
        label: 'Destination',
      ),
      vehicleTypeCode: 'economy',
      paymentMethod: 'cash',
      stops: stops,
    );
    await repository.updateBookingDraft(
      bookingRequestId: 'booking-1',
      expectedBookingVersion: 1,
      pickup: const FareRouteLocation(
        latitude: 31.95,
        longitude: 35.92,
        label: 'Pickup',
      ),
      destination: const FareRouteLocation(
        latitude: 32.0,
        longitude: 35.95,
        label: 'Destination',
      ),
      vehicleTypeCode: 'economy',
      paymentMethod: 'cash',
      stops: stops,
    );

    expect(paramsByCall, hasLength(2));
    expect(paramsByCall[0]['name'], 'rider_create_booking_draft');
    expect(paramsByCall[1]['name'], 'rider_update_booking_draft');
    for (final params in paramsByCall) {
      final requested = params['requested_stops'] as List;
      expect(requested, hasLength(3));
      expect(
        [for (final stop in requested) (stop as Map)['label']],
        ['First', 'Second', 'Third'],
      );
      expect(
        (requested[0] as Map)['location'],
        {'latitude': 31.90, 'longitude': 35.90, 'label': 'First'},
      );
    }
  });

  test('trip creation carries ordered stops into the booking', () async {
    final container = createContainer();
    final controller = container.read(bookingControllerProvider.notifier);
    seedEndpoints(controller);
    seedThreeStops(controller);
    controller.setVehicleType(MockData.vehicleTypes[0]);
    await controller.estimateFare();

    final trip = await MockTripsRepository()
        .createTrip(container.read(bookingControllerProvider));

    expect(
      [for (final stop in trip.booking.stops) stop.label],
      ['First', 'Second', 'Third'],
    );
    expect(trip.booking.pickup!.label, 'Pickup');
    expect(trip.booking.destination!.label, 'Destination');
    expect(trip.finalFare, MockData.vehicleTypes[0].baseFare);
  });
}
