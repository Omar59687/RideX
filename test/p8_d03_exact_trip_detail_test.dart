import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/features/history/data/fake_rider_trip_history_repository.dart';
import 'package:ridex/features/history/data/rider_exact_trip_detail.dart';
import 'package:ridex/features/history/data/rider_trip_history_contract.dart';
import 'package:ridex/features/history/presentation/widgets/canonical_rider_trip_detail.dart';

const a = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const b = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const tripId = '11111111-1111-4111-8111-000000000001';
const bookingId = '22222222-2222-4222-8222-000000000001';
const paymentId = '33333333-3333-4333-8333-000000000001';

RiderHistoryTrip record({
  String rider = a,
  DriverTripLifecycleStatus status = DriverTripLifecycleStatus.completed,
  String? payment = paymentId,
}) => RiderHistoryTrip(
  tripId: tripId,
  bookingRequestId: bookingId,
  riderId: rider,
  status: status,
  createdAt: DateTime.utc(2026, 11, 18, 8),
  updatedAt: DateTime.utc(2026, 11, 18, 9),
  pickupLabel: 'Synthetic pickup',
  destinationLabel: 'Synthetic destination',
  lockedFareFils: 4500,
  currency: 'JOD',
  paymentId: payment,
);

class _Finance implements RiderTripFinancialReadPort {
  _Finance(this.result);
  final RiderDetailFinancialRead? result;
  int reads = 0;

  @override
  Future<RiderDetailFinancialRead?> readForTrip({
    required String riderId,
    required String tripId,
    required String bookingRequestId,
    required String paymentId,
  }) async {
    reads++;
    return result;
  }
}

class _DelayedHistory implements RiderTripHistoryRepository {
  final completer = Completer<RiderHistoryTrip?>();
  @override
  Future<RiderHistoryTrip?> readExactTrip({
    required String riderId, required String tripId,
  }) => completer.future;
  @override
  Future<RiderHistoryPage> readPage(RiderHistoryRequest request) async =>
      RiderHistoryPage(trips: [], nextCursor: null);
}

RiderExactTripDetailReader reader(
  RiderTripHistoryRepository history, {
  RiderTripFinancialReadPort? finance,
  String? Function()? actor,
  bool Function()? allowed,
  Object? Function()? epoch,
}) => RiderExactTripDetailReader(
  history: history,
  financial: finance,
  activeRiderId: actor ?? () => a,
  isAuthorized: allowed ?? () => true,
  sessionEpoch: epoch ?? () => null,
);

Widget detailWidget(RiderExactTripDetailReader source, {
  String rider = a,
  bool Function()? current,
}) => MaterialApp(
  home: Scaffold(
    body: CanonicalRiderTripDetail(
      reader: source,
      riderId: rider,
      tripId: tripId,
      isCurrentRider: current ?? () => true,
    ),
  ),
);

RiderDetailFinancialRead evidence({
  String rider = a,
  RiderDetailPaymentState payment =
      RiderDetailPaymentState.cashReportedPaidUnverified,
  RiderDetailReceiptState receipt =
      RiderDetailReceiptState.reportedIssuedUnverified,
}) => RiderDetailFinancialRead(
  tripId: tripId,
  bookingRequestId: bookingId,
  riderId: rider,
  paymentId: paymentId,
  payment: payment,
  receipt: receipt,
);

