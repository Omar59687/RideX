import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/core/services/supabase/supabase_initialization_provenance.dart';
import 'package:ridex/features/history/data/supabase_rider_history_summary_repository.dart';

final riderHistorySummaryRepositoryProvider =
    Provider.autoDispose<RiderHistorySummaryReader?>((ref) {
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
  final subscription = client.auth.onAuthStateChange.listen((_) {
    if (!identical(client.auth.currentSession, sdkSession)) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(subscription.cancel);
  bool isCurrent() =>
      !disposed &&
      identical(ref.read(sessionControllerProvider), appSession) &&
      identical(ref.read(supabaseClientProvider), client) &&
      identical(client.auth.currentSession, sdkSession) &&
      provenance.snapshot.state == SupabaseProvenanceState.trusted &&
      provenance.snapshot.endpoint == snapshot.endpoint;

  return SupabaseRiderHistorySummaryRepository(
    client: client,
    riderId: rider!.id,
    readSession: () => ref.read(sessionControllerProvider),
    isCurrent: isCurrent,
  );
});
