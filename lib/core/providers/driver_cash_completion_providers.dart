import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/supabase_driver_completion_source.dart';
import 'package:ridex/core/repositories/supabase_driver_cash_completion_composition.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/core/services/trips/application_completion_store.dart';
import 'package:ridex/core/services/trips/driver_completion_command_store.dart';
import 'package:ridex/core/services/trips/driver_completion_staging_gateway.dart';
import 'package:ridex/features/trips/application/driver_cash_completion_controller.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';
import 'package:ridex/features/trips/application/driver_cash_recovery_controller.dart';

/// Integration-owned deployment allowlist. Deliberately empty pending explicit
/// endpoint/namespace approval. No dart-define or URL-derived namespace fallback.
final approvedDriverCompletionBackendsProvider =
    Provider<DriverBackendRegistry>((ref) => DriverBackendRegistry([]));

/// Native app support directory; errors are handled by the staging gateway.
final driverCompletionStoreFactoryProvider =
    Provider<Future<DriverCompletionCommandStore> Function()>(
        (ref) => openApplicationCompletionStore);

/// Safe seam for a future canonical Driver screen. Never consumed by the
/// existing MockTrip screen. Each mounted owner is permanently one-attempt;
/// journal create-or-load also prevents dispatch across separate instances.
final driverCashCompletionProvider =
    ChangeNotifierProvider.autoDispose<DriverCashCompletionController?>((ref) {
  final session = ref.watch(sessionControllerProvider);
  final user = session.user;
  if (session.status != SessionStatus.authenticated ||
      session.role != RideRole.driver ||
      user == null ||
      user.isBlocked ||
      user.driverApprovalStatus != DriverApprovalStatus.approved) {
    return null;
  }
  final access = ref
      .watch(supabaseInitializationProvenanceProvider)
      .driverAccess(ref.watch(approvedDriverCompletionBackendsProvider));
  if (access == null) return null;
  final auth = ref.watch(authServiceProvider);
  if (auth == null || access.client?.auth.currentUser?.id != user.id) {
    return null;
  }
  final binding = auth.driverBinding(access);
  final owner = binding.currentOwner;
  if (!owner.isUsable) {
    binding.dispose();
    return null;
  }
  final source =
      SupabaseDriverCompletionSource(access: access, authority: binding);
  final repository = SupabaseDriverCashCompletionComposition(
      access: access, authority: binding);
  final openStore = ref.watch(driverCompletionStoreFactoryProvider);
  final coordinator = DriverCompletionCoordinator(
    canonicalSource: source,
    stagingGateway: JournalDriverCompletionStagingGateway(
        backendNamespace: access.backend.namespace,
        driverId: owner.driverId!,
        openStore: openStore),
    repository: repository,
    sessionReader: source.readSession,
  );
  final recovery = DriverCashRecoveryController(
    source: source,
    authority: binding,
    repository: repository,
    openJournal: openStore,
  );
  final controller = DriverCashCompletionController(
    coordinator: coordinator,
    recovery: recovery,
    prepareContext: () async => await source.load() != null,
    isCurrent: () => source.isCurrent,
    failureState: () => switch (source.lastFailure) {
      DriverCashContextFailure.unavailable =>
        DriverCashCompletionState.networkFailure,
      DriverCashContextFailure.changed => DriverCashCompletionState.unresolved,
      _ => DriverCashCompletionState.authorizationLost,
    },
    release: () {
      source.dispose();
      binding.dispose();
    },
  );
  final subscription = auth.authStateChanges().listen(
      (_) => controller.observeAuthority(),
      onError: (Object _) => controller.observeAuthority());
  ref.onDispose(subscription.cancel);
  return controller;
});
