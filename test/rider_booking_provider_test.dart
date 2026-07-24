import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';

void main() {
  test('rider categories match the approved deterministic demo data', () {
    expect(
      MockData.vehicleTypes.map((vehicle) => vehicle.id),
      ['economy', 'standard', 'premium'],
    );
    expect(
      MockData.vehicleTypes.map((vehicle) => vehicle.baseFare),
      [4.20, 5.80, 8.90],
    );
    expect(
      MockData.vehicleTypes.map((vehicle) => vehicle.arrivalMinutes),
      [3, 5, 7],
    );
    expect(
      MockData.vehicleTypes.map((vehicle) => vehicle.capacity),
      everyElement(4),
    );
  });

  test('booking controller preserves explicit vehicle selection for review',
      () async {
    final container = ProviderContainer(
      overrides: [
        bookingRepositoryProvider.overrideWith(
          (ref) => MockBookingRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final standard = MockData.vehicleTypes[1];
    container.read(bookingControllerProvider.notifier).setVehicleType(standard);
    await container.read(bookingControllerProvider.notifier).estimateFare();

    final booking = container.read(bookingControllerProvider);
    expect(booking.vehicleType, standard);
    expect(booking.estimatedFare, 5.80);
  });

  test('changing either endpoint clears stale vehicle and fare', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(bookingControllerProvider.notifier);

    controller.setVehicleType(MockData.vehicleTypes[1]);
    controller.setDestination(MockData.locations[1]);
    expect(container.read(bookingControllerProvider).vehicleType, isNull);
    expect(container.read(bookingControllerProvider).estimatedFare, 0);

    controller.setVehicleType(MockData.vehicleTypes[2]);
    controller.setPickup(MockData.locations[0]);
    expect(container.read(bookingControllerProvider).vehicleType, isNull);
    expect(container.read(bookingControllerProvider).estimatedFare, 0);
  });

  test('sign out clears session-scoped booking, trip, and preferences',
      () async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => MockAuthRepository()),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(bookingControllerProvider.notifier)
        .setVehicleType(MockData.vehicleTypes[2]);
    container
        .read(activeTripControllerProvider.notifier)
        .setTrip(MockData.sampleTrip());
    container.read(notificationPreferencesProvider.notifier).state =
        const NotificationPreferences(push: false, sms: false, email: true);
    container.read(driverOnlineProvider.notifier).state = false;

    await container.read(sessionControllerProvider.notifier).continueAsDemo();
    await container.read(sessionControllerProvider.notifier).signOut();

    expect(container.read(bookingControllerProvider).vehicleType, isNull);
    expect(container.read(activeTripControllerProvider), isNull);
    expect(container.read(notificationPreferencesProvider).email, isFalse);
    expect(container.read(driverOnlineProvider), isTrue);
  });
}
