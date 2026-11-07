import 'dart:async';

import 'package:flutter/widgets.dart';

/// App-lifecycle input for canonical Rider Trip reconciliation.
///
/// Implementations emit [resumed] only when the app transitions from a
/// non-resumed state to `resumed`. Lifecycle signals request a canonical read;
/// they never establish Trip status.
abstract interface class RiderTripAppLifecycleSignalSource {
  Stream<void> get resumed;

  void dispose();
}

/// Flutter lifecycle adapter. It deliberately emits no initial signal: the
/// controller's startup read already handles initial reconciliation.
final class WidgetsRiderTripAppLifecycleSignalSource
    with WidgetsBindingObserver
    implements RiderTripAppLifecycleSignalSource {
  WidgetsRiderTripAppLifecycleSignalSource()
      : _lastState = WidgetsBinding.instance.lifecycleState {
    WidgetsBinding.instance.addObserver(this);
  }

  final StreamController<void> _resumed =
      StreamController<void>.broadcast(sync: true);
  AppLifecycleState? _lastState;
  bool _disposed = false;

  @override
  Stream<void> get resumed => _resumed.stream;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final enteredResumed = _lastState != null &&
        _lastState != AppLifecycleState.resumed &&
        state == AppLifecycleState.resumed;
    _lastState = state;
    if (enteredResumed && !_disposed) _resumed.add(null);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_resumed.close());
  }
}

/// No-op lifecycle input for deterministic callers that do not own a Flutter
/// binding. Production provider composition uses the Widgets binding adapter.
final class NoopRiderTripAppLifecycleSignalSource
    implements RiderTripAppLifecycleSignalSource {
  const NoopRiderTripAppLifecycleSignalSource();

  @override
  Stream<void> get resumed => const Stream<void>.empty();

  @override
  void dispose() {}
}

/// Status of the transport/subscription owner, not general network
/// connectivity. A [restored] signal is valid only after the owner has
/// confirmed its current subscription is active.
enum RiderTripConnectionStatus { connecting, interrupted, restored }

sealed class RiderTripConnectionSignal {
  const RiderTripConnectionSignal();
}

/// A connection-owner event. [generation] must increase for each new
/// transport/subscription attempt; status callbacks within that attempt share
/// its generation.
final class RiderTripConnectionStatusChanged extends RiderTripConnectionSignal {
  RiderTripConnectionStatusChanged({
    required this.status,
    required this.generation,
  }) {
    if (generation <= 0) {
      throw ArgumentError.value(
        generation,
        'generation',
        'Must be positive.',
      );
    }
  }

  final RiderTripConnectionStatus status;
  final int generation;
}

/// Connectivity is only a hint that a network may be reachable. It is
/// deliberately distinct from transport restoration and must not trigger a
/// canonical Trip read.
final class RiderTripConnectivityAvailable extends RiderTripConnectionSignal {
  const RiderTripConnectivityAvailable();
}

/// Read-only observation of the current Rider Trip transport.
///
/// The lifecycle controller listens to this source but does not create,
/// replace, or dispose the underlying transport. A production implementation
/// must be supplied by a trusted connection owner and emit [restored] only
/// after confirmed subscription readiness.
abstract interface class RiderTripConnectionSignalSource {
  Stream<RiderTripConnectionSignal> get events;
}

/// Keeps Slice 2 independent of any unverified production Rider transport.
final class NoopRiderTripConnectionSignalSource
    implements RiderTripConnectionSignalSource {
  const NoopRiderTripConnectionSignalSource();

  @override
  Stream<RiderTripConnectionSignal> get events =>
      const Stream<RiderTripConnectionSignal>.empty();
}
