import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/rider_payments/data/a04_rider_financial_read_adapter.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';
import 'package:ridex/features/rider_payments/models/rider_receipt_state.dart';

const _tripId = 'a1b2c3d4-e5f6-4a1b-8c2d-a1b2c3d4e5f6';
const _bookingId = '22222222-2222-4222-8222-222222222222';
const _riderId = '33333333-3333-4333-8333-333333333333';
const _driverId = '44444444-4444-4444-8444-444444444444';
const _paymentId = '55555555-5555-4555-8555-555555555555';
const _receiptId = '66666666-6666-4666-8666-666666666666';

final _rider = AppUser(
  id: _riderId,
  name: 'Rider',
  email: 'rider@example.test',
  role: RideRole.rider,
);

RiderCheckoutTrip _trip({
  String tripId = _tripId,
  String riderId = _riderId,
  int version = 4,
  int currentFareFils = 7450,
  DriverTripLifecycleStatus status = DriverTripLifecycleStatus.accepted,
  PaymentMethod method = PaymentMethod.card,
}) =>
    RiderCheckoutTrip(
      tripId: tripId,
      bookingRequestId: _bookingId,
      riderId: riderId,
      driverId: _driverId,
      version: version,
      currentFareFils: currentFareFils,
      currency: 'JOD',
      status: status,
      paymentMethod: method,
    );

Map<String, Object?> _row({
  Object? contractVersion = 1,
  Object? tripId = _tripId,
  Object? tripVersion = 4,
  Object? tripStatus = 'accepted',
  Object? paymentId = _paymentId,
  Object? paymentVersion = 2,
  Object? paymentMethod = 'card',
  Object? amount = 7450,
  Object? currency = 'JOD',
  Object? cardStatus = 'cardPaymentSucceeded',
  Object? receiptEvidence = 'linked',
  Object? receiptId = _receiptId,
  Object? receiptNumber = 'RDX-20261120-AB12CD34',
  Object? receiptAmount = 7450,
  Object? receiptCurrency = 'JOD',
  Object? receiptIssuedAt = '2026-11-20T00:00:00.000Z',
}) =>
    {
      'contract_version': contractVersion,
      'trip_id': tripId,
      'trip_version': tripVersion,
      'trip_status': tripStatus,
      'payment_id': paymentId,
      'payment_version': paymentVersion,
      'payment_method': paymentMethod,
      'amount_fils': amount,
      'currency': currency,
      'cash_status': null,
      'card_status': cardStatus,
      'receipt_evidence': receiptEvidence,
      'receipt_id': receiptId,
      'receipt_number': receiptNumber,
      'receipt_amount_fils': receiptAmount,
      'receipt_currency': receiptCurrency,
      'receipt_issued_at': receiptIssuedAt,
    };

class _TripReader implements A04AuthorizedTripContextReader {
  RiderCheckoutTrip? trip;
  Completer<RiderCheckoutTrip?>? gate;
  final reads = <({String tripId, String riderId})>[];

  @override
  Future<RiderCheckoutTrip?> readAuthorizedTrip({
    required String tripId,
    required String riderId,
  }) async {
    reads.add((tripId: tripId, riderId: riderId));
    final currentGate = gate;
    if (currentGate != null) {
      gate = null;
      return currentGate.future;
    }
    return trip;
  }
}

class _Transport implements A04FinancialReadTransport {
  Object? response = [_row()];
  Object? error;
  Completer<Object?>? gate;
  final reads = <String>[];

  @override
  Future<Object?> readFinancialRow({required String tripId}) async {
    reads.add(tripId);
    final currentGate = gate;
    if (currentGate != null) {
      gate = null;
      return currentGate.future;
    }
    final currentError = error;
    error = null;
    if (currentError != null) throw currentError;
    return response;
  }
}

