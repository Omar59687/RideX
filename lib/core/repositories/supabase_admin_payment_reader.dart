import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/features/auth/presentation/providers/admin_payment_providers.dart';
import 'package:ridex/features/auth/presentation/widgets/admin_sanitized_payment_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Production-only read adapter for migration 027's server-authorized RPC.
///
/// The RPC enforces Admin authorization on the server. The local identity
/// check prevents dispatch/publication across an SDK session switch; it is
/// not a substitute for backend authorization.
final class SupabaseAdminPaymentReader implements AdminPaymentReader {
  SupabaseAdminPaymentReader(this._client, {required this.adminUserId})
      : _initialSession = _client.auth.currentSession;

  final SupabaseClient _client;
  final String adminUserId;
  final Session? _initialSession;

  bool get _sameSession =>
      _initialSession != null &&
      !_initialSession.isExpired &&
      identical(_client.auth.currentSession, _initialSession) &&
      adminUserId.isNotEmpty &&
      _initialSession.user.id == adminUserId;

  @override
  Future<List<AdminSanitizedPayment>> readPayments() async {
    if (!_sameSession) {
      throw const AdminPaymentReadException(
        AdminPaymentReadFailure.unauthorized,
      );
    }
    final dynamic response = await _client.rpc('admin_recent_canonical_payments');
    if (!_sameSession) {
      throw const AdminPaymentReadException(
        AdminPaymentReadFailure.unauthorized,
      );
    }
    return parseAdminCanonicalPayments(response);
  }
}

/// Strict allowlist conversion: no raw response map or identifier reaches UI.
/// Invalid or incomplete backend data fails the entire read closed.
List<AdminSanitizedPayment> parseAdminCanonicalPayments(Object? response) {
  if (response is! List || response.length > 50) {
    throw const FormatException('Invalid canonical payment response');
  }
  final output = <AdminSanitizedPayment>[];
  for (final raw in response) {
    if (raw is! Map) {
      throw const FormatException('Invalid canonical payment row');
    }
    final row = Map<String, dynamic>.from(raw);
    String requiredString(String key) {
      final value = row[key];
      if (value is! String || value.trim().isEmpty) {
        throw const FormatException('Invalid canonical payment field');
      }
      return value;
    }

    String? optionalString(String key) {
      final value = row[key];
      if (value == null) return null;
      if (value is! String) {
        throw const FormatException('Invalid canonical payment field');
      }
      return value;
    }

    final paymentId = requiredString('id');
    final bookingId = requiredString('booking_request_id');
    final tripId = requiredString('trip_id');
    requiredString('rider_id');
    final amount = row['final_amount_fils'];
    final version = row['version'];
    if (amount is! int || version is! int) {
      throw const FormatException('Invalid canonical payment amount/version');
    }
    final currency = requiredString('currency');
    final method = PaymentMethod.fromBackendValue(requiredString('method'));

    switch (method) {
      case PaymentMethod.cash:
        if (row['card_status'] != null ||
            row['card_brand'] != null ||
            row['card_last_four'] != null) {
          throw const FormatException('Invalid cash payment metadata');
        }
        output.add(mapCashPaymentForAdmin(CashPayment(
          paymentId: paymentId,
          bookingRequestId: bookingId,
          tripId: tripId,
          amountFils: amount,
          currency: currency,
          status: CashPaymentStatus.fromBackendValue(
            requiredString('cash_status'),
          ),
          version: version,
        )));
      case PaymentMethod.card:
        if (row['cash_status'] != null) {
          throw const FormatException('Invalid card payment metadata');
        }
        output.add(mapCardPaymentForAdmin(CardPayment(
          paymentId: paymentId,
          bookingRequestId: bookingId,
          tripId: tripId,
          amountFils: amount,
          currency: currency,
          status: CardPaymentStatus.fromBackendValue(
            requiredString('card_status'),
          ),
          version: version,
          cardBrand: optionalString('card_brand'),
          cardLastFour: optionalString('card_last_four'),
        )));
    }
  }
  return List<AdminSanitizedPayment>.unmodifiable(output);
}
