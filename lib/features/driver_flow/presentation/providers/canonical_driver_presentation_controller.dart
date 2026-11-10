import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import '../../data/canonical_driver_repository.dart';
import '../../domain/canonical_driver_delivery.dart';
import '../../domain/driver_flow_contract.dart';
import 'driver_trip_presentation_controller.dart' show DriverTripCompletionGate;

/// No production construction, route, delivery adapter or SDK access is supplied.
/// The session/provider owner outlives widget removal and must retain B07's
/// repository/intent. Removing a panel must not erase pending/UNKNOWN evidence.
final driverCanonicalPresentationProvider =
    ChangeNotifierProvider<CanonicalDriverPresentationController?>(
        (ref) => null);

enum CanonicalDriverPresentationPhase {
  disabled,
  missingDelivery,
  disconnected,
  loading,
  empty,
  offer,
  expired,
  trip,
  declined,
  pending,
  unknown,
  stale,
  unavailable,
  unauthorized,
}

/// B08 canonical references only; never a simulated B01 snapshot/full journey.
/// Getters remain revocable after capture. No amount, route, rider display name,
/// vehicle description or payment success is manufactured from identifier data.
final class CanonicalDriverPresentationView {
  CanonicalDriverPresentationView._(this._controller, this._publication);
  final CanonicalDriverPresentationController _controller;
  final int _publication;

  bool get _current =>
      _controller._publication == _publication &&
      _controller._authorized &&
      _controller._resultOwned;
  CanonicalDriverPresentationPhase get phase =>
      !_controller._authorized || !_controller._resultOwned
          ? CanonicalDriverPresentationPhase.unauthorized
          : !_current
              ? CanonicalDriverPresentationPhase.stale
              : _controller._visiblePhase;
  bool get connected => _current && _controller._connected;
  bool get _show =>
      _current &&
      connected &&
      {
        CanonicalDriverPresentationPhase.offer,
        CanonicalDriverPresentationPhase.expired,
        CanonicalDriverPresentationPhase.trip,
        CanonicalDriverPresentationPhase.pending,
        CanonicalDriverPresentationPhase.unknown,
      }.contains(phase);
  CanonicalDriverOffer? get offer => _show ? _controller._result?.offer : null;
  CanonicalDriverTrip? get trip =>
      _show && phase == CanonicalDriverPresentationPhase.trip
          ? _controller._result?.trip
          : null;
  bool get canDecide =>
      _current &&
      phase == CanonicalDriverPresentationPhase.offer &&
      _controller.offerActionsEnabled &&
      _controller.repository.offerCommandsEnabled &&
      _controller._attempt == null &&
      offer != null;
  bool get canReconcile =>
      _current &&
      connected &&
      phase == CanonicalDriverPresentationPhase.unknown &&
      !_controller._decisionPending &&
      _controller._handedOff;
  DriverTripCompletionGate get completionGate =>
      DriverTripCompletionGate.blocked;
}

/// Presentation-only composition. B07 remains the canonical read/command owner.
/// The injected UI SessionState can suppress access, never grant it: all data and
/// commands still pass B07's authenticated backend/session/eligibility checks.
final class CanonicalDriverPresentationController extends ChangeNotifier {
  CanonicalDriverPresentationController({
    required this.repository,
    required ValueListenable<SessionState> session,
    required Listenable authorityInvalidations,
    CanonicalDriverDelivery? delivery,
    this.enabled = false,
    this.offerActionsEnabled = false,
    DateTime Function()? clock,
    String Function()? createIdempotencyKey,
  })  : _sessionSource = session,
        _session = session.value,
        _authorityInvalidations = authorityInvalidations,
        _clock = clock ?? DateTime.now,
        _createKey = createIdempotencyKey ??
            (() =>
                'b08-${Random.secure().nextInt(1 << 32)}-${Random.secure().nextInt(1 << 32)}') {
    _phase = !enabled
        ? CanonicalDriverPresentationPhase.disabled
        : delivery == null
            ? CanonicalDriverPresentationPhase.missingDelivery
            : CanonicalDriverPresentationPhase.disconnected;
    _sessionSource.addListener(_onSession);
    _authorityInvalidations.addListener(_revoke);
    if (enabled && delivery != null && _authorized) {
      try {
        final subscription = delivery.signals.listen(_onSignal,
            onError: (Object _, StackTrace __) => _disconnect(),
            onDone: _disconnect);
        if (!_authorized) {
          unawaited(subscription.cancel());
        } else {
          _subscription = subscription;
        }
      } on Object {
        _phase = CanonicalDriverPresentationPhase.unavailable;
      }
    }
  }

