import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/features/history/data/fake_rider_trip_history_repository.dart';
import 'package:ridex/features/history/data/rider_active_trip_restoration.dart';
import 'package:ridex/features/history/data/rider_active_trip_restore_controller.dart';
import 'package:ridex/features/history/data/rider_history_integration_bundle.dart';
import 'package:ridex/features/history/data/rider_trip_history_contract.dart';

const riderA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const riderB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const tripId = '11111111-1111-4111-8111-000000000001';
const bookingId = '22222222-2222-4222-8222-000000000001';

RiderHistoryTrip sample() => RiderHistoryTrip(
      tripId: tripId,
      bookingRequestId: bookingId,
      riderId: riderA,
      status: DriverTripLifecycleStatus.inProgress,
      createdAt: DateTime.utc(2026, 11, 18),
      updatedAt: DateTime.utc(2026, 11, 18, 0, 1),
      pickupLabel: 'Synthetic pickup',
      destinationLabel: 'Synthetic destination',
      lockedFareFils: 5000,
      currency: 'JOD',
    );

class _ActiveReader implements RiderActiveTripReadPort {
  _ActiveReader(this.trip);
  final RiderHistoryTrip trip;

  @override
  Future<List<RiderHistoryTrip>> findActiveCandidates({
    required String riderId,
    required int limit,
  }) async => [trip];

  @override
  Future<RiderHistoryTrip?> rereadExact({
    required String riderId,
    required String tripId,
  }) async => trip;
}

void main() {
  test('bundle joins exact detail and active restoration without financial inference',
      () async {
    String? current = riderA;
    final history = FakeRiderTripHistoryRepository(
      records: [sample()],
      currentRiderId: () => current,
    );
    final bundle = RiderHistoryIntegrationBundle(
      history: history,
      activeTrips: _ActiveReader(sample()),
      currentRiderId: () => current,
      isAuthorizedRider: () => current == riderA,
      sessionEpoch: () => null,
    );
    final exact = await bundle.details.readExact(
      riderId: riderA,
      tripId: tripId,
    );
    expect(exact!.trip.tripId, tripId);
    expect(exact.financial, isNull);
    final restored = await bundle.activeController.refresh(riderA);
    expect(restored.stage, RiderActiveRestoreStage.restored);
    current = riderB;
    bundle.onAuthIdentityChanged();
    expect(bundle.activeController.state.stage, RiderActiveRestoreStage.idle);
    expect(bundle.activeController.state.snapshot, isNull);
    await expectLater(
      bundle.details.readExact(riderId: riderA, tripId: tripId),
      throwsA(isA<RiderHistoryException>()),
    );
    bundle.dispose();
  });
}
