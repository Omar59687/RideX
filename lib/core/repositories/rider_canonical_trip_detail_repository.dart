import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/repositories/canonical_payment_repository.dart';
import 'package:ridex/core/repositories/payment_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum RiderTripDetailFailure { unauthorized, unavailable, invalidResponse }

final class RiderTripDetailException implements Exception {
  const RiderTripDetailException(this.failure);
  final RiderTripDetailFailure failure;
}

enum RiderReceiptEvidence { issued, unverified }

/// Created only after participant-scoped discovery and independent RPC reads.
/// This is a read snapshot, never permission to perform a financial operation.
final class RiderCanonicalTripDetail {
  const RiderCanonicalTripDetail._(
      this.tripId, this.tripVersion, this.payment, this.receipt);
  final String tripId;
  final int tripVersion;
  final CashPayment payment;
  final RiderReceiptEvidence receipt;

  /// Preserve every fils; use the usual two decimals only when exact.
  String get amountDisplay {
    final fils = payment.amountFils;
    final fraction = (fils % 1000).toString().padLeft(3, '0');
    return 'JOD ${fils ~/ 1000}.${fils % 10 == 0 ? fraction.substring(0, 2) : fraction}';
  }
}

/// One latest completed Cash Trip, not a replacement history/matching system.
/// No caller-supplied Trip/Payment identifiers are accepted by [loadLatest].
final class RiderCanonicalTripDetailRepository {
  RiderCanonicalTripDetailRepository(
      {required this.client,
      required this.riderId,
      required this.payments,
      required this.isCurrent})
      : _session = client.auth.currentSession;

  final SupabaseClient client;
  final String riderId;
  final PaymentRepository payments;
  final bool Function() isCurrent;
  final Session? _session;
  static final _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  Never _fail(RiderTripDetailFailure failure) =>
      throw RiderTripDetailException(failure);

  void _current() {
    if (_session == null ||
        _session.isExpired ||
        _session.user.id != riderId ||
        !_uuid.hasMatch(riderId) ||
        !identical(client.auth.currentSession, _session) ||
        !isCurrent()) {
      _fail(RiderTripDetailFailure.unauthorized);
    }
  }

  Future<T> _read<T>(Future<T> Function() action) async {
    _current();
    final value = await action().timeout(const Duration(seconds: 15));
    _current();
    return value;
  }

  Future<void> _profile() async {
    final row = await _read(() => client
        .from('users')
        .select('id,role,is_blocked')
        .eq('id', riderId)
        .maybeSingle());
    if (row == null ||
        row['id'] != riderId ||
        row['role'] != 'rider' ||
        row['is_blocked'] != false) {
      _fail(RiderTripDetailFailure.unauthorized);
    }
  }

  String _id(Object? value) {
    if (value is! String || !_uuid.hasMatch(value)) {
      _fail(RiderTripDetailFailure.invalidResponse);
    }
    return value;
  }

  Map<String, dynamic> _trip(Object? value) {
    if (value is! Map) _fail(RiderTripDetailFailure.invalidResponse);
    final row = Map<String, dynamic>.from(value);
    _id(row['id']);
    _id(row['booking_request_id']);
    if (row['rider_id'] != riderId) _fail(RiderTripDetailFailure.unauthorized);
    if (row['status'] != 'completed' ||
        row['payment_method'] != 'cash' ||
        row['version'] is! int ||
        (row['version'] as int) < 1) {
      _fail(RiderTripDetailFailure.invalidResponse);
    }
    return row;
  }

