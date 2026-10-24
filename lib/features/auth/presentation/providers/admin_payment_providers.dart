import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/canonical_payment_repository.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/features/auth/presentation/providers/canonical_admin_payment_reader.dart';
import 'package:ridex/features/auth/presentation/widgets/admin_sanitized_payment_mapper.dart';

/// Read-only boundary. Implementations must authorize the current Admin and
/// return canonical, sanitized data. Fixture readers belong only in tests.
abstract interface class AdminPaymentReader {
  Future<List<AdminSanitizedPayment>> readPayments();
}

enum AdminPaymentReadFailure { unauthorized, unavailable, failed }

final class AdminPaymentReadException implements Exception {
  const AdminPaymentReadException(this.failure);
  final AdminPaymentReadFailure failure;
}

bool canReadAdminPayments(SessionState session) =>
    session.status == SessionStatus.authenticated &&
    session.role == RideRole.admin &&
    session.user?.isBlocked == false &&
    session.user!.id.trim().isNotEmpty;

/// Borrow the application client; never create a second authentication owner.
final adminPaymentReaderProvider = Provider<AdminPaymentReader?>((ref) {
  if (!canReadAdminPayments(ref.watch(sessionControllerProvider))) return null;
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? null
      : CanonicalAdminPaymentReader(SupabaseCanonicalPaymentRepository(client));
});

final adminPaymentsProvider =
    FutureProvider.autoDispose<List<AdminSanitizedPayment>>((ref) async {
  final owner = ref.watch(sessionControllerProvider);
  if (!canReadAdminPayments(owner)) {
    throw const AdminPaymentReadException(
      AdminPaymentReadFailure.unauthorized,
    );
  }
  final reader = ref.watch(adminPaymentReaderProvider);
  if (reader == null) {
    throw const AdminPaymentReadException(
      AdminPaymentReadFailure.unavailable,
    );
  }
  var active = true;
  ref.onDispose(() => active = false);
  try {
    final payments = await reader.readPayments();
    if (!active ||
        !identical(ref.read(sessionControllerProvider), owner) ||
        !canReadAdminPayments(ref.read(sessionControllerProvider))) {
      throw const AdminPaymentReadException(
        AdminPaymentReadFailure.unauthorized,
      );
    }
    return List.unmodifiable(payments);
  } on AdminPaymentReadException {
    rethrow;
  } on Object {
    // Backend errors and payloads never become UI text or logs.
    throw const AdminPaymentReadException(AdminPaymentReadFailure.failed);
  }
});
