import 'dart:async';

import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';

/// Test-only scripted repository. No SDK, persistence, GPS or wall-clock work.
/// Commands never establish authority; uncertain attempts remain read-only.
final class FakeDriverFlowRepository implements DriverFlowRepository {
  FakeDriverFlowRepository(this._current, {required this.now}) {
    _requireFake(_current);
  }

  final DateTime Function() now;
  final _events = StreamController<DriverFlowSnapshot>.broadcast(sync: true);
  final List<DriverFlowCommand> _commands = [];
  final Map<DriverFlowDecideOffer, _AcceptanceAttempt> _acceptances = {};
  DriverFlowSnapshot _current;
  Future<DriverFlowSnapshot>? nextRead;
  Future<DriverFlowResult>? nextCommand;
  bool _disposed = false;

  DriverFlowSnapshot get current => _current;
  List<DriverFlowCommand> get commands => List.unmodifiable(_commands);

  static void _requireFake(DriverFlowSnapshot snapshot) {
    if (snapshot.source != DriverFlowSource.simulated) {
      throw ArgumentError('Fake accepts simulated snapshots only.');
    }
  }

  bool _owns(DriverFlowSession session) =>
      !_disposed && _current.session.sameSession(session);

  /// Duplicate/older revisions and events from retired sessions are ignored.
  bool emit(DriverFlowSnapshot snapshot) {
    _requireFake(snapshot);
    if (!_owns(snapshot.session) || snapshot.revision <= _current.revision) {
      return false;
    }
    final guarded = _guardAcceptanceObservation(snapshot);
    _current = guarded;
    _events.add(guarded);
    return true;
  }

  /// Explicit test-script outcome read, separate from repeated offer events and
  /// command replies. This is simulated fixture evidence, never backend authority.
  bool observeAcceptanceOutcome(DriverFlowSnapshot snapshot) {
    _requireFake(snapshot);
    if (!_owns(snapshot.session) ||
        snapshot.revision <= _current.revision ||
        snapshot.phase != DriverFlowPhase.ready ||
        snapshot.offer != null ||
        _acceptances.isEmpty) {
      return false;
    }
    final trip = snapshot.trip;
    if (trip != null &&
        _acceptances.values.any(
            (attempt) => !_sameJourney(attempt.offer.journey, trip.journey))) {
      return false;
    }
    _acceptances.clear();
    return emit(snapshot);
  }

  DriverFlowSnapshot _guardAcceptanceObservation(DriverFlowSnapshot snapshot) {
    var phase = snapshot.phase;
    for (final entry in _acceptances.entries) {
      if (!entry.key.session.sameSession(snapshot.session)) continue;
      final attempt = entry.value;
      if (!_matchesAttempt(entry.key, attempt, snapshot)) {
        attempt.phase = DriverFlowPhase.stale;
      } else if (attempt.phase != DriverFlowPhase.stale &&
          (attempt.phase == DriverFlowPhase.unknown ||
              snapshot.phase == DriverFlowPhase.unknown ||
              attempt.offer.isExpiredAt(now()))) {
        attempt.phase = DriverFlowPhase.unknown;
      }
      if (phase == DriverFlowPhase.unauthorized) continue;
      if (attempt.phase == DriverFlowPhase.stale) {
        phase = DriverFlowPhase.stale;
      } else if (phase != DriverFlowPhase.stale &&
          attempt.phase == DriverFlowPhase.unknown) {
        phase = DriverFlowPhase.unknown;
      } else if (phase == DriverFlowPhase.ready) {
        phase = DriverFlowPhase.pending;
      }
    }
    return phase == snapshot.phase ? snapshot : _withPhase(snapshot, phase);
  }

  static DriverFlowSnapshot _withPhase(
          DriverFlowSnapshot snapshot, DriverFlowPhase phase,
          {int? revision}) =>
      DriverFlowSnapshot(
        session: snapshot.session,
        revision: revision ?? snapshot.revision,
        phase: phase,
        source: snapshot.source,
        availability: snapshot.availability,
        offer: snapshot.offer,
        trip: snapshot.trip,
      );

  static bool _matchesAttempt(DriverFlowDecideOffer command,
          _AcceptanceAttempt attempt, DriverFlowSnapshot snapshot) =>
      command.session.sameSession(snapshot.session) &&
      snapshot.trip == null &&
      snapshot.offer != null &&
      _sameOffer(attempt.offer, snapshot.offer!);

  /// Compare the complete captured offer payload, not allocation identity.
  static bool _sameOffer(DriverFlowOffer a, DriverFlowOffer b) =>
      a.id == b.id &&
      a.version == b.version &&
      a.bookingId == b.bookingId &&
      a.quoteId == b.quoteId &&
      a.expiresAt.isAtSameMomentAs(b.expiresAt) &&
      _sameJourney(a.journey, b.journey);

