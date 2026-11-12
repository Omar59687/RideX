import 'dart:async';
import '../../data/driver_offer_command_journal.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/repositories/driver_eligibility_repository.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import '../../data/canonical_driver_offer_discovery_port.dart';
import '../../data/canonical_driver_repository.dart';
import '../../data/polling_canonical_driver_offer_delivery.dart';
import '../../data/supabase_canonical_driver_port.dart';
import 'canonical_driver_presentation_controller.dart';

/// Build opt-in is necessary, never sufficient. Release builds always deny.
bool controlledDriverRuntimeAllowed({
  required bool release,
  required bool optIn,
}) =>
    !release && optIn;

/// Independent command authorization; read opt-in alone never enables writes.
final controlledDriverCommandsEnabledProvider = Provider<bool>((ref) => false);
final driverOfferCommandJournalProvider = Provider<DriverOfferCommandJournal>(
  (ref) => DriverOfferCommandJournal(),
);

final controlledDriverRuntimeEnabledProvider = Provider<bool>(
  (ref) => controlledDriverRuntimeAllowed(
    release: kReleaseMode,
    optIn: const bool.fromEnvironment('RIDEX_ENABLE_TEST_DRIVER_CANONICAL'),
  ),
);

/// Trusted composition input, never a route/query parameter, JWT claim or UI
/// assertion. Owners must separately approve a nonproduction deployment/actor.
/// No endpoint or identity is approved by this slice.
final approvedCanonicalDriverTargetProvider =
    Provider<CanonicalDriverTestTarget?>((ref) => null);

final class CanonicalDriverTestTarget {
  CanonicalDriverTestTarget({
    required this.backend,
    required this.driverId,
    required this.vehicleId,
  }) {
    if (!isCanonicalTripId(driverId) || !isCanonicalTripId(vehicleId)) {
      throw ArgumentError('Invalid approved Driver target.');
    }
  }
  final DriverBackendIdentity backend;
  final String driverId, vehicleId;
}

/// Borrowed normal-user port plus canonical active-vehicle read, using the
/// SAME verified client. This seam permits deterministic local composition tests.
final class ControlledDriverInputs {
  const ControlledDriverInputs({
    required this.port,
    required this.discovery,
    required this.readVehicle,
    required this.release,
    required this.authEvents,
    required this.target,
    this.clock,
  });
  final CanonicalDriverPort port;
  final CanonicalDriverOfferDiscoveryPort discovery;
  final Future<Map<String, Object?>?> Function() readVehicle;
  final Future<void> Function() release;
  final Stream<void> authEvents;
  final CanonicalDriverTestTarget target;
  final DateTime Function()? clock;
}

final controlledDriverInputsProvider =
    Provider.autoDispose<ControlledDriverInputs?>((ref) {
  if (kReleaseMode || !ref.watch(controlledDriverRuntimeEnabledProvider)) {
    return null;
  }
  final session = ref.watch(sessionControllerProvider);
  final target = ref.watch(approvedCanonicalDriverTargetProvider);
  if (target == null ||
      !ControlledDriverRuntime.accepts(session) ||
      session.user?.id.toLowerCase() != target.driverId.toLowerCase()) {
    return null;
  }
  final access = ref
      .watch(supabaseInitializationProvenanceProvider)
      .driverAccess(DriverBackendRegistry([target.backend]));
  final auth = ref.watch(authServiceProvider);
  if (access == null || auth == null) return null;
  final SupabaseCanonicalDriverPort port;
  try {
    port = SupabaseCanonicalDriverPort.create(access: access, auth: auth);
  } on Object {
    return null;
  }
  return ControlledDriverInputs(
    port: port,
    discovery: port,
    target: target,
    authEvents: auth.authStateChanges(),
    release: port.dispose,
    readVehicle: () async {
      final client = access.client;
      if (client == null) throw StateError('Driver access unavailable.');
      return await client
          .from('vehicles')
          .select('id,driver_id,is_active')
          .eq('id', target.vehicleId)
          .eq('driver_id', target.driverId)
          .maybeSingle();
    },
  );
});

