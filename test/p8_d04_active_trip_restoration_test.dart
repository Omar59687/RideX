import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/features/history/data/rider_active_trip_restoration.dart';
import 'package:ridex/features/history/data/rider_active_trip_restore_controller.dart';
import 'package:ridex/features/history/data/rider_trip_history_contract.dart';

const riderA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const riderB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

RiderHistoryTrip active(int n, {
  String rider = riderA,
  DriverTripLifecycleStatus status = DriverTripLifecycleStatus.accepted,
  int minute = 1,
}) {
  final suffix = n.toRadixString(16).padLeft(12, '0');
  return RiderHistoryTrip(
    tripId: '11111111-1111-4111-8111-$suffix',
    bookingRequestId: '22222222-2222-4222-8222-$suffix',
    riderId: rider,
    status: status,
    createdAt: DateTime.utc(2026, 11, 18),
    updatedAt: DateTime.utc(2026, 11, 18, 0, minute),
    pickupLabel: 'Synthetic pickup',
    destinationLabel: 'Synthetic destination',
    lockedFareFils: 4500,
    currency: 'JOD',
  );
}

class _Port implements RiderActiveTripReadPort {
  _Port({
    required this.onCandidates,
    required this.onExact,
  });

  final Future<List<RiderHistoryTrip>> Function(String rider, int limit)
      onCandidates;
  final Future<RiderHistoryTrip?> Function(String rider, String trip)
      onExact;
  int candidatesCalled = 0;
  int exactCalled = 0;
  int? requestedLimit;

  @override
  Future<List<RiderHistoryTrip>> findActiveCandidates({
    required String riderId,
    required int limit,
  }) {
    candidatesCalled++;
    requestedLimit = limit;
    return onCandidates(riderId, limit);
  }

  @override
  Future<RiderHistoryTrip?> rereadExact({
    required String riderId,
    required String tripId,
  }) {
    exactCalled++;
    return onExact(riderId, tripId);
  }
}

_Port port(List<RiderHistoryTrip> trips, {RiderHistoryTrip? exact}) => _Port(
  onCandidates: (_, __) async => trips,
  onExact: (_, __) async => exact ?? trips.single,
);

RiderActiveTripRestorer make(
  RiderActiveTripReadPort reader, {
  String? Function()? actor,
  bool Function()? authorized,
  Object? Function()? epoch,
}) => RiderActiveTripRestorer(
  reader: reader,
  currentRiderId: actor ?? () => riderA,
  isAuthorized: authorized ?? () => true,
  sessionEpoch: epoch ?? () => null,
);

