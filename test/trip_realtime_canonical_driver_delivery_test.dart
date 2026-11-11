import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/trip_realtime.dart';
import 'package:ridex/core/services/trips/trip_realtime_source.dart';
import 'package:ridex/features/driver_flow/data/trip_realtime_canonical_driver_delivery.dart';
import 'package:ridex/features/driver_flow/domain/canonical_driver_delivery.dart';

const _driver = 'b1000000-0000-4000-8000-000000000001';
const _otherDriver = 'b2000000-0000-4000-8000-000000000002';
const _rider = 'a1000000-0000-4000-8000-000000000001';
const _trip = 'c1000000-0000-4000-8000-000000000001';

void main() {
  test('known canonical assigned Trip becomes a B08 advisory hint', () async {
    final source = _FakeTripRealtimeSource(userId: _driver);
    final delivery = TripRealtimeCanonicalDriverDelivery(
      source: source,
      tripId: _trip,
      assignedDriverId: _driver,
    );
    final seen = _SignalLog();
    final subscription = delivery.signals.listen(seen.add, onError: seen.addError);
    addTearDown(subscription.cancel);

    await seen.waitFor((signal) => signal is CanonicalDriverTripHint);
    final hint = seen.signals.whereType<CanonicalDriverTripHint>().single;
    expect(hint.tripId, _trip);
    expect(source.readCount, 1);
    expect(source.watchCount, 1);

    await subscription.cancel();
    expect(source.activeSubscriptions, 0);
  });

  test('a different authenticated Driver receives no Trip identifier',
      () async {
    final source = _FakeTripRealtimeSource(userId: _otherDriver);
    final delivery = TripRealtimeCanonicalDriverDelivery(
      source: source,
      tripId: _trip,
      assignedDriverId: _driver,
    );
    final signals = await delivery.signals.toList();

    expect(signals, hasLength(1));
    expect(signals.single, isA<CanonicalDriverConnectionHint>());
    expect((signals.single as CanonicalDriverConnectionHint).connected, isFalse);
    expect(source.watchCount, 0);
    expect(signals.whereType<CanonicalDriverTripHint>(), isEmpty);
  });

  test('D02 session replacement closes the B08 delivery scope', () async {
    final source = _FakeTripRealtimeSource(userId: _driver);
    final delivery = TripRealtimeCanonicalDriverDelivery(
      source: source,
      tripId: _trip,
      assignedDriverId: _driver,
    );
    final seen = _SignalLog();
    final subscription = delivery.signals.listen(seen.add, onError: seen.addError);
    addTearDown(subscription.cancel);
    await seen.waitFor((signal) => signal is CanonicalDriverTripHint);

    source.sessionIdentity = Object();
    source.events.add(const TripRealtimeSessionChangedSignal());
    await seen.waitFor((signal) =>
        signal is CanonicalDriverConnectionHint && !signal.connected);
    // The disconnect hint can precede asynchronous stream cancellation.
    await source.cancellationCompleted.future.timeout(const Duration(seconds: 2));
    expect(source.activeSubscriptions, 0);
  });
}

final class _SignalLog {
  final signals = <CanonicalDriverDeliverySignal>[];
  final _waiters = <bool Function(CanonicalDriverDeliverySignal),
      Completer<CanonicalDriverDeliverySignal>>{};

  void add(CanonicalDriverDeliverySignal signal) {
    signals.add(signal);
    for (final entry in _waiters.entries.toList()) {
      if (entry.key(signal) && !entry.value.isCompleted) {
        entry.value.complete(signal);
        _waiters.remove(entry.key);
      }
    }
  }

  void addError(Object error, StackTrace stackTrace) {
    fail('Unexpected signal error: $error');
  }

  Future<CanonicalDriverDeliverySignal> waitFor(
    bool Function(CanonicalDriverDeliverySignal) predicate,
  ) {
    for (final signal in signals) {
      if (predicate(signal)) return Future.value(signal);
    }
    final completer = Completer<CanonicalDriverDeliverySignal>();
    _waiters[predicate] = completer;
    return completer.future;
  }
}

final class _FakeTripRealtimeSource implements TripRealtimeSource {
  _FakeTripRealtimeSource({required this.userId});

  String? userId;
  Object? sessionIdentity = Object();
  final events = StreamController<TripRealtimeSourceSignal>.broadcast();
  int readCount = 0;
  int watchCount = 0;
  int activeSubscriptions = 0;
  final cancellationCompleted = Completer<void>();

  @override
  String? get authenticatedUserId => userId;

  @override
  Object? get authenticatedSessionIdentity => sessionIdentity;

  @override
  Stream<TripRealtimeSourceSignal> watchTrip(String tripId) {
    watchCount++;
    return Stream<TripRealtimeSourceSignal>.multi((controller) {
      activeSubscriptions++;
      final subscription = events.stream.listen(controller.add);
      controller.onCancel = () async {
        activeSubscriptions--;
        await subscription.cancel();
        if (!cancellationCompleted.isCompleted) cancellationCompleted.complete();
      };
    });
  }

  @override
  Future<TripRealtimeTrip?> readCanonicalTrip(String tripId) async {
    readCount++;
    return TripRealtimeTrip(
      tripId: _trip,
      riderId: _rider,
      driverId: _driver,
      status: DriverTripLifecycleStatus.accepted,
      version: 1,
    );
  }
}
