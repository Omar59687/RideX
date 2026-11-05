import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import 'driver_availability_controller.dart';
import 'driver_flow_repository_provider.dart';

final driverOfferClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);
final driverIncomingOfferProvider =
    NotifierProvider<DriverIncomingOfferController, DriverIncomingOfferView>(
        DriverIncomingOfferController.new);

enum IncomingOfferStatus {
  loading,
  empty,
  offer,
  replaced,
  stale,
  expired,
  pending,
  unknown,
  unauthorized,
  unavailable
}

class DriverIncomingOfferView {
  const DriverIncomingOfferView(this.status,
      {this.offer, this.remainingSeconds = 0});
  final IncomingOfferStatus status;
  final DriverFlowOffer? offer;
  final int remainingSeconds;
}

class _OfferMemory {
  _OfferMemory(this.offer);
  final DriverFlowOffer offer;
  bool expired = false;
  bool stale = false;
  IncomingOfferStatus? uncertainty;
}

typedef _OfferLifetime = ({
  int epoch,
  DriverAvailabilityScope? scope,
  DriverFlowRepository repository
});

/// Presentation observations only; never executes repository commands or owns Trips.
class DriverIncomingOfferController extends Notifier<DriverIncomingOfferView> {
  int _epoch = 0;
  int _revision = -1;
  int _sequence = 0;
  bool _reading = false;
  bool _unauthorized = false;
  late _OfferLifetime _lifetime;
  late DateTime Function() _clock;
  DateTime? _lastNow;
  final _seen = <(String, int), _OfferMemory>{};
  final _highestVersions = <String, int>{};
  (String, int)? _currentKey;
  IncomingOfferStatus _base = IncomingOfferStatus.loading;

  @override
  DriverIncomingOfferView build() {
    ++_epoch;
    _revision = -1;
    _sequence = 0;
    _reading = false;
    _unauthorized = false;
    _seen.clear();
    _highestVersions.clear();
    _currentKey = null;
    _lastNow = null;
    // Capture the injected clock for this scope. Replacing a clock fixture alone
    // must not retire offer identity/version or uncertainty memory.
    _clock = ref.read(driverOfferClockProvider);
    final scope = ref.watch(driverAvailabilityScopeProvider);
    final repository = ref.watch(driverFlowRepositoryProvider);
    final lifetime =
        _lifetime = (epoch: _epoch, scope: scope, repository: repository);
    StreamSubscription<DriverFlowSnapshot>? subscription;
    ref.onDispose(() {
      ++_epoch;
      unawaited(subscription?.cancel());
    });
    _base = scope == null
        ? IncomingOfferStatus.unavailable
        : IncomingOfferStatus.loading;
    if (scope != null) {
      Future.microtask(() async {
        if (!_valid(lifetime)) return;
        try {
          subscription = repository
              .watch(scope.session)
              .listen((snapshot) => _observe(snapshot, lifetime),
                  onError: (Object error) {
            if (_valid(lifetime)) _publish(IncomingOfferStatus.unavailable);
          });
        } on Object {
          if (_valid(lifetime)) _publish(IncomingOfferStatus.unavailable);
        }
        if (_valid(lifetime)) await refresh();
      });
    }
    return DriverIncomingOfferView(_base);
  }

  bool _valid(_OfferLifetime lifetime) {
    if (lifetime.epoch != _epoch) return false;
    // Flush derived dependencies before validating the captured lifetime.
    final ignored = state;
    return lifetime.epoch == _epoch &&
        identical(lifetime.scope, _lifetime.scope) &&
        identical(lifetime.repository, _lifetime.repository) &&
        ignored.status != IncomingOfferStatus.unauthorized &&
        !_unauthorized;
  }

  Future<void> refresh() async {
    final lifetime = _lifetime;
    if (!_valid(lifetime) || lifetime.scope == null || _reading) return;
    _reading = true;
    final sequence = _sequence;
    try {
      final result = await lifetime.repository.read(lifetime.scope!.session);
      if (!_valid(lifetime) || sequence != _sequence) return;
      if (result.outcome == DriverFlowOutcome.observed &&
          result.snapshot != null) {
        _observe(result.snapshot!, lifetime, read: true);
      } else {
        _publish(result.outcome == DriverFlowOutcome.unauthorized
            ? IncomingOfferStatus.unauthorized
            : IncomingOfferStatus.unavailable);
      }
    } on Object {
      if (_valid(lifetime) && sequence == _sequence) {
        _publish(IncomingOfferStatus.unavailable);
      }
    } finally {
      if (_valid(lifetime)) _reading = false;
    }
  }

