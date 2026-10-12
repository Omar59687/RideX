import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/errors/auth_exception.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/models/app_notification.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/booking_handoff.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/models/fare_lock_recovery.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/repositories/fare_repository.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/models/vehicle_type.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/providers/driver_tracking_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';
import 'package:ridex/core/services/fare/pending_fare_lock_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';

class SessionState {
  const SessionState({
    required this.status,
    this.user,
    this.errorMessage,
  });

  const SessionState.loading()
      : status = SessionStatus.loading,
        user = null,
        errorMessage = null;

  const SessionState.unauthenticated({this.errorMessage})
      : status = SessionStatus.unauthenticated,
        user = null;

  const SessionState.profileError({required this.errorMessage})
      : status = SessionStatus.profileError,
        user = null;

  final SessionStatus status;
  final AppUser? user;
  final String? errorMessage;

  bool get isAuthenticated => user != null;
  RideRole? get role => user?.role;

  factory SessionState.fromUser(AppUser user) {
    if (user.isBlocked) {
      return SessionState(status: SessionStatus.blocked, user: user);
    }

    if (user.role == RideRole.driver) {
      return switch (user.driverApprovalStatus) {
        DriverApprovalStatus.rejected =>
          SessionState(status: SessionStatus.driverRejected, user: user),
        DriverApprovalStatus.pending ||
        null =>
          SessionState(status: SessionStatus.driverPending, user: user),
        DriverApprovalStatus.approved =>
          SessionState(status: SessionStatus.authenticated, user: user),
      };
    }

    return SessionState(status: SessionStatus.authenticated, user: user);
  }

  SessionState copyWith({
    SessionStatus? status,
    AppUser? user,
    String? errorMessage,
    bool clearUser = false,
  }) {
    return SessionState(
      status: status ?? this.status,
      user: clearUser ? null : user ?? this.user,
      errorMessage: errorMessage,
    );
  }
}

class SessionController extends Notifier<SessionState> {
  StreamSubscription<void>? _authSubscription;

  @override
  SessionState build() {
    _authSubscription ??=
        ref.read(authRepositoryProvider).authStateChanges().listen((_) {
      unawaited(refreshSession());
    });

    ref.onDispose(() => _authSubscription?.cancel());
    Future<void>.microtask(refreshSession);
    return const SessionState.loading();
  }

  Future<void> refreshSession() async {
    try {
      final user = await ref.read(authRepositoryProvider).restoreSession();
      state = user == null
          ? const SessionState.unauthenticated()
          : SessionState.fromUser(user);
    } on ProfileException catch (error) {
      state = SessionState.profileError(errorMessage: error.message);
    } on AuthException catch (error) {
      state = SessionState.unauthenticated(errorMessage: error.message);
    } catch (_) {
      state = const SessionState.unauthenticated(
        errorMessage: 'Unable to restore your session.',
      );
    }
  }

  Future<void> continueAsDemo() async {
    final user = await ref.read(authRepositoryProvider).continueAsDemo();
    state = SessionState.fromUser(user);
  }

  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    state = const SessionState.loading();
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .signIn(email: email, password: password);
      state = SessionState.fromUser(user);
      return null;
    } on ProfileException catch (error) {
      state = SessionState.profileError(errorMessage: error.message);
      return error.message;
    } on AuthException catch (error) {
      state = SessionState.unauthenticated(errorMessage: error.message);
      return error.message;
    } catch (_) {
      const message = 'Unable to sign in right now.';
      state = const SessionState.unauthenticated(errorMessage: message);
      return message;
    }
  }

  Future<String?> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    state = const SessionState.loading();
    try {
      final user = await ref.read(authRepositoryProvider).signUp(
            name: name,
            email: email,
            password: password,
          );
      state = SessionState.fromUser(user);
      return null;
    } on ProfileException catch (error) {
      state = SessionState.profileError(errorMessage: error.message);
      return error.message;
    } on AuthException catch (error) {
      state = SessionState.unauthenticated(errorMessage: error.message);
      return error.message;
    } catch (_) {
      const message = 'Unable to create your account right now.';
      state = const SessionState.unauthenticated(errorMessage: message);
      return message;
    }
  }

  Future<void> signOut() async {
    await ref.read(driverTrackingControllerProvider.notifier).stopForSignOut();
    await ref.read(authRepositoryProvider).signOut();
    ref.invalidate(bookingControllerProvider);
    // Drop the pending lock from visible in-memory state. The persisted
    // per-rider slot is intentionally retained: it is recovery evidence,
    // not session state, and only the same rider may restore it.
    // (A plain read: invalidating here would cycle against the
    // session listener owned below.)
    ref.read(pendingFareLockControllerProvider.notifier).clearMemory();
    ref.invalidate(activeTripControllerProvider);
    ref.invalidate(notificationsControllerProvider);
    ref.invalidate(notificationPreferencesProvider);
    ref.invalidate(driverOnlineProvider);
    state = const SessionState.unauthenticated();
  }
}

