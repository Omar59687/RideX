import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_assigned_trip.dart';
import 'package:ridex/core/models/rider_trip_lifecycle_state.dart';
import 'package:ridex/core/models/rider_trip_tracking_event.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/rider_trip_tracking_repository.dart';
import 'package:ridex/core/services/rider_trip_lifecycle_signals.dart';

/// Injection seam for the merged C01 read/watch contract.
///
/// Slice 1 intentionally has no production repository. Callers without an
/// explicitly composed source remain unavailable rather than falling back to
/// mock Trip state.
final riderTripTrackingRepositoryProvider =
    Provider<RiderTripTrackingRepository?>((ref) => null);

final riderTripLifecycleClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final riderTripAppLifecycleSignalSourceProvider =
    Provider<RiderTripAppLifecycleSignalSource>((ref) {
  final source = WidgetsRiderTripAppLifecycleSignalSource();
  ref.onDispose(source.dispose);
  return source;
});

final riderTripConnectionSignalSourceProvider =
    Provider<RiderTripConnectionSignalSource>(
  (ref) => const NoopRiderTripConnectionSignalSource(),
);

final riderTripLifecycleControllerProvider = NotifierProvider.autoDispose
    .family<RiderTripLifecycleController, RiderTripLifecycleState,
        RiderTripLifecycleRequest>(RiderTripLifecycleController.new);

