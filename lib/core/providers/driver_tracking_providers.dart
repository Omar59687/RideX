import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:ridex/core/errors/driver_location_exception.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/services/driver_location/driver_gps_stream_service.dart';
import 'package:ridex/core/services/driver_location/driver_tracking_connection.dart';
import 'package:ridex/core/services/driver_location/geolocator_driver_gps_stream_service.dart';
import 'package:ridex/core/services/driver_location/supabase_driver_tracking_connection.dart';
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
  (ref) => GeolocatorDriverGpsStreamService(),
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
    final connection = SupabaseDriverTrackingConnection(client);
    ref.onDispose(connection.dispose);
    return connection;
  },
);

final driverTrackingControllerProvider =
    NotifierProvider.autoDispose<DriverTrackingController, DriverTrackingState>(
  DriverTrackingController.new,
);

class DriverTrackingController
    extends AutoDisposeNotifier<DriverTrackingState> {
  StreamSubscription<DriverLocationFix>? _subscription;
  StreamSubscription<DriverTrackingLifecycleState>? _lifecycleSubscription;
  StreamSubscription<DriverTrackingConnectionEvent>? _connectionSubscription;
  Future<void> _publishQueue = Future<void>.value();
  Future<void> _lifecycleQueue = Future<void>.value();
  ({DriverLocationFix fix, int generation})? _pendingPublish;
  DriverLocationFix? _latestAcceptedFix;
  DateTime? _latestRecordedAt;
  DateTime? _latestConfirmedAt;
  String? _activeTripId;
  int _nextSequence = 1;
  bool _startInProgress = false;
  bool _recoveryInProgress = false;
  bool _trackingRequested = false;
  bool _backgrounded = false;
  bool _connectionFailurePending = false;
  bool _publishDrainScheduled = false;
  int? _connectionGeneration;
  int _generation = 0;
  bool _disposed = false;

  @override
  DriverTrackingState build() {
    final connection = ref.read(driverTrackingConnectionProvider);
    _lifecycleSubscription = ref
        .read(driverTrackingLifecycleProvider)
        .changes
        .listen(_handleLifecycleChange);
    _connectionSubscription = connection.events.listen(_handleConnectionEvent);
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _subscription?.cancel();
      _subscription = null;
      _lifecycleSubscription?.cancel();
      _lifecycleSubscription = null;
      _connectionSubscription?.cancel();
      _connectionSubscription = null;
      _connectionGeneration = null;
      _connectionFailurePending = false;
      unawaited(connection.dispose());
    });
    return const DriverTrackingState.initial();
  }

  Future<void> start() async {
    _trackingRequested = true;
    if (_backgrounded) return;
    await _startSession();
  }

  Future<void> _startSession() async {
    if (_backgrounded || _startInProgress || _subscription != null) return;

    final generation = ++_generation;
    _startInProgress = true;
    state = DriverTrackingState(
      status: DriverTrackingStatus.starting,
      latestConfirmedAt: _latestConfirmedAt,
    );
    try {
      final repository = ref.read(driverLocationRepositoryProvider);
      final availability = await repository.fetchAvailability();
      if (!_isCurrent(generation)) return;
      if (availability == null || !availability.canShareLocation) {
        _setUnavailable(DriverLocationFailure.ineligible);
        return;
      }

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
      _nextSequence = (latest?.sequence ?? 0) + 1;
      state = DriverTrackingState(
        status: DriverTrackingStatus.sharing,
        nextSequence: _nextSequence,
        latestConfirmedAt: _latestConfirmedAt,
      );
      final subscription =
          ref.read(driverGpsStreamServiceProvider).foregroundFixes().listen(
                (fix) => _handleFix(fix, generation),
                onError: (error, stackTrace) =>
                    _handleStreamError(error, stackTrace, generation),
              );
      if (!_isCurrent(generation)) {
        await subscription.cancel();
      } else {
        _subscription = subscription;
        _connectionGeneration =
            await ref.read(driverTrackingConnectionProvider).connect();
      }
    } catch (error) {
      if (_isCurrent(generation)) {
        _setUnavailable(_failureFromError(error));
        await _cancelSubscription(generation);
        _connectionGeneration = null;
        _connectionFailurePending = false;
        await ref.read(driverTrackingConnectionProvider).disconnect();
      }
    } finally {
      if (_generation == generation) _startInProgress = false;
    }
  }

  Future<void> stop() async {
    _trackingRequested = false;
    await _stopSession();
  }

  Future<void> _stopSession({
    DriverTrackingStatus status = DriverTrackingStatus.stopped,
  }) async {
    _generation++;
    _startInProgress = false;
    _activeTripId = null;
    _pendingPublish = null;
    _connectionGeneration = null;
    _connectionFailurePending = false;
    final subscription = _subscription;
    _subscription = null;
    final connection = ref.read(driverTrackingConnectionProvider);
    if (!_disposed) {
      state = DriverTrackingState(
        status: status,
        latestConfirmedAt: _latestConfirmedAt,
      );
    }
    await subscription?.cancel();
    await connection.disconnect();
  }

  Future<void> stopForSignOut() => stop();

  Future<void> recoverAfterConnectivity() async {
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
    }
  }

  void _handleLifecycleChange(DriverTrackingLifecycleState lifecycleState) {
    _lifecycleQueue = _lifecycleQueue.then((_) async {
      if (lifecycleState == DriverTrackingLifecycleState.background) {
        _backgrounded = true;
        if (_trackingRequested) {
          await _stopSession(status: DriverTrackingStatus.paused);
        }
      } else if (_trackingRequested) {
        _backgrounded = false;
        await _startSession();
      } else {
        _backgrounded = false;
      }
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
    }
  }

  void _handleFix(DriverLocationFix fix, int generation) {
    if (!_isCurrent(generation) ||
        state.status != DriverTrackingStatus.sharing ||
        fix.point.accuracyMeters == null ||
        (_latestRecordedAt != null &&
            !fix.recordedAt.isAfter(_latestRecordedAt!)) ||
        _hasSameLocationContent(fix, _latestAcceptedFix)) {
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
        } catch (error) {
          if (_isCurrent(generation)) {
            final failure = _failureFromError(error);
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

  bool _hasSameLocationContent(
    DriverLocationFix fix,
    DriverLocationFix? previous,
  ) {
    if (previous == null) return false;
    return fix.point == previous.point &&
        fix.headingDegrees == previous.headingDegrees &&
        fix.speedMetersPerSecond == previous.speedMetersPerSecond;
  }

  void _handleStreamError(Object error, StackTrace stackTrace, int generation) {
    if (!_isCurrent(generation)) return;
    _setUnavailable(_failureFromError(error));
    unawaited(_cancelSubscription(generation));
  }

  Future<void> _cancelSubscription(int generation) async {
    if (!_isCurrent(generation)) {
      return;
    }
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _setUnavailable(DriverLocationFailure failure) {
    state = DriverTrackingState(
      status: DriverTrackingStatus.unavailable,
      failure: failure,
      latestConfirmedAt: _latestConfirmedAt,
    );
  }

  DriverLocationFailure _failureFromError(Object error) =>
      error is DriverLocationException
          ? error.failure
          : DriverLocationFailure.unavailable;
}
