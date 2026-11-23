import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/features/rider_payments/application/rider_checkout_controller.dart';
import 'package:ridex/features/rider_payments/application/rider_checkout_launcher.dart';
import 'package:ridex/features/rider_payments/data/supabase_rider_financial_reader.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';
import 'package:ridex/features/rider_payments/models/rider_receipt_state.dart';

/// Builds a read-only adapter only for an authenticated, unblocked Rider and
/// the existing normal Supabase client. The adapter rechecks SDK/session/profile
/// ownership at every awaited boundary. Card dispatch remains default-off.
final riderFinancialReadAdapterProvider =
    Provider<SupabaseRiderFinancialReader?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final session = ref.watch(sessionControllerProvider);
  if (client == null ||
      session.status != SessionStatus.authenticated ||
      session.role != RideRole.rider ||
      session.user == null ||
      session.user!.isBlocked) {
    return null;
  }
  return SupabaseRiderFinancialReader.forClient(
    client: client,
    readSession: () => ref.read(sessionControllerProvider),
  );
});

/// Feature-local override point for deterministic readers in tests. A04
/// production wiring still uses the participant-scoped authenticated reader.
final riderCheckoutReaderProvider = Provider<RiderCheckoutReader>(
  (ref) => ref.watch(riderFinancialReadAdapterProvider) ??
      const UnavailableRiderCheckoutReader(),
);

final riderCheckoutLauncherProvider = Provider<RiderCheckoutLauncher>(
  (ref) => const DisabledRiderCheckoutLauncher(),
);

final riderReceiptReaderProvider = Provider<RiderReceiptReader>(
  (ref) => ref.watch(riderFinancialReadAdapterProvider) ??
      const UnavailableRiderReceiptReader(),
);

final riderCheckoutControllerProvider =
    ChangeNotifierProvider.autoDispose<RiderCheckoutController>((ref) {
  final controller = RiderCheckoutController(
    reader: ref.watch(riderCheckoutReaderProvider),
    receiptReader: ref.watch(riderReceiptReaderProvider),
    launcher: ref.watch(riderCheckoutLauncherProvider),
    readSession: () => ref.read(sessionControllerProvider),
  );
  ref.listen(sessionControllerProvider, (previous, next) {
    if (!identical(previous, next)) controller.sessionChanged();
  });
  return controller;
});
