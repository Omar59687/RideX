import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/features/history/data/fake_rider_trip_history_repository.dart';
import 'package:ridex/features/history/data/rider_trip_history_contract.dart';
import 'package:ridex/features/history/presentation/widgets/canonical_rider_history_list.dart';

const riderA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const riderB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

RiderHistoryTrip record(int n, String rider,
    {DriverTripLifecycleStatus status = DriverTripLifecycleStatus.completed}) {
  final suffix = n.toRadixString(16).padLeft(12, '0');
  return RiderHistoryTrip(
    tripId: '11111111-1111-4111-8111-$suffix',
    bookingRequestId: '22222222-2222-4222-8222-$suffix',
    riderId: rider,
    status: status,
    createdAt: DateTime.utc(2026, 11, 18).subtract(Duration(minutes: n)),
    updatedAt: DateTime.utc(2026, 11, 18),
    pickupLabel: 'Synthetic pickup $n',
    destinationLabel: 'Synthetic destination $n',
    lockedFareFils: 4000,
    currency: 'JOD',
  );
}

Widget screen(RiderTripHistoryRepository repository, String riderId,
    String? Function() currentRiderId, ValueChanged<String> onOpen) {
  return MaterialApp(
    home: Scaffold(
      body: CanonicalRiderHistoryList(
        repository: repository,
        riderId: riderId,
        currentRiderId: currentRiderId,
        onOpenTrip: onOpen,
      ),
    ),
  );
}

class _ControlledReader implements RiderTripHistoryRepository {
  final Completer<RiderHistoryPage> pending = Completer<RiderHistoryPage>();

  @override
  Future<RiderHistoryPage> readPage(RiderHistoryRequest request) =>
      pending.future;

  @override
  Future<RiderHistoryTrip?> readExactTrip({
    required String riderId,
    required String tripId,
  }) async => null;
}


class _ScriptedReader implements RiderTripHistoryRepository {
  final requests = <RiderHistoryRequest>[];
  final pending = <Completer<RiderHistoryPage>>[];