class BookingController extends Notifier<BookingDraft> {
  /// Maximum number of intermediate stops in a booking draft.
  static const int maxStops = 3;

  @override
  BookingDraft build() => MockData.initialDraft();

  void setPickup(RideLocation location) {
    state = state.copyWith(
      pickup: location,
      clearVehicleType: true,
      estimatedFare: 0,
      distanceKm: 0,
      etaMinutes: 0,
    );
  }

  void setDestination(RideLocation location) {
    state = state.copyWith(
      destination: location,
      clearVehicleType: true,
      estimatedFare: 0,
      distanceKm: 0,
      etaMinutes: 0,
    );
  }

  void clearPickup() {
    state = state.copyWith(
      clearPickup: true,
      clearVehicleType: true,
      estimatedFare: 0,
      distanceKm: 0,
      etaMinutes: 0,
    );
  }

  void clearDestination() {
    state = state.copyWith(
      clearDestination: true,
      clearVehicleType: true,
      estimatedFare: 0,
      distanceKm: 0,
      etaMinutes: 0,
    );
  }

  void setVehicleType(VehicleType vehicleType) {
    state = state.copyWith(
      vehicleType: vehicleType,
      estimatedFare: vehicleType.baseFare,
    );
  }

  /// Adds an intermediate stop at the end of the ordered stop list.
  ///
  /// Returns `true` when the stop was added and `false` when it was
  /// rejected. A stop is rejected when the draft already holds [maxStops]
  /// stops, when its coordinates are invalid (non-finite or outside the
  /// `LocationPoint` latitude/longitude ranges), or when its coordinates
  /// duplicate the current pickup, the current destination, or an
  /// already-added stop (latitude/longitude equality, matching the
  /// `sameLocation` convention in [BookingDraft.locationValidation]).
  /// A successful add clears the selected vehicle and any fare, distance,
  /// and ETA estimates, consistent with [setPickup]/[setDestination].
  /// Rejected adds leave the state untouched.
  bool addStop(RideLocation stop) {
    if (state.stops.length >= maxStops) return false;
    if (!_hasValidCoordinates(stop.point)) return false;
    if (_isDuplicateStop(stop)) return false;
    state = state.copyWith(
      stops: [...state.stops, stop],
      clearVehicleType: true,
      estimatedFare: 0,
      distanceKm: 0,
      etaMinutes: 0,
    );
    return true;
  }

  /// Removes the stop at [index].
  ///
  /// Out-of-range indexes are a no-op: the state is left untouched
  /// (no estimate reset), so callers can safely forward UI indexes.
  void removeStopAt(int index) {
    if (index < 0 || index >= state.stops.length) return;
    final stops = [...state.stops]..removeAt(index);
    state = state.copyWith(
      stops: stops,
      clearVehicleType: true,
      estimatedFare: 0,
      distanceKm: 0,
      etaMinutes: 0,
    );
  }

  /// Moves the stop at [from] to position [to], preserving list order
  /// for all other stops.
  ///
  /// Out-of-range indexes (or a [from] equal to [to]) are a no-op: the
  /// state is left untouched, so callers can safely forward UI indexes.
  void moveStop(int from, int to) {
    if (from < 0 ||
        from >= state.stops.length ||
        to < 0 ||
        to >= state.stops.length ||
        from == to) {
      return;
    }
    final stops = [...state.stops];
    final stop = stops.removeAt(from);
    stops.insert(to, stop);
    state = state.copyWith(
      stops: stops,
      clearVehicleType: true,
      estimatedFare: 0,
      distanceKm: 0,
      etaMinutes: 0,
    );
  }

  /// Removes all intermediate stops.
  ///
  /// Clearing an already-empty stop list is a no-op: the state is left
  /// untouched. A non-empty clear resets the selected vehicle and any
  /// fare, distance, and ETA estimates, consistent with [setPickup].
  void clearStops() {
    if (state.stops.isEmpty) return;
    state = state.copyWith(
      stops: const [],
      clearVehicleType: true,
      estimatedFare: 0,
      distanceKm: 0,
      etaMinutes: 0,
    );
  }

  bool _hasValidCoordinates(LocationPoint point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90 &&
        point.latitude <= 90 &&
        point.longitude >= -180 &&
        point.longitude <= 180;
  }

  bool _isDuplicateStop(RideLocation stop) {
    bool samePoint(RideLocation other) =>
        other.point.latitude == stop.point.latitude &&
        other.point.longitude == stop.point.longitude;
    final pickup = state.pickup;
    if (pickup != null && samePoint(pickup)) return true;
    final destination = state.destination;
    if (destination != null && samePoint(destination)) return true;
    return state.stops.any(samePoint);
  }

  Future<void> estimateFare() async {
    final fare = await ref.read(bookingRepositoryProvider).estimateFare(state);
    state = state.copyWith(estimatedFare: fare);
  }
}

