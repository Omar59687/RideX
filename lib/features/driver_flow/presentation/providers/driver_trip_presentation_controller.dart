import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import '../../domain/driver_flow_contract.dart';
import 'driver_availability_controller.dart';
import 'driver_flow_repository_provider.dart';
import 'driver_incoming_offer_controller.dart';

/// Local test/demo intent only; never enabled in application composition.
final driverTripSimulationEnabledProvider = Provider<bool>((ref) => false);
typedef DriverTripResponseScheduler = void Function() Function(
    Duration duration, void Function() callback);
final driverTripResponseSchedulerProvider =
    Provider<DriverTripResponseScheduler>((ref) => (duration, callback) {
          final timer = Timer(duration, callback);
          return timer.cancel;
        });

enum DriverTripProgressStatus {
  idle,
  pending,
  simulated,
  rejected,
  stale,
  unknown,
  unauthorized
}

final driverTripPresentationProvider = NotifierProvider<
    DriverTripPresentationController,
    DriverTripPresentationView>(DriverTripPresentationController.new);

class DriverTripPresentationView {
  const DriverTripPresentationView(this.phase,
      {this.trip,
      this.progressStatus = DriverTripProgressStatus.idle,
      this.command,
      this.canProgress = false,
      this.reading = false,
      this.offerBlocked = false,
      this.lifetime = 0,
      this.session});
  final DriverFlowPhase phase;
  final DriverFlowTrip? trip;
  final DriverTripProgressStatus progressStatus;
  final DriverFlowProgressTrip? command;
  final bool canProgress;
  final bool reading;
  final bool offerBlocked;
  final int lifetime;
  final DriverFlowSession? session;
  DriverTripLifecycleStatus? get nextStatus => _next(trip?.status);
}

DriverTripLifecycleStatus? _next(DriverTripLifecycleStatus? status) =>
    switch (status) {
      DriverTripLifecycleStatus.accepted =>
        DriverTripLifecycleStatus.driverArriving,
      DriverTripLifecycleStatus.driverArriving =>
        DriverTripLifecycleStatus.driverArrived,
      DriverTripLifecycleStatus.driverArrived =>
        DriverTripLifecycleStatus.inProgress,
      _ => null,
    };

typedef _TripLifetime = ({
  int epoch,
  DriverAvailabilityScope? scope,
  DriverFlowRepository repository
});