  static bool _sameJourney(DriverFlowJourney a, DriverFlowJourney b) {
    if (a.pickup != b.pickup ||
        a.destination != b.destination ||
        a.vehicleId != b.vehicleId ||
        a.vehicleLabel != b.vehicleLabel ||
        a.lockedFareFils != b.lockedFareFils ||
        a.distanceMeters != b.distanceMeters ||
        a.durationSeconds != b.durationSeconds ||
        a.paymentMethod != b.paymentMethod ||
        a.stops.length != b.stops.length) {
      return false;
    }
    for (var i = 0; i < a.stops.length; i++) {
      if (a.stops[i] != b.stops[i]) return false;
    }
    return true;
  }

  /// Reusing a generation is forbidden, including A -> B -> A replacement.
  void replaceSession(DriverFlowSession session) {
    if (_disposed || session.generation <= _current.session.generation) {
      throw StateError('A fresh session generation is required.');
    }
    _current = DriverFlowSnapshot(
      session: session,
      revision: 0,
      phase: DriverFlowPhase.loading,
      source: DriverFlowSource.simulated,
    );
    nextRead = null;
    nextCommand = null;
    _acceptances.clear();
    _events.add(_current);
  }

  @override
  Stream<DriverFlowSnapshot> watch(DriverFlowSession session) => _events.stream
      .where((event) => _owns(session) && event.session.sameSession(session));

  @override
  Future<DriverFlowResult> read(DriverFlowSession session) async {
    if (!_owns(session)) {
      return const DriverFlowResult(DriverFlowOutcome.unauthorized);
    }
    _observePendingExpiry();
    final revision = _current.revision;
    final response = nextRead;
    nextRead = null;
    DriverFlowSnapshot snapshot;
    try {
      snapshot = response == null ? _current : await response;
    } on Object {
      return DriverFlowResult(!_owns(session)
          ? DriverFlowOutcome.unauthorized
          : _current.revision != revision
              ? DriverFlowOutcome.stale
              : DriverFlowOutcome.unavailable);
    }
    if (!_owns(session)) {
      return const DriverFlowResult(DriverFlowOutcome.unauthorized);
    }
    if (_current.revision != revision ||
        !snapshot.session.sameSession(session) ||
        snapshot.revision < revision) {
      return const DriverFlowResult(DriverFlowOutcome.stale);
    }
    _requireFake(snapshot);
    if (snapshot.revision > revision) emit(snapshot);
    return DriverFlowResult(DriverFlowOutcome.observed, _current);
  }

  @override
  Future<DriverFlowResult> execute(DriverFlowCommand command) async {
    if (!_owns(command.session)) {
      return const DriverFlowResult(DriverFlowOutcome.unauthorized);
    }
    final failure = _validate(command);
    if (failure != null) return DriverFlowResult(failure);
    _commands.add(command);
    final revision = _current.revision;
    final response = nextCommand;
    nextCommand = null;
    final acceptance = command is DriverFlowDecideOffer &&
            command.decision == DriverFlowOfferDecision.accept
        ? command
        : null;
    final attempt =
        acceptance == null ? null : _AcceptanceAttempt(_current.offer!);
    if (acceptance != null) _acceptances[acceptance] = attempt!;
    var retainAcceptance = false;
    try {
      // Missing/lost responses never synthesize accepted Trips or retry commands.
      DriverFlowResult result;
      try {
        result = response == null
            ? const DriverFlowResult(DriverFlowOutcome.unknown)
            : await response;
      } on Object {
        result = const DriverFlowResult(DriverFlowOutcome.unknown);
      }
      if (!_owns(command.session)) {
        return const DriverFlowResult(DriverFlowOutcome.unauthorized);
      }
      if (_current.phase == DriverFlowPhase.unauthorized) {
        return const DriverFlowResult(DriverFlowOutcome.unauthorized);
      }
      _observePendingExpiry();
      if (acceptance != null && _acceptances.containsKey(acceptance)) {
        if (attempt!.phase == DriverFlowPhase.stale) {
          retainAcceptance = true;
          return const DriverFlowResult(DriverFlowOutcome.stale);
        }
        if (_matchesAttempt(acceptance, attempt, _current) &&
            (attempt.phase == DriverFlowPhase.unknown ||
                _current.revision != revision ||
                result.outcome == DriverFlowOutcome.unknown ||
                result.outcome == DriverFlowOutcome.unavailable)) {
          attempt.phase = DriverFlowPhase.unknown;
          if (_current.phase != DriverFlowPhase.unknown) {
            emit(_withPhase(_current, DriverFlowPhase.unknown,
                revision: _current.revision + 1));
          }
          retainAcceptance = true;
          return DriverFlowResult(DriverFlowOutcome.unknown, _current);
        }
      }
      if (_current.revision != revision) {
        return const DriverFlowResult(DriverFlowOutcome.stale);
      }
      final snapshot = result.snapshot;
      if (snapshot != null) {
        _requireFake(snapshot);
        if (result.outcome != DriverFlowOutcome.simulated ||
            !snapshot.session.sameSession(command.session) ||
            snapshot.revision <= revision) {
          return const DriverFlowResult(DriverFlowOutcome.stale);
        }
        _acceptances.remove(command);
        emit(snapshot);
        return DriverFlowResult(result.outcome, _current);
      }
      return result;
    } finally {
      if (!retainAcceptance) _acceptances.remove(command);
    }
  }

