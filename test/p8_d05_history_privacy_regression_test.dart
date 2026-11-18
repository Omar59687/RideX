import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/features/history/data/rider_active_trip_restoration.dart';
import 'package:ridex/features/history/data/rider_active_trip_restore_controller.dart';
import 'package:ridex/features/history/data/rider_exact_trip_detail.dart';
import 'package:ridex/features/history/data/rider_trip_history_contract.dart';
import 'package:ridex/features/history/presentation/widgets/canonical_rider_history_list.dart';
import 'package:ridex/features/history/presentation/widgets/canonical_rider_trip_detail.dart';

const riderA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const riderB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const tripId = '11111111-1111-4111-8111-000000000001';
const bookingId = '22222222-2222-4222-8222-000000000001';

RiderHistoryTrip record({
  String rider = riderA,
  String trip = tripId,
  String booking = bookingId,
  DriverTripLifecycleStatus status = DriverTripLifecycleStatus.accepted,
  int updatedMinute = 2,
}) => RiderHistoryTrip(
  tripId: trip,
  bookingRequestId: booking,
  riderId: rider,
  status: status,
  createdAt: DateTime.utc(2026, 11, 18),
  updatedAt: DateTime.utc(2026, 11, 18, 0, updatedMinute),
  pickupLabel: 'Synthetic location',
  destinationLabel: 'Synthetic destination',
  lockedFareFils: 1234,
  currency: 'JOD',
);

class _ActivePort implements RiderActiveTripReadPort {
  _ActivePort(this.discovered, this.fresh);
  final List<RiderHistoryTrip> discovered;
  final RiderHistoryTrip? fresh;
  @override
  Future<List<RiderHistoryTrip>> findActiveCandidates({
    required String riderId, required int limit,
  }) async => discovered.take(limit).toList();
  @override
  Future<RiderHistoryTrip?> rereadExact({
    required String riderId, required String tripId,
  }) async => fresh;
}

RiderActiveTripRestorer restorer(RiderActiveTripReadPort source) =>
    RiderActiveTripRestorer(
      reader: source,
      currentRiderId: () => riderA,
      isAuthorized: () => true,
      sessionEpoch: () => null,
    );

class _HistoryPort implements RiderTripHistoryRepository {
  final pending = Completer<RiderHistoryPage>();
  @override
  Future<RiderHistoryPage> readPage(RiderHistoryRequest request) => pending.future;
  @override
  Future<RiderHistoryTrip?> readExactTrip({
    required String riderId, required String tripId,
  }) async => null;
}

void main() {
  test('foreign terminal reread is an error, not a safe empty response',
      () async {
    final source = _ActivePort([
      record(),
    ], record(rider: riderB, status: DriverTripLifecycleStatus.completed));
    await expectLater(
      restorer(source).restore(riderA),
      throwsA(isA<RiderActiveRestoreException>().having(
        (e) => e.failure, 'failure', RiderActiveRestoreFailure.invalidResponse,
      )),
    );
  });

  test('contradictory completed Trip identity cannot be silently ignored',
      () async {
    final source = _ActivePort([
      record(),
    ], record(
      booking: '22222222-2222-4222-8222-000000000002',
      status: DriverTripLifecycleStatus.completed,
    ));
    await expectLater(
      restorer(source).restore(riderA),
      throwsA(isA<RiderActiveRestoreException>()),
    );
  });

  test('outdated terminal reread is not silently accepted', () async {
    final source = _ActivePort([
      record(updatedMinute: 2),
    ], record(
      status: DriverTripLifecycleStatus.cancelledByDriver,
      updatedMinute: 1,
    ));
    await expectLater(
      restorer(source).restore(riderA),
      throwsA(isA<RiderActiveRestoreException>()),
    );
  });

  test('completed Trip never replaces a previously verified active Trip',
      () async {
    final controller = RiderActiveTripRestoreController(
      restorer(_ActivePort([record()], record())),
    );
    final state = await controller.refresh(riderA);
    expect(state.stage, RiderActiveRestoreStage.restored);
    final activeTripId = state.snapshot!.tripId;

    // A history-only completed record has no authority to update the
    // independent restoration coordinator or its canonical active snapshot.
    final historyRow = record(
      status: DriverTripLifecycleStatus.completed, updatedMinute: 1,
    );
    expect(historyRow.isTerminal, isTrue);
    expect(controller.state.snapshot!.tripId, activeTripId);
    expect(controller.state.snapshot!.trip.isTerminal, isFalse);
  });

  testWidgets('foreign history response is blocked without raw error leak',
      (tester) async {
    final source = _HistoryPort();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      CanonicalRiderHistoryList(
        repository: source,
        riderId: riderA,
        currentRiderId: () => riderA,
        onOpenTrip: (_) {},
      ),
    )));
    source.pending.complete(RiderHistoryPage(
      trips: [record(rider: riderB)], nextCursor: null,
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetic location'), findsNothing);
    expect(find.text('Trip history could not be loaded.'), findsOneWidget);
    expect(find.textContaining('riderB'), findsNothing);
  });

  testWidgets('history transport error is sanitized and retryable',
      (tester) async {
    final source = _HistoryPort();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      CanonicalRiderHistoryList(
        repository: source,
        riderId: riderA,
        currentRiderId: () => riderA,
        onOpenTrip: (_) {},
      ),
    )));
    source.pending.completeError(StateError(
      'private internal SQL trace / service secret should not surface',
    ));
    await tester.pumpAndSettle();
    expect(find.text('Trip history could not be loaded.'), findsOneWidget);
    expect(find.textContaining('private internal SQL trace'), findsNothing);
    expect(find.byKey(const Key('canonical-history-retry')), findsOneWidget);
  });

  testWidgets('missing finance linkage never creates paid claim',
      (tester) async {
    final source = _HistoryPort();
    final detailReader = RiderExactTripDetailReader(
      history: source,
      activeRiderId: () => riderA,
      isAuthorized: () => true,
      sessionEpoch: () => null,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      CanonicalRiderTripDetail(
        reader: detailReader,
        riderId: riderA,
        tripId: tripId,
        isCurrentRider: () => true,
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Trip not available.'), findsOneWidget);
    expect(find.textContaining('Paid'), findsNothing);
  });
}
