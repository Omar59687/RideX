import 'dart:async';
import 'dart:math';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import 'driver_availability_controller.dart';
import 'driver_flow_repository_provider.dart';

final driverOfferClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// Deliberate test/demo override only. Never enabled by application composition.
final driverOfferSimulationEnabledProvider = Provider<bool>((ref) => false);

/// Returns cancellation for a one-shot response deadline; tests inject a scheduler.
typedef DriverOfferDecisionScheduler = void Function() Function(
    Duration duration, void Function() callback);
final driverOfferDecisionSchedulerProvider =
    Provider<DriverOfferDecisionScheduler>((ref) => (duration, callback) {
          final timer = Timer(duration, callback);
          return timer.cancel;
        });

enum DriverOfferDecisionStatus {
  idle,
  pendingAccept,
  pendingDecline,
  simulatedAccepted,
  simulatedDeclined,
  rejected,
  stale,
  expired,
  unknown,
  unauthorized
}

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
      {this.offer,
      this.remainingSeconds = 0,
      this.decisionStatus = DriverOfferDecisionStatus.idle,
      this.command,
      this.canDecide = false});
  final IncomingOfferStatus status;
  final DriverFlowOffer? offer;
  final int remainingSeconds;
  final DriverOfferDecisionStatus decisionStatus;
  final DriverFlowDecideOffer? command;
  final bool canDecide;
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

final class _DecisionAttempt {
  _DecisionAttempt(
      this.command, this.offer, this.lifetime, this.revision, this.operation);
  final DriverFlowDecideOffer command;
  final DriverFlowOffer offer;
  final _OfferLifetime lifetime;
  final int revision;
  final int operation;
  bool finished = false;
  bool dispatched = false;
  void Function()? cancel;
  final retirement = Completer<DriverFlowResult>();
  void retire() {
    cancel?.call();
    if (!retirement.isCompleted) {
      retirement
          .complete(const DriverFlowResult(DriverFlowOutcome.unauthorized));
    }
  }
}

