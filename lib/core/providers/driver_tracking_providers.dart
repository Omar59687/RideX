import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:ridex/core/errors/driver_location_exception.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/services/driver_location/driver_gps_stream_service.dart';
import 'package:ridex/core/services/driver_location/driver_location_validation_policy.dart';
import 'package:ridex/core/services/driver_location/driver_tracking_connection.dart';
import 'package:ridex/core/services/driver_location/geolocator_driver_gps_stream_service.dart';
import 'package:ridex/core/services/driver_location/supabase_driver_tracking_connection.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';

enum DriverTrackingStatus {
  stopped,
  paused,
  starting,
  sharing,
  unavailable,
}

enum DriverTrackingLifecycleState { foreground, background }

abstract interface class DriverTrackingLifecycle {
  Stream<DriverTrackingLifecycleState> get changes;

  void dispose();
}

class WidgetsDriverTrackingLifecycle
    with WidgetsBindingObserver
    implements DriverTrackingLifecycle {
  WidgetsDriverTrackingLifecycle() {
    WidgetsBinding.instance.addObserver(this);
  }

  final _changes = StreamController<DriverTrackingLifecycleState>.broadcast();

  @override
  Stream<DriverTrackingLifecycleState> get changes => _changes.stream;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _changes.add(
      state == AppLifecycleState.resumed
          ? DriverTrackingLifecycleState.foreground
          : DriverTrackingLifecycleState.background,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _changes.close();
  }
}

class DriverTrackingState extends Equatable {
  const DriverTrackingState({
    required this.status,
    this.failure,
    this.nextSequence,
    this.latestConfirmedAt,
  });

  const DriverTrackingState.initial()
      : status = DriverTrackingStatus.stopped,
        failure = null,
        nextSequence = null,
        latestConfirmedAt = null;

  final DriverTrackingStatus status;
  final DriverLocationFailure? failure;
  final int? nextSequence;
  final DateTime? latestConfirmedAt;

  @override
  List<Object?> get props => [status, failure, nextSequence, latestConfirmedAt];
}

final driverGpsStreamServiceProvider = Provider<DriverGpsStreamService>(
  (ref) => GeolocatorDriverGpsStreamService(
    errorReporter: ref.watch(appErrorReporterProvider),
  ),
);

final driverTrackingLifecycleProvider = Provider<DriverTrackingLifecycle>(
  (ref) {
    final lifecycle = WidgetsDriverTrackingLifecycle();
    ref.onDispose(lifecycle.dispose);
    return lifecycle;
  },
);

final driverTrackingConnectionProvider = Provider<DriverTrackingConnection>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    if (client == null) return const NoopDriverTrackingConnection();
    final connection = SupabaseDriverTrackingConnection(
      client,
      ref.watch(appErrorReporterProvider),
    );
    ref.onDispose(connection.dispose);
    return connection;
  },
);

final driverTrackingClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final driverTrackingControllerProvider =
    NotifierProvider.autoDispose<DriverTrackingController, DriverTrackingState>(
  DriverTrackingController.new,
);

