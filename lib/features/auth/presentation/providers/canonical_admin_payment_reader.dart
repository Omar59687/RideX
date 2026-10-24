import 'package:ridex/core/repositories/canonical_payment_repository.dart';
import 'package:ridex/features/auth/presentation/providers/admin_payment_providers.dart';
import 'package:ridex/features/auth/presentation/widgets/admin_sanitized_payment_mapper.dart';

/// Sanitizes before records enter the Admin provider or widget tree.
final class CanonicalAdminPaymentReader implements AdminPaymentReader {
  CanonicalAdminPaymentReader(this.repository);
  final SupabaseCanonicalPaymentRepository repository;
  @override
  Future<List<AdminSanitizedPayment>> readPayments() async {
    try {
      return [
        for (final record in await repository.readRecentAdminPayments())
          switch (record) {
            CanonicalCashPayment(:final payment) =>
              mapCashPaymentForAdmin(payment),
            CanonicalCardPayment(:final payment) =>
              mapCardPaymentForAdmin(payment),
          }
      ];
    } on CanonicalPaymentReadException catch (error) {
      throw AdminPaymentReadException(
          error.failure == CanonicalPaymentReadFailure.unauthorized
              ? AdminPaymentReadFailure.unauthorized
              : AdminPaymentReadFailure.failed);
    }
  }
}