void main() {
  late _TripReader tripReader;
  late _Transport transport;
  late SessionState session;
  late A04RiderFinancialReadAdapter adapter;

  setUp(() {
    tripReader = _TripReader()..trip = _trip();
    transport = _Transport();
    session = SessionState.fromUser(_rider);
    adapter = A04RiderFinancialReadAdapter(
      tripReader: tripReader,
      transport: transport,
      readSession: () => session,
    );
  });

  Future<void> loadContext() async {
    expect(await adapter.readTrip(tripId: _tripId), isNotNull);
  }

  test('maps exact Card/JOD row and linked receipt evidence', () async {
    await loadContext();

    final paymentRead = await adapter.readCardPayment(tripId: _tripId);
    expect(paymentRead, isA<RiderCheckoutPaymentFound>());
    final payment = (paymentRead as RiderCheckoutPaymentFound).payment;
    expect(payment.paymentId, _paymentId);
    expect(payment.bookingRequestId, _bookingId);
    expect(payment.tripId, _tripId);
    expect(payment.version, 2);
    expect(payment.amountFils, 7450);

    final receiptRead = await adapter.readReceipt(
      tripId: _tripId,
      paymentId: _paymentId,
    );
    expect(receiptRead, isA<RiderCanonicalReceiptFound>());
    final receipt = (receiptRead as RiderCanonicalReceiptFound).receipt;
    expect(receipt.receiptId, _receiptId);
    expect(receipt.paymentId, _paymentId);
    expect(receipt.amountPaidFils, 7450);
  });

  test('linked receipt evidence does not promote pending Card status',
      () async {
    transport.response = [_row(cardStatus: 'cardPaymentPending')];
    await loadContext();

    final paymentRead = await adapter.readCardPayment(tripId: _tripId);
    expect(paymentRead, isA<RiderCheckoutPaymentFound>());
    expect(
      (paymentRead as RiderCheckoutPaymentFound).payment.status,
      CardPaymentStatus.cardPaymentPending,
    );
    expect(
      await adapter.readReceipt(tripId: _tripId, paymentId: _paymentId),
      isA<RiderCanonicalReceiptFound>(),
    );
  });

  test('unverified receipt evidence is UNKNOWN, never not-issued', () async {
    transport.response = [
      _row(
        receiptEvidence: 'unverified',
        receiptId: null,
        receiptNumber: null,
        receiptAmount: null,
        receiptCurrency: null,
        receiptIssuedAt: null,
      ),
    ];
    await loadContext();
    await adapter.readCardPayment(tripId: _tripId);

    await expectLater(
      adapter.readReceipt(tripId: _tripId, paymentId: _paymentId),
      throwsA(isA<RiderReceiptOutcomeUnknownException>()),
    );
  });

  test('zero rows and P0002 remain unknown outcomes', () async {
    await loadContext();
    transport.response = <Object?>[];
    await expectLater(
      adapter.readCardPayment(tripId: _tripId),
      throwsA(
        isA<RiderCheckoutPaymentReadException>().having(
          (error) => error.failure,
          'failure',
          RiderCheckoutPaymentReadFailure.unknownOutcome,
        ),
      ),
    );

    transport.error = StateError('P0002: Payment was not found');
    await expectLater(
      adapter.readCardPayment(tripId: _tripId),
      throwsA(
        isA<RiderCheckoutPaymentReadException>().having(
          (error) => error.failure,
          'failure',
          RiderCheckoutPaymentReadFailure.unknownOutcome,
        ),
      ),
    );
  });

  test('malformed A04 response maps to invalid response', () async {
    await loadContext();
    transport.response = [
      {'contract_version': 1, 'trip_id': _tripId},
    ];
    await expectLater(
      adapter.readCardPayment(tripId: _tripId),
      throwsA(
        isA<RiderCheckoutPaymentReadException>().having(
          (error) => error.failure,
          'failure',
          RiderCheckoutPaymentReadFailure.invalidResponse,
        ),
      ),
    );
  });

  test('malformed identities, status, versions and currency fail closed', () {
    final malformedRows = [
      _row(tripId: 'not-a-uuid'),
      _row(contractVersion: 2),
      _row(paymentId: 'not-a-uuid'),
      _row(tripStatus: 'requested'),
      _row(cardStatus: 'paid'),
      _row(tripVersion: 0),
      _row(paymentVersion: -1),
      _row(paymentVersion: 2147483648),
      _row(amount: -1),
      _row(currency: 'USD'),
      _row(paymentMethod: 'cash'),
      _row(receiptNumber: 'receipt-1'),
    ];
    for (final row in malformedRows) {
      expect(
        () => A04FinancialReadParser.parse([row]),
        throwsA(isA<FormatException>()),
        reason: 'Expected malformed row rejection: $row',
      );
    }
  });

  test('unknown Trip status is normalized to FormatException', () {
    expect(
      () => A04FinancialReadParser.parse([_row(tripStatus: 'requested')]),
      throwsA(isA<FormatException>()),
    );
  });

  test('unknown Payment method is normalized to FormatException', () {
    expect(
      () => A04FinancialReadParser.parse([_row(paymentMethod: 'credit')]),
      throwsA(isA<FormatException>()),
    );
  });

  test('unknown Card status is normalized to FormatException', () {
    expect(
      () => A04FinancialReadParser.parse([_row(cardStatus: 'paid')]),
      throwsA(isA<FormatException>()),
    );
  });

  test('linked receipt amount and currency must exactly match payment', () {
    expect(
      () => A04FinancialReadParser.parse([_row(receiptAmount: 7451)]),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => A04FinancialReadParser.parse([_row(receiptCurrency: 'USD')]),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => A04FinancialReadParser.parse([
        _row(receiptIssuedAt: '2026-11-20T00:00:00'),
      ]),
      throwsA(isA<FormatException>()),
    );
  });

  test('Trip identity, version, status and method must match verified context',
      () async {
    await loadContext();
    for (final row in [
      _row(tripId: '77777777-7777-4777-8777-777777777777'),
      _row(tripVersion: 3),
      _row(tripStatus: 'inProgress'),
    ]) {
      transport.response = [row];
      await expectLater(
        adapter.readCardPayment(tripId: _tripId),
        throwsA(
          isA<RiderCheckoutPaymentReadException>().having(
            (error) => error.failure,
            'failure',
            RiderCheckoutPaymentReadFailure.unknownOutcome,
          ),
        ),
      );
    }
  });

  test('canonical fare amount must match A04 Payment amount', () async {
    tripReader.trip = _trip(currentFareFils: 7451);
    await loadContext();

    await expectLater(
      adapter.readCardPayment(tripId: _tripId),
      throwsA(
        isA<RiderCheckoutPaymentReadException>().having(
          (error) => error.failure,
          'failure',
          RiderCheckoutPaymentReadFailure.unknownOutcome,
        ),
      ),
    );
  });

  test('foreign Rider context is not returned or used for financial reads',
      () async {
    tripReader.trip = _trip(riderId: '77777777-7777-4777-8777-777777777777');

    expect(await adapter.readTrip(tripId: _tripId), isNull);
    await expectLater(
      adapter.readCardPayment(tripId: _tripId),
      throwsA(isA<RiderCheckoutPaymentReadException>()),
    );
    expect(transport.reads, isEmpty);
  });

  test('blocked Rider session cannot read Trip or financial data', () async {
    session = SessionState.fromUser(
      const AppUser(
        id: _riderId,
        name: 'Blocked Rider',
        email: 'blocked@example.test',
        role: RideRole.rider,
        isBlocked: true,
      ),
    );

    expect(await adapter.readTrip(tripId: _tripId), isNull);
    expect(tripReader.reads, isEmpty);
    expect(transport.reads, isEmpty);
  });

  test('logout while A04 read is pending fences the late response', () async {
    await loadContext();
    final gate = Completer<Object?>();
    transport.gate = gate;
    final pending = adapter.readCardPayment(tripId: _tripId);
    session = const SessionState.unauthenticated();
    gate.complete([_row()]);

    await expectLater(
      pending,
      throwsA(
        isA<RiderCheckoutPaymentReadException>().having(
          (error) => error.failure,
          'failure',
          RiderCheckoutPaymentReadFailure.unauthorized,
        ),
      ),
    );
    await expectLater(
      adapter.readReceipt(tripId: _tripId, paymentId: _paymentId),
      throwsA(isA<RiderReceiptOutcomeUnknownException>()),
    );
  });

  test('A to B to A replacement does not restore old session ownership',
      () async {
    await loadContext();
    final gate = Completer<Object?>();
    transport.gate = gate;
    final pending = adapter.readCardPayment(tripId: _tripId);
    session = SessionState.fromUser(
      const AppUser(
        id: '77777777-7777-4777-8777-777777777777',
        name: 'Other Rider',
        email: 'other@example.test',
        role: RideRole.rider,
      ),
    );
    session = SessionState.fromUser(_rider);
    gate.complete([_row()]);

    await expectLater(
      pending,
      throwsA(isA<RiderCheckoutPaymentReadException>()),
    );
  });

  test('Trip reader session replacement fences late Trip context', () async {
    final gate = Completer<RiderCheckoutTrip?>();
    tripReader.gate = gate;
    final pending = adapter.readTrip(tripId: _tripId);
    session = const SessionState.unauthenticated();
    gate.complete(_trip());

    await expectLater(
      pending,
      throwsA(
        isA<RiderCheckoutTripReadException>().having(
          (error) => error.failure,
          'failure',
          RiderCheckoutTripReadFailure.unauthorized,
        ),
      ),
    );
  });
}