class DriverTrackingController
    extends AutoDisposeNotifier<DriverTrackingState> {
  static const _validationPolicy = DriverLocationValidationPolicy();

  StreamSubscription<DriverLocationFix>? _subscription;
  StreamSubscription<DriverTrackingLifecycleState>? _lifecycleSubscription;
  StreamSubscription<DriverTrackingConnectionEvent>? _connectionSubscription;
  Future<void> _publishQueue = Future<void>.value();
  Future<void> _lifecycleQueue = Future<void>.value();
  Future<void>? _configurationSyncFuture;
  Future<void>? _subscriptionCancellation;
  ({DriverLocationFix fix, int generation})? _pendingPublish;
  DriverLocationFix? _latestAcceptedFix;
  DriverGpsTrackingConfig? _trackingConfig;
  DateTime? _latestRecordedAt;
  DateTime? _latestConfirmedAt;
  String? _activeTripId;
  int _nextSequence = 1;
  bool _startInProgress = false;
  bool _recoveryInProgress = false;
  bool _trackingRequested = false;
  bool _backgrounded = false;
  bool _connectionFailurePending = false;
  bool _configurationSyncPending = false;
  bool _configurationSyncRequested = false;
  bool _recoveryRequested = false;
  bool _publishDrainScheduled = false;
  int? _connectionGeneration;
  int _generation = 0;
  bool _disposed = false;
  late final AppErrorReporter _errorReporter;

  @override
  DriverTrackingState build() {
    _errorReporter = ref.read(appErrorReporterProvider);
    final connection = ref.read(driverTrackingConnectionProvider);
    _lifecycleSubscription = ref
        .read(driverTrackingLifecycleProvider)
        .changes
        .listen(_handleLifecycleChange);
    _connectionSubscription = connection.events.listen(_handleConnectionEvent);
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      final subscription = _subscription;
      _subscription = null;
      final lifecycleSubscription = _lifecycleSubscription;
      _lifecycleSubscription = null;
      final connectionSubscription = _connectionSubscription;
      _connectionSubscription = null;
      _connectionGeneration = null;
      _connectionFailurePending = false;
      if (subscription != null) {
        unawaited(_containCleanup(
          'disposing the driver GPS stream',
          subscription.cancel,
        ));
      }
      if (lifecycleSubscription != null) {
        unawaited(_containCleanup(
          'disposing the driver lifecycle subscription',
          lifecycleSubscription.cancel,
        ));
      }
      if (connectionSubscription != null) {
        unawaited(_containCleanup(
          'disposing the driver connection subscription',
          connectionSubscription.cancel,
        ));
      }
      unawaited(_containCleanup(
        'disposing the driver tracking connection',
        connection.dispose,
      ));
    });
    return const DriverTrackingState.initial();
  }

  Future<void> start() async {
    _trackingRequested = true;
    if (_backgrounded) return;
    if (state.status == DriverTrackingStatus.unavailable ||
        _subscriptionCancellation != null) {
      await recoverAfterConnectivity();
      return;
    }
    await _startSession();
  }

  Future<void> _startSession(
      {DriverAvailability? canonicalAvailability}) async {
    if (_backgrounded || _startInProgress || _subscription != null) return;

    final generation = ++_generation;
    _startInProgress = true;
    state = DriverTrackingState(
      status: DriverTrackingStatus.starting,
      latestConfirmedAt: _latestConfirmedAt,
    );
    try {
      final repository = ref.read(driverLocationRepositoryProvider);
      final availability =
          canonicalAvailability ?? await repository.fetchAvailability();
      if (!_isCurrent(generation)) return;
      if (availability == null || !availability.canShareLocation) {
        _setUnavailable(DriverLocationFailure.ineligible);
        return;
      }
      final trackingConfig =
          DriverGpsTrackingConfig.forAvailability(availability.state)!;

      final latest = await repository.fetchLatestLocation();
      if (!_isCurrent(generation)) return;
      _latestRecordedAt = latest?.recordedAt;
      _latestConfirmedAt = latest?.receivedAt;
      _latestAcceptedFix = latest == null
          ? null
          : DriverLocationFix(
              point: latest.point,
              recordedAt: latest.recordedAt,
              headingDegrees: latest.headingDegrees,
              speedMetersPerSecond: latest.speedMetersPerSecond,
            );
      _activeTripId = availability.state == DriverAvailabilityState.onTrip
          ? availability.activeTripId
          : null;
      _trackingConfig = trackingConfig;
      _nextSequence = (latest?.sequence ?? 0) + 1;
      state = DriverTrackingState(
        status: DriverTrackingStatus.sharing,
        nextSequence: _nextSequence,
        latestConfirmedAt: _latestConfirmedAt,
      );
      final subscription = ref
          .read(driverGpsStreamServiceProvider)
          .foregroundFixes(trackingConfig)
          .listen(
            (fix) => _handleFix(fix, generation),
            onError: (error, stackTrace) =>
                _handleStreamError(error, stackTrace, generation),
          );
      if (!_isCurrent(generation)) {
        await _containCleanup(
          'discarding a stale driver GPS stream',
          subscription.cancel,
        );
      } else {
        _subscription = subscription;
        _connectionGeneration =
            await ref.read(driverTrackingConnectionProvider).connect();
      }
    } on Object catch (error, stackTrace) {
      if (_isCurrent(generation)) {
        _setUnavailable(_failureFromError(
          error,
          stackTrace: stackTrace,
          operation: 'starting driver location sharing',
          fallback: DriverLocationFailure.networkFailure,
        ));
        await _cancelSubscription(generation);
        _connectionGeneration = null;
        _connectionFailurePending = false;
        await _disconnectSafely(
          ref.read(driverTrackingConnectionProvider),
          'disconnecting after driver tracking startup failed',
        );
      }
    } finally {
      if (_generation == generation) _startInProgress = false;
      _runPendingCanonicalSync();
    }
  }

  Future<void> stop() async {
    _trackingRequested = false;
    _configurationSyncPending = false;
    await _stopSession();
  }

  Future<void> _stopSession({
    DriverTrackingStatus status = DriverTrackingStatus.stopped,
  }) async {
    _generation++;
    _startInProgress = false;
    _activeTripId = null;
    _trackingConfig = null;
    _pendingPublish = null;
    _connectionGeneration = null;
    _connectionFailurePending = false;
    final subscription = _subscription;
    _subscription = null;
    final pendingCancellation = _subscriptionCancellation;
    final connection = ref.read(driverTrackingConnectionProvider);
    if (!_disposed) {
      state = DriverTrackingState(
        status: status,
        latestConfirmedAt: _latestConfirmedAt,
      );
    }
    if (subscription != null) {
      await _containCleanup(
        'stopping the driver GPS stream',
        subscription.cancel,
      );
    }
    await pendingCancellation;
    await _disconnectSafely(connection, 'stopping driver location sharing');
  }

  Future<void> stopForSignOut() => stop();

  Future<void> synchronizeCanonicalState() {
    if (!_trackingRequested || _backgrounded || _disposed) {
      return Future<void>.value();
    }

    if (_configurationSyncFuture case final sync?) {
      _configurationSyncRequested = true;
      return sync;
    }

    if (_recoveryInProgress || _startInProgress) {
      _configurationSyncPending = true;
      return Future<void>.value();
    }
    final sync = _synchronizeCanonicalStateLoop();
    _configurationSyncFuture = sync;
    return sync;
  }

  Future<void> _synchronizeCanonicalStateLoop() async {
    try {
      do {
        _configurationSyncRequested = false;
        await _synchronizeCanonicalStateOnce();
      } while (_configurationSyncRequested &&
          _trackingRequested &&
          !_backgrounded &&
          !_disposed);
    } finally {
      _configurationSyncFuture = null;
      if (_recoveryRequested) {
        _recoveryRequested = false;
        unawaited(recoverAfterConnectivity());
      }
    }
  }

  void _runPendingCanonicalSync() {
    if (!_configurationSyncPending) return;
    if (!_trackingRequested || _backgrounded || _disposed) {
      _configurationSyncPending = false;
      return;
    }
    if (_startInProgress || _recoveryInProgress) {
      return;
    }

    _configurationSyncPending = false;
    unawaited(synchronizeCanonicalState());
  }

  Future<void> _synchronizeCanonicalStateOnce() async {
    final generation = _generation;
    DriverAvailability? availability;
    try {
      availability =
          await ref.read(driverLocationRepositoryProvider).fetchAvailability();
    } on Object catch (error, stackTrace) {
      _reportUnexpected(
        'synchronizing driver availability',
        error,
        stackTrace,
      );
      return;
    }
    if (!_isCurrent(generation)) {
      return;
    }
    if (availability == null || !availability.canShareLocation) {
      await _stopForCanonicalState(generation);
      return;
    }
    if (_connectionFailurePending || _recoveryRequested) return;

    if (_subscription == null && _connectionGeneration == null) {
      await _startSession(canonicalAvailability: availability);
      return;
    }

    final trackingConfig =
        DriverGpsTrackingConfig.forAvailability(availability.state)!;
    final activeTripId = availability.state == DriverAvailabilityState.onTrip
        ? availability.activeTripId
        : null;
    if (trackingConfig == _trackingConfig &&
        activeTripId == _activeTripId &&
        _subscription != null) {
      return;
    }

    await _replaceGpsSubscription(trackingConfig, activeTripId);
  }

  Future<void> _stopForCanonicalState(int generation) async {
    if (!_isCurrent(generation)) return;
    if (_subscription == null &&
        _connectionGeneration == null &&
        state.status == DriverTrackingStatus.unavailable &&
        state.failure == DriverLocationFailure.ineligible) {
      return;
    }

    final stopGeneration = ++_generation;
    _activeTripId = null;
    _trackingConfig = null;
    _pendingPublish = null;
    _connectionGeneration = null;
    _connectionFailurePending = false;
    _recoveryRequested = false;
    final subscription = _subscription;
    _subscription = null;
    final pendingCancellation = _subscriptionCancellation;
    final connection = ref.read(driverTrackingConnectionProvider);
    _setUnavailable(DriverLocationFailure.ineligible);
    if (subscription != null) {
      await _containCleanup(
        'stopping GPS for canonical driver state',
        subscription.cancel,
      );
    }
    await pendingCancellation;
    if (_isCurrent(stopGeneration)) {
      await _disconnectSafely(
        connection,
        'disconnecting for canonical driver state',
      );
    }
  }

  Future<void> _replaceGpsSubscription(
    DriverGpsTrackingConfig trackingConfig,
    String? activeTripId,
  ) async {
    final generation = ++_generation;
    _pendingPublish = null;
    final subscription = _subscription;
    _subscription = null;
    try {
      await subscription?.cancel();
    } on Object catch (error, stackTrace) {
      if (_isCurrent(generation)) {
        _trackingConfig = null;
        _activeTripId = null;
        _setUnavailable(_failureFromError(
          error,
          stackTrace: stackTrace,
          operation: 'stopping the driver GPS stream',
          fallback: DriverLocationFailure.gpsUnavailable,
        ));
      }
      return;
    }
    if (!_isCurrent(generation) || !_trackingRequested || _backgrounded) return;

    _trackingConfig = trackingConfig;
    _activeTripId = activeTripId;
    late final StreamSubscription<DriverLocationFix> replacement;
    try {
      replacement = ref
          .read(driverGpsStreamServiceProvider)
          .foregroundFixes(trackingConfig)
          .listen(
            (fix) => _handleFix(fix, generation),
            onError: (error, stackTrace) =>
                _handleStreamError(error, stackTrace, generation),
          );
    } on Object catch (error, stackTrace) {
      if (_isCurrent(generation)) {
        _trackingConfig = null;
        _activeTripId = null;
        _setUnavailable(_failureFromError(
          error,
          stackTrace: stackTrace,
          operation: 'restarting the driver GPS stream',
          fallback: DriverLocationFailure.gpsUnavailable,
        ));
      }
      return;
    }
    if (!_isCurrent(generation)) {
      await _containCleanup(
        'discarding a stale replacement GPS stream',
        replacement.cancel,
      );
    } else {
      _subscription = replacement;
      if (state.status != DriverTrackingStatus.sharing) {
        state = DriverTrackingState(
          status: DriverTrackingStatus.sharing,
          nextSequence: _nextSequence,
          latestConfirmedAt: _latestConfirmedAt,
        );
      }
    }
  }

  Future<void> recoverAfterConnectivity() async {
    if (_configurationSyncFuture != null) {
      _recoveryRequested = true;
      return;
    }
    if (!_trackingRequested ||
        _backgrounded ||
        _disposed ||
        _recoveryInProgress ||
        _startInProgress) {
      return;
    }
    _recoveryInProgress = true;
    try {
      await _stopSession();
      if (_trackingRequested && !_backgrounded && !_disposed) {
        await _startSession();
      }
    } finally {
      _recoveryInProgress = false;
      _runPendingCanonicalSync();
    }
  }

  void _handleLifecycleChange(DriverTrackingLifecycleState lifecycleState) {
    _lifecycleQueue = _lifecycleQueue.then((_) async {
      if (lifecycleState == DriverTrackingLifecycleState.background) {
        _backgrounded = true;
        _configurationSyncPending = false;
        if (_trackingRequested) {
          await _stopSession(status: DriverTrackingStatus.paused);
        }
      } else if (_trackingRequested) {
        _backgrounded = false;
        await _startSession();
      } else {
        _backgrounded = false;
      }
    }).onError((Object error, StackTrace stackTrace) {
      _reportUnexpected(
        'handling the driver tracking lifecycle',
        error,
        stackTrace,
      );
    });
  }

  void _handleConnectionEvent(DriverTrackingConnectionEvent event) {
    if (event.generation != _connectionGeneration) return;
    final status = event.status;
    if (status == DriverTrackingConnectionStatus.subscribed) {
      if (_connectionFailurePending) {
        _connectionFailurePending = false;
        unawaited(recoverAfterConnectivity());
      }
      return;
    }
    if (status == DriverTrackingConnectionStatus.channelError ||
        status == DriverTrackingConnectionStatus.closed ||
        status == DriverTrackingConnectionStatus.timedOut) {
      _connectionFailurePending = true;
      _setUnavailable(DriverLocationFailure.networkFailure);
      unawaited(_cancelSubscription(_generation));
    }
  }

  void _handleFix(DriverLocationFix fix, int generation) {
    final trackingConfig = _trackingConfig;
    if (!_isCurrent(generation) ||
        state.status != DriverTrackingStatus.sharing ||
        trackingConfig == null) {
      return;
    }
    if (_validationPolicy.rejectionFor(
          candidate: fix,
          previous: _latestAcceptedFix,
          now: ref.read(driverTrackingClockProvider)(),
        ) !=
        null) {
      return;
    }
    if ((_latestRecordedAt != null &&
            fix.recordedAt.difference(_latestRecordedAt!) <
                trackingConfig.minimumUpdateInterval) ||
        !trackingConfig.isMeaningfulUpdate(fix, _latestAcceptedFix)) {
      return;
    }

    _latestRecordedAt = fix.recordedAt;
    _latestAcceptedFix = fix;
    _pendingPublish = (fix: fix, generation: generation);
    if (_publishDrainScheduled) return;

    _publishDrainScheduled = true;
    _publishQueue = _publishQueue.then((_) => _drainPublishes());
  }

  Future<void> _drainPublishes() async {
    try {
      while (true) {
        final pending = _pendingPublish;
        if (pending == null) break;
        _pendingPublish = null;
        final generation = pending.generation;
        if (!_isCurrent(generation) ||
            state.status != DriverTrackingStatus.sharing) {
          continue;
        }

        final fix = pending.fix;
        final sequence = _nextSequence++;
        try {
          final saved =
              await ref.read(driverLocationRepositoryProvider).publish(
                    DriverLocationSample(
                      point: fix.point,
                      sequence: sequence,
                      recordedAt: fix.recordedAt,
                      tripId: _activeTripId,
                      headingDegrees: fix.headingDegrees,
                      speedMetersPerSecond: fix.speedMetersPerSecond,
                    ),
                  );
          if (_isCurrent(generation)) {
            _latestConfirmedAt = saved.receivedAt;
            state = DriverTrackingState(
              status: DriverTrackingStatus.sharing,
              nextSequence: _nextSequence,
              latestConfirmedAt: _latestConfirmedAt,
            );
          }
        } on Object catch (error, stackTrace) {
          if (_isCurrent(generation)) {
            final failure = _failureFromError(
              error,
              stackTrace: stackTrace,
              operation: 'publishing driver location',
              fallback: DriverLocationFailure.networkFailure,
            );
            _setUnavailable(failure);
            await _cancelSubscription(generation);
            if (failure == DriverLocationFailure.staleSequence) {
              await recoverAfterConnectivity();
            }
          }
        }
      }
    } finally {
      _publishDrainScheduled = false;
    }
  }

  void _handleStreamError(Object error, StackTrace stackTrace, int generation) {
    if (!_isCurrent(generation)) return;
    _setUnavailable(_failureFromError(
      error,
      stackTrace: stackTrace,
      operation: 'reading the driver GPS stream',
      fallback: DriverLocationFailure.gpsUnavailable,
    ));
    unawaited(_cancelSubscription(generation));
  }

  Future<void> _cancelSubscription(int generation) async {
    if (!_isCurrent(generation)) {
      return;
    }
    final subscription = _subscription;
    _subscription = null;
    if (subscription == null) {
      await _subscriptionCancellation;
      return;
    }
    final cancellation = _containCleanup(
      'cancelling the driver GPS stream',
      subscription.cancel,
    );
    _subscriptionCancellation = cancellation;
    try {
      await cancellation;
    } finally {
      if (identical(_subscriptionCancellation, cancellation)) {
        _subscriptionCancellation = null;
      }
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _setUnavailable(DriverLocationFailure failure) {
    state = DriverTrackingState(
      status: DriverTrackingStatus.unavailable,
      failure: failure,
      latestConfirmedAt: _latestConfirmedAt,
    );
  }

  DriverLocationFailure _failureFromError(
    Object error, {
    required StackTrace stackTrace,
    required String operation,
    required DriverLocationFailure fallback,
  }) {
    if (error case DriverLocationException(:final failure)) return failure;
    _reportUnexpected(operation, error, stackTrace);
    return fallback;
  }

  void _reportUnexpected(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    if (error is DriverLocationException) return;
    _errorReporter.report(
      operation: operation,
      error: error,
      stackTrace: stackTrace,
    );
  }

  Future<void> _disconnectSafely(
    DriverTrackingConnection connection,
    String operation,
  ) {
    return _containCleanup(operation, connection.disconnect);
  }

  Future<void> _containCleanup(
    String operation,
    Future<void> Function() cleanup,
  ) async {
    try {
      await cleanup();
    } on Object catch (error, stackTrace) {
      _reportUnexpected(operation, error, stackTrace);
    }
  }
}