/// Durable owner of the pending fare-lock command (booking state, not
/// widget state).
///
/// The command survives screen disposal, redirects, and same-user
/// restoration: memory holds it while the provider lives, and the store
/// slot (per rider) survives provider invalidation and app restarts.
/// Different users and signed-out sessions always resolve to null while
/// the stored record is left untouched.
///
/// Slice 1 guarantees (SOL remediation):
/// - F1 exclusive ownership: [stageForDispatch] never overwrites a different
///   unresolved command. Exact replay of the same immutable tuple
///   (booking id/version, quote id/version, rider id) is permitted; anything
///   else throws [PendingFareLockConflictException] with both memory and
///   persisted evidence preserved. Unreadable persisted evidence blocks
///   staging with [PendingFareLockCorruptException], never silent absence.
/// - F2 atomic ordering: stage/clear/restore affecting the same slot are
///   serialized through [_operationQueue]. A stale restore never replaces
///   newer staged state, an old clear never deletes a newer command, and
///   clear removes only the exact staged lineage. Delete failures preserve
///   both memory and persisted evidence.
/// - F3 session isolation: the authenticated rider is validated before and
///   after every async persistence boundary. Session/role/status changes
///   invalidate stale completions via [_generation]; nothing is ever
///   published into another user's session, and staging failures (including
///   ownership loss) must prevent Lock RPC dispatch. Disposal is safe.
/// - F4 corrupt evidence: persisted slots are inspected as
///   absent/valid/corrupt with rider-namespace validation. Corrupt records
///   are preserved and surface [pendingFareLockStorageBlockedProvider].
class PendingFareLockController extends Notifier<PendingFareLock?> {
  int _generation = 0;
  bool _disposed = false;
  Future<void> _operationQueue = Future<void>.value();
  AppErrorReporter _errorReporter = const NoopAppErrorReporter();

  @override
  PendingFareLock? build() {
    // Rebuilds reuse the same Notifier instance (e.g. invalidate for
    // redirect/disposal simulation): mark alive again so the fresh build's
    // restore can publish. Disposal still sets [_disposed] via onDispose.
    _disposed = false;
    _errorReporter = ref.read(appErrorReporterProvider);
    // Session isolation: the in-memory command always belongs to the
    // active rider. Any user, role, or status change drops it from view
    // while the persisted per-rider slot is left untouched. Every session
    // change also invalidates in-flight async completions and resets the
    // transient blocked flag; the next restore for the new rider re-derives
    // it from that rider's own slot.
    ref.listen(sessionControllerProvider, (previous, next) {
      if (previous?.user?.id == next.user?.id &&
          previous?.status == next.status &&
          previous?.role == next.role) {
        return;
      }
      _generation++;
      ref.read(confirmedBookingReferencesProvider.notifier).state = const [];
      _setBlocked(false);
      final pending = state;
      if (pending == null) return;
      final user = next.user;
      if (user == null ||
          next.status != SessionStatus.authenticated ||
          next.role != RideRole.rider ||
          user.id != pending.riderId) {
        state = null;
      }
    });
    ref.onDispose(() {
      _disposed = true;
      _generation++;
    });
    // Best-effort restoration; the session may still be loading here, so
    // entry points (fare screen) retry explicitly via restorePendingLock.
    Future<void>.microtask(restorePendingLock);
    return null;
  }

  /// True while the active rider's slot holds unresolved corrupt evidence.
  ///
  /// Surfaced via [pendingFareLockStorageBlockedProvider] so widgets can
  /// render a safe blocked state without treating corruption as absence.
  bool get isStorageBlocked {
    if (_disposed) return false;
    try {
      return ref.read(pendingFareLockStorageBlockedProvider);
    } on Object {
      return false;
    }
  }