  @override
  Future<RiderHistoryPage> readPage(RiderHistoryRequest request) {
    requests.add(request);
    final completer = Completer<RiderHistoryPage>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<RiderHistoryTrip?> readExactTrip({
    required String riderId,
    required String tripId,
  }) async => null;
}

void main() {
  testWidgets('empty canonical history shows no demo records', (tester) async {
    final repository = FakeRiderTripHistoryRepository(
      records: const [], currentRiderId: () => riderA,
    );
    await tester.pumpWidget(screen(repository, riderA, () => riderA, (_) {}));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('canonical-history-empty')), findsOneWidget);
    expect(find.textContaining('Synthetic pickup'), findsNothing);
  });

  testWidgets('completed/cancelled filters remain Rider-scoped', (tester) async {
    final repository = FakeRiderTripHistoryRepository(
      records: [
        record(1, riderA),
        record(2, riderA, status: DriverTripLifecycleStatus.cancelledByRider),
        record(3, riderB),
      ],
      currentRiderId: () => riderA,
    );
    await tester.pumpWidget(screen(repository, riderA, () => riderA, (_) {}));
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetic pickup 1'), findsOneWidget);
    expect(find.textContaining('Synthetic pickup 2'), findsOneWidget);
    expect(find.textContaining('Synthetic pickup 3'), findsNothing);

    await tester.tap(find.byKey(const Key('canonical-filter-completed')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetic pickup 1'), findsOneWidget);
    expect(find.textContaining('Synthetic pickup 2'), findsNothing);

    await tester.tap(find.byKey(const Key('canonical-filter-cancelled')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetic pickup 1'), findsNothing);
    expect(find.textContaining('Synthetic pickup 2'), findsOneWidget);
  });

  testWidgets('foreign login does not display or open previous Rider Trip',
      (tester) async {
    String? current = riderA;
    final opened = <String>[];
    final repository = FakeRiderTripHistoryRepository(
      records: [record(1, riderA)],
      currentRiderId: () => current,
    );
    await tester.pumpWidget(
      screen(repository, riderA, () => current, opened.add),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetic pickup 1'), findsOneWidget);
    current = riderB;
    await tester.pumpWidget(
      screen(repository, riderA, () => current, opened.add),
    );
    await tester.pump();
    expect(find.textContaining('Synthetic pickup 1'), findsNothing);
    expect(find.textContaining('Sign in as the owning Rider'), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('stale response after Rider switch is never rendered',
      (tester) async {
    String? current = riderA;
    final repository = _ControlledReader();
    await tester.pumpWidget(
      screen(repository, riderA, () => current, (_) {}),
    );
    expect(find.byKey(const Key('canonical-history-loading')), findsOneWidget);
    current = riderB;
    repository.pending.complete(RiderHistoryPage(
      trips: [record(1, riderA)], nextCursor: null,
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetic pickup 1'), findsNothing);
    expect(find.textContaining('Sign in as the owning Rider'), findsOneWidget);
  });

  testWidgets('backend failure is not replaced with mock fallback',
      (tester) async {
    final repository = _ControlledReader();
    await tester.pumpWidget(screen(repository, riderA, () => riderA, (_) {}));
    repository.pending.completeError(
      const RiderHistoryException(RiderHistoryFailure.unavailable),
    );
    await tester.pumpAndSettle();
    expect(find.text('Trip history could not be loaded.'), findsOneWidget);
    expect(find.byKey(const Key('canonical-history-retry')), findsOneWidget);
  });
  testWidgets('load more deduplicates overlapping rows with stable cursor',
      (tester) async {
    final repo = _ScriptedReader();
    await tester.pumpWidget(screen(repo, riderA, () => riderA, (_) {}));
    final first = record(1, riderA);
    final second = record(2, riderA);
    final third = record(3, riderA);
    repo.pending[0].complete(RiderHistoryPage(
      trips: [first, second],
      nextCursor: RiderHistoryCursor(
        createdAt: second.createdAt, tripId: second.tripId,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('canonical-history-more')), findsOneWidget);
    await tester.tap(find.byKey(const Key('canonical-history-more')));
    await tester.pump();
    expect(repo.requests[1].cursor!.tripId, second.tripId);
    repo.pending[1].complete(RiderHistoryPage(
      trips: [second, third], nextCursor: null,
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('canonical-history-${second.tripId}')), findsOneWidget);
    expect(find.byKey(Key('canonical-history-${third.tripId}')), findsOneWidget);
    expect(find.byKey(const Key('canonical-history-more')), findsNothing);
  });

  testWidgets('failed next page retains rows and retry preserves cursor',
      (tester) async {
    final repo = _ScriptedReader();
    await tester.pumpWidget(screen(repo, riderA, () => riderA, (_) {}));
    final first = record(1, riderA);
    final cursor = RiderHistoryCursor(
      createdAt: first.createdAt, tripId: first.tripId,
    );
    repo.pending[0].complete(RiderHistoryPage(
      trips: [first], nextCursor: cursor,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('canonical-history-more')));
    await tester.pump();
    repo.pending[1].completeError(
      const RiderHistoryException(RiderHistoryFailure.unavailable),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(Key('canonical-history-${first.tripId}')), findsOneWidget);
    await tester.tap(find.byKey(const Key('canonical-history-retry')));
    await tester.pump();
    expect(repo.requests[2].cursor!.tripId, first.tripId);
    repo.pending[2].complete(RiderHistoryPage(
      trips: [record(2, riderA)], nextCursor: null,
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetic pickup 1'), findsOneWidget);
    expect(find.textContaining('Synthetic pickup 2'), findsOneWidget);
  });

  testWidgets('older filter response is discarded after filter change',
      (tester) async {
    final repo = _ScriptedReader();
    await tester.pumpWidget(screen(repo, riderA, () => riderA, (_) {}));
    await tester.tap(find.byKey(const Key('canonical-filter-cancelled')));
    await tester.pump();
    expect(repo.requests[1].filter, RiderHistoryFilter.cancelled);
    repo.pending[1].complete(RiderHistoryPage(
      trips: [record(2, riderA,
          status: DriverTripLifecycleStatus.cancelledByRider)],
      nextCursor: null,
    ));
    await tester.pumpAndSettle();
    repo.pending[0].complete(RiderHistoryPage(
      trips: [record(1, riderA)], nextCursor: null,
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetic pickup 1'), findsNothing);
    expect(find.textContaining('Synthetic pickup 2'), findsOneWidget);
  });

  testWidgets('adapter cannot display a foreign Rider trip',
      (tester) async {
    final repo = _ScriptedReader();
    await tester.pumpWidget(screen(repo, riderA, () => riderA, (_) {}));
    repo.pending[0].complete(RiderHistoryPage(
      trips: [record(1, riderB)], nextCursor: null,
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetic pickup 1'), findsNothing);
    expect(find.byKey(const Key('canonical-history-retry')), findsOneWidget);
  });

  testWidgets('can open only an owned canonical Trip ID', (tester) async {
    final opened = <String>[];
    final repo = FakeRiderTripHistoryRepository(
      records: [record(1, riderA)], currentRiderId: () => riderA,
    );
    await tester.pumpWidget(screen(repo, riderA, () => riderA, opened.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('canonical-history-${record(1, riderA).tripId}')));
    expect(opened, [record(1, riderA).tripId]);
  });

}
