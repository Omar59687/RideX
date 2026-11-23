import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/rider_payments/data/supabase_rider_financial_reader.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';
import 'package:ridex/features/rider_payments/models/rider_receipt_state.dart';

const _riderId = 'a5100000-0000-4000-8000-000000000001';
const _driverId = 'a5100000-0000-4000-8000-000000000002';
const _tripId = 'a5100000-0000-4000-8000-000000000003';
const _bookingId = 'a5100000-0000-4000-8000-000000000004';
const _paymentId = 'a5100000-0000-4000-8000-000000000005';
const _receiptId = 'a5100000-0000-4000-8000-000000000006';

SessionState _riderSession() => SessionState.fromUser(
      const AppUser(
        id: _riderId,
        name: 'Synthetic Rider',
        email: 'rider@example.invalid',
        role: RideRole.rider,
      ),
    );

Map<String, Object?> _tripRow({
  String tripId = _tripId,
  String riderId = _riderId,
  String driverId = _driverId,
  int version = 3,
  String status = 'accepted',
  String method = 'card',
  int amount = 3250,
  String currency = 'JOD',
}) => {
      'id': tripId,
      'booking_request_id': _bookingId,
      'rider_id': riderId,
      'driver_id': driverId,
      'version': version,
      'status': status,
      'payment_method': method,
      'current_fare_fils': amount,
      'currency': currency,
    };

Map<String, Object?> _financialRow({
  int contractVersion = 1,
  String tripId = _tripId,
  int tripVersion = 3,
  String tripStatus = 'accepted',
  String paymentId = _paymentId,
  int paymentVersion = 4,
  String method = 'card',
  int amount = 3250,
  String currency = 'JOD',
  String? cardStatus = 'cardPaymentAuthorized',
  String? cashStatus,
  String receiptEvidence = 'unverified',
  String? receiptId,
  String? receiptNumber,
  int? receiptAmount,
  String? receiptCurrency,
  String? receiptIssuedAt,
}) => {
      'contract_version': contractVersion,
      'trip_id': tripId,
      'trip_version': tripVersion,
      'trip_status': tripStatus,
      'payment_id': paymentId,
      'payment_version': paymentVersion,
      'payment_method': method,
      'amount_fils': amount,
      'currency': currency,
      'cash_status': cashStatus,
      'card_status': cardStatus,
      'receipt_evidence': receiptEvidence,
      'receipt_id': receiptId,
      'receipt_number': receiptNumber,
      'receipt_amount_fils': receiptAmount,
      'receipt_currency': receiptCurrency,
      'receipt_issued_at': receiptIssuedAt,
    };

final class _FakeReadTransport implements RiderFinancialReadTransport {
  Object sdkSession = Object();
  String userId = _riderId;
  bool expired = false;
  Map<String, Object?>? profile = {
    'id': _riderId,
    'role': 'rider',
    'is_blocked': false,
  };
  Map<String, Object?>? trip = _tripRow();
  Object? financial = [_financialRow()];
  Future<void> Function()? onFinancialRead;
  final profileReads = <String>[];
  final tripReads = <String>[];
  final financialReads = <String>[];

  @override
  Object get sessionIdentity => sdkSession;

  @override
  String? get authenticatedUserId => userId;

  @override
  bool get sessionExpired => expired;

  @override
  Future<Map<String, Object?>?> readProfile(String riderId) async {
    profileReads.add(riderId);
    return profile == null ? null : Map.of(profile!);
  }

  @override
  Future<Map<String, Object?>?> readTrip({
    required String tripId,
    required String riderId,
  }) async {
    tripReads.add('$tripId:$riderId');
    return trip == null ? null : Map.of(trip!);
  }

  @override
  Future<Object?> readTripFinancial(String tripId) async {
    financialReads.add(tripId);
    await onFinancialRead?.call();
    return financial;
  }
}

