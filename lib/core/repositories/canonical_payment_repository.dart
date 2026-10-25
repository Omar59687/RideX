import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/repositories/card_payment_repository.dart';
import 'package:ridex/core/repositories/payment_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum CanonicalPaymentReadFailure { unauthorized, invalidResponse, unavailable }

final class CanonicalPaymentReadException implements Exception {
  const CanonicalPaymentReadException(this.failure);
  final CanonicalPaymentReadFailure failure;
  @override
  String toString() => 'CanonicalPaymentReadException($failure)';
}

sealed class CanonicalPaymentRecord {
  const CanonicalPaymentRecord(this.riderId);
  final String riderId;

  static CanonicalPaymentRecord fromRow(Map<String, dynamic> row) {
    try {
      final id = _id(row['id']);
      final booking = _id(row['booking_request_id']);
      final trip = _id(row['trip_id']);
      final rider = _id(row['rider_id']);
      final amount = row['final_amount_fils'];
      final version = row['version'];
      if (amount is! int ||
          amount < 0 ||
          version is! int ||
          version < 1 ||
          row['currency'] != 'JOD') {
        throw const FormatException();
      }
      if (row['method'] == 'cash' && row['card_status'] == null) {
        return CanonicalCashPayment(
            rider,
            CashPayment(
              paymentId: id,
              bookingRequestId: booking,
              tripId: trip,
              amountFils: amount,
              version: version,
              status: CashPaymentStatus.fromBackendValue(
                  row['cash_status'] as String),
            ));
      }
      if (row['method'] == 'card' && row['cash_status'] == null) {
        return CanonicalCardPayment(
            rider,
            CardPayment(
              paymentId: id,
              bookingRequestId: booking,
              tripId: trip,
              amountFils: amount,
              version: version,
              status: CardPaymentStatus.fromBackendValue(
                  row['card_status'] as String),
              cardBrand: row['card_brand'] as String?,
              cardLastFour: row['card_last_four'] as String?,
            ));
      }
      throw const FormatException();
    } on Object {
      throw const CanonicalPaymentReadException(
          CanonicalPaymentReadFailure.invalidResponse);
    }
  }
}

final class CanonicalCashPayment extends CanonicalPaymentRecord {
  const CanonicalCashPayment(super.riderId, this.payment);
  final CashPayment payment;
}

final class CanonicalCardPayment extends CanonicalPaymentRecord {
  const CanonicalCardPayment(super.riderId, this.payment);
  final CardPayment payment;
}

final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
String _id(Object? value) {
  if (value is! String || !_uuid.hasMatch(value)) throw const FormatException();
  return value;
}

bool _sameId(String a, String b) => a.toLowerCase() == b.toLowerCase();