  void _observe(DriverFlowSnapshot snapshot, _OfferLifetime lifetime,
      {bool read = false}) {
    if (!_valid(lifetime)) return;
    if (!snapshot.session.sameSession(lifetime.scope!.session) ||
        snapshot.source != DriverFlowSource.simulated) {
      return;
    }
    if (snapshot.revision < _revision ||
        (!read && snapshot.revision == _revision)) {
      return;
    }
    _revision = snapshot.revision;
    ++_sequence;
    if (snapshot.phase == DriverFlowPhase.unauthorized) {
      _publish(IncomingOfferStatus.unauthorized);
      return;
    }
    final incoming = snapshot.offer;
    var status = switch (snapshot.phase) {
      DriverFlowPhase.loading => IncomingOfferStatus.loading,
      DriverFlowPhase.pending => IncomingOfferStatus.pending,
      DriverFlowPhase.unknown => IncomingOfferStatus.unknown,
      DriverFlowPhase.stale ||
      DriverFlowPhase.completionBlocked =>
        IncomingOfferStatus.stale,
      DriverFlowPhase.unavailable => IncomingOfferStatus.unavailable,
      _ => incoming == null
          ? IncomingOfferStatus.empty
          : IncomingOfferStatus.offer,
    };
    if (incoming != null) {
      final highest = _highestVersions[incoming.id];
      if (highest != null && incoming.version < highest) {
        // Event revisions order observations, not versions of an offer entity.
        // Keep the current payload and its expiry/uncertainty memory intact.
        _publish(IncomingOfferStatus.stale);
        return;
      }
      _highestVersions[incoming.id] = incoming.version;
      final key = (incoming.id, incoming.version);
      final previousKey = _currentKey;
      final memory = _seen.putIfAbsent(key, () => _OfferMemory(incoming));
      if (!_equivalent(memory.offer, incoming)) memory.stale = true;
      if (previousKey != null && previousKey != key) {
        _seen[previousKey]!.stale = true;
        if (status == IncomingOfferStatus.offer) {
          status = IncomingOfferStatus.replaced;
        }
      }
      _currentKey = key;
    } else if (status == IncomingOfferStatus.empty) {
      if (_currentKey != null) _seen[_currentKey]!.stale = true;
      _currentKey = null;
    }
    final current = _seen[_currentKey];
    if (current != null) {
      if (status == IncomingOfferStatus.stale) current.stale = true;
      if (status == IncomingOfferStatus.unknown ||
          status == IncomingOfferStatus.pending) {
        if (current.uncertainty != IncomingOfferStatus.unknown) {
          current.uncertainty = status;
        }
      }
    }
    _publish(status);
  }

  /// Timer and resume both derive remaining time from the injected absolute clock.
  void updateTime() {
    final lifetime = _lifetime;
    if (_valid(lifetime)) _publish(_base);
  }

  /// Pure render projection: mounting must not display an expired cached view
  /// while waiting for a timer. No provider state or expiry latch is mutated.
  DriverIncomingOfferView viewAtCurrentTime(DriverIncomingOfferView view) {
    final offer = view.offer;
    if (offer == null) return view;
    final now = _clock().toUtc();
    final effectiveNow =
        _lastNow != null && now.isBefore(_lastNow!) ? _lastNow! : now;
    final micros = offer.expiresAt.difference(effectiveNow).inMicroseconds;
    final expired = view.status == IncomingOfferStatus.expired || micros <= 0;
    var status = view.status;
    if (expired && status != IncomingOfferStatus.stale) {
      status = status == IncomingOfferStatus.pending ||
              status == IncomingOfferStatus.unknown
          ? IncomingOfferStatus.unknown
          : IncomingOfferStatus.expired;
    }
    return DriverIncomingOfferView(status,
        offer: offer,
        remainingSeconds: expired ? 0 : (micros + 999999) ~/ 1000000);
  }

  void _publish(IncomingOfferStatus status) {
    _base = status;
    if (status == IncomingOfferStatus.unauthorized) {
      _unauthorized = true;
      state = const DriverIncomingOfferView(IncomingOfferStatus.unauthorized);
      return;
    }
    final now = _clock().toUtc();
    if (_lastNow == null || now.isAfter(_lastNow!)) _lastNow = now;
    final memory = _seen[_currentKey];
    var seconds = 0;
    if (memory != null) {
      if (memory.offer.isExpiredAt(_lastNow!)) memory.expired = true;
      final micros =
          memory.offer.expiresAt.difference(_lastNow!).inMicroseconds;
      seconds = micros <= 0 ? 0 : (micros + 999999) ~/ 1000000;
      if (memory.stale) {
        status = IncomingOfferStatus.stale;
      } else if (memory.uncertainty != null) {
        status =
            memory.expired ? IncomingOfferStatus.unknown : memory.uncertainty!;
      } else if (memory.expired) {
        status = IncomingOfferStatus.expired;
      }
    }
    state = DriverIncomingOfferView(status,
        offer: memory?.offer, remainingSeconds: seconds);
  }

  bool _equivalent(DriverFlowOffer a, DriverFlowOffer b) {
    final x = a.journey, y = b.journey;
    return a.id == b.id &&
        a.version == b.version &&
        a.bookingId == b.bookingId &&
        a.quoteId == b.quoteId &&
        a.expiresAt == b.expiresAt &&
        x.pickup == y.pickup &&
        x.destination == y.destination &&
        x.vehicleId == y.vehicleId &&
        x.vehicleLabel == y.vehicleLabel &&
        x.lockedFareFils == y.lockedFareFils &&
        x.paymentMethod == y.paymentMethod &&
        x.distanceMeters == y.distanceMeters &&
        x.durationSeconds == y.durationSeconds &&
        x.stops.length == y.stops.length &&
        List.generate(x.stops.length, (i) => x.stops[i] == y.stops[i])
            .every((v) => v);
  }
}