void main() {
  late _FakeReadTransport transport;
  late SessionState session;
  late SupabaseRiderFinancialReader reader;

  setUp(() {
    transport = _FakeReadTransport();
    session = _riderSession();
    reader = SupabaseRiderFinancialReader(
      transport: transport,
      readSession: () => session,
    );
  });

  test('composes an exact assigned Rider Trip from RLS Trip read', () async {
    final trip = await reader.readTrip(tripId: _tripId);
    expect(trip, isNotNull);
    expect(trip!.tripId, _tripId);
    expect(trip.bookingRequestId, _bookingId);
    expect(trip.riderId, _riderId);
    expect(trip.driverId, _driverId);
    expect(trip.version, 3);
    expect(trip.status, DriverTripLifecycleStatus.accepted);
    expect(trip.paymentMethod, PaymentMethod.card);
    expect(transport.profileReads, hasLength(2));
  });

  test('maps valid v1 JOD Card evidence only after exact Trip rereads',
      () async {
    await reader.readTrip(tripId: _tripId);
    final result = await reader.readCardPayment(tripId: _tripId);
    expect(result, isA<RiderCheckoutPaymentFound>());
    final payment = (result as RiderCheckoutPaymentFound).payment;
    expect(payment.paymentId, _paymentId);
    expect(payment.tripId, _tripId);
    expect(payment.bookingRequestId, _bookingId);
    expect(payment.amountFils, 3250);
    expect(payment.currency, 'JOD');
    expect(payment.version, 4);
    expect(payment.status, CardPaymentStatus.cardPaymentAuthorized);
    expect(transport.tripReads, hasLength(3));
  });

  test('malformed contract version fails closed as invalid response', () async {
    await reader.readTrip(tripId: _tripId);
    transport.financial = [_financialRow(contractVersion: 2)];
    await expectLater(
      reader.readCardPayment(tripId: _tripId),
      throwsA(isA<RiderCheckoutPaymentReadException>().having(
        (error) => error.failure,
        'failure',
        RiderCheckoutPaymentReadFailure.invalidResponse,
      )),
    );
  });

  test('zero A04 rows remain UNKNOWN, never action required', () async {
    await reader.readTrip(tripId: _tripId);
    transport.financial = const <Object?>[];
    await expectLater(
      reader.readCardPayment(tripId: _tripId),
      throwsA(isA<RiderCheckoutPaymentReadException>().having(
        (error) => error.failure,
        'failure',
        RiderCheckoutPaymentReadFailure.unknownOutcome,
      )),
    );
  });

  test('stale Trip version in A04 response is UNKNOWN', () async {
    await reader.readTrip(tripId: _tripId);
    transport.financial = [_financialRow(tripVersion: 2)];
    await expectLater(
      reader.readCardPayment(tripId: _tripId),
      throwsA(isA<RiderCheckoutPaymentReadException>().having(
        (error) => error.failure,
        'failure',
        RiderCheckoutPaymentReadFailure.unknownOutcome,
      )),
    );
  });

  test('Trip changed while A04 is pending cannot publish Payment evidence',
      () async {
    await reader.readTrip(tripId: _tripId);
    transport.onFinancialRead = () async {
      transport.trip = _tripRow(version: 4);
    };

    await expectLater(
      reader.readCardPayment(tripId: _tripId),
      throwsA(isA<RiderCheckoutPaymentReadException>().having(
        (error) => error.failure,
        'failure',
        RiderCheckoutPaymentReadFailure.unknownOutcome,
      )),
    );
  });

  test('amount or currency mismatch cannot be accepted as canonical', () async {
    await reader.readTrip(tripId: _tripId);
    transport.financial = [_financialRow(amount: 3251)];
    await expectLater(
      reader.readCardPayment(tripId: _tripId),
      throwsA(isA<RiderCheckoutPaymentReadException>().having(
        (error) => error.failure,
        'failure',
        RiderCheckoutPaymentReadFailure.unknownOutcome,
      )),
    );

    transport.financial = [_financialRow(currency: 'USD')];
    await expectLater(
      reader.readCardPayment(tripId: _tripId),
      throwsA(isA<RiderCheckoutPaymentReadException>().having(
        (error) => error.failure,
        'failure',
        RiderCheckoutPaymentReadFailure.invalidResponse,
      )),
    );
  });

  test('blocked or changed Rider profile is unauthorized', () async {
    transport.profile = {
      'id': _riderId,
      'role': 'rider',
      'is_blocked': true,
    };
    await expectLater(
      reader.readTrip(tripId: _tripId),
      throwsA(isA<RiderCheckoutTripReadException>().having(
        (error) => error.failure,
        'failure',
        RiderCheckoutTripReadFailure.unauthorized,
      )),
    );
  });

  test('foreign Trip and malformed assigned Driver evidence are rejected', () async {
    transport.trip = _tripRow(tripId: 'a5100000-0000-4000-8000-000000000099');
    await expectLater(
      reader.readTrip(tripId: _tripId),
      throwsA(isA<RiderCheckoutTripReadException>()),
    );

    transport.trip = _tripRow(driverId: 'foreign-driver-id');
    await expectLater(
      reader.readTrip(tripId: _tripId),
      throwsA(isA<RiderCheckoutTripReadException>().having(
        (error) => error.failure,
        'failure',
        RiderCheckoutTripReadFailure.invalidResponse,
      )),
    );

    transport.trip = _tripRow();
    final trip = await reader.readTrip(tripId: _tripId);
    expect(trip!.driverId, _driverId);
  });

  test('unverified A04 receipt evidence stays UNKNOWN', () async {
    await reader.readTrip(tripId: _tripId);
    await reader.readCardPayment(tripId: _tripId);
    transport.financial = [_financialRow(
      cardStatus: 'cardPaymentSucceeded',
      receiptEvidence: 'unverified',
    )];
    await expectLater(
      reader.readReceipt(tripId: _tripId, paymentId: _paymentId),
      throwsA(isA<RiderReceiptOutcomeUnknownException>()),
    );
  });

  test('linked receipt requires exact returned payment and money evidence',
      () async {
    await reader.readTrip(tripId: _tripId);
    transport.financial = [_financialRow(cardStatus: 'cardPaymentSucceeded')];
    await reader.readCardPayment(tripId: _tripId);
    transport.financial = [
      _financialRow(
        cardStatus: 'cardPaymentSucceeded',
        receiptEvidence: 'linked',
        receiptId: _receiptId,
        receiptNumber: 'RDX-SYNTHETIC-1',
        receiptAmount: 3250,
        receiptCurrency: 'JOD',
        receiptIssuedAt: '2026-11-23T10:00:00Z',
      ),
    ];
    final result = await reader.readReceipt(
      tripId: _tripId,
      paymentId: _paymentId,
    );
    expect(result, isA<RiderCanonicalReceiptFound>());
    final receipt = (result as RiderCanonicalReceiptFound).receipt;
    expect(receipt.receiptId, _receiptId);
    expect(receipt.tripId, _tripId);
    expect(receipt.paymentId, _paymentId);
    expect(receipt.amountPaidFils, 3250);
    expect(receipt.currency, 'JOD');
    expect(receipt.paymentMethod, PaymentMethod.card);
  });

  test('linked receipt with wrong Payment ID is UNKNOWN', () async {
    await reader.readTrip(tripId: _tripId);
    transport.financial = [_financialRow(cardStatus: 'cardPaymentSucceeded')];
    await reader.readCardPayment(tripId: _tripId);
    transport.financial = [
      _financialRow(
        paymentId: 'a5100000-0000-4000-8000-000000000099',
        cardStatus: 'cardPaymentSucceeded',
        receiptEvidence: 'linked',
        receiptId: _receiptId,
        receiptNumber: 'RDX-SYNTHETIC-1',
        receiptAmount: 3250,
        receiptCurrency: 'JOD',
        receiptIssuedAt: '2026-11-23T10:00:00Z',
      ),
    ];
    await expectLater(
      reader.readReceipt(tripId: _tripId, paymentId: _paymentId),
      throwsA(isA<RiderReceiptOutcomeUnknownException>()),
    );
  });

  test('linked receipt with mismatched amount is UNKNOWN', () async {
    await reader.readTrip(tripId: _tripId);
    transport.financial = [_financialRow(cardStatus: 'cardPaymentSucceeded')];
    await reader.readCardPayment(tripId: _tripId);
    transport.financial = [
      _financialRow(
        cardStatus: 'cardPaymentSucceeded',
        receiptEvidence: 'linked',
        receiptId: _receiptId,
        receiptNumber: 'RDX-SYNTHETIC-1',
        receiptAmount: 3251,
        receiptCurrency: 'JOD',
        receiptIssuedAt: '2026-11-23T10:00:00Z',
      ),
    ];
    await expectLater(
      reader.readReceipt(tripId: _tripId, paymentId: _paymentId),
      throwsA(isA<RiderReceiptOutcomeUnknownException>()),
    );
  });

  test('older Payment version cannot replace the last observed version',
      () async {
    await reader.readTrip(tripId: _tripId);
    await reader.readCardPayment(tripId: _tripId);
    transport.financial = [_financialRow(paymentVersion: 3)];

    await expectLater(
      reader.readCardPayment(tripId: _tripId),
      throwsA(isA<RiderCheckoutPaymentReadException>().having(
        (error) => error.failure,
        'failure',
        RiderCheckoutPaymentReadFailure.unknownOutcome,
      )),
    );
  });

  test('A-B-A SDK session replacement fences a delayed A04 result', () async {
    await reader.readTrip(tripId: _tripId);
    final entered = Completer<void>();
    final release = Completer<void>();
    transport.onFinancialRead = () async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    };
    final pending = reader.readCardPayment(tripId: _tripId);
    await entered.future;
    transport.sdkSession = Object();
    transport.userId = 'a5100000-0000-4000-8000-000000000099';
    session = SessionState.fromUser(
      const AppUser(
        id: 'a5100000-0000-4000-8000-000000000099',
        name: 'Synthetic Other Rider',
        email: 'other-rider@example.invalid',
        role: RideRole.rider,
      ),
    );
    transport.sdkSession = Object();
    transport.userId = _riderId;
    session = _riderSession();
    release.complete();
    await expectLater(
      pending,
      throwsA(isA<RiderCheckoutPaymentReadException>().having(
        (error) => error.failure,
        'failure',
        RiderCheckoutPaymentReadFailure.unauthorized,
      )),
    );
  });
}