/// Canonical payment reads through migration 027's server-authorized RPCs,
/// never direct finance-table SELECT (denied by migration 019). No inferred identity/version, migrations,
/// financial writes or trusted Trip/receipt-success claims. No Driver reads.
class SupabaseCanonicalPaymentRepository
    implements PaymentRepository, CardPaymentRepository {
  SupabaseCanonicalPaymentRepository(this._client);
  final SupabaseClient _client;
  static const adminPageSize = 50;

  Session _owner() {
    final session = _client.auth.currentSession;
    if (session == null ||
        session.isExpired ||
        !_uuid.hasMatch(session.user.id)) {
      throw const CanonicalPaymentReadException(
          CanonicalPaymentReadFailure.unauthorized);
    }
    return session;
  }

  void _requireCurrent(Session owner) {
    if (!identical(_client.auth.currentSession, owner) || owner.isExpired) {
      throw const CanonicalPaymentReadException(
          CanonicalPaymentReadFailure.unauthorized);
    }
  }

  Future<String> _financeRole(Session owner, {bool adminOnly = false}) async {
    _requireCurrent(owner);
    final user = await _client
        .from('users')
        .select('id,role,is_blocked')
        .eq('id', owner.user.id)
        .maybeSingle();
    _requireCurrent(owner);
    if (user == null ||
        user['id'] is! String ||
        !_sameId(user['id'] as String, owner.user.id) ||
        user['is_blocked'] != false ||
        (user['role'] != 'admin' && (adminOnly || user['role'] != 'rider'))) {
      throw const CanonicalPaymentReadException(
          CanonicalPaymentReadFailure.unauthorized);
    }
    return user['role'] as String;
  }

  Future<T> _read<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on CanonicalPaymentReadException {
      rethrow;
    } on PaymentException {
      rethrow;
    } on PostgrestException catch (error) {
      throw CanonicalPaymentReadException(error.code == '42501' ||
              error.code == '401' ||
              error.code == '403' ||
              error.code?.startsWith('PGRST3') == true
          ? CanonicalPaymentReadFailure.unauthorized
          : CanonicalPaymentReadFailure.unavailable);
    } on Object {
      throw const CanonicalPaymentReadException(
          CanonicalPaymentReadFailure.unavailable);
    }
  }

  Future<CanonicalPaymentRecord> _byId(String paymentId) => _read(() async {
        if (!_uuid.hasMatch(paymentId)) {
          throw const PaymentException(PaymentFailure.invalidRequest);
        }
        final owner = _owner();
        final role = await _financeRole(owner);
        final dynamic response = await _client.rpc(
          'user_canonical_payment_record',
          params: {'target_payment_id': paymentId},
        );
        _requireCurrent(owner);
        if (await _financeRole(owner) != role) {
          throw const CanonicalPaymentReadException(
              CanonicalPaymentReadFailure.unauthorized);
        }
        if (response is! List || response.length > 1) {
          throw const CanonicalPaymentReadException(
              CanonicalPaymentReadFailure.invalidResponse);
        }
        if (response.isEmpty) throw const PaymentException(PaymentFailure.notFound);
        if (response.single is! Map) {
          throw const CanonicalPaymentReadException(
              CanonicalPaymentReadFailure.invalidResponse);
        }
        final record = CanonicalPaymentRecord.fromRow(
            Map<String, dynamic>.from(response.single as Map));
        final actualId = switch (record) {
          CanonicalCashPayment(:final payment) => payment.paymentId!,
          CanonicalCardPayment(:final payment) => payment.paymentId!,
        };
        if (!_sameId(actualId, paymentId) ||
            (role == 'rider' && !_sameId(record.riderId, owner.user.id))) {
          throw const CanonicalPaymentReadException(
              CanonicalPaymentReadFailure.unauthorized);
        }
        return record;
      });
  @override
  Future<CashPayment> readCashPayment({required String paymentId}) async {
    final record = await _byId(paymentId);
    if (record is CanonicalCashPayment) return record.payment;
    throw const CanonicalPaymentReadException(
        CanonicalPaymentReadFailure.invalidResponse);
  }

  @override
  Future<CardPayment> readCardPayment({required String paymentId}) async {
    final record = await _byId(paymentId);
    if (record is CanonicalCardPayment) return record.payment;
    throw const CanonicalPaymentReadException(
        CanonicalPaymentReadFailure.invalidResponse);
  }

  Future<List<CanonicalPaymentRecord>> readRecentAdminPayments() =>
      _read(() async {
        final owner = _owner();
        await _financeRole(owner, adminOnly: true);
        final dynamic rows = await _client.rpc('admin_recent_canonical_payments');
        _requireCurrent(owner);
        await _financeRole(owner, adminOnly: true);
        if (rows is! List || rows.length > adminPageSize) {
          throw const CanonicalPaymentReadException(
              CanonicalPaymentReadFailure.invalidResponse);
        }
        final records = <CanonicalPaymentRecord>[];
        for (final row in rows) {
          if (row is! Map) {
            throw const CanonicalPaymentReadException(
                CanonicalPaymentReadFailure.invalidResponse);
          }
          records.add(CanonicalPaymentRecord.fromRow(
              Map<String, dynamic>.from(row)));
        }
        final ids = <String>{};
        for (final record in records) {
          final id = switch (record) {
            CanonicalCashPayment(:final payment) => payment.paymentId!,
            CanonicalCardPayment(:final payment) => payment.paymentId!,
          };
          if (!ids.add(id.toLowerCase())) {
            throw const CanonicalPaymentReadException(
                CanonicalPaymentReadFailure.invalidResponse);
          }
        }
        return List.unmodifiable(records);
      });
}