void main() {
  test('restores only independently reread nonterminal Trip', () async {
    final first = active(1);
    final reread = active(1, status: DriverTripLifecycleStatus.inProgress,
        minute: 2);
    final reader = port([first], exact: reread);
    final found = await make(reader).restore(riderA);
    expect(found!.tripId, first.tripId);
    expect(found.trip.status, DriverTripLifecycleStatus.inProgress);
    expect(reader.requestedLimit, 2);
    expect(reader.exactCalled, 1);
  });

  test('empty candidate set is normal no-active result', () async {
    final reader = _Port(
      onCandidates: (_, __) async => [],
      onExact: (_, __) async => active(1),
    );
    expect(await make(reader).restore(riderA), isNull);
    expect(reader.exactCalled, 0);
  });

  test('multiple active Trips fail closed, not arbitrary selection', () async {
    final reader = _Port(
      onCandidates: (_, __) async => [active(1), active(2)],
      onExact: (_, __) async => active(1),
    );
    await expectLater(make(reader).restore(riderA),
        throwsA(isA<RiderActiveRestoreException>()));
    expect(reader.exactCalled, 0);
  });

  test('foreign Rider candidate is rejected', () async {
    final reader = port([active(1, rider: riderB)]);
    await expectLater(make(reader).restore(riderA),
        throwsA(isA<RiderActiveRestoreException>()));
    expect(reader.exactCalled, 0);
  });

  test('terminal discovered Trip fails closed', () async {
    final reader = port([active(1,
        status: DriverTripLifecycleStatus.completed)]);
    await expectLater(make(reader).restore(riderA),
        throwsA(isA<RiderActiveRestoreException>()));
    expect(reader.exactCalled, 0);
  });

  test('Trip that ends between discovery and reread is not restored',
      () async {
    final reader = port([active(1)], exact: active(1,
        status: DriverTripLifecycleStatus.cancelledByRider));
    expect(await make(reader).restore(riderA), isNull);
  });

  test('older exact Trip snapshot is rejected', () async {
    final reader = port([active(1, minute: 3)],
        exact: active(1, minute: 2));
    await expectLater(make(reader).restore(riderA),
        throwsA(isA<RiderActiveRestoreException>()));
  });

  test('blocked or unauthenticated Rider never touches backend', () async {
    final reader = port([active(1)]);
    await expectLater(make(reader, authorized: () => false).restore(riderA),
        throwsA(isA<RiderActiveRestoreException>()));
    expect(reader.candidatesCalled, 0);
  });

  test('session A to B to A change during awaited read fails closed',
      () async {
    Object currentEpoch = Object();
    final candidates = Completer<List<RiderHistoryTrip>>();
    final reader = _Port(
      onCandidates: (_, __) => candidates.future,
      onExact: (_, __) async => active(1),
    );
    final restoring = make(reader, epoch: () => currentEpoch).restore(riderA);
    currentEpoch = Object(); // A -> B -> A, same Rider ID, newer session
    candidates.complete([active(1)]);
    await expectLater(restoring, throwsA(isA<RiderActiveRestoreException>()));
    expect(reader.exactCalled, 0);
  });

  test('session switch during exact reread cannot restore', () async {
    Object currentEpoch = Object();
    final exact = Completer<RiderHistoryTrip?>();
    final reader = _Port(
      onCandidates: (_, __) async => [active(1)],
      onExact: (_, __) => exact.future,
    );
    final restoring = make(reader, epoch: () => currentEpoch).restore(riderA);
    await Future<void>.delayed(Duration.zero);
    currentEpoch = Object();
    exact.complete(active(1));
    await expectLater(restoring, throwsA(isA<RiderActiveRestoreException>()));
  });

  test('unknown backend read returns error, not no-active', () async {
    final reader = _Port(
      onCandidates: (_, __) async => throw StateError('network failure'),
      onExact: (_, __) async => active(1),
    );
    await expectLater(make(reader).restore(riderA),
        throwsA(isA<RiderActiveRestoreException>()));
  });

  test('stale refresh cannot replace later fresh successful result',
      () async {
    final pending = Completer<List<RiderHistoryTrip>>();
    var calls = 0;
    final reader = _Port(
      onCandidates: (_, __) {
        calls++;
        return calls == 1 ? pending.future : Future.value([active(2)]);
      },
      onExact: (_, tripId) async => active(tripId == active(2).tripId ? 2 : 1),
    );
    final controller = RiderActiveTripRestoreController(make(reader));
    final old = controller.refresh(riderA);
    final fresh = await controller.refresh(riderA);
    expect(fresh.stage, RiderActiveRestoreStage.restored);
    expect(fresh.snapshot!.tripId, active(2).tripId);
    pending.complete([active(1)]);
    await old;
    expect(controller.state.snapshot!.tripId, active(2).tripId);
  });

  test('logout invalidation clears restored Trip immediately', () async {
    final controller = RiderActiveTripRestoreController(make(port([active(1)])));
    await controller.refresh(riderA);
    expect(controller.state.stage, RiderActiveRestoreStage.restored);
    controller.invalidate();
    expect(controller.state.stage, RiderActiveRestoreStage.idle);
    expect(controller.state.snapshot, isNull);
  });

  test('unavailable state is retryable on reconnect', () async {
    var calls = 0;
    final reader = _Port(
      onCandidates: (_, __) async {
        calls++;
        if (calls == 1) throw StateError('offline');
        return [active(1)];
      },
      onExact: (_, __) async => active(1),
    );
    final controller = RiderActiveTripRestoreController(make(reader));
    expect((await controller.refresh(riderA)).stage,
        RiderActiveRestoreStage.unavailable);
    expect((await controller.refresh(riderA)).stage,
        RiderActiveRestoreStage.restored);
  });
}