  /// Serializes slot-affecting work so overlapping stage/restore/clear calls
  /// cannot interleave their persistence boundaries. Errors propagate to
  /// the caller while the chain itself never breaks.
  Future<T> _serialize<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _operationQueue = _operationQueue.then((_) async {
      try {
        completer.complete(await task());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  String? _authenticatedRiderId(SessionState session) {
    final user = session.user;
    if (user == null ||
        session.status != SessionStatus.authenticated ||
        session.role != RideRole.rider) {
      return null;
    }
    return user.id;
  }

  bool _sdkOwnsRider(String riderId) {
    final client = ref.read(supabaseClientProvider);
    return client == null || client.auth.currentUser?.id == riderId;
  }

  SessionState _readSessionSafely() {
    return ref.read(sessionControllerProvider);
  }

  void _setBlocked(bool value) {
    if (_disposed) return;
    try {
      ref.read(pendingFareLockStorageBlockedProvider.notifier).state = value;
    } on Object {
      // Disposal race: the flag is transient; the next live restore
      // re-derives it. Never throw from bookkeeping.
    }
  }

  void _report(String operation, Object error, StackTrace? stackTrace) {
    try {
      _errorReporter.report(
        operation: operation,
        error: error,
        stackTrace: stackTrace,
      );
    } on Object {
      // Diagnostics must never break recovery bookkeeping.
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  /// The server-backed draft boundary. Readiness is established afresh for
  /// every operation, never inferred from a null in-memory command. The same
  /// queue protects restore, staging, recovery and the entire RPC dispatch.
  Future<T> runBookingMutation<T>(Future<T> Function() dispatch) {
    final generation = _generation;
    final session = _readSessionSafely();
    final riderId = _authenticatedRiderId(session);
    bool current() =>
        _isCurrent(generation) &&
        identical(_readSessionSafely(), session) &&
        riderId != null;
    return _serialize(() async {
      if (!current()) {
        throw const FareException(FareFailure.mutationBlocked);
      }
      final PendingFareLockSlot slot;
      try {
        slot = await ref
            .read(pendingFareLockStoreProvider)
            .inspectForRider(riderId!);
      } on Object catch (error, stackTrace) {
        if (current()) _setBlocked(true);
        _report('checking booking mutation safety', error, stackTrace);
        throw const FareException(FareFailure.mutationBlocked);
      }
      if (!current()) {
        throw const FareException(FareFailure.mutationBlocked);
      }
      if (slot.isCorrupt ||
          (slot.isValid && slot.command!.riderId != riderId)) {
        _setBlocked(true);
        throw const FareException(FareFailure.mutationBlocked);
      }
      _setBlocked(false);
      _publishReferences(slot);
      // A well-formed transferred envelope can have confirmed references
      // and no pending command. Those locators do not impose an active-trip
      // policy: only unresolved evidence blocks legitimate draft dispatch.
      if (slot.isValid) {
        // Restore only this rider's evidence. A memory/storage conflict is
        // preserved, and neither command can authorize a mutation.
        state ??= slot.command;
      }
      if (state != null || slot.isValid) {
        throw const FareException(FareFailure.mutationBlocked);
      }
      // There is no await between the last ownership check and dispatch.
      final result = await dispatch();
      if (!current()) {
        // The RPC may have committed; never publish into a changed session.
        throw const FareException(FareFailure.mutationBlocked);
      }
      return result;
    });
  }

  /// Persists [command] completely, then publishes it.
  ///
  /// Callers dispatch the lock RPC only after this completes. Any throw
  /// (conflict, corruption, ownership loss, store failure, disposal)
  /// leaves state untouched (or, for post-save ownership loss, leaves the
  /// just-persisted per-rider evidence in place while publishing nothing),
  /// so the request must not be dispatched.
  Future<void> stageForDispatch(PendingFareLock command) {
    final generation = _generation;
    return _serialize(() async {
      if (!_isCurrent(generation)) {
        throw const PendingFareLockOwnershipException();
      }
      // F3: pre-flight ownership. The command must belong to the currently
      // authenticated rider; anything else fails closed without touching
      // storage, preserving existing evidence.
      SessionState preSession;
      try {
        preSession = _readSessionSafely();
      } on Object {
        throw const PendingFareLockOwnershipException();
      }
      final preRider = _authenticatedRiderId(preSession);
      if (preRider == null) {
        throw const PendingFareLockOwnershipException();
      }
      if (preRider != command.riderId) {
        _report(
          'staging the pending fare lock',
          const PendingFareLockOwnershipException(
            'Staged command rider does not match the active rider.',
          ),
          StackTrace.current,
        );
        throw const PendingFareLockOwnershipException();
      }
      // F1: in-memory exclusivity. Exact replay of the same tuple is
      // permitted; a different unresolved command blocks staging.
      final memory = state;
      if (memory != null && !memory.hasSameLockIdentity(command)) {
        _report(
          'staging the pending fare lock',
          const PendingFareLockConflictException(),
          StackTrace.current,
        );
        throw const PendingFareLockConflictException();
      }
      // F1+F4: persisted exclusivity. Inspect (never blind load) so corrupt
      // evidence cannot be mistaken for absence.
      final PendingFareLockSlot slot;
      try {
        slot = await ref
            .read(pendingFareLockStoreProvider)
            .inspectForRider(command.riderId);
      } on Object catch (error, stackTrace) {
        if (_isCurrent(generation)) _setBlocked(true);
        _report('staging the pending fare lock', error, stackTrace);
        throw const PendingFareLockCorruptException();
      }
      // F2+F3: invalidate stale work that overlapped the persistence read.
      if (!_isCurrent(generation)) {
        throw const PendingFareLockOwnershipException();
      }
      SessionState postInspectSession;
      try {
        postInspectSession = _readSessionSafely();
      } on Object {
        throw const PendingFareLockOwnershipException();
      }
      if (_authenticatedRiderId(postInspectSession) != command.riderId) {
        throw const PendingFareLockOwnershipException();
      }
      if (slot.isCorrupt) {
        _setBlocked(true);
        final corrupt = PendingFareLockCorruptException(
          'Persisted fare-lock evidence is ${slot.detail ?? 'unreadable'} '
          'and must not be overwritten.',
        );
        _report('staging the pending fare lock', corrupt, StackTrace.current);
        throw corrupt;
      }
      if (slot.isValid && !slot.command!.hasSameLockIdentity(command)) {
        _report(
          'staging the pending fare lock',
          const PendingFareLockConflictException(),
          StackTrace.current,
        );
        throw const PendingFareLockConflictException();
      }
      if (slot.confirmed
          .any((r) => r.command.bookingRequestId == command.bookingRequestId)) {
        throw const PendingFareLockConflictException(
            'Booking lineage was retired.');
      }
      // Durability first: a persistence failure is a known non-commit.
      try {
        await ref.read(pendingFareLockStoreProvider).save(
              memory ?? slot.command ?? command,
            );
      } on Object {
        rethrow;
      }
      // F3: post-save ownership. If the session changed, was signed out, or
      // the provider was disposed while persistence was pending, publish
      // nothing (never into another user's session) while preserving the
      // just-persisted per-rider evidence for same-user recovery. Throw so
      // callers cannot dispatch the Lock RPC.
      if (!_isCurrent(generation)) {
        throw const PendingFareLockOwnershipException();
      }
      SessionState postSaveSession;
      try {
        postSaveSession = _readSessionSafely();
      } on Object {
        throw const PendingFareLockOwnershipException();
      }
      if (_authenticatedRiderId(postSaveSession) != command.riderId) {
        throw const PendingFareLockOwnershipException();
      }
      if (_disposed) {
        throw const PendingFareLockOwnershipException();
      }
      _setBlocked(false);
      state = memory ?? slot.command ?? command;
    });
  }

  /// Drops the in-memory command and deletes its persisted slot.
  ///
  /// The slot is addressed by the command's own rider, never by a guessed
  /// active user. Only the exact staged lineage is deleted: a persisted
  /// record with a different identity, a corrupt record, or an unreadable
  /// slot is preserved and memory is kept (safe direction: still
  /// replayable). A delete failure keeps the in-memory command and reports
  /// the diagnostic.
  Future<void> clear(PendingFareLock command) {
    final generation = _generation;
    return _serialize(() => _clearExact(command, generation));
  }

  // Called only while holding the existing slot-operation queue.
  Future<void> _clearExact(PendingFareLock command, int generation) async {
    if (!_isCurrent(generation)) return;
    if (_authenticatedRiderId(_readSessionSafely()) != command.riderId) {
      return;
    }
    final pending = state;
    if (pending == null || !pending.hasSameLockIdentity(command)) return;
    // F2 exactness: verify the persisted slot still carries this exact
    // lineage before deleting. Never delete a newer or suspicious record.
    final PendingFareLockSlot slot;
    try {
      slot = await ref
          .read(pendingFareLockStoreProvider)
          .inspectForRider(command.riderId);
    } on Object catch (error, stackTrace) {
      _report('clearing the pending fare lock', error, stackTrace);
      return;
    }
    if (!_isCurrent(generation)) return;
    if (slot.isCorrupt) {
      _setBlocked(true);
      _report(
        'clearing the pending fare lock',
        PendingFareLockCorruptException(
          'Refusing to clear over ${slot.detail ?? 'unreadable'} evidence.',
        ),
        StackTrace.current,
      );
      return;
    }
    if (slot.isValid && !slot.command!.hasSameLockIdentity(command)) {
      _report(
        'clearing the pending fare lock',
        const PendingFareLockConflictException(
          'Refusing to clear a newer persisted fare lock.',
        ),
        StackTrace.current,
      );
      return;
    }
    try {
      await ref.read(pendingFareLockStoreProvider).clearForRider(
            command.riderId,
          );
    } on Object catch (error, stackTrace) {
      _report('clearing the pending fare lock', error, stackTrace);
      return;
    }
    if (!_isCurrent(generation)) return;
    // F2: only drop memory if it still carries this exact lineage, so an
    // overlapping newer stage is never discarded by an old clear.
    final current = state;
    if (current != null && current.hasSameLockIdentity(command)) {
      if (!_disposed) {
        state = null;
      }
      _setBlocked(false);
    }
  }

  /// Restores the same rider's hint, then reads canonical state without any
  /// RPC replay or draft mutation. Holds the slot queue through classification
  /// and exact evidence verification, so stale reads cannot erase commands.
  /// A missing SELECT is never proof that the original request cannot commit.
  Future<FareLockRecovery?> recoverCanonically() async {
    final generation = _generation;
    await restorePendingLock();
    return _serialize(() async {
      if (!_isCurrent(generation)) return null;
      final command = state;
      if (command == null ||
          _authenticatedRiderId(_readSessionSafely()) != command.riderId) {
        return null;
      }
      bool current() =>
          _isCurrent(generation) &&
          _authenticatedRiderId(_readSessionSafely()) == command.riderId &&
          state?.hasSameLockIdentity(command) == true;
      FareLockRecovery failed(FareFailure failure) => FareLockRecovery(
            command: command,
            status: failure == FareFailure.unauthorized ||
                    failure == FareFailure.forbidden
                ? FareLockRecoveryStatus.suspended
                : FareLockRecoveryStatus.uncertain,
            failure: failure,
          );
      if (isStorageBlocked) return failed(FareFailure.invalidResponse);
      final repository = ref.read(fareRepositoryProvider);
      if (repository is! FareLockRecoveryRepository) {
        return failed(FareFailure.unavailable);
      }
      final FareLockRecovery result;
      try {
        final rows = await (repository as FareLockRecoveryRepository)
            .readCanonicalFareLock(
          bookingRequestId: command.bookingRequestId,
          riderId: command.riderId,
        );
        if (!current()) return null;
        result = FareLockRecovery.classify(command, rows);
      } on FareException catch (error) {
        if (!current()) return null;
        return failed(error.failure);
      } on Object catch (error, stackTrace) {
        _report('recovering the canonical fare lock', error, stackTrace);
        if (!current()) return null;
        return failed(FareFailure.networkFailure);
      }
      if (result.status != FareLockRecoveryStatus.confirmed) return result;
      // Slice 3: a committed lock is not permission to create a replacement.
      // Retain evidence until authorized lifecycle cleanup can consume it.
      // Reinspect the exact slot before publishing canonical confirmation.
      final PendingFareLockSlot slot;
      try {
        slot = await ref
            .read(pendingFareLockStoreProvider)
            .inspectForRider(command.riderId);
      } on Object {
        if (current()) _setBlocked(true);
        return current() ? failed(FareFailure.unavailable) : null;
      }
      if (!current()) return null;
      if (!slot.isValid || !slot.command!.hasSameLockIdentity(command)) {
        if (slot.isCorrupt) _setBlocked(true);
        return failed(FareFailure.unavailable);
      }
      return result;
    });
  }

  /// Resolves or explicitly confirms only the protected original lineage.
  /// Confirmation never enters the draft gate, creates a draft, or clears
  /// evidence. A lost response is reconciled by the next canonical read.
  Future<BookingHandoff> bookingHandoff(
      {bool confirm = false, String? bookingRequestId}) async {
    final generation = _generation;
    final session = _readSessionSafely();
    final riderId = _authenticatedRiderId(session);
    await restorePendingLock();
    return _serialize(() async {
      bool current() =>
          _isCurrent(generation) &&
          riderId != null &&
          identical(_readSessionSafely(), session);
      void requireCurrent() {
        if (!current()) throw const FareException(FareFailure.mutationBlocked);
      }

      requireCurrent();
      final references = ref.read(confirmedBookingReferencesProvider);
      final retained = references
          .where((r) =>
              bookingRequestId == null ||
              r.command.bookingRequestId == bookingRequestId)
          .toList();
      final pending = state;
      final reference =
          (bookingRequestId != null || pending == null) && retained.isNotEmpty
              ? retained.last
              : null;
      final command = reference?.command ?? pending;
      if (command == null ||
          command.riderId != riderId ||
          isStorageBlocked ||
          (bookingRequestId != null &&
              command.bookingRequestId != bookingRequestId)) {
        throw const FareException(FareFailure.mutationBlocked);
      }
      final repository = ref.read(fareRepositoryProvider);
      if (repository is! FareLockRecoveryRepository) {
        throw const FareException(FareFailure.unavailable);
      }
      Future<BookingHandoff> read() async {
        final rows = await (repository as FareLockRecoveryRepository)
            .readCanonicalFareLock(
                bookingRequestId: command.bookingRequestId,
                riderId: command.riderId);
        requireCurrent();
        final slot = await ref
            .read(pendingFareLockStoreProvider)
            .inspectForRider(command.riderId);
        requireCurrent();
        final ownsPending = reference == null &&
            slot.isValid &&
            slot.command!.hasSameLockIdentity(command) &&
            state?.hasSameLockIdentity(command) == true;
        final ownsConfirmed = reference != null &&
            !slot.isCorrupt &&
            slot.confirmed.any((r) =>
                r.command.hasSameLockIdentity(command) &&
                r.quote == reference.quote);
        if (!ownsPending && !ownsConfirmed) {
          throw const FareException(FareFailure.mutationBlocked);
        }
        final handoff = BookingHandoff.classify(command, rows);
        if (handoff == null ||
            (reference != null &&
                (!handoff.isConfirmed || handoff.quote != reference.quote))) {
          throw const FareException(FareFailure.mutationBlocked);
        }
        return handoff;
      }

      final handoff = await read();
      if (!confirm || handoff.isConfirmed) return handoff;
      requireCurrent();
      if (repository is! BookingConfirmationRepository) {
        throw const FareException(FareFailure.unavailable);
      }
      await (repository as BookingConfirmationRepository).confirmLockedBooking(
          bookingRequestId: command.bookingRequestId,
          expectedVersion: handoff.booking.version,
          idempotencyKey:
              'confirm:${command.bookingRequestId}:${handoff.booking.version}',
          riderId: command.riderId);
      requireCurrent();
      final confirmed = await read();
      if (!confirmed.isConfirmed || confirmed.quote != handoff.quote) {
        throw const FareException(FareFailure.invalidResponse);
      }
      return confirmed;
    });
  }

  /// Fresh canonical authorization and one per-Rider best-effort transfer.
  /// Runs directly on the existing queue; never awaits another queued method.
  Future<BookingHandoff> resolveConfirmedEvidence(PendingFareLock command) {
    final generation = _generation;
    final session = _readSessionSafely();
    bool current() =>
        _isCurrent(generation) &&
        identical(_readSessionSafely(), session) &&
        _authenticatedRiderId(session) == command.riderId &&
        _sdkOwnsRider(command.riderId);
    void requireCurrent() {
      if (!current()) throw const FareException(FareFailure.mutationBlocked);
    }

    return _serialize(() async {
      requireCurrent();
      final store = ref.read(pendingFareLockStoreProvider);
      if (store is! ConfirmedBookingTransferStore) {
        throw const FareException(FareFailure.unavailable);
      }
      final repository = ref.read(fareRepositoryProvider);
      if (repository is! FareLockRecoveryRepository) {
        throw const FareException(FareFailure.unavailable);
      }
      // Even duplicate requests require fresh authenticated canonical proof.
      final rows = await (repository as FareLockRecoveryRepository)
          .readCanonicalFareLock(
              bookingRequestId: command.bookingRequestId,
              riderId: command.riderId);
      requireCurrent();
      final handoff = BookingHandoff.classify(command, rows);
      if (handoff == null || !handoff.isConfirmed) {
        throw const FareException(FareFailure.mutationBlocked);
      }
      final slot = await store.inspectForRider(command.riderId);
      requireCurrent();
      if (slot.isCorrupt) {
        _setBlocked(true);
        throw const FareException(FareFailure.mutationBlocked);
      }
      final retired = slot.confirmed
          .where((r) => r.command.bookingRequestId == command.bookingRequestId)
          .toList();
      if (retired.isNotEmpty) {
        if (!retired.single.command.hasSameLockIdentity(command) ||
            retired.single.quote != handoff.quote) {
          throw const FareException(FareFailure.mutationBlocked);
        }
        // Duplicate cleanup never clears an unrelated newer command.
        _publishReferences(slot);
        if (state?.hasSameLockIdentity(command) == true) {
          state = null;
        }
        _setBlocked(false);
        return handoff;
      }
      if (!slot.isValid ||
          !slot.command!.hasSameLockIdentity(command) ||
          state?.hasSameLockIdentity(command) != true) {
        throw const FareException(FareFailure.mutationBlocked);
      }
      final reference = ConfirmedBookingReference(
          command: slot.command!, quote: handoff.quote);
      try {
        await (store as ConfirmedBookingTransferStore)
            .retireConfirmed(reference, isAuthorized: current);
        requireCurrent();
        final written = await store.inspectForRider(command.riderId);
        requireCurrent();
        if (!written.isAbsent ||
            !written.confirmed.any((r) =>
                r.command.hasSameLockIdentity(command) &&
                r.quote == handoff.quote)) {
          throw const FareException(FareFailure.mutationBlocked);
        }
        _publishReferences(written);
        state = null;
        _setBlocked(false);
      } on Object {
        if (current()) _setBlocked(true);
        rethrow;
      }
      return handoff;
    });
  }

  void _publishReferences(PendingFareLockSlot slot) {
    ref.read(confirmedBookingReferencesProvider.notifier).state =
        List.unmodifiable(slot.confirmed);
  }

  /// Drops the in-memory command without touching persisted storage.
  /// Used at sign-out: visible state clears while recovery evidence stays.
  void clearMemory() {
    _generation++;
    _setBlocked(false);
    if (!_disposed) {
      ref.read(confirmedBookingReferencesProvider.notifier).state = const [];
      state = null;
    }
  }

  /// Re-hydrates the persisted command for the currently authenticated
  /// rider only. Anything else resolves to null without touching storage.
  /// Corrupt evidence surfaces [pendingFareLockStorageBlockedProvider]
  /// instead of resolving to silent absence; the suspicious record is
  /// preserved. Stale completions (session change, newer staged state,
  /// disposal) publish nothing. Never throws, so build-time and
  /// fire-and-forget callers stay safe.
  Future<void> restorePendingLock() {
    final generation = _generation;
    return _serialize(() async {
      if (!_isCurrent(generation)) return;
      SessionState preSession;
      try {
        preSession = _readSessionSafely();
      } on Object {
        return;
      }
      final preRider = _authenticatedRiderId(preSession);
      if (preRider == null) {
        return;
      }
      final PendingFareLockSlot slot;
      try {
        slot = await ref
            .read(pendingFareLockStoreProvider)
            .inspectForRider(preRider);
      } on Object catch (error, stackTrace) {
        if (_isCurrent(generation)) _setBlocked(true);
        _report('restoring the pending fare lock', error, stackTrace);
        return;
      }
      // F2+F3: stale restores publish nothing.
      if (!_isCurrent(generation)) return;
      SessionState postSession;
      try {
        postSession = _readSessionSafely();
      } on Object {
        return;
      }
      final postRider = _authenticatedRiderId(postSession);
      if (postRider == null || postRider != preRider) {
        return;
      }
      if (_disposed) return;
      if (slot.isCorrupt) {
        _setBlocked(true);
        _report(
          'restoring the pending fare lock',
          PendingFareLockCorruptException(
            'Persisted fare-lock evidence is ${slot.detail ?? 'unreadable'}.',
          ),
          StackTrace.current,
        );
        return;
      }
      _publishReferences(slot);
      final memoryBeforeRestore = state;
      if (memoryBeforeRestore != null &&
          slot.confirmed
              .any((r) => r.command.hasSameLockIdentity(memoryBeforeRestore))) {
        // A complete envelope proves transfer even if the previous write
        // completed after session loss or threw after applying its value.
        state = null;
      }
      if (slot.isAbsent) {
        _setBlocked(false);
        // Never discard newer in-memory state: absence only confirms
        // nothing when memory is already empty.
        return;
      }
      final stored = slot.command!;
      // Defense in depth: the slot is namespaced, but the record must still
      // attribute to the requesting rider before it may enter memory.
      if (stored.riderId != preRider) {
        _setBlocked(true);
        _report(
          'restoring the pending fare lock',
          const PendingFareLockCorruptException(
            'Persisted fare-lock rider mismatch.',
          ),
          StackTrace.current,
        );
        return;
      }
      final memory = state;
      if (memory != null && !memory.hasSameLockIdentity(stored)) {
        // A newer staged command wins over a stale restore; both records
        // are preserved and the conflict is diagnosed.
        _report(
          'restoring the pending fare lock',
          const PendingFareLockConflictException(
            'Stale restore refused over newer staged fare lock.',
          ),
          StackTrace.current,
        );
        return;
      }
      _setBlocked(false);
      state = stored;
    });
  }
}

class ActiveTripController extends Notifier<MockTrip?> {
  Future<void>? _tripCreation;

  @override
  MockTrip? build() => null;

  Future<void> createTrip() {
    return _tripCreation ??= _createTrip().whenComplete(() {
      _tripCreation = null;
    });
  }

  Future<void> _createTrip() async {
    final trip = await ref
        .read(tripsRepositoryProvider)
        .createTrip(ref.read(bookingControllerProvider));
    state = trip;
  }

  void setTrip(MockTrip trip) => state = trip;

  void setStatus(TripStatus status) {
    final trip = state;
    if (trip == null || !canTransition(trip.status, status)) {
      return;
    }
    state = trip.copyWith(status: status);
  }

  void reset() => state = null;
}

class NotificationsController extends Notifier<List<AppNotification>> {
  @override
  List<AppNotification> build() => MockData.notifications;

  void markAllRead() {
    state = [
      for (final notification in state) notification.copyWith(isRead: true),
    ];
  }

  void markRead(String id) {
    state = [
      for (final notification in state)
        notification.id == id
            ? notification.copyWith(isRead: true)
            : notification,
    ];
  }
}

class NotificationPreferences {
  const NotificationPreferences({
    this.push = true,
    this.sms = true,
    this.email = false,
  });

  final bool push;
  final bool sms;
  final bool email;

  NotificationPreferences copyWith({bool? push, bool? sms, bool? email}) {
    return NotificationPreferences(
      push: push ?? this.push,
      sms: sms ?? this.sms,
      email: email ?? this.email,
    );
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
final bookingControllerProvider =
    NotifierProvider<BookingController, BookingDraft>(BookingController.new);
final pendingFareLockStoreProvider = Provider<PendingFareLockStore>((ref) {
  return SharedPreferencesPendingFareLockStore(SharedPreferencesAsync());
});
final pendingFareLockControllerProvider =
    NotifierProvider<PendingFareLockController, PendingFareLock?>(
  PendingFareLockController.new,
);

/// Transient safe-blocked flag for unresolved pending-lock storage
/// corruption (Slice 1, F4).
///
/// True only while the active rider's slot inspected as corrupt/unreadable.
/// It is reset on session changes and re-derived by the next restore/stage
/// for the new rider, so one rider's suspicious evidence never blocks
/// another rider. Widgets combine this with existing conflict/suspension
/// guards to render "Fare recovery blocked" without exposing raw records.
final pendingFareLockStorageBlockedProvider = StateProvider<bool>(
  (ref) => false,
);
final activeTripControllerProvider =
    NotifierProvider<ActiveTripController, MockTrip?>(
  ActiveTripController.new,
);
final notificationsControllerProvider =
    NotifierProvider<NotificationsController, List<AppNotification>>(
  NotificationsController.new,
);
final notificationPreferencesProvider = StateProvider<NotificationPreferences>(
  (ref) => const NotificationPreferences(),
);
final driverOnlineProvider = StateProvider<bool>((ref) => true);

/// Session-scoped confirmed locators. Canonical reads remain authoritative.
final confirmedBookingReferencesProvider =
    StateProvider<List<ConfirmedBookingReference>>((ref) => const []);
