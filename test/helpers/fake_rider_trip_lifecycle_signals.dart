import 'dart:async';

import 'package:ridex/core/services/rider_trip_lifecycle_signals.dart';

/// Deterministic lifecycle and connection input for C05 controller tests.
///
/// [resume] emits only when moving from the simulated background to resumed.
/// Late emit methods deliberately invoke callbacks captured by canceled
/// subscriptions to exercise controller generation fences.
final class FakeRiderTripLifecycleSignals
    implements
        RiderTripAppLifecycleSignalSource,
        RiderTripConnectionSignalSource {
  final _FakeSignalStream<void> _resumeEvents = _FakeSignalStream<void>();
  final _FakeSignalStream<RiderTripConnectionSignal> _connectionEvents =
      _FakeSignalStream<RiderTripConnectionSignal>();
  bool _isResumed = true;

  @override
  Stream<void> get resumed => _resumeEvents;

  @override
  Stream<RiderTripConnectionSignal> get events => _connectionEvents;

  int get activeResumeListeners => _resumeEvents.activeListeners;

  int get activeConnectionListeners => _connectionEvents.activeListeners;

  void background() => _isResumed = false;

  void resume() {
    if (_isResumed) return;
    _isResumed = true;
    _resumeEvents.emit(null);
  }

  /// Emits a raw resume signal to model a duplicate or faulty upstream source.
  void emitDuplicateResumeSignal() => _resumeEvents.emit(null);

  void connectivityAvailable() =>
      _connectionEvents.emit(const RiderTripConnectivityAvailable());

  void connecting(int generation) => _connectionEvents.emit(
        RiderTripConnectionStatusChanged(
          status: RiderTripConnectionStatus.connecting,
          generation: generation,
        ),
      );

  void interrupted(int generation) => _connectionEvents.emit(
        RiderTripConnectionStatusChanged(
          status: RiderTripConnectionStatus.interrupted,
          generation: generation,
        ),
      );

  void confirmedRestoration(int generation) => _connectionEvents.emit(
        RiderTripConnectionStatusChanged(
          status: RiderTripConnectionStatus.restored,
          generation: generation,
        ),
      );

  void emitLateResumeSignal() => _resumeEvents.emitLateToCanceled(null);

  void emitLateConnectionSignal(RiderTripConnectionSignal signal) =>
      _connectionEvents.emitLateToCanceled(signal);

  @override
  Future<void> dispose() async {
    await Future.wait([
      _resumeEvents.close(),
      _connectionEvents.close(),
    ]);
  }
}

final class _FakeSignalStream<T> extends Stream<T> {
  final List<_FakeSignalSubscription<T>> _subscriptions = [];
  bool _closed = false;

  int get activeListeners =>
      _subscriptions.where((subscription) => !subscription.isCancelled).length;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = _FakeSignalSubscription<T>(
      onDataCallback: onData,
      onErrorCallback: onError,
      onDoneCallback: onDone,
    );
    _subscriptions.add(subscription);
    if (_closed) subscription.finish();
    return subscription;
  }

  void emit(T event) {
    for (final subscription in List<_FakeSignalSubscription<T>>.of(
      _subscriptions,
    )) {
      subscription.emit(event);
    }
  }

  void emitLateToCanceled(T event) {
    for (final subscription in _subscriptions) {
      if (subscription.isCancelled) {
        subscription.emitIgnoringCancellation(event);
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final subscription in _subscriptions) {
      subscription.finish();
    }
  }
}

final class _FakeSignalSubscription<T> implements StreamSubscription<T> {
  _FakeSignalSubscription({
    required this.onDataCallback,
    required this.onErrorCallback,
    required this.onDoneCallback,
  });

  void Function(T event)? onDataCallback;
  Function? onErrorCallback;
  void Function()? onDoneCallback;
  bool _cancelled = false;
  bool _paused = false;

  bool get isCancelled => _cancelled;

  void emit(T event) {
    if (!_cancelled && !_paused) onDataCallback?.call(event);
  }

  void emitIgnoringCancellation(T event) => onDataCallback?.call(event);

  void finish() {
    if (!_cancelled) onDoneCallback?.call();
    _cancelled = true;
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
  }

  @override
  void onData(void Function(T data)? handleData) => onDataCallback = handleData;

  @override
  void onDone(void Function()? handleDone) => onDoneCallback = handleDone;

  @override
  void onError(Function? handleError) => onErrorCallback = handleError;

  @override
  void pause([Future<void>? resumeSignal]) {
    _paused = true;
    resumeSignal?.whenComplete(resume);
  }

  @override
  void resume() => _paused = false;

  @override
  bool get isPaused => _paused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => Completer<E>().future;
}