/// One owner for offer observations and explicitly enabled simulated decisions.
/// Never owns canonical Trip state or financial authority.
class DriverIncomingOfferController extends Notifier<DriverIncomingOfferView> {
  int _epoch = 0;
  int _operation = 0;
  final String _nonce =
      '${Random.secure().nextInt(1 << 32)}-${Random.secure().nextInt(1 << 32)}';
  _DecisionAttempt? _attempt;
  DriverOfferDecisionStatus _decision = DriverOfferDecisionStatus.idle;
  DriverFlowSnapshot? _latestSnapshot;
  bool _simulatedAssignment = false;
  final _retiredDecisions = <(String, int)>{};
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
    _attempt?.retire();
    _attempt = null;
    _decision = DriverOfferDecisionStatus.idle;
    _latestSnapshot = null;
    _simulatedAssignment = false;
    _retiredDecisions.clear();
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
      _attempt?.retire();
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
      if (_valid(lifetime)) {
        _reading = false;
        _publish(_base);
      }
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
    final attempt = _attempt;
    if (attempt != null && !attempt.finished && attempt.dispatched) {
      if ((snapshot.trip != null &&
              (attempt.command.decision == DriverFlowOfferDecision.decline ||
                  snapshot.trip!.status != DriverTripLifecycleStatus.accepted ||
                  !_sameJourney(
                      snapshot.trip!.journey, attempt.offer.journey))) ||
          snapshot.phase == DriverFlowPhase.unknown ||
          snapshot.phase == DriverFlowPhase.stale ||
          snapshot.phase == DriverFlowPhase.completionBlocked ||
          snapshot.phase == DriverFlowPhase.unavailable ||
          (snapshot.offer != null &&
              !_equivalent(attempt.offer, snapshot.offer!)) ||
          (snapshot.offer == null && snapshot.phase != DriverFlowPhase.ready)) {
        _decision = DriverOfferDecisionStatus.unknown;
      }
    }
    _latestSnapshot = snapshot;
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
      if (_attempt?.finished == true &&
          _decision != DriverOfferDecisionStatus.unknown &&
          !_simulatedAssignment &&
          !_retiredDecisions.contains(key)) {
        _attempt = null;
        _decision = DriverOfferDecisionStatus.idle;
      }
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
        decisionStatus: expired && _pendingDecision && _attempt!.dispatched
            ? DriverOfferDecisionStatus.unknown
            : view.decisionStatus,
        command: view.command,
        canDecide: view.canDecide && !expired,
        remainingSeconds: expired ? 0 : (micros + 999999) ~/ 1000000);
  }

  void _publish(IncomingOfferStatus status) {
    _base = status;
    if (status == IncomingOfferStatus.unavailable &&
        _pendingDecision &&
        _attempt!.dispatched) {
      _decision = DriverOfferDecisionStatus.unknown;
    }
    if (status == IncomingOfferStatus.unauthorized) {
      _unauthorized = true;
      _decision = DriverOfferDecisionStatus.unauthorized;
      _attempt?.retire();
      state = const DriverIncomingOfferView(IncomingOfferStatus.unauthorized,
          decisionStatus: DriverOfferDecisionStatus.unauthorized);
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
    if (_pendingDecision &&
        _attempt!.dispatched &&
        _attempt!.offer.isExpiredAt(_lastNow!)) {
      _decision = DriverOfferDecisionStatus.unknown;
    }
    final canDecide = ref.read(driverOfferSimulationEnabledProvider) &&
        !_reading &&
        _decision == DriverOfferDecisionStatus.idle &&
        !_simulatedAssignment &&
        _latestSnapshot?.trip == null &&
        (status == IncomingOfferStatus.offer ||
            status == IncomingOfferStatus.replaced) &&
        seconds > 0 &&
        memory != null &&
        !_retiredDecisions.contains((memory.offer.id, memory.offer.version));
    final displayOffer = memory?.offer ??
        ((_pendingDecision || _decision == DriverOfferDecisionStatus.unknown)
            ? _attempt?.offer
            : null);
    if (memory == null && displayOffer != null) {
      final micros =
          displayOffer.expiresAt.difference(_lastNow!).inMicroseconds;
      seconds = micros <= 0 ? 0 : (micros + 999999) ~/ 1000000;
    }
    state = DriverIncomingOfferView(status,
        offer: displayOffer,
        remainingSeconds: seconds,
        decisionStatus: _decision,
        command: _attempt?.command,
        canDecide: canDecide);
  }

  bool get _pendingDecision => _attempt != null && !_attempt!.finished;

  bool _ownsAttempt(_DecisionAttempt attempt) =>
      _valid(attempt.lifetime) &&
      identical(_attempt, attempt) &&
      _attempt!.operation == attempt.operation;

  /// Admission uses the current scope after flushing dependencies. The displayed
  /// payload prevents a callback captured for an old frame acting on a new offer.
  Future<void> decide(
      DriverFlowOffer displayed, DriverFlowOfferDecision decision) async {
    final lifetime = _lifetime;
    if (!_valid(lifetime) ||
        lifetime.scope == null ||
        !ref.read(driverOfferSimulationEnabledProvider)) {
      return;
    }
    _publish(
        _base); // Enforce the absolute deadline even without a widget timer.
    if (!_valid(lifetime)) return;
    final current = state;
    final offer = current.offer;
    if (!current.canDecide ||
        offer == null ||
        !_equivalent(displayed, offer) ||
        _latestSnapshot?.source != DriverFlowSource.simulated ||
        !_latestSnapshot!.session.sameSession(lifetime.scope!.session)) {
      return;
    }
    final operation = ++_operation;
    final command = DriverFlowDecideOffer(
        session: lifetime.scope!.session,
        targetId: offer.id,
        expectedVersion: offer.version,
        idempotencyToken:
            'offer-$_nonce-${lifetime.scope!.session.generation}-$operation',
        decision: decision);
    final attempt =
        _DecisionAttempt(command, offer, lifetime, _revision, operation);
    _attempt = attempt;
    _decision = decision == DriverFlowOfferDecision.accept
        ? DriverOfferDecisionStatus.pendingAccept
        : DriverOfferDecisionStatus.pendingDecline;
    _publish(
        _base); // Synchronous single flight, before any await or repository call.
    final timeout = Completer<DriverFlowResult>();
    try {
      attempt.cancel = ref.read(driverOfferDecisionSchedulerProvider)(
          const Duration(seconds: 15), () {
        if (_ownsAttempt(attempt) &&
            attempt.dispatched &&
            !attempt.finished &&
            !timeout.isCompleted) {
          timeout.complete(const DriverFlowResult(DriverFlowOutcome.unknown));
        }
      });
      // Publishing pending state can synchronously notify a host that revokes
      // the scope, changes the offer, or advances the clock. Flush and validate
      // again at the actual dispatch boundary, not just before publication.
      if (!_ownsAttempt(attempt)) return;
      final enabled = ref.read(driverOfferSimulationEnabledProvider);
      final now = _clock().toUtc();
      // Provider/clock overrides can run host code too. Flush once more before
      // inspecting the observation and making the uninterrupted execute call.
      if (!_ownsAttempt(attempt)) return;
      final effectiveNow =
          _lastNow != null && now.isBefore(_lastNow!) ? _lastNow! : now;
      if (offer.isExpiredAt(effectiveNow)) {
        _decision = DriverOfferDecisionStatus.expired;
        attempt.finished = true;
        _retiredDecisions.add((offer.id, offer.version));
        return;
      }
      if (!enabled || !_observationAllowsDispatch(attempt)) {
        // There was no dispatch: cancel locally rather than invent uncertainty
        // about an operation that the repository never received.
        _decision = DriverOfferDecisionStatus.stale;
        attempt.finished = true;
        return;
      }
      attempt.dispatched = true;
      final result = await Future.any<DriverFlowResult>([
        lifetime.repository.execute(command),
        timeout.future,
        attempt.retirement.future,
      ]);
      if (!_ownsAttempt(attempt)) return;
      _publish(
          _base); // Expiry while pending cannot establish a command outcome.
      if (result.outcome == DriverFlowOutcome.unauthorized) {
        _publish(IncomingOfferStatus.unauthorized);
        return;
      }
      if (_decision == DriverOfferDecisionStatus.unknown) return;
      if (result.outcome == DriverFlowOutcome.simulated &&
          _validDecisionResult(attempt, result.snapshot)) {
        _decision = decision == DriverFlowOfferDecision.accept
            ? DriverOfferDecisionStatus.simulatedAccepted
            : DriverOfferDecisionStatus.simulatedDeclined;
        _simulatedAssignment = decision == DriverFlowOfferDecision.accept;
        attempt.finished = true;
        _retiredDecisions.add((offer.id, offer.version));
        _observe(result.snapshot!, lifetime, read: true);
      } else if ({
        DriverFlowOutcome.rejected,
        DriverFlowOutcome.stale,
        DriverFlowOutcome.expired
      }.contains(result.outcome)) {
        _decision = switch (result.outcome) {
          DriverFlowOutcome.rejected => DriverOfferDecisionStatus.rejected,
          DriverFlowOutcome.expired => DriverOfferDecisionStatus.expired,
          _ => DriverOfferDecisionStatus.stale,
        };
        attempt.finished = true;
        _retiredDecisions.add((offer.id, offer.version));
      } else {
        _decision = DriverOfferDecisionStatus.unknown;
      }
    } on Object {
      if (_ownsAttempt(attempt)) {
        _decision = attempt.dispatched
            ? DriverOfferDecisionStatus.unknown
            : DriverOfferDecisionStatus.stale;
      }
    } finally {
      // Neither disposal nor an old future may cancel a replacement timer or lock.
      attempt.cancel?.call();
      if (_ownsAttempt(attempt)) {
        attempt.finished = true;
        _publish(_base);
      }
    }
  }

  /// Observation readiness is independent of our own pending decision lock.
  /// Do not use view.canDecide: the admitted operation intentionally disabled it.
  bool _observationAllowsDispatch(_DecisionAttempt attempt) {
    final snapshot = _latestSnapshot;
    final view = state;
    final expectedPending =
        attempt.command.decision == DriverFlowOfferDecision.accept
            ? DriverOfferDecisionStatus.pendingAccept
            : DriverOfferDecisionStatus.pendingDecline;
    return !_reading &&
        !_unauthorized &&
        !_simulatedAssignment &&
        _decision == expectedPending &&
        (view.status == IncomingOfferStatus.offer ||
            view.status == IncomingOfferStatus.replaced) &&
        snapshot != null &&
        snapshot.source == DriverFlowSource.simulated &&
        snapshot.session.sameSession(attempt.command.session) &&
        snapshot.phase == DriverFlowPhase.ready &&
        snapshot.trip == null &&
        snapshot.offer != null &&
        _equivalent(attempt.offer, snapshot.offer!) &&
        view.offer != null &&
        _equivalent(attempt.offer, view.offer!) &&
        !_retiredDecisions.contains((attempt.offer.id, attempt.offer.version));
  }

  bool _validDecisionResult(
      _DecisionAttempt attempt, DriverFlowSnapshot? snapshot) {
    if (snapshot == null ||
        snapshot.source != DriverFlowSource.simulated ||
        !snapshot.session.sameSession(attempt.command.session) ||
        snapshot.phase != DriverFlowPhase.ready ||
        snapshot.offer != null ||
        snapshot.revision <= attempt.revision ||
        snapshot.revision < _revision) {
      return false;
    }
    final trip = snapshot.trip;
    if (attempt.command.decision == DriverFlowOfferDecision.accept) {
      if (trip == null ||
          trip.status != DriverTripLifecycleStatus.accepted ||
          !_sameJourney(attempt.offer.journey, trip.journey)) {
        return false;
      }
    } else if (trip != null) {
      return false;
    }
    // Fake execute may publish its result synchronously before returning it.
    // Equal revisions must describe the same complete publication.
    final latest = _latestSnapshot;
    if (latest?.trip != null &&
        (trip == null ||
            latest!.trip!.id != trip.id ||
            latest.trip!.version != trip.version ||
            latest.trip!.status != trip.status ||
            !_sameJourney(latest.trip!.journey, trip.journey))) {
      return false;
    }
    return latest == null ||
        snapshot.revision > latest.revision ||
        (latest.source == snapshot.source &&
            latest.phase == snapshot.phase &&
            latest.session.sameSession(snapshot.session) &&
            latest.offer == null &&
            latest.availability?.state == snapshot.availability?.state &&
            latest.availability?.version == snapshot.availability?.version &&
            latest.availability?.vehicleId ==
                snapshot.availability?.vehicleId &&
            latest.availability?.bookingId ==
                snapshot.availability?.bookingId &&
            latest.availability?.tripId == snapshot.availability?.tripId &&
            latest.trip?.id == trip?.id &&
            latest.trip?.version == trip?.version &&
            latest.trip?.status == trip?.status &&
            (trip == null ||
                (latest.trip != null &&
                    _sameJourney(latest.trip!.journey, trip.journey))));
  }

  bool _equivalent(DriverFlowOffer a, DriverFlowOffer b) {
    return a.id == b.id &&
        a.version == b.version &&
        a.bookingId == b.bookingId &&
        a.quoteId == b.quoteId &&
        a.expiresAt == b.expiresAt &&
        _sameJourney(a.journey, b.journey);
  }

  bool _sameJourney(DriverFlowJourney x, DriverFlowJourney y) =>
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
