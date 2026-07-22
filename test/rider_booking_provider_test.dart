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
}