  final CanonicalDriverRepository repository;
  final bool enabled, offerActionsEnabled;
  final ValueListenable<SessionState> _sessionSource;
  final SessionState _session;
  final Listenable _authorityInvalidations;
  final DateTime Function() _clock;
  final String Function() _createKey;
  StreamSubscription<CanonicalDriverDeliverySignal>? _subscription;
  late CanonicalDriverPresentationPhase _phase;
  CanonicalDriverResult? _result;
  String? _offerId;
  CanonicalDriverTrip? _pinnedTrip;
  CanonicalDriverOffer? _attempt;
  String? _key;
  bool _connected = false, _disposed = false, _revoked = false;
  bool _decisionPending = false, _unknown = false, _handedOff = false;
  bool _stale = false;
  int _generation = 0, _publication = 0, _revision = -1;
  final Set<String> _expired = {};

  CanonicalDriverPresentationView get view =>
      CanonicalDriverPresentationView._(this, _publication);
  bool get _authorized {
    final user = _session.user;
    return !_disposed &&
        !_revoked &&
        identical(_sessionSource.value, _session) &&
        _session.status == SessionStatus.authenticated &&
        user?.role == RideRole.driver &&
        user?.isBlocked == false &&
        user?.driverApprovalStatus == DriverApprovalStatus.approved &&
        isCanonicalTripId(user!.id);
  }

  bool get _resultOwned =>
      _result?.outcome != CanonicalDriverOutcome.unauthorized;
  CanonicalDriverPresentationPhase get _visiblePhase {
    if (!_authorized || !_resultOwned) {
      return CanonicalDriverPresentationPhase.unauthorized;
    }
    if (_unknown) return CanonicalDriverPresentationPhase.unknown;
    if (_decisionPending) return CanonicalDriverPresentationPhase.pending;
    if (_stale) return CanonicalDriverPresentationPhase.stale;
    final offer = _result?.offer;
    if (_phase == CanonicalDriverPresentationPhase.offer &&
        offer != null &&
        (_expired.contains(offer.id) ||
            !_clock().toUtc().isBefore(offer.expiresAt))) {
      return CanonicalDriverPresentationPhase.expired;
    }
    return _phase;
  }

  void _publish() {
    _publication++;
    if (!_disposed) notifyListeners();
  }

  void _onSession() {
    if (!identical(_sessionSource.value, _session)) _revoke();
  }

  void _revoke() {
    if (_disposed || _revoked) return;
    _revoked = true;
    _generation++;
    _connected = false;
    _result = null;
    _pinnedTrip = null;
    _offerId = null;
    _phase = CanonicalDriverPresentationPhase.unauthorized;
    _publish();
    unawaited(_cancel());
  }

  Future<void> _cancel() async {
    final old = _subscription;
    _subscription = null;
    try {
      await old?.cancel();
    } on Object {/* Already hidden. */}
  }

  void _disconnect() {
    if (_disposed) return;
    _generation++;
    _connected = false;
    _result = null;
    if (_decisionPending && _handedOff) _unknown = true;
    _phase = CanonicalDriverPresentationPhase.disconnected;
    _publish();
  }

  void _onSignal(CanonicalDriverDeliverySignal signal) {
    if (!_authorized ||
        !enabled ||
        signal.revision <= _revision ||
        signal.revision < 0) {
      return;
    }
    _revision = signal.revision;
    if (signal is CanonicalDriverConnectionHint) {
      if (!signal.connected) {
        _disconnect();
        return;
      }
      _connected = true;
      unawaited(refresh());
    } else if (_connected && signal is CanonicalDriverOfferHint) {
      if (!isCanonicalTripId(signal.offerId)) {
        _invalidate();
        return;
      }
      if (_attempt != null) {
        if (_attempt!.id != signal.offerId.toLowerCase()) {
          _invalidate();
        }
        // Delivery never reconciles an intent or rotates its original key.
        return;
      }
      _offerId = signal.offerId.toLowerCase();
      unawaited(refresh());
    } else if (_connected && signal is CanonicalDriverTripHint) {
      // A hint cannot discover or replace the current Trip identity.
      if (_pinnedTrip != null &&
          signal.tripId.toLowerCase() == _pinnedTrip!.id) {
        unawaited(refresh());
      }
    }
  }

  void _invalidate() {
    _generation++;
    _result = null;
    _stale = true;
    if (_handedOff) _unknown = true;
    _phase = CanonicalDriverPresentationPhase.stale;
    _publish();
  }