final controlledDriverRuntimeProvider =
    Provider.autoDispose<ControlledDriverRuntime?>((ref) {
  // Capture once for this route lifetime. Session refresh must revoke, never
  // rebuild/restart a stopped owner. Login happens through the existing router.
  if (kReleaseMode || !ref.read(controlledDriverRuntimeEnabledProvider)) {
    return null;
  }
  final session = ref.read(sessionControllerProvider);
  if (!ControlledDriverRuntime.accepts(session)) return null;
  final inputs = ref.read(controlledDriverInputsProvider);
  if (inputs == null) return null;
  final runtime = ControlledDriverRuntime(
      inputs: inputs,
      session: session,
      commandsEnabled:
          !kReleaseMode && ref.read(controlledDriverCommandsEnabledProvider),
      journal: ref.read(driverOfferCommandJournalProvider),
      clock: inputs.clock,
      sessionCurrent: () =>
          identical(ref.read(sessionControllerProvider), session));
  ref.listen(
      sessionControllerProvider, (_, next) => runtime.observeSession(next));
  ref.listen(
      controlledDriverRuntimeEnabledProvider, (_, __) => runtime.invalidate());
  ref.listen(
      approvedCanonicalDriverTargetProvider, (_, __) => runtime.invalidate());
  ref.listen(
      controlledDriverCommandsEnabledProvider, (_, __) => runtime.invalidate());
  ref.onDispose(runtime.dispose);
  return runtime;
});

/// Route-owned B07/B08/B09 composition. Commands require independent approval
/// and a durable replay barrier in addition to all canonical authority checks.
final class ControlledDriverRuntime {
  ControlledDriverRuntime({
    required ControlledDriverInputs inputs,
    required SessionState session,
    bool commandsEnabled = false,
    DriverOfferCommandJournal? journal,
    DateTime Function()? clock,
    bool Function()? sessionCurrent,
  }) : _inputs = inputs {
    _session = ValueNotifier(session);
    _port = _ApprovedPort(
        inputs,
        () => !_stopped && (sessionCurrent?.call() ?? true),
        commandsEnabled && !kReleaseMode ? journal : null);
    repository = CanonicalDriverRepository(_port,
        clock: clock,
        offerCommandsEnabled:
            commandsEnabled && !kReleaseMode && journal != null);
    delivery = PollingCanonicalDriverOfferDelivery(
      port: _port,
      session: _session,
      authorityInvalidations: _invalidations,
      enabled: true,
      clock: clock,
    );
    controller = CanonicalDriverPresentationController(
      repository: repository,
      offerActionsEnabled: commandsEnabled && !kReleaseMode && journal != null,
      session: _session,
      authorityInvalidations: _invalidations,
      delivery: delivery,
      enabled: true,
      clock: clock,
    );
    try {
      _auth = inputs.authEvents.listen((_) => observeAuthority(),
          onError: (Object _, StackTrace __) => invalidate(),
          onDone: invalidate);
    } on Object {
      invalidate();
    }
  }
  final ControlledDriverInputs _inputs;
  late final ValueNotifier<SessionState> _session;
  final _invalidations = ValueNotifier<int>(0);
  late final _ApprovedPort _port;
  late final CanonicalDriverRepository repository;
  late final PollingCanonicalDriverOfferDelivery delivery;
  late final CanonicalDriverPresentationController controller;
  StreamSubscription<void>? _auth;
  bool _stopped = false, _disposed = false;
  static bool accepts(SessionState session) =>
      session.status == SessionStatus.authenticated &&
      session.user?.role == RideRole.driver &&
      session.user?.isBlocked == false &&
      session.user?.driverApprovalStatus == DriverApprovalStatus.approved;

  /// The SDK replays its latest auth event on subscribe. The captured owner and
  /// SDK session must still match; never blindly skip a first event or revoke
  /// merely because a replay occurred. Later authority changes fail closed.
  void observeAuthority() {
    if (!_port.currentOwner.isUsable) invalidate();
  }

  void observeSession(SessionState next) {
    if (_disposed || _stopped) return;
    if (!identical(next, _session.value)) {
      _session.value = next;
      invalidate();
    }
  }

  /// Stop synchronously; late reads and already captured views lose authority.
  /// Resume needs explicit route reentry. No auth event restarts polling.
  void invalidate() {
    if (_stopped) return;
    _stopped = true;
    _invalidations.value++;
    delivery.dispose();
    repository.dispose();
    unawaited(_auth?.cancel());
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    invalidate();
    controller.dispose();
    _session.dispose();
    _invalidations.dispose();
    unawaited(_inputs.release().catchError((Object _) {}));
  }
}