class _ProgressAttempt {
  _ProgressAttempt(this.command, this.trip, this.lifetime, this.revision);
  final DriverFlowProgressTrip command;
  final DriverFlowTrip trip;
  final _TripLifetime lifetime;
  final int revision;
  bool dispatched = false;
  bool finished = false;
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

/// Sole owner of simulated Trip progression. The repository remains the source
/// of observations; this owner never populates shared mock/canonical Trip state.
/// Persistent across widget removal, with one pinned Trip per scope lifetime.
class DriverTripPresentationController
    extends Notifier<DriverTripPresentationView> {
  int _epoch = 0;
  int _operation = 0;
  final _nonce =
      '${Random.secure().nextInt(1 << 32)}-${Random.secure().nextInt(1 << 32)}';
  _TripLifetime? _lifetime;
  final _retiredSessions = <(String, int)>{};
  final _retiredTargets = <(String, int)>{};
  _ProgressAttempt? _attempt;
  DriverTripProgressStatus _progress = DriverTripProgressStatus.idle;
  DriverFlowPhase _phase = DriverFlowPhase.loading;
  DriverFlowSnapshot? _latest;
  DriverFlowTrip? _trip;
  String? _pinnedId;
  int _revision = -1;
  int _sequence = 0;
  bool _reading = false;
  bool _authLost = false;
  bool _conflict = false;
  bool _externalUnknown = false;
  bool _transportUnavailable = false;

  @override
  DriverTripPresentationView build() {
    final previous = _lifetime;
    if (previous?.scope != null) {
      final session = previous!.scope!.session;
      // A repository replacement also needs a fresh local generation. Reusing
      // the retired scope must not erase unresolved work or revive A -> B -> A.
      _retiredSessions.add((session.driverId, session.generation));
    }
    ++_epoch;
    _attempt?.retire();
    _attempt = null;
    _progress = DriverTripProgressStatus.idle;
    _latest = null;
    _trip = null;
    _pinnedId = null;
    _revision = -1;
    _sequence = 0;
    _reading = false;
    _authLost = false;
    _conflict = false;
    _externalUnknown = false;
    _transportUnavailable = false;
    _retiredTargets.clear();
    final scope = ref.watch(driverAvailabilityScopeProvider);
    final repository = ref.watch(driverFlowRepositoryProvider);
    final life =
        _lifetime = (epoch: _epoch, scope: scope, repository: repository);
    StreamSubscription<DriverFlowSnapshot>? subscription;
    ref.onDispose(() {
      ++_epoch;
      _attempt?.retire();
      unawaited(subscription?.cancel());
    });
    _phase =
        scope == null ? DriverFlowPhase.unavailable : DriverFlowPhase.loading;
    if (scope != null) {
      if (_retiredSessions
              .contains((scope.session.driverId, scope.session.generation)) ||
          !_sessionEligible(scope)) {
        _authLost = true;
        _phase = DriverFlowPhase.unauthorized;
      }
      // Listeners, not watched dependencies: normal auth/offer notifications
      // must never rebuild this owner and drop a pending or UNKNOWN attempt.
      ref.listen(sessionControllerProvider, (_, next) {
        if (life.epoch == _epoch && !_sessionEligible(scope)) _revoke();
      });
      ref.listen(driverIncomingOfferProvider, (_, next) {
        if (life.epoch != _epoch || _authLost) return;
        if (_offerBlocked() &&
            _attempt?.dispatched == true &&
            !_attempt!.finished) {
          _progress = DriverTripProgressStatus.unknown;
        }
        _publish();
      });
      ref.listen(driverTripSimulationEnabledProvider, (_, next) {
        if (life.epoch == _epoch && !_authLost) _publish();
      });
      Future.microtask(() async {
        if (!_valid(life)) return;
        try {
          subscription = repository.watch(scope.session).listen(
              (snapshot) => _observe(snapshot, life), onError: (Object error) {
            if (_valid(life)) _unavailable();
          }, onDone: () {
            if (_valid(life)) _unavailable();
          });
        } on Object {
          if (_valid(life)) _unavailable();
        }
        if (_valid(life)) await refresh();
      });
    }
    return DriverTripPresentationView(_phase, lifetime: _epoch);
  }

  bool _sessionEligible(DriverAvailabilityScope scope) {
    final session = ref.read(sessionControllerProvider);
    final user = session.user;
    return session.status == SessionStatus.authenticated &&
        user != null &&
        user.id == scope.session.driverId &&
        user.role == RideRole.driver &&
        !user.isBlocked &&
        user.driverApprovalStatus == DriverApprovalStatus.approved;
  }

  bool _valid(_TripLifetime life) {
    if (life.epoch != _epoch) return false;
    final ignored = state; // Flush pending dependency invalidations first.
    return life.epoch == _epoch &&
        !_authLost &&
        identical(life.scope, _lifetime?.scope) &&
        identical(life.repository, _lifetime?.repository) &&
        ignored.phase != DriverFlowPhase.unauthorized;
  }

  void _revoke() {
    _authLost = true;
    final session = _lifetime?.scope?.session;
    if (session != null) {
      _retiredSessions.add((session.driverId, session.generation));
    }
    _phase = DriverFlowPhase.unauthorized;
    // Revocation is access evidence, not evidence that a dispatched command
    // failed. Keep its uncertainty and immutable command while hiding all data.
    if (_progress != DriverTripProgressStatus.unknown) {
      _progress = _attempt?.dispatched == true && !_attempt!.finished
          ? DriverTripProgressStatus.unknown
          : DriverTripProgressStatus.unauthorized;
    }
    _attempt?.retire();
    _publish();
  }

  bool _offerBlocked() {
    final offer = ref.read(driverIncomingOfferProvider);
    return switch (offer.decisionStatus) {
      DriverOfferDecisionStatus.pendingAccept ||
      DriverOfferDecisionStatus.pendingDecline ||
      DriverOfferDecisionStatus.unknown ||
      DriverOfferDecisionStatus.unauthorized =>
        true,
      _ => offer.status == IncomingOfferStatus.pending ||
          offer.status == IncomingOfferStatus.unknown ||
          offer.status == IncomingOfferStatus.unauthorized,
    };
  }

  void _unavailable() {
    _transportUnavailable = true;
    _phase = DriverFlowPhase.unavailable;
    if (_attempt?.dispatched == true && !_attempt!.finished) {
      _progress = DriverTripProgressStatus.unknown;
    }
    _publish();
  }

  Future<void> refresh() async {
    final life = _lifetime!;
    if (!_valid(life) || life.scope == null || _reading) return;
    if (!_sessionEligible(life.scope!)) {
      _revoke();
      return;
    }
    _reading = true;
    final sequence = _sequence;
    _publish();
    try {
      if (!_valid(life) || !_sessionEligible(life.scope!)) return;
      final result = await life.repository.read(life.scope!.session);
      if (!_valid(life) || sequence != _sequence) return;
      if (result.outcome == DriverFlowOutcome.unauthorized) {
        _revoke();
      } else if (result.outcome == DriverFlowOutcome.observed &&
          result.snapshot != null) {
        _observe(result.snapshot!, life, readRecovery: true);
      } else {
        _unavailable();
      }
    } on Object {
      if (_valid(life) && sequence == _sequence) _unavailable();
    } finally {
      if (_valid(life)) {
        _reading = false;
        _publish();
      }
    }
  }

  void _observe(DriverFlowSnapshot snapshot, _TripLifetime life,
      {bool readRecovery = false}) {
    if (!_valid(life)) return;
    if (!_sessionEligible(life.scope!)) {
      _revoke();
      return;
    }
    final matchingSession = snapshot.session.sameSession(life.scope!.session);
    // A matching denial remains meaningful without simulated journey data.
    // Foreign/retired sessions cannot revoke this lifetime.
    if (matchingSession && snapshot.phase == DriverFlowPhase.unauthorized) {
      _revoke();
      return;
    }
    if (!matchingSession || snapshot.source != DriverFlowSource.simulated) {
      _phase = DriverFlowPhase.stale;
      if (_attempt?.dispatched == true && !_attempt!.finished) {
        _progress = DriverTripProgressStatus.unknown;
      }
      _publish();
      return;
    }
    if (snapshot.revision < _revision) return;
    if (snapshot.revision == _revision && _latest != null) {
      if (!_samePublication(_latest!, snapshot)) {
        _conflict = true;
        _phase = DriverFlowPhase.stale;
        _publish();
      } else if (readRecovery &&
          _transportUnavailable &&
          _phase == DriverFlowPhase.unavailable &&
          !_conflict &&
          !_externalUnknown &&
          _progress != DriverTripProgressStatus.unknown &&
          snapshot.phase == DriverFlowPhase.ready &&
          snapshot.offer == null &&
          snapshot.trip != null &&
          _trip != null &&
          snapshot.trip!.id == _pinnedId &&
          _sameTrip(snapshot.trip!, _trip!)) {
        // Only an explicit, fully equivalent read can recover transport loss.
        // Duplicate watch events and all uncertainty/conflict barriers survive.
        _transportUnavailable = false;
        _phase = DriverFlowPhase.ready;
        _publish();
      }
      return;
    }
    _latest = snapshot;
    _revision = snapshot.revision;
    ++_sequence;
    if (snapshot.phase == DriverFlowPhase.unauthorized) {
      _revoke();
      return;
    }
    _phase = snapshot.phase;
    _transportUnavailable = false;
    final incoming = snapshot.trip;
    if (snapshot.phase == DriverFlowPhase.unknown) _externalUnknown = true;
    if (incoming != null) {
      final previous = _trip;
      _pinnedId ??= incoming.id;
      if (incoming.id != _pinnedId ||
          snapshot.offer != null ||
          incoming.journey.vehicleId != life.scope!.vehicleId) {
        _conflict = true;
      } else if (previous != null) {
        if (incoming.version < previous.version) {
          _phase = DriverFlowPhase.stale;
        } else if ((incoming.version == previous.version &&
                !_sameTrip(incoming, previous)) ||
            !_sameJourney(incoming.journey, previous.journey) ||
            !_reachable(previous.status, incoming.status)) {
          _conflict = true;
        } else {
          _trip = incoming;
        }
      } else {
        _trip = incoming;
      }
    }
    final attempt = _attempt;
    if (attempt != null &&
        !attempt.finished &&
        attempt.dispatched &&
        (_phase != DriverFlowPhase.ready ||
            incoming == null ||
            (!_sameTrip(incoming, attempt.trip) &&
                !_matchesSuccess(attempt, snapshot)))) {
      _progress = DriverTripProgressStatus.unknown;
    }
    if (_conflict) {
      _phase = DriverFlowPhase.stale;
      if (attempt?.dispatched == true && !attempt!.finished) {
        _progress = DriverTripProgressStatus.unknown;
      }
    }
    // Completed/definitively rejected commands cannot be reissued against the
    // same target version. A genuinely new observation may enable the next edge.
    if (attempt?.finished == true &&
        _progress != DriverTripProgressStatus.unknown &&
        incoming != null &&
        !_retiredTargets.contains((incoming.id, incoming.version))) {
      _progress = DriverTripProgressStatus.idle;
    }
    _publish();
  }

  bool _observationReady() {
    final snapshot = _latest;
    final trip = snapshot?.trip;
    return !_authLost &&
        !_conflict &&
        !_externalUnknown &&
        !_reading &&
        _phase == DriverFlowPhase.ready &&
        snapshot != null &&
        snapshot.phase == DriverFlowPhase.ready &&
        snapshot.source == DriverFlowSource.simulated &&
        snapshot.session.sameSession(_lifetime!.scope!.session) &&
        snapshot.offer == null &&
        trip != null &&
        _trip != null &&
        trip.id == _pinnedId &&
        _sameTrip(trip, _trip!) &&
        !_retiredTargets.contains((trip.id, trip.version));
  }

  void _publish() {
    if (_authLost) {
      state = DriverTripPresentationView(DriverFlowPhase.unauthorized,
          progressStatus: _progress,
          command: _attempt?.command,
          lifetime: _epoch);
      return;
    }
    final blocked = _lifetime!.scope != null && _offerBlocked();
    final observed = _latest?.trip;
    final visible =
        observed == null && _phase == DriverFlowPhase.ready ? null : _trip;
    final pending = _attempt != null && !_attempt!.finished;
    state = DriverTripPresentationView(
        _conflict
            ? DriverFlowPhase.stale
            : _externalUnknown && _phase == DriverFlowPhase.ready
                ? DriverFlowPhase.unknown
                : _phase,
        trip: visible,
        progressStatus: _progress,
        command: _attempt?.command,
        reading: _reading,
        offerBlocked: blocked,
        lifetime: _epoch,
        session: _lifetime!.scope?.session,
        canProgress: _lifetime!.scope != null &&
            ref.read(driverTripSimulationEnabledProvider) &&
            !blocked &&
            !pending &&
            _progress != DriverTripProgressStatus.unknown &&
            _observationReady() &&
            _next(observed?.status) != null);
  }

  bool _owns(_ProgressAttempt attempt) =>
      _valid(attempt.lifetime) && identical(_attempt, attempt);

  /// Read-only handoff validation; never derives a Trip from a navigation event.
  bool canPreview(
      DriverFlowTrip displayed, DriverFlowSession session, int lifetime) {
    final life = _lifetime!;
    return _valid(life) &&
        life.scope != null &&
        lifetime == life.epoch &&
        _sessionEligible(life.scope!) &&
        session.sameSession(life.scope!.session) &&
        !_conflict &&
        _phase == DriverFlowPhase.ready &&
        _latest?.source == DriverFlowSource.simulated &&
        _latest?.trip != null &&
        _sameTrip(displayed, _latest!.trip!);
  }

  Future<void> progress(
      DriverFlowTrip displayed, DriverTripLifecycleStatus requested,
      {required int lifetime}) async {
    final life = _lifetime!;
    if (!_valid(life) || life.scope == null || lifetime != life.epoch) return;
    if (!_sessionEligible(life.scope!)) {
      _revoke();
      return;
    }
    _publish();
    if (!_valid(life) ||
        !state.canProgress ||
        !_sameTrip(displayed, state.trip!) ||
        _next(displayed.status) != requested) {
      return;
    }
    final command = DriverFlowProgressTrip(
        session: life.scope!.session,
        targetId: displayed.id,
        expectedVersion: displayed.version,
        idempotencyToken:
            'trip-$_nonce-${life.scope!.session.generation}-${++_operation}',
        status: requested);
    final attempt = _ProgressAttempt(command, displayed, life, _revision);
    _attempt = attempt;
    _progress = DriverTripProgressStatus.pending;
    _publish(); // Synchronous ownership before notifying potentially reentrant hosts.
    final timeout = Completer<DriverFlowResult>();
    try {
      attempt.cancel = ref.read(driverTripResponseSchedulerProvider)(
          const Duration(seconds: 15), () {
        if (_owns(attempt) &&
            attempt.dispatched &&
            !attempt.finished &&
            !timeout.isCompleted) {
          timeout.complete(const DriverFlowResult(DriverFlowOutcome.unknown));
        }
      });
      if (!_owns(attempt)) return;
      final authorized = _sessionEligible(life.scope!);
      final offerBlocked = _offerBlocked();
      final enabled = ref.read(driverTripSimulationEnabledProvider);
      // Dependency/host reads above may execute code. Flush once more, then use
      // observation-side eligibility independently from our OWN pending lock.
      if (!_owns(attempt)) return;
      if (!authorized) {
        _revoke();
        return;
      }
      if (!enabled ||
          offerBlocked ||
          !_observationReady() ||
          _progress != DriverTripProgressStatus.pending ||
          !_sameTrip(attempt.trip, _latest!.trip!) ||
          _next(_latest!.trip!.status) != command.status) {
        attempt.finished = true;
        _progress =
            DriverTripProgressStatus.stale; // Definitely unsent, not UNKNOWN.
        return;
      }
      // No publication, await or host callback between validation and execute.
      attempt.dispatched = true;
      final response = life.repository.execute(command).then((result) {
        // A timeout settles presentation uncertainty, not access authority.
        // A late denial still revokes only its own current operation/lifetime.
        if (result.outcome == DriverFlowOutcome.unauthorized &&
            _owns(attempt)) {
          _revoke();
        }
        return result;
      });
      final result = await Future.any(
          [response, timeout.future, attempt.retirement.future]);
      if (!_owns(attempt)) return;
      if (result.outcome == DriverFlowOutcome.unauthorized) {
        _revoke();
        return;
      }
      if (!_sessionEligible(life.scope!)) {
        _revoke();
        return;
      }
      if (_progress == DriverTripProgressStatus.unknown) return;
      if (result.outcome == DriverFlowOutcome.simulated &&
          _validResult(attempt, result.snapshot)) {
        _observe(result.snapshot!, life);
        // _observe can publish and reenter. Never settle another operation.
        if (_owns(attempt) && _progress != DriverTripProgressStatus.unknown) {
          _progress = DriverTripProgressStatus.simulated;
          _retiredTargets.add((command.targetId, command.expectedVersion));
        }
      } else if ({
        DriverFlowOutcome.rejected,
        DriverFlowOutcome.expired,
        DriverFlowOutcome.stale,
        DriverFlowOutcome.unsupported
      }.contains(result.outcome)) {
        // A negative result contradicting a newer Trip observation is ambiguous.
        if (_latest?.trip == null || !_sameTrip(_latest!.trip!, attempt.trip)) {
          _progress = DriverTripProgressStatus.unknown;
        } else {
          _progress = result.outcome == DriverFlowOutcome.stale ||
                  result.outcome == DriverFlowOutcome.expired
              ? DriverTripProgressStatus.stale
              : DriverTripProgressStatus.rejected;
          _retiredTargets.add((command.targetId, command.expectedVersion));
        }
      } else {
        _progress = DriverTripProgressStatus.unknown;
      }
    } on Object {
      if (_owns(attempt)) {
        _progress = attempt.dispatched
            ? DriverTripProgressStatus.unknown
            : DriverTripProgressStatus.stale;
      }
    } finally {
      attempt.cancel?.call(); // Cancellation closes only this attempt's timer.
      if (_owns(attempt)) {
        attempt.finished = true;
        _publish();
      }
    }
  }

  bool _matchesSuccess(_ProgressAttempt attempt, DriverFlowSnapshot snapshot) {
    final trip = snapshot.trip;
    return snapshot.source == DriverFlowSource.simulated &&
        snapshot.session.sameSession(attempt.command.session) &&
        snapshot.phase == DriverFlowPhase.ready &&
        snapshot.offer == null &&
        snapshot.revision > attempt.revision &&
        trip != null &&
        trip.id == attempt.command.targetId &&
        trip.version > attempt.command.expectedVersion &&
        trip.status == attempt.command.status &&
        _sameJourney(trip.journey, attempt.trip.journey);
  }

  bool _validResult(_ProgressAttempt attempt, DriverFlowSnapshot? snapshot) =>
      snapshot != null &&
      !_conflict &&
      !_externalUnknown &&
      _matchesSuccess(attempt, snapshot) &&
      snapshot.revision >= _revision &&
      (snapshot.revision > _revision ||
          (_latest != null && _samePublication(snapshot, _latest!)));

  static bool _sameTrip(DriverFlowTrip a, DriverFlowTrip b) =>
      a.id == b.id &&
      a.version == b.version &&
      a.status == b.status &&
      _sameJourney(a.journey, b.journey);

  static bool _sameJourney(DriverFlowJourney a, DriverFlowJourney b) =>
      a.pickup == b.pickup &&
      a.destination == b.destination &&
      a.vehicleId == b.vehicleId &&
      a.vehicleLabel == b.vehicleLabel &&
      a.lockedFareFils == b.lockedFareFils &&
      a.paymentMethod == b.paymentMethod &&
      a.distanceMeters == b.distanceMeters &&
      a.durationSeconds == b.durationSeconds &&
      a.stops.length == b.stops.length &&
      List.generate(a.stops.length, (i) => a.stops[i] == b.stops[i])
          .every((v) => v);

  static bool _samePublication(DriverFlowSnapshot a, DriverFlowSnapshot b) =>
      a.session.sameSession(b.session) &&
      a.source == b.source &&
      a.phase == b.phase &&
      a.revision == b.revision &&
      a.offer == b.offer &&
      a.availability?.state == b.availability?.state &&
      a.availability?.version == b.availability?.version &&
      a.availability?.vehicleId == b.availability?.vehicleId &&
      a.availability?.bookingId == b.availability?.bookingId &&
      a.availability?.tripId == b.availability?.tripId &&
      ((a.trip == null && b.trip == null) ||
          (a.trip != null && b.trip != null && _sameTrip(a.trip!, b.trip!)));

  static bool _reachable(
      DriverTripLifecycleStatus before, DriverTripLifecycleStatus after) {
    if (before == after) return true;
    // Reconnect may skip observations, but never regress or resurrect a terminal.
    const active = [
      DriverTripLifecycleStatus.accepted,
      DriverTripLifecycleStatus.driverArriving,
      DriverTripLifecycleStatus.driverArrived,
      DriverTripLifecycleStatus.inProgress
    ];
    final first = active.indexOf(before);
    final second = active.indexOf(after);
    if (first < 0) return false;
    if (second >= 0) return second > first;
    if (after == DriverTripLifecycleStatus.completed) {
      return true; // Missed forward observations are read-only.
    }
    if (before == DriverTripLifecycleStatus.inProgress) {
      return after == DriverTripLifecycleStatus.cancelledByAdmin ||
          after == DriverTripLifecycleStatus.failed;
    }
    return true;
  }
}