  Future<RiderCanonicalTripDetail?> loadLatest() async {
    try {
      await _profile();
      // Existing trips_participant_select RLS is the authority. Additional
      // filters bound the query; response ownership is checked independently.
      final rows = await _read(() => client
          .from('trips')
          .select(
              'id,booking_request_id,rider_id,status,version,payment_method')
          .eq('rider_id', riderId)
          .eq('status', 'completed')
          .eq('payment_method', 'cash')
          .order('created_at', ascending: false)
          .order('id', ascending: true)
          .limit(1));
      if (rows.isEmpty) return null;
      if (rows.length != 1) _fail(RiderTripDetailFailure.invalidResponse);
      final trip = _trip(rows.single);
      final tripId = trip['id'] as String;
      final dynamic linked = await _read(() => client.rpc(
          'user_trip_payment_summary',
          params: {'target_trip_id': tripId}));
      if (linked is! List || linked.length != 1 || linked.single is! Map) {
        _fail(RiderTripDetailFailure.invalidResponse);
      }
      final linkage = linked.single as Map;
      final paymentId = _id(linkage['id']);
      if (linkage['trip_id'] != tripId || linkage['method'] != 'cash') {
        _fail(RiderTripDetailFailure.invalidResponse);
      }
      // Reuse R05's exact-ID reader, including current Rider profile checks,
      // strict money/status/version parsing and SDK Session-object pinning.
      final payment =
          await _read(() => payments.readCashPayment(paymentId: paymentId));
      if (payment.paymentId != paymentId ||
          payment.tripId != tripId ||
          payment.bookingRequestId != trip['booking_request_id']) {
        _fail(RiderTripDetailFailure.invalidResponse);
      }
      final receipt = await _receipt(tripId, payment);
      final currentTrip = _trip(await _read(() => client
          .from('trips')
          .select(
              'id,booking_request_id,rider_id,status,version,payment_method')
          .eq('id', tripId)
          .eq('rider_id', riderId)
          .maybeSingle()));
      for (final key in trip.keys) {
        if (currentTrip[key] != trip[key]) {
          _fail(RiderTripDetailFailure.invalidResponse);
        }
      }
      final currentPayment =
          await _read(() => payments.readCashPayment(paymentId: paymentId));
      if (currentPayment != payment) {
        _fail(RiderTripDetailFailure.invalidResponse);
      }
      await _profile();
      return RiderCanonicalTripDetail._(
          tripId, trip['version'] as int, payment, receipt);
    } on RiderTripDetailException {
      rethrow;
    } on CanonicalPaymentReadException catch (e) {
      _current();
      _fail(e.failure == CanonicalPaymentReadFailure.unauthorized
          ? RiderTripDetailFailure.unauthorized
          : e.failure == CanonicalPaymentReadFailure.invalidResponse
              ? RiderTripDetailFailure.invalidResponse
              : RiderTripDetailFailure.unavailable);
    } on PaymentException {
      _current();
      return null;
    } on PostgrestException catch (e) {
      _current();
      if (e.code == 'P0002') return null;
      _fail(e.code == '42501' || e.code?.startsWith('PGRST3') == true
          ? RiderTripDetailFailure.unauthorized
          : RiderTripDetailFailure.unavailable);
    } on Object {
      _current();
      _fail(RiderTripDetailFailure.unavailable);
    }
  }

  Future<RiderReceiptEvidence> _receipt(
      String tripId, CashPayment payment) async {
    try {
      final dynamic rows = await _read(() => client.rpc(
          'user_trip_receipt_summary',
          params: {'target_trip_id': tripId}));
      if (rows is! List || rows.length != 1 || rows.single is! Map) {
        return RiderReceiptEvidence.unverified;
      }
      final row = rows.single as Map;
      if (row['id'] is! String ||
          !_uuid.hasMatch(row['id'] as String) ||
          row['trip_id'] != tripId ||
          row['payment_method'] != 'cash' ||
          row['currency'] != payment.currency ||
          row['amount_paid_fils'] is! int ||
          row['amount_paid_fils'] != payment.amountFils ||
          row['issued_at'] is! String ||
          DateTime.tryParse(row['issued_at'] as String) == null ||
          payment.status != CashPaymentStatus.paid) {
        return RiderReceiptEvidence.unverified;
      }
      return RiderReceiptEvidence.issued;
    } on PostgrestException catch (e) {
      _current();
      if (e.code == '42501' || e.code?.startsWith('PGRST3') == true) {
        _fail(RiderTripDetailFailure.unauthorized);
      }
      return RiderReceiptEvidence.unverified;
    } on RiderTripDetailException {
      rethrow;
    } on Object {
      _current();
      return RiderReceiptEvidence.unverified;
    }
  }
}