  /// Deterministic clock observation only, not a timer or assignment decision.
  /// Expiry after dispatch cannot establish whether the claim took effect.
  void _observePendingExpiry() {
    if (_current.trip != null ||
        (_current.phase != DriverFlowPhase.ready &&
            _current.phase != DriverFlowPhase.pending)) {
      return;
    }
    final expired = _acceptances.entries.any((entry) =>
        _owns(entry.key.session) &&
        _matchesAttempt(entry.key, entry.value, _current) &&
        entry.value.offer.isExpiredAt(now()));
    if (!expired) return;
    emit(DriverFlowSnapshot(
      session: _current.session,
      revision: _current.revision + 1,
      phase: DriverFlowPhase.unknown,
      source: DriverFlowSource.simulated,
      availability: _current.availability,
      offer: _current.offer,
      trip: _current.trip,
    ));
  }

  DriverFlowOutcome? _validate(DriverFlowCommand command) {
    if (_current.phase == DriverFlowPhase.unauthorized) {
      return DriverFlowOutcome.unauthorized;
    }
    if (_current.phase != DriverFlowPhase.ready) return DriverFlowOutcome.stale;
    if (command is DriverFlowDecideOffer) {
      final offer = _current.offer;
      if (offer == null ||
          offer.id != command.targetId ||
          offer.version != command.expectedVersion) {
        return DriverFlowOutcome.stale;
      }
      if (offer.isExpiredAt(now())) return DriverFlowOutcome.expired;
    } else if (command is DriverFlowSetAvailability) {
      final availability = _current.availability;
      if (command.targetId != command.session.driverId ||
          availability == null ||
          availability.version != command.expectedVersion) {
        return DriverFlowOutcome.stale;
      }
      if (availability.state == DriverAvailabilityState.reserved ||
          availability.state == DriverAvailabilityState.onTrip) {
        return DriverFlowOutcome.rejected;
      }
    } else if (command is DriverFlowProgressTrip) {
      final trip = _current.trip;
      if (trip == null ||
          trip.id != command.targetId ||
          trip.version != command.expectedVersion) {
        return DriverFlowOutcome.stale;
      }
      // Exact local sequence; canonical transition authorization is not modeled.
      final expected = switch (trip.status) {
        DriverTripLifecycleStatus.accepted =>
          DriverTripLifecycleStatus.driverArriving,
        DriverTripLifecycleStatus.driverArriving =>
          DriverTripLifecycleStatus.driverArrived,
        DriverTripLifecycleStatus.driverArrived =>
          DriverTripLifecycleStatus.inProgress,
        _ => null,
      };
      if (command.status != expected) return DriverFlowOutcome.rejected;
    }
    return null;
  }

  Future<void> dispose() async {
    _disposed = true;
    _acceptances.clear();
    await _events.close();
  }
}

final class _AcceptanceAttempt {
  _AcceptanceAttempt(this.offer);
  final DriverFlowOffer offer;
  DriverFlowPhase phase = DriverFlowPhase.pending;
}

final driverFlowTestTime = DateTime.utc(2026, 11, 4, 12);

DriverFlowJourney driverFlowJourney() => DriverFlowJourney(
      pickup: RideLocation(
        point: LocationPoint(latitude: 32.1, longitude: 36.1),
        label: 'Pickup',
        address: 'Synthetic pickup',
        source: LocationSelectionSource.demo,
      ),
      destination: RideLocation(
        point: LocationPoint(latitude: 32.2, longitude: 36.2),
        label: 'Destination',
        address: 'Synthetic destination',
        source: LocationSelectionSource.demo,
      ),
      vehicleId: 'fake-vehicle',
      vehicleLabel: 'Taxi',
      lockedFareFils: 1990,
      distanceMeters: 5000,
      durationSeconds: 600,
    );

DriverFlowOffer driverFlowOffer({
  String id = 'fake-offer',
  int version = 3,
  DateTime? expiresAt,
}) =>
    DriverFlowOffer(
      id: id,
      bookingId: 'fake-booking',
      quoteId: 'fake-quote',
      version: version,
      expiresAt:
          expiresAt ?? driverFlowTestTime.add(const Duration(seconds: 30)),
      journey: driverFlowJourney(),
    );

DriverFlowSnapshot driverFlowSnapshot({
  DriverFlowSession? session,
  int revision = 1,
  DriverFlowPhase phase = DriverFlowPhase.ready,
  DriverFlowAvailability? availability,
  DriverFlowOffer? offer,
  DriverFlowTrip? trip,
}) =>
    DriverFlowSnapshot(
      session: session ?? DriverFlowSession('fake-driver', 1),
      revision: revision,
      phase: phase,
      source: DriverFlowSource.simulated,
      availability: availability,
      offer: offer,
      trip: trip,
    );