class RiderTripLifecycleController extends AutoDisposeFamilyNotifier<
    RiderTripLifecycleState, RiderTripLifecycleRequest> {
  StreamSubscription<RiderTripTrackingEvent>? _eventsSubscription;
  StreamSubscription<void>? _appLifecycleSubscription;
  StreamSubscription<RiderTripConnectionSignal>? _connectionSignalSubscription;
  Future<void>? _watchCancellation;
  Future<void>? _readRun;
  int? _readRunGeneration;
  int _generation = 0;
  int _watchGeneration = 0;
  int _signalGeneration = 0;
  int _reconciliationRevision = 0;
  int? _latestConnectionGeneration;
  int? _lastInterruptedConnectionGeneration;
  int? _lastRestoredConnectionGeneration;
  int? _latestEventSequence;
  int? _latestSnapshotVersion;
  DriverTripLifecycleStatus? _latestSnapshotStatus;
  bool _readAgain = false;
  bool _connectionInterrupted = false;
  bool _disposed = false;
  late RiderTripLifecycleRequest _request;
  late SessionState _session;
  RiderTripTrackingRepository? _repository;
  RiderAssignedTrip? _lastCanonicalTrip;

  @override
  RiderTripLifecycleState build(RiderTripLifecycleRequest arg) {
    _request = arg;
    _session = ref.read(sessionControllerProvider);
    _repository = ref.read(riderTripTrackingRepositoryProvider);
    _disposed = false;

    ref.listen<SessionState>(sessionControllerProvider, (previous, next) {
      if (identical(previous, next)) return;
      _replaceScope(session: next, repository: _repository);
    });
    ref.listen<RiderTripTrackingRepository?>(
      riderTripTrackingRepositoryProvider,
      (previous, next) {
        if (identical(previous, next)) return;
        _replaceScope(session: _session, repository: next);
      },
    );
    ref.listen<RiderTripAppLifecycleSignalSource>(
      riderTripAppLifecycleSignalSourceProvider,
      (previous, next) {
        if (identical(previous, next)) return;
        _replaceSignalSubscriptions();
      },
    );
    ref.listen<RiderTripConnectionSignalSource>(
      riderTripConnectionSignalSourceProvider,
      (previous, next) {
        if (identical(previous, next)) return;
        _replaceSignalSubscriptions();
      },
    );
    _replaceSignalSubscriptions();
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _signalGeneration++;
      _lastCanonicalTrip = null;
      _readRun = null;
      _readRunGeneration = null;
      _readAgain = false;
      final appLifecycleSubscription = _appLifecycleSubscription;
      _appLifecycleSubscription = null;
      final connectionSignalSubscription = _connectionSignalSubscription;
      _connectionSignalSubscription = null;
      if (appLifecycleSubscription != null) {
        unawaited(_cancelSignalSubscription(appLifecycleSubscription));
      }
      if (connectionSignalSubscription != null) {
        unawaited(_cancelSignalSubscription(connectionSignalSubscription));
      }
      unawaited(_detachWatch());
    });

    final initial = _initialState(_session, _repository);
    final context = _captureContext();
    if (context != null) unawaited(_start(context));
    return initial;
  }

  /// Explicit reconnect hook for a future connection owner.
  ///
  /// A reconnect always replaces the old watcher and obtains a new canonical
  /// read. It does not interpret the reconnect signal as a Trip status.
  Future<void> reconcileAfterReconnect() => _reconcileAfterLifecycleSignal();

  /// Explicit resume hook for a future app-lifecycle owner.
  Future<void> reconcileAfterResume() => _reconcileAfterLifecycleSignal();

  Future<void> _reconcileAfterLifecycleSignal() async {
    final context = _captureContext();
    if (context == null) return;

    if (_lastCanonicalTrip != null || state.isVerified) {
      state = state.markStale(RiderTripLifecycleFailure.disconnected);
    }
    _reconciliationRevision++;
    await _detachWatch();
    if (!_isCurrent(context)) return;
    if (!(_lastCanonicalTrip?.isTerminal ?? false)) _attachWatch(context);
    await _requestCanonicalRead(context);
  }

  Future<void> _start(_RiderTripLifecycleContext context) async {
    await _detachWatch();
    if (!_isCurrent(context)) return;
    _attachWatch(context);
    await _requestCanonicalRead(context);
  }

  void _replaceScope({
    required SessionState session,
    required RiderTripTrackingRepository? repository,
  }) {
    _session = session;
    _repository = repository;
    final generation = ++_generation;
    _lastCanonicalTrip = null;
    _latestEventSequence = null;
    _latestSnapshotVersion = null;
    _latestSnapshotStatus = null;
    _reconciliationRevision = 0;
    _latestConnectionGeneration = null;
    _lastInterruptedConnectionGeneration = null;
    _lastRestoredConnectionGeneration = null;
    _connectionInterrupted = false;
    _readRun = null;
    _readRunGeneration = null;
    _readAgain = false;
    unawaited(_detachWatch());
    _replaceSignalSubscriptions();

    state = _initialState(session, repository);
    final context = _captureContext(generation: generation);
    if (context != null) unawaited(_start(context));
  }

  RiderTripLifecycleState _initialState(
    SessionState session,
    RiderTripTrackingRepository? repository,
  ) {
    if (session.status == SessionStatus.loading) {
      return RiderTripLifecycleState.loading();
    }
    if (_riderIdFor(session) == null) {
      return const RiderTripLifecycleState.unavailable(
        failure: RiderTripLifecycleFailure.authorizationUnavailable,
      );
    }
    if (repository == null) {
      return const RiderTripLifecycleState.unavailable(
        failure: RiderTripLifecycleFailure.repositoryUnavailable,
      );
    }
    return RiderTripLifecycleState.loading();
  }

  _RiderTripLifecycleContext? _captureContext({int? generation}) {
    final riderId = _riderIdFor(_session);
    final repository = _repository;
    if (riderId == null || repository == null) return null;
    return _RiderTripLifecycleContext(
      generation: generation ?? _generation,
      session: _session,
      riderId: riderId,
      repository: repository,
    );
  }

  String? _riderIdFor(SessionState session) {
    final user = session.user;
    if (session.status != SessionStatus.authenticated ||
        user == null ||
        user.role != RideRole.rider ||
        user.isBlocked ||
        !isCanonicalTripId(user.id)) {
      return null;
    }
    return user.id;
  }

  bool _isCurrent(_RiderTripLifecycleContext context) {
    if (_disposed ||
        context.generation != _generation ||
        !identical(ref.read(sessionControllerProvider), context.session) ||
        !identical(
          ref.read(riderTripTrackingRepositoryProvider),
          context.repository,
        )) {
      return false;
    }
    return _riderIdFor(context.session) == context.riderId;
  }

  void _replaceSignalSubscriptions() {
    final signalGeneration = ++_signalGeneration;
    final scopeGeneration = _generation;
    final previousAppSubscription = _appLifecycleSubscription;
    final previousConnectionSubscription = _connectionSignalSubscription;
    _appLifecycleSubscription = null;
    _connectionSignalSubscription = null;
    _latestConnectionGeneration = null;
    _lastInterruptedConnectionGeneration = null;
    _lastRestoredConnectionGeneration = null;
    _connectionInterrupted = false;
    if (previousAppSubscription != null) {
      unawaited(_cancelSignalSubscription(previousAppSubscription));
    }
    if (previousConnectionSubscription != null) {
      unawaited(_cancelSignalSubscription(previousConnectionSubscription));
    }
    if (_disposed) return;

    final appLifecycleSource =
        ref.read(riderTripAppLifecycleSignalSourceProvider);
    final connectionSource = ref.read(riderTripConnectionSignalSourceProvider);
    _appLifecycleSubscription = appLifecycleSource.resumed.listen((_) {
      if (!_isCurrentSignal(
        scopeGeneration,
        signalGeneration,
        appLifecycleSource,
        connectionSource,
      )) {
        return;
      }
      unawaited(reconcileAfterResume());
    });
    _connectionSignalSubscription = connectionSource.events.listen((signal) {
      _handleConnectionSignal(
        signal,
        scopeGeneration: scopeGeneration,
        signalGeneration: signalGeneration,
        appLifecycleSource: appLifecycleSource,
        connectionSource: connectionSource,
      );
    });
  }

  bool _isCurrentSignal(
    int scopeGeneration,
    int signalGeneration,
    RiderTripAppLifecycleSignalSource appLifecycleSource,
    RiderTripConnectionSignalSource connectionSource,
  ) {
    if (_disposed ||
        scopeGeneration != _generation ||
        signalGeneration != _signalGeneration) {
      return false;
    }
    try {
      return identical(
            ref.read(riderTripAppLifecycleSignalSourceProvider),
            appLifecycleSource,
          ) &&
          identical(
            ref.read(riderTripConnectionSignalSourceProvider),
            connectionSource,
          );
    } on Object {
      return false;
    }
  }

  void _handleConnectionSignal(
    RiderTripConnectionSignal signal, {
    required int scopeGeneration,
    required int signalGeneration,
    required RiderTripAppLifecycleSignalSource appLifecycleSource,
    required RiderTripConnectionSignalSource connectionSource,
  }) {
    if (!_isCurrentSignal(
      scopeGeneration,
      signalGeneration,
      appLifecycleSource,
      connectionSource,
    )) {
      return;
    }

    switch (signal) {
      case RiderTripConnectivityAvailable():
        return;
      case RiderTripConnectionStatusChanged(
          status: final status,
          generation: final generation,
        ):
        final previousGeneration = _latestConnectionGeneration;
        if (previousGeneration != null && generation < previousGeneration) {
          return;
        }
        if (previousGeneration == null || generation > previousGeneration) {
          _latestConnectionGeneration = generation;
        }
        switch (status) {
          case RiderTripConnectionStatus.connecting:
            return;
          case RiderTripConnectionStatus.interrupted:
            _recordConnectionInterruption(generation: generation);
            return;
          case RiderTripConnectionStatus.restored:
            final previousRestoredGeneration =
                _lastRestoredConnectionGeneration;
            if (previousRestoredGeneration != null &&
                generation <= previousRestoredGeneration) {
              return;
            }
            // Record even an initial/unpaired restoration so a delayed
            // duplicate cannot satisfy a later interruption on this attempt.
            _lastRestoredConnectionGeneration = generation;
            final interruptedGeneration = _lastInterruptedConnectionGeneration;
            if (!_connectionInterrupted ||
                (interruptedGeneration != null &&
                    generation <= interruptedGeneration)) {
              return;
            }
            _connectionInterrupted = false;
            unawaited(reconcileAfterReconnect());
            return;
        }
    }
  }

  Future<void> _cancelSignalSubscription(
      StreamSubscription<dynamic> sub) async {
    try {
      await sub.cancel();
    } on Object {
      // Cleanup failures cannot restore a signal subscription's authority.
    }
  }

  Future<void> _requestCanonicalRead(
    _RiderTripLifecycleContext context, {
    bool supersedeInFlight = false,
  }) {
    if (!_isCurrent(context)) return Future<void>.value();
    if (supersedeInFlight) _reconciliationRevision++;
    final activeRun = _readRun;
    if (activeRun != null && _readRunGeneration == context.generation) {
      _readAgain = true;
      return activeRun;
    }

    _readAgain = false;
    _readRunGeneration = context.generation;
    late final Future<void> run;
    run = _drainCanonicalReads(context).whenComplete(() {
      if (!identical(_readRun, run)) return;
      _readRun = null;
      _readRunGeneration = null;
      final hasTrailingRead = _readAgain && _isCurrent(context);
      _readAgain = false;
      if (hasTrailingRead) unawaited(_requestCanonicalRead(context));
    });
    _readRun = run;
    return run;
  }

  Future<void> _drainCanonicalReads(_RiderTripLifecycleContext context) async {
    do {
      _readAgain = false;
      final revision = _reconciliationRevision;
      await _readCanonicalOnce(context, revision);
      if (!_isCurrent(context)) return;
    } while (_readAgain);
  }

  Future<void> _readCanonicalOnce(
    _RiderTripLifecycleContext context,
    int reconciliationRevision,
  ) async {
    try {
      final trip = await context.repository.findByTrip(tripId: _request.tripId);
      if (!_isCurrent(context) ||
          reconciliationRevision != _reconciliationRevision) {
        return;
      }
      if (trip == null) {
        _lastCanonicalTrip = null;
        state = RiderTripLifecycleState.unavailable(
          failure: RiderTripLifecycleFailure.tripUnavailable,
          latestEventSequence: _latestEventSequence,
        );
        unawaited(_detachWatch());
        return;
      }
      if (!_isValidCanonicalTrip(trip, context.riderId)) {
        _lastCanonicalTrip = null;
        state = RiderTripLifecycleState.unavailable(
          failure: RiderTripLifecycleFailure.invalidCanonicalData,
          latestEventSequence: _latestEventSequence,
        );
        unawaited(_detachWatch());
        return;
      }

      final previous = _lastCanonicalTrip;
      if (previous != null) {
        if (trip.version < previous.version) {
          state = state.markStale(
            RiderTripLifecycleFailure.staleCanonicalRead,
            eventSequence: _latestEventSequence,
          );
          return;
        }
        if (trip.version == previous.version &&
            trip.status != previous.status) {
          state = state.markStale(
            RiderTripLifecycleFailure.conflictingCanonicalVersion,
            eventSequence: _latestEventSequence,
          );
          return;
        }
        if (previous.isTerminal &&
            (trip.version != previous.version ||
                trip.status != previous.status)) {
          state = state.markStale(
            RiderTripLifecycleFailure.invalidStatusTransition,
            eventSequence: _latestEventSequence,
          );
          return;
        }
        if (trip.version > previous.version &&
            !_canReachStatus(previous.status, trip.status)) {
          state = state.markStale(
            RiderTripLifecycleFailure.invalidStatusTransition,
            eventSequence: _latestEventSequence,
          );
          return;
        }
      }

      final verifiedAt = ref.read(riderTripLifecycleClockProvider)().toUtc();
      _lastCanonicalTrip = trip;
      state = trip.isTerminal
          ? RiderTripLifecycleState.terminal(
              trip: trip,
              verifiedAt: verifiedAt,
              latestEventSequence: _latestEventSequence,
            )
          : RiderTripLifecycleState.verified(
              trip: trip,
              verifiedAt: verifiedAt,
              latestEventSequence: _latestEventSequence,
            );
      if (trip.isTerminal) {
        unawaited(_detachWatch());
      } else if (_eventsSubscription == null) {
        _attachWatch(context);
      }
    } on Object {
      if (!_isCurrent(context) ||
          reconciliationRevision != _reconciliationRevision) {
        return;
      }
      if (_lastCanonicalTrip != null) {
        state = state.markStale(
          RiderTripLifecycleFailure.readFailed,
          eventSequence: _latestEventSequence,
        );
      } else {
        state = RiderTripLifecycleState.unavailable(
          failure: RiderTripLifecycleFailure.readFailed,
          latestEventSequence: _latestEventSequence,
        );
      }
    }
  }

  bool _isValidCanonicalTrip(RiderAssignedTrip trip, String riderId) {
    return isCanonicalTripId(trip.tripId) &&
        trip.tripId.toLowerCase() == _request.tripId.toLowerCase() &&
        isCanonicalTripId(trip.bookingRequestId) &&
        trip.bookingRequestId.toLowerCase() ==
            _request.bookingRequestId.toLowerCase() &&
        isCanonicalTripId(trip.riderId) &&
        trip.riderId.toLowerCase() == riderId.toLowerCase() &&
        trip.version > 0 &&
        DriverTripLifecycleStatus.values.contains(trip.status) &&
        trip.paymentMethod == PaymentMethod.cash;
  }

  void _attachWatch(_RiderTripLifecycleContext context) {
    if (!_isCurrent(context) ||
        _eventsSubscription != null ||
        (_lastCanonicalTrip?.isTerminal ?? false)) {
      return;
    }
    final watchGeneration = ++_watchGeneration;
    try {
      final stream = context.repository.watch(tripId: _request.tripId);
      _eventsSubscription = stream.listen(
        (event) => _handleEvent(event, context, watchGeneration),
        onError: (Object _, StackTrace __) {
          _markDisconnected(context, watchGeneration);
        },
        onDone: () => _markDisconnected(context, watchGeneration),
      );
    } on Object {
      _markStale(RiderTripLifecycleFailure.disconnected);
    }
  }

  void _handleEvent(
    RiderTripTrackingEvent event,
    _RiderTripLifecycleContext context,
    int watchGeneration,
  ) {
    if (!_isCurrent(context) ||
        watchGeneration != _watchGeneration ||
        event.tripId.toLowerCase() != _request.tripId.toLowerCase()) {
      return;
    }

    switch (event) {
      case RiderTripStatusChanged():
        _handleStatusEvent(event, context);
      case RiderTripSnapshot():
        _handleSnapshotEvent(event, context);
      case RiderTripTrackingDisconnected():
        _recordConnectionInterruption();
      case RiderTripLocationChanged():
        // Location is not lifecycle authority and is outside Slice 1 state.
        return;
    }
  }

  void _handleStatusEvent(
    RiderTripStatusChanged event,
    _RiderTripLifecycleContext context,
  ) {
    final previousSequence = _latestEventSequence;
    if (previousSequence != null && event.eventSequence <= previousSequence) {
      return;
    }
    _latestEventSequence = event.eventSequence;
    state = state.withEventSequence(event.eventSequence);

    final current = _lastCanonicalTrip;
    if (current == null) {
      unawaited(_requestCanonicalRead(context, supersedeInFlight: true));
      return;
    }
    if (!state.isVerified) {
      unawaited(_requestCanonicalRead(context, supersedeInFlight: true));
      return;
    }
    if (event.tripVersion < current.version) return;
    if (event.tripVersion == current.version &&
        event.status == current.status) {
      return;
    }

    state = state.markStale(
      event.tripVersion == current.version
          ? RiderTripLifecycleFailure.conflictingCanonicalVersion
          : RiderTripLifecycleFailure.disconnected,
      eventSequence: event.eventSequence,
    );
    unawaited(_requestCanonicalRead(context, supersedeInFlight: true));
  }

  void _handleSnapshotEvent(
    RiderTripSnapshot event,
    _RiderTripLifecycleContext context,
  ) {
    final snapshot = event.trip;
    if (!_isValidCanonicalTrip(snapshot, context.riderId)) return;

    final previousSnapshotVersion = _latestSnapshotVersion;
    if (previousSnapshotVersion != null &&
        snapshot.version < previousSnapshotVersion) {
      return;
    }
    if (previousSnapshotVersion == snapshot.version &&
        _latestSnapshotStatus == snapshot.status) {
      return;
    }
    _latestSnapshotVersion = snapshot.version;
    _latestSnapshotStatus = snapshot.status;

    final current = _lastCanonicalTrip;
    if (!state.isVerified) {
      state = state.markStale(
        RiderTripLifecycleFailure.disconnected,
      );
      unawaited(_requestCanonicalRead(context, supersedeInFlight: true));
      return;
    }
    if (current != null && snapshot.version < current.version) return;
    if (current != null &&
        snapshot.version == current.version &&
        snapshot.status == current.status) {
      return;
    }

    state = state.markStale(
      current != null && snapshot.version == current.version
          ? RiderTripLifecycleFailure.conflictingCanonicalVersion
          : RiderTripLifecycleFailure.disconnected,
    );
    unawaited(_requestCanonicalRead(context, supersedeInFlight: true));
  }

  void _markDisconnected(
    _RiderTripLifecycleContext context,
    int watchGeneration,
  ) {
    if (!_isCurrent(context) || watchGeneration != _watchGeneration) return;
    _recordConnectionInterruption();
  }

  void _recordConnectionInterruption({int? generation}) {
    _connectionInterrupted = true;
    final interruptedGeneration = generation ?? _latestConnectionGeneration;
    final previousInterruptedGeneration = _lastInterruptedConnectionGeneration;
    if (interruptedGeneration != null &&
        (previousInterruptedGeneration == null ||
            interruptedGeneration > previousInterruptedGeneration)) {
      _lastInterruptedConnectionGeneration = interruptedGeneration;
    }
    _markStale(RiderTripLifecycleFailure.disconnected);
  }

  void _markStale(RiderTripLifecycleFailure failure) {
    state = state.markStale(failure, eventSequence: _latestEventSequence);
  }

  Future<void> _detachWatch() {
    ++_watchGeneration;
    final subscription = _eventsSubscription;
    _eventsSubscription = null;
    if (subscription == null) {
      return _watchCancellation ?? Future<void>.value();
    }
    final cancellation = _cancelSubscription(subscription);
    _watchCancellation = cancellation;
    return cancellation;
  }

  Future<void> _cancelSubscription(
    StreamSubscription<RiderTripTrackingEvent> subscription,
  ) async {
    try {
      await subscription.cancel();
    } on Object {
      // Cleanup failures must not restore the subscription's authority.
    }
  }

  bool _canReachStatus(
    DriverTripLifecycleStatus from,
    DriverTripLifecycleStatus to,
  ) {
    if (from == to) return true;
    if (_isTerminalStatus(from)) return false;

    return switch (to) {
      DriverTripLifecycleStatus.accepted => false,
      DriverTripLifecycleStatus.driverArriving =>
        from == DriverTripLifecycleStatus.accepted,
      DriverTripLifecycleStatus.driverArrived =>
        from == DriverTripLifecycleStatus.accepted ||
            from == DriverTripLifecycleStatus.driverArriving,
      DriverTripLifecycleStatus.inProgress =>
        from == DriverTripLifecycleStatus.accepted ||
            from == DriverTripLifecycleStatus.driverArriving ||
            from == DriverTripLifecycleStatus.driverArrived,
      DriverTripLifecycleStatus.completed =>
        from == DriverTripLifecycleStatus.accepted ||
            from == DriverTripLifecycleStatus.driverArriving ||
            from == DriverTripLifecycleStatus.driverArrived ||
            from == DriverTripLifecycleStatus.inProgress,
      DriverTripLifecycleStatus.cancelledByRider ||
      DriverTripLifecycleStatus.cancelledByDriver =>
        from == DriverTripLifecycleStatus.accepted ||
            from == DriverTripLifecycleStatus.driverArriving ||
            from == DriverTripLifecycleStatus.driverArrived,
      DriverTripLifecycleStatus.cancelledByAdmin ||
      DriverTripLifecycleStatus.failed =>
        true,
    };
  }

  bool _isTerminalStatus(DriverTripLifecycleStatus status) => switch (status) {
        DriverTripLifecycleStatus.completed ||
        DriverTripLifecycleStatus.cancelledByRider ||
        DriverTripLifecycleStatus.cancelledByDriver ||
        DriverTripLifecycleStatus.cancelledByAdmin ||
        DriverTripLifecycleStatus.failed =>
          true,
        DriverTripLifecycleStatus.accepted ||
        DriverTripLifecycleStatus.driverArriving ||
        DriverTripLifecycleStatus.driverArrived ||
        DriverTripLifecycleStatus.inProgress =>
          false,
      };
}

class _RiderTripLifecycleContext {
  const _RiderTripLifecycleContext({
    required this.generation,
    required this.session,
    required this.riderId,
    required this.repository,
  });

  final int generation;
  final SessionState session;
  final String riderId;
  final RiderTripTrackingRepository repository;
}