void main() {
  test('exact Trip detail never substitutes foreign Rider record', () async {
    final history = FakeRiderTripHistoryRepository(
      records: [record(rider: b)], currentRiderId: () => a,
    );
    final result = await reader(history).readExact(riderId: a, tripId: tripId);
    expect(result, isNull);
  });

  test('blocked Rider is denied before any repository access', () async {
    final history = _DelayedHistory();
    await expectLater(
      reader(history, allowed: () => false).readExact(
        riderId: a, tripId: tripId,
      ),
      throwsA(isA<RiderHistoryException>()),
    );
  });

  test('session epoch change during read invalidates result', () async {
    Object session = Object();
    final history = _DelayedHistory();
    final source = reader(history, epoch: () => session);
    final pending = source.readExact(riderId: a, tripId: tripId);
    session = Object();
    history.completer.complete(record());
    await expectLater(pending, throwsA(isA<RiderHistoryException>()));
  });

  test('payment read is skipped when backend did not link payment ID', () async {
    final finance = _Finance(evidence());
    final history = FakeRiderTripHistoryRepository(
      records: [record(payment: null)], currentRiderId: () => a,
    );
    final result = await reader(history, finance: finance)
        .readExact(riderId: a, tripId: tripId);
    expect(result!.financial, isNull);
    expect(finance.reads, 0);
  });

  test('mismatched payment linkage fails closed', () async {
    final finance = _Finance(evidence(rider: b));
    final history = FakeRiderTripHistoryRepository(
      records: [record()], currentRiderId: () => a,
    );
    await expectLater(
      reader(history, finance: finance).readExact(
        riderId: a, tripId: tripId,
      ),
      throwsA(isA<RiderHistoryException>()),
    );
  });

  testWidgets('completed Trip does not imply payment or receipt', (tester) async {
    final history = FakeRiderTripHistoryRepository(
      records: [record()], currentRiderId: () => a,
    );
    await tester.pumpWidget(detailWidget(reader(history)));
    await tester.pumpAndSettle();
    expect(find.text('Trip status: completed'), findsOneWidget);
    expect(find.text('Payment: Not verified'), findsOneWidget);
    expect(
      find.text('Receipt: Unavailable (not proof of non-issuance)'),
      findsOneWidget,
    );
    expect(find.textContaining('Payment completed'), findsNothing);
  });

  testWidgets('card UNKNOWN and late receipt are honest states', (tester) async {
    final history = FakeRiderTripHistoryRepository(
      records: [record()], currentRiderId: () => a,
    );
    final finance = _Finance(evidence(
      payment: RiderDetailPaymentState.cardUnknown,
      receipt: RiderDetailReceiptState.unavailable,
    ));
    await tester.pumpWidget(detailWidget(reader(history, finance: finance)));
    await tester.pumpAndSettle();
    expect(find.text('Payment: Card status unknown'), findsOneWidget);
    expect(
      find.text('Receipt: Unavailable (not proof of non-issuance)'),
      findsOneWidget,
    );
  });

  testWidgets('reported success is explicitly unverified', (tester) async {
    final history = FakeRiderTripHistoryRepository(
      records: [record()], currentRiderId: () => a,
    );
    final finance = _Finance(evidence());
    await tester.pumpWidget(detailWidget(reader(history, finance: finance)));
    await tester.pumpAndSettle();
    expect(
      find.text('Payment: Cash reported paid — verification pending'),
      findsOneWidget,
    );
    expect(
      find.text('Receipt: Reported issued — verification pending'),
      findsOneWidget,
    );
  });

  testWidgets('Rider switch hides detail and prevents old data display',
      (tester) async {
    var authorized = true;
    final history = FakeRiderTripHistoryRepository(
      records: [record()], currentRiderId: () => a,
    );
    final source = reader(history);
    await tester.pumpWidget(
      detailWidget(source, current: () => authorized),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetic pickup'), findsOneWidget);
    authorized = false;
    await tester.pumpWidget(
      detailWidget(source, current: () => authorized),
    );
    await tester.pump();
    expect(find.textContaining('Synthetic pickup'), findsNothing);
    expect(find.text('Trip access could not be verified.'), findsOneWidget);
  });

  testWidgets('cancelled Trip does not imply charge or refund',
      (tester) async {
    final history = FakeRiderTripHistoryRepository(
      records: [record(
        status: DriverTripLifecycleStatus.cancelledByRider,
        payment: null,
      )],
      currentRiderId: () => a,
    );
    await tester.pumpWidget(detailWidget(reader(history)));
    await tester.pumpAndSettle();
    expect(find.text('Trip status: cancelledByRider'), findsOneWidget);
    expect(find.text('Payment: Not verified'), findsOneWidget);
    expect(find.textContaining('Refund completed'), findsNothing);
  });
}
