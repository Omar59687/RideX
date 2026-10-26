import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/rider_canonical_trip_detail_repository.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/core/services/supabase/supabase_initialization_provenance.dart';
import 'package:ridex/features/history/presentation/providers/rider_payment_providers.dart';

final riderCanonicalTripDetailRepositoryProvider =
    Provider.autoDispose<RiderCanonicalTripDetailRepository?>((ref) {
  final session = ref.watch(sessionControllerProvider);
  final client = ref.watch(supabaseClientProvider);
  final payments = ref.watch(riderCashPaymentRepositoryProvider);
  final provenance = ref.watch(supabaseInitializationProvenanceProvider);
  final snapshot = provenance.snapshot;
  if (session.status != SessionStatus.authenticated ||
      session.role != RideRole.rider ||
      session.user?.isBlocked != false ||
      client == null ||
      payments == null ||
      snapshot.state != SupabaseProvenanceState.trusted) {
    return null;
  }
  var disposed = false;
  ref.onDispose(() => disposed = true);
  return RiderCanonicalTripDetailRepository(
      client: client,
      riderId: session.user!.id,
      payments: payments,
      isCurrent: () =>
          !disposed &&
          identical(ref.read(sessionControllerProvider), session) &&
          identical(ref.read(supabaseClientProvider), client) &&
          provenance.snapshot.state == SupabaseProvenanceState.trusted &&
          provenance.snapshot.endpoint == snapshot.endpoint);
});

final riderCanonicalTripDetailProvider =
    FutureProvider.autoDispose<RiderCanonicalTripDetail?>((ref) async {
  // Auth events invalidate already displayed snapshots as well as in-flight
  // reads. No new auth/epoch owner is introduced.
  final client = ref.watch(supabaseClientProvider);
  final sdkSession = client?.auth.currentSession;
  final subscription = client?.auth.onAuthStateChange.listen((_) {
    // The SDK replays initialSession to a new subscriber. Rebuilding for that
    // same object would restart the read indefinitely; a replacement object
    // (including A-B-A) or logout must still invalidate loaded evidence.
    if (identical(client.auth.currentSession, sdkSession)) return;
    ref.invalidate(riderCanonicalTripDetailRepositoryProvider);
    ref.invalidateSelf();
  });
  ref.onDispose(() => subscription?.cancel());
  final repository = ref.watch(riderCanonicalTripDetailRepositoryProvider);
  return repository?.loadLatest();
});