/// Pins the approved vehicle/Driver/backend in addition to B07/B09 checks.
/// Canonical vehicle eligibility is reread on every profile authorization.
final class _ApprovedPort
    implements CanonicalDriverPort, CanonicalDriverOfferDiscoveryPort {
  _ApprovedPort(this.inputs, this.active, this.journal)
      : _owner = inputs.port.currentOwner,
        _sdkSession = inputs.port.sessionIdentity;
  final ControlledDriverInputs inputs;
  final DriverOfferCommandJournal? journal;
  final bool Function() active;
  final DriverAuthorityOwner _owner;
  final Object? _sdkSession;
  void _check() {
    final owner = inputs.port.currentOwner;
    if (!active() ||
        !_owner.isUsable ||
        !owner.isUsable ||
        !_owner.sameOwner(owner) ||
        !identical(owner.backend, inputs.target.backend) ||
        owner.driverId?.toLowerCase() != inputs.target.driverId.toLowerCase() ||
        _sdkSession == null ||
        !identical(_sdkSession, inputs.port.sessionIdentity) ||
        !owner.sameOwner(inputs.discovery.currentOwner) ||
        !identical(_sdkSession, inputs.discovery.sessionIdentity)) {
      throw const DriverEligibilityReadException(
        DriverEligibilityFailure.sessionInvalidated,
      );
    }
  }

  Future<T> _read<T>(Future<T> Function() action) async {
    _check();
    final value = await action();
    _check();
    return value;
  }

  @override
  DriverAuthorityOwner get currentOwner {
    try {
      _check();
      return inputs.port.currentOwner;
    } on Object {
      return DriverAuthorityOwner(
        driverId: null,
        backend: _owner.backend,
        epoch: -1,
        hasValidSession: false,
      );
    }
  }

  @override
  Object? get sessionIdentity => active() ? inputs.port.sessionIdentity : null;
  @override
  Future<Map<String, Object?>?> readUser(String id) =>
      _read(() => inputs.port.readUser(id));
  @override
  Future<Map<String, Object?>?> readDriverProfile(String id) => _read(() async {
        final profile = await inputs.port.readDriverProfile(id);
        _check();
        final vehicle = await inputs.readVehicle();
        if (vehicle?['id'] != inputs.target.vehicleId ||
            vehicle?['driver_id'] != inputs.target.driverId ||
            vehicle?['is_active'] != true) {
          throw const DriverEligibilityReadException(
            DriverEligibilityFailure.notApproved,
          );
        }
        return profile;
      });
  Future<Map<String, Object?>?> _vehicleRow(
    Future<Map<String, Object?>?> Function() read,
  ) =>
      _read(() async {
        final row = await read();
        if (row != null && row['vehicle_id'] != inputs.target.vehicleId) {
          throw const DriverEligibilityReadException(
            DriverEligibilityFailure.foreignIdentity,
          );
        }
        return row;
      });
  @override
  Future<Map<String, Object?>?> readAvailability() =>
      _vehicleRow(inputs.port.readAvailability);
  @override
  Future<Map<String, Object?>?> readOffer(String id) =>
      _vehicleRow(() => inputs.port.readOffer(id));
  @override
  Future<Map<String, Object?>?> readTrip(String id) =>
      _vehicleRow(() => inputs.port.readTrip(id));
  @override
  Future<Map<String, Object?>?> readTripForBooking(String id) =>
      _vehicleRow(() => inputs.port.readTripForBooking(id));
  @override
  Future<Map<String, Object?>?> readBooking(String id) =>
      _read(() => inputs.port.readBooking(id));
  @override
  Future<List<Map<String, Object?>>> readOfferedRows(DateTime after) =>
      _read(() async {
        final rows = await inputs.discovery.readOfferedRows(after);
        if (rows.any((row) => row['vehicle_id'] != inputs.target.vehicleId)) {
          throw const DriverEligibilityReadException(
            DriverEligibilityFailure.foreignIdentity,
          );
        }
        return rows;
      });
  @override
  Future<Object?> acceptOffer(String id, int version, String key) =>
      _command(id, version, key, true);
  @override
  Future<Object?> declineOffer(String id, int version, String key) =>
      _command(id, version, key, false);
  Future<Object?> _command(
      String id, int version, String key, bool accept) async {
    _check();
    final store = journal;
    if (store == null) throw StateError('Offer commands are disabled.');
    // Reserve durably BEFORE handing off. Never clear on timeout, navigation,
    // logout or success. Reentry can read assignment but cannot replay an offer.
    // No dispatch lives inside this timed future: a late storage/read result
    // after its deadline can never reach the RPC below.
    await (() async {
      await store.reserve(inputs.target.backend, inputs.target.driverId, id,
          version, key, accept);
      _check();
      final profile = await readDriverProfile(inputs.target.driverId);
      final row = await readOffer(id);
      final expires = DateTime.tryParse(row?['expires_at'] as String? ?? '');
      if (profile?['approval_status'] != 'approved' ||
          row?['status'] != 'offered' ||
          row?['version'] != version ||
          expires == null ||
          !(inputs.clock?.call() ?? DateTime.now()).toUtc().isBefore(expires)) {
        throw StateError('Original offer is no longer actionable.');
      }
    })()
        .timeout(const Duration(seconds: 8));
    _check();
    return accept
        ? inputs.port.acceptOffer(id, version, key)
        : inputs.port.declineOffer(id, version, key);
  }
}