  bool _readCurrent(int generation) =>
      _authorized &&
      _connected &&
      !_stale &&
      generation == _generation &&
      !_disposed;

  Future<void> refresh() async {
    if (!enabled || !_authorized || !_connected || _stale) return;
    if (_decisionPending || _unknown) {
      return; // Only explicit recovery may reconcile.
    }
    final generation = ++_generation;
    _result = null;
    _phase = CanonicalDriverPresentationPhase.loading;
    _publish();
    if (!_readCurrent(generation)) return;
    final result = _pinnedTrip == null
        ? await repository.observe(offerId: _offerId)
        : await repository.readTrip(_pinnedTrip!.id);
    if (!_readCurrent(generation)) return;
    if (result.outcome == CanonicalDriverOutcome.unauthorized) {
      _revoke();
      return;
    }
    if (_pinnedTrip != null) {
      _admitTrip(result);
    } else if (result.outcome == CanonicalDriverOutcome.observed) {
      final offer = result.offer;
      if (offer != null &&
          (offer.id != _offerId ||
              offer.driverId != _session.user!.id.toLowerCase())) {
        _invalidate();
        return;
      }
      final tripId = result.availability?.tripId;
      if (tripId != null) {
        final tripResult = await repository.readTrip(tripId);
        if (!_readCurrent(generation)) return;
        if (offer != null &&
            (tripResult.trip?.bookingId != offer.bookingId ||
                tripResult.trip?.quoteId != offer.quoteId ||
                tripResult.trip?.vehicleId != offer.vehicleId)) {
          _invalidate();
          return;
        }
        _admitTrip(tripResult);
      } else {
        if (offer?.status == 'offered' &&
            (result.availability?.state != DriverAvailabilityState.reserved ||
                result.availability?.bookingId != offer!.bookingId ||
                result.availability?.vehicleId != offer.vehicleId)) {
          _invalidate();
          return;
        }
        _result = result;
        _phase = offer == null
            ? CanonicalDriverPresentationPhase.empty
            : offer.status == 'offered'
                ? CanonicalDriverPresentationPhase.offer
                : CanonicalDriverPresentationPhase.unavailable;
      }
    } else {
      _result = result;
      _phase = result.outcome == CanonicalDriverOutcome.stale
          ? CanonicalDriverPresentationPhase.stale
          : CanonicalDriverPresentationPhase.unavailable;
      if (_phase == CanonicalDriverPresentationPhase.stale) _stale = true;
    }
    tick();
    _publish();
  }

  void _admitTrip(CanonicalDriverResult result,
      {CanonicalDriverTrip? expected}) {
    if (result.outcome == CanonicalDriverOutcome.unauthorized) {
      _revoke();
      return;
    }
    final trip = result.trip, prior = _pinnedTrip ?? expected;
    if (result.outcome != CanonicalDriverOutcome.observed || trip == null) {
      if (result.outcome == CanonicalDriverOutcome.stale) _stale = true;
      _result = null;
      _phase = _stale
          ? CanonicalDriverPresentationPhase.stale
          : CanonicalDriverPresentationPhase.unavailable;
      return;
    }
    if (trip.driverId != _session.user!.id.toLowerCase() ||
        (prior != null &&
            (trip.id != prior.id ||
                trip.bookingId != prior.bookingId ||
                trip.quoteId != prior.quoteId ||
                trip.vehicleId != prior.vehicleId ||
                trip.riderId != prior.riderId ||
                trip.version < prior.version ||
                (_terminal(prior.status) && trip.status != prior.status)))) {
      _invalidate();
      return;
    }
    _pinnedTrip = trip;
    _result = result;
    _phase = CanonicalDriverPresentationPhase.trip;
  }

  void tick() {
    if (_disposed) return;
    final offer = _attempt ?? _result?.offer;
    if (offer != null &&
        !_clock().toUtc().isBefore(offer.expiresAt) &&
        _expired.add(offer.id)) {
      if (_decisionPending && _handedOff) _unknown = true;
      _publish();
    }
  }

