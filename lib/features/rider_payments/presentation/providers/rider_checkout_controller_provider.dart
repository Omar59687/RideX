import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/core/services/supabase/supabase_initialization_provenance.dart';
import 'package:ridex/features/rider_payments/application/rider_checkout_controller.dart';
import 'package:ridex/features/rider_payments/application/rider_checkout_launcher.dart';
import 'package:ridex/features/rider_payments/data/a04_rider_financial_read_adapter.dart';
import 'package:ridex/core/repositories/supabase_a04_rider_financial_read_source.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';
import 'package:ridex/features/rider_payments/models/rider_receipt_state.dart';

/// Production read-only A04 composition. A missing/untrusted client, blocked
/// account, non-Rider session, or SDK identity mismatch remains unavailable.
final a04RiderFinancialReadAdapterProvider =
    Provider.autoDispose<A04RiderFinancialReadAdapter?>((ref) {
  final appSession = ref.watch(sessionControllerProvider);
  final client = ref.watch(supabaseClientProvider);
  final provenance = ref.watch(supabaseInitializationProvenanceProvider);
  final snapshot = provenance.snapshot;
  final rider = appSession.user;
  final sdkSession = client?.auth.currentSession;
  if (appSession.status != SessionStatus.authenticated ||
      appSession.role != RideRole.rider ||
      rider?.isBlocked != false ||
      client == null ||
      sdkSession == null ||
      sdkSession.isExpired ||
      sdkSession.user.id != rider?.id ||
      snapshot.state != SupabaseProvenanceState.trusted) {
    return null;
  }

  var disposed = false;
  ref.onDispose(() => disposed = true);
  final authSubscription = client.auth.onAuthStateChange.listen((_) {
    if (!identical(client.auth.currentSession, sdkSession)) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(authSubscription.cancel);

  bool isCurrent() =>
      !disposed &&
      identical(ref.read(sessionControllerProvider), appSession) &&
      identical(ref.read(supabaseClientProvider), client) &&
      identical(client.auth.currentSession, sdkSession) &&
      provenance.snapshot.state == SupabaseProvenanceState.trusted &&
      provenance.snapshot.endpoint == snapshot.endpoint;

  return A04RiderFinancialReadAdapter(
    tripReader: SupabaseA04AuthorizedTripContextReader(
      client: client,
      riderId: rider!.id,
      readSession: () => ref.read(sessionControllerProvider),
      isCurrent: isCurrent,
    ),
    transport: SupabaseA04FinancialReadTransport(client),
    readSession: () => ref.read(sessionControllerProvider),
  );
});

final riderCheckoutReaderProvider = Provider<RiderCheckoutReader>((ref) =>
    ref.watch(a04RiderFinancialReadAdapterProvider) ??
    const UnavailableRiderCheckoutReader());

final riderCheckoutLauncherProvider = Provider<RiderCheckoutLauncher>(
  (ref) => const DisabledRiderCheckoutLauncher(),
);

final riderReceiptReaderProvider = Provider<RiderReceiptReader>((ref) =>
    ref.watch(a04RiderFinancialReadAdapterProvider) ??
    const UnavailableRiderReceiptReader());

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
