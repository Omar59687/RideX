import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/features/history/data/fake_rider_trip_history_repository.dart';
import 'package:ridex/features/history/data/rider_trip_history_contract.dart';

const riderA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const riderB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

RiderHistoryTrip trip(int n, String rider, {
  DriverTripLifecycleStatus status = DriverTripLifecycleStatus.completed,
  DateTime? createdAt,
}) {
  final suffix = n.toRadixString(16).padLeft(12, '0');
  final created = createdAt ?? DateTime.utc(2026, 11, 18);
  return RiderHistoryTrip(
    tripId: '11111111-1111-4111-8111-$suffix',
    bookingRequestId: '22222222-2222-4222-8222-$suffix',
    riderId: rider,
    status: status,
    createdAt: created,
    updatedAt: created.add(const Duration(minutes: 1)),
    pickupLabel: 'Synthetic pickup',
    destinationLabel: 'Synthetic destination',
    lockedFareFils: 4500,
    currency: 'JOD',
  );
}

void main() {
  test('contract rejects mock IDs and unverified receipt claims', () {
    expect(
      () => RiderHistoryRequest(riderId: 'mock-rider'),
      throwsArgumentError,
    );
    expect(
      () => RiderHistoryTrip(
        tripId: 'mock-trip',
        bookingRequestId: 'mock-booking',
        riderId: riderA,
        status: DriverTripLifecycleStatus.completed,
        createdAt: DateTime.utc(2026, 11, 18),
        updatedAt: DateTime.utc(2026, 11, 18),
        pickupLabel: 'Pickup',
        destinationLabel: 'Destination',
        lockedFareFils: 0,
        currency: 'JOD',
      ),
      throwsA(isA<RiderHistoryException>()),
    );
    expect(
      () => RiderHistoryTrip(
        tripId: '11111111-1111-4111-8111-000000000001',
        bookingRequestId: '22222222-2222-4222-8222-000000000001',
        riderId: riderA,
        status: DriverTripLifecycleStatus.completed,
        createdAt: DateTime.utc(2026, 11, 18),
        updatedAt: DateTime.utc(2026, 11, 18),
        pickupLabel: 'Pickup',
        destinationLabel: 'Destination',
        lockedFareFils: 0,
        currency: 'JOD',
        verifiedReceiptIssued: true,
      ),
      throwsA(isA<RiderHistoryException>()),
    );
  });

  test('stable keyset pages do not duplicate same-time Trips', () async {
    final repository = FakeRiderTripHistoryRepository(
      records: [trip(1, riderA), trip(3, riderA), trip(2, riderA), trip(4, riderB)],
      currentRiderId: () => riderA,
    );
    final first = await repository.readPage(
      RiderHistoryRequest(riderId: riderA, limit: 2),
    );
    expect(first.trips.map((t) => t.tripId).toList(), [
      trip(3, riderA).tripId,
      trip(2, riderA).tripId,
    ]);
    expect(first.nextCursor, isNotNull);

    final second = await repository.readPage(
      RiderHistoryRequest(riderId: riderA, limit: 2, cursor: first.nextCursor),
    );
    expect(second.trips.map((t) => t.tripId), [trip(1, riderA).tripId]);
    expect(second.nextCursor, isNull);
  });

  test('filter exposes completed and cancelled separately', () async {
    final repository = FakeRiderTripHistoryRepository(
      records: [
        trip(1, riderA),
        trip(2, riderA, status: DriverTripLifecycleStatus.cancelledByRider),
        trip(3, riderA, status: DriverTripLifecycleStatus.failed),
      ],
      currentRiderId: () => riderA,
    );
    final completed = await repository.readPage(RiderHistoryRequest(
      riderId: riderA, filter: RiderHistoryFilter.completed,
    ));
    final cancelled = await repository.readPage(RiderHistoryRequest(
      riderId: riderA, filter: RiderHistoryFilter.cancelled,
    ));
    expect(completed.trips.map((e) => e.tripId), [trip(1, riderA).tripId]);
    expect(cancelled.trips.map((e) => e.tripId), [trip(2, riderA).tripId]);
  });

  test('foreign Rider cannot access page or exact Trip', () async {
    final repository = FakeRiderTripHistoryRepository(
      records: [trip(1, riderA), trip(2, riderB)],
      currentRiderId: () => riderA,
    );
    await expectLater(
      repository.readPage(RiderHistoryRequest(riderId: riderB)),
      throwsA(isA<RiderHistoryException>()),
    );
    expect(
      await repository.readExactTrip(
        riderId: riderA, tripId: trip(2, riderB).tripId,
      ),
      isNull,
    );
  });
}