  Future<void> decide(CanonicalDriverPresentationView displayed,
      CanonicalOfferDecision decision) async {
    if (!identical(displayed._controller, this) || !displayed.canDecide) return;
    final offer = displayed.offer;
    if (offer == null) return;
    _attempt = offer;
    _decisionPending = true;
    final generation = ++_generation;
    try {
      _publish(); // Reentrant invalidation/disconnect must win before handoff.
      if (!_readCurrent(generation) ||
          !_clock().toUtc().isBefore(offer.expiresAt)) {
        _phase = CanonicalDriverPresentationPhase.stale;
        return;
      }
      _key = _createKey();
      // The injected key generator must not revoke the lifetime then dispatch.
      if (!_readCurrent(generation)) return;
      if (!_clock().toUtc().isBefore(offer.expiresAt)) {
        _expired.add(offer.id);
        _phase = CanonicalDriverPresentationPhase.expired;
        return;
      }
      _handedOff = true;
      final result = await repository.decideOffer(offer, decision, _key!);
      if (!_authorized || _disposed) return;
      if (result.outcome == CanonicalDriverOutcome.unauthorized) {
        _revoke();
        return;
      }
      if (!_operationCurrent(generation, recovery: false)) {
        _retainUnknown();
        return;
      }
      await _resolveDecision(result, generation: generation, recovery: false);
    } on Object {
      if (_handedOff) _unknown = true;
      _result = null;
      _phase = CanonicalDriverPresentationPhase.unavailable;
    } finally {
      // Includes the final presentation reread; no ordinary refresh/recovery
      // can enter between acknowledgement and verified publication.
      _decisionPending = false;
      _publish();
    }
  }

  bool _operationCurrent(int generation, {required bool recovery}) =>
      _readCurrent(generation) &&
      (recovery ||
          (!_unknown && _clock().toUtc().isBefore(_attempt!.expiresAt)));

  void _retainUnknown() {
    _unknown = true;
    _result = null;
  }

  Future<void> _resolveDecision(CanonicalDriverResult result,
      {required int generation, required bool recovery}) async {
    if (!_operationCurrent(generation, recovery: recovery)) {
      _retainUnknown();
      return;
    }
    if (result.outcome == CanonicalDriverOutcome.accepted &&
        result.trip != null) {
      final trip = result.trip!;
      // Command reconciliation is not the final presentation read.
      final read = await repository.readTrip(trip.id);
      if (!_operationCurrent(generation, recovery: recovery)) {
        _retainUnknown();
        return;
      }
      _admitTrip(read, expected: trip);
      _unknown = _phase != CanonicalDriverPresentationPhase.trip;
    } else if (result.outcome == CanonicalDriverOutcome.declined) {
      _unknown = false;
      _result = null;
      _phase = CanonicalDriverPresentationPhase.declined;
    } else if (result.outcome == CanonicalDriverOutcome.expired) {
      _result = null;
      _phase = CanonicalDriverPresentationPhase.expired;
    } else if (result.outcome == CanonicalDriverOutcome.stale) {
      _result = null;
      _stale = true;
      _phase = CanonicalDriverPresentationPhase.stale;
    } else {
      _unknown = true;
      _result = null;
    }
  }

  Future<void> reconcile() async {
    if (!view.canReconcile) return;
    _decisionPending = true;
    final generation = ++_generation;
    try {
      _publish();
      // Notification listeners may retire and reconnect the source immediately.
      // Connectivity alone cannot revive this operation's captured generation.
      if (!_operationCurrent(generation, recovery: true)) return;
      final result = await repository.reconcile();
      if (!_authorized || _disposed) return;
      if (result.outcome == CanonicalDriverOutcome.unauthorized) {
        _revoke();
        return;
      }
      if (!_operationCurrent(generation, recovery: true)) {
        _retainUnknown();
        return;
      }
      // Only this explicit, command-correlated canonical recovery can clear it.
      if (result.outcome == CanonicalDriverOutcome.accepted ||
          result.outcome == CanonicalDriverOutcome.declined) {
        await _resolveDecision(result, generation: generation, recovery: true);
      }
    } on Object {
      _retainUnknown();
    } finally {
      _decisionPending = false;
      _publish();
    }
  }

  /// Reuses B06's unconditional stop. No repository call or state mutation.
  DriverFlowOutcome requestCompletion() => DriverFlowOutcome.unsupported;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _result = null;
    _pinnedTrip = null;
    _sessionSource.removeListener(_onSession);
    _authorityInvalidations.removeListener(_revoke);
    unawaited(_cancel());
    // Borrowed repository survives remount; never erase its uncertain intent.
    super.dispose();
  }
}

bool _terminal(DriverTripLifecycleStatus status) => const {
      DriverTripLifecycleStatus.completed,
      DriverTripLifecycleStatus.cancelledByRider,
      DriverTripLifecycleStatus.cancelledByDriver,
      DriverTripLifecycleStatus.cancelledByAdmin,
      DriverTripLifecycleStatus.failed,
    }.contains(status);
