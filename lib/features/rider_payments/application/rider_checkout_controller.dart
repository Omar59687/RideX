import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/rider_payments/application/rider_checkout_launcher.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';

/// Read-only controller for the post-assignment Rider checkout presentation.
///
/// It never dispatches a payment action. A future B02 adapter can only be
/// enabled after a separate reviewed backend/provider boundary is approved.
class RiderCheckoutController extends ChangeNotifier {
  RiderCheckoutController({
    required RiderCheckoutReader reader,
    required SessionState Function() readSession,
    RiderCheckoutLauncher launcher = const DisabledRiderCheckoutLauncher(),
    this.readDeadline = const Duration(seconds: 15),
  }) : _reader = reader,
       _readSession = readSession,
       _launcher = launcher {
    if (readDeadline <= Duration.zero) {
      throw ArgumentError.value(
        readDeadline,
        'readDeadline',
        'Must be positive.',
      );
    }
  }

  final RiderCheckoutReader _reader;
  final SessionState Function() _readSession;
  final RiderCheckoutLauncher _launcher;
  final Duration readDeadline;

  RiderCheckoutState _state = const RiderCheckoutState.unavailable();
  RiderCheckoutState get state => _state;

  Future<void>? _pending;
  Future<void>? _handoffPending;
  Object? _handoffToken;
  String? _attemptedHandoffKey;
  String? _pendingTripId;
  String? _tripId;
  SessionState? _ownerSession;
  RiderCheckoutTrip? _lastTrip;
  CardPayment? _lastPayment;
  int _generation = 0;
  int _sessionEpoch = 0;
  bool _disposed = false;

  Future<void> refresh({required String tripId}) {
    return _refresh(tripId: tripId, force: false);
  }

  Future<void> _refresh({required String tripId, required bool force}) {
    if (_disposed || !isCanonicalTripId(tripId)) {
      return Future<void>.value();
    }
    final currentSession = _readSession();
    final pending = _pending;
    if (!force &&
        pending != null &&
        _pendingTripId?.toLowerCase() == tripId.toLowerCase() &&
        identical(currentSession, _ownerSession)) {
      return pending;
    }

    final generation = ++_generation;
    final oldTripId = _tripId;
    _tripId = tripId;
    if (oldTripId?.toLowerCase() != tripId.toLowerCase()) {
      _lastTrip = null;
      _lastPayment = null;
    }
    _ownerSession = currentSession;
    _pendingTripId = tripId;
    _set(
      const RiderCheckoutState(
        trip: RiderCheckoutTripLoading(),
        payment: RiderCheckoutPaymentUnavailable(),
      ),
    );
    final operation = _load(tripId: tripId, generation: generation);
    _pending = operation.whenComplete(() {
      if (generation == _generation) {
        _pending = null;
        _pendingTripId = null;
      }
    });
    return _pending!;
  }

  /// Retries only canonical reads. It can never authorize, capture, cancel or
  /// refund a payment.
  Future<void> retry() {
    final tripId = _tripId;
    final tripFailed =
        _state.trip is RiderCheckoutTripReadError ||
        _state.trip is RiderCheckoutTripStale;
    final paymentFailed =
        _state.payment is RiderCheckoutPaymentReadError ||
        _state.payment is RiderCheckoutPaymentUnknown;
    if (tripId == null || (!tripFailed && !paymentFailed)) {
      return Future<void>.value();
    }
    return refresh(tripId: tripId);
  }

  /// Rechecks canonical Trip and Payment state before handing off to an
  /// optional checkout adapter. A callback/redirect is advisory only; after
  /// it returns, the controller reads canonical state again. One handoff is
  /// allowed per Rider/Trip/version in this session to prevent duplicate
  /// authorization attempts when a callback is repeated or ambiguous.
  Future<void> startCheckout() {
    if (_disposed) return Future<void>.value();
    final existing = _handoffPending;
    if (existing != null) return existing;
    final trip = _state.trip;
    if (trip is! RiderCheckoutTripEligible ||
        _state.payment is! RiderCheckoutActionRequired) {
      return Future<void>.value();
    }
    final owner = _readSession();
    final riderId = _authenticatedRiderId(owner);
    if (riderId == null || !identical(owner, _ownerSession)) {
      return Future<void>.value();
    }
    final key =
        '${riderId.toLowerCase()}:${trip.trip.tripId.toLowerCase()}:'
        '${trip.trip.version}';
    if (_attemptedHandoffKey == key) return Future<void>.value();
    final generation = _generation;
    final sessionEpoch = _sessionEpoch;
    final token = Object();
    _handoffToken = token;
    final operation = _launchAndReconcile(
      trip: trip.trip,
      key: key,
      owner: owner,
      generation: generation,
      sessionEpoch: sessionEpoch,
    );
    _handoffPending = operation.whenComplete(() {
      if (identical(_handoffToken, token)) {
        _handoffPending = null;
        _handoffToken = null;
      }
    });
    return _handoffPending!;
  }

  /// Reconciliation hook for app foreground/resume. It never relaunches
  /// checkout and never treats the return signal as canonical payment state.
  Future<void> onAppResumed() {
    final tripId = _tripId;
    if (tripId == null || _disposed) return Future<void>.value();
    return refresh(tripId: tripId);
  }

  Future<void> _launchAndReconcile({
    required RiderCheckoutTrip trip,
    required String key,
    required SessionState owner,
    required int generation,
    required int sessionEpoch,
  }) async {
    if (_sessionEpoch != sessionEpoch || !_isCurrent(generation, owner)) return;
    // Confirm fresh Trip and Payment state immediately before external UI.
    final canonicalRead = refresh(tripId: trip.tripId);
    final preflightGeneration = _generation;
    await canonicalRead;
    if (_sessionEpoch != sessionEpoch ||
        preflightGeneration != _generation ||
        !_isCurrent(_generation, owner) ||
        _state.trip is! RiderCheckoutTripEligible ||
        _state.payment is! RiderCheckoutActionRequired) {
      return;
    }
    final tripState = _state.trip;
    if (tripState is! RiderCheckoutTripEligible) return;
    final freshTrip = tripState.trip;
    if (freshTrip.version != trip.version ||
        freshTrip.tripId.toLowerCase() != trip.tripId.toLowerCase()) {
      return;
    }
    final freshRiderId = _authenticatedRiderId(owner);
    if (freshRiderId == null) return;
    final freshKey =
        '${freshRiderId.toLowerCase()}:'
        '${freshTrip.tripId.toLowerCase()}:${freshTrip.version}';
    if (freshKey != key || _attemptedHandoffKey == freshKey) return;
    _attemptedHandoffKey = freshKey;

    try {
      await _launcher.launch(
        RiderCheckoutLaunchRequest(
          tripId: freshTrip.tripId,
          expectedTripVersion: freshTrip.version,
        ),
      );
    } on Object {
      // The provider outcome is uncertain. Reconciliation below is the only
      // route to a payment state; it does not permit a second handoff.
    }
    if (_sessionEpoch == sessionEpoch &&
        identical(_readSession(), owner) &&
        _authenticatedRiderId(owner) != null &&
        _tripId?.toLowerCase() == freshTrip.tripId.toLowerCase()) {
      // Always reread after the adapter returns. An app-resume read may have
      // completed while the provider UI was still open and is too early to
      // reconcile the eventual return signal.
      await _refresh(tripId: freshTrip.tripId, force: true);
    }
  }

  /// Invalidates all data and fences late reads after logout, account change,
  /// profile refresh, or SDK session replacement. The owner calls this from
  /// its feature-local session listener.
  void sessionChanged() {
    if (_disposed) return;
    _sessionEpoch++;
    _generation++;
    _pending = null;
    _pendingTripId = null;
    _handoffPending = null;
    _handoffToken = null;
    _attemptedHandoffKey = null;
    _ownerSession = null;
    _tripId = null;
    _lastTrip = null;
    _lastPayment = null;
    _set(const RiderCheckoutState.unavailable());
  }

  Future<void> _load({required String tripId, required int generation}) async {
    final owner = _ownerSession;
    final riderId = _authenticatedRiderId(owner);
    if (owner == null || riderId == null) {
      // _isCurrent intentionally rejects invalid actors, so it cannot be
      // used to clear Loading for a blocked or unauthenticated Rider.
      if (!_disposed &&
          generation == _generation &&
          identical(_readSession(), owner)) {
        _set(const RiderCheckoutState.unavailable());
      }
      return;
    }

    final RiderCheckoutTrip? trip;
    try {
      trip = await _reader.readTrip(tripId: tripId).timeout(readDeadline);
    } on RiderCheckoutTripReadException catch (error) {
      if (!_isCurrent(generation, owner)) return;
      _set(
        RiderCheckoutState(
          trip: RiderCheckoutTripReadError(error.failure),
          payment: const RiderCheckoutPaymentUnavailable(),
        ),
      );
      return;
    } on Object {
      if (!_isCurrent(generation, owner)) return;
      _set(
        const RiderCheckoutState(
          trip: RiderCheckoutTripReadError(
            RiderCheckoutTripReadFailure.unavailable,
          ),
          payment: RiderCheckoutPaymentUnavailable(),
        ),
      );
      return;
    }
    if (!_isCurrent(generation, owner)) return;
    if (trip == null ||
        trip.tripId.toLowerCase() != tripId.toLowerCase() ||
        trip.riderId.toLowerCase() != riderId.toLowerCase()) {
      _set(
        const RiderCheckoutState(
          trip: RiderCheckoutTripUnavailable(),
          payment: RiderCheckoutPaymentUnavailable(),
        ),
      );
      return;
    }

    final previous = _lastTrip;
    if (previous != null &&
        previous.tripId.toLowerCase() == trip.tripId.toLowerCase() &&
        (trip.version < previous.version ||
            (trip.version == previous.version &&
                (trip.status != previous.status ||
                    trip.bookingRequestId.toLowerCase() !=
                        previous.bookingRequestId.toLowerCase() ||
                    trip.riderId.toLowerCase() !=
                        previous.riderId.toLowerCase() ||
                    trip.driverId.toLowerCase() !=
                        previous.driverId.toLowerCase() ||
                    trip.paymentMethod != previous.paymentMethod)))) {
      _set(
        const RiderCheckoutState(
          trip: RiderCheckoutTripStale(),
          payment: RiderCheckoutPaymentUnavailable(),
        ),
      );
      return;
    }
    _lastTrip = trip;

    if (trip.isTerminal) {
      _set(
        RiderCheckoutState(
          trip: RiderCheckoutTripTerminal(trip),
          payment: const RiderCheckoutPaymentUnavailable(),
        ),
      );
      return;
    }
    if (trip.paymentMethod != PaymentMethod.card ||
        !isCanonicalTripId(trip.driverId) ||
        !trip.isEligibleAssignedCardTrip) {
      _set(
        const RiderCheckoutState(
          trip: RiderCheckoutTripIneligible(),
          payment: RiderCheckoutPaymentUnavailable(),
        ),
      );
      return;
    }

    _set(
      RiderCheckoutState(
        trip: RiderCheckoutTripEligible(trip),
        payment: const RiderCheckoutPaymentLoading(),
      ),
    );

    try {
      final payment = await _reader
          .readCardPayment(tripId: trip.tripId)
          .timeout(readDeadline);
      if (!_isCurrent(generation, owner)) return;
      if (payment == null) {
        _set(
          RiderCheckoutState(
            trip: RiderCheckoutTripEligible(trip),
            payment: const RiderCheckoutActionRequired(),
          ),
        );
        return;
      }
      if (payment.paymentId?.trim().isNotEmpty != true ||
          payment.tripId?.toLowerCase() != trip.tripId.toLowerCase() ||
          payment.bookingRequestId?.toLowerCase() !=
              trip.bookingRequestId.toLowerCase()) {
        _set(
          RiderCheckoutState(
            trip: RiderCheckoutTripEligible(trip),
            payment: const RiderCheckoutPaymentUnknown(),
          ),
        );
        return;
      }
      final previousPayment = _lastPayment;
      if (previousPayment != null &&
          (payment.version < previousPayment.version ||
              (payment.version == previousPayment.version &&
                  payment != previousPayment))) {
        _set(
          RiderCheckoutState(
            trip: RiderCheckoutTripEligible(trip),
            payment: const RiderCheckoutPaymentUnknown(),
          ),
        );
        return;
      }
      _lastPayment = payment;
      _set(
        RiderCheckoutState(
          trip: RiderCheckoutTripEligible(trip),
          payment: riderCheckoutPaymentState(payment),
        ),
      );
    } on RiderCheckoutPaymentReadException catch (error) {
      if (!_isCurrent(generation, owner)) return;
      if (error.failure == RiderCheckoutPaymentReadFailure.unauthorized) {
        _set(const RiderCheckoutState.unavailable());
      } else if (error.failure ==
          RiderCheckoutPaymentReadFailure.unknownOutcome) {
        _set(
          RiderCheckoutState(
            trip: RiderCheckoutTripEligible(trip),
            payment: const RiderCheckoutPaymentUnknown(),
          ),
        );
      } else {
        _set(
          RiderCheckoutState(
            trip: RiderCheckoutTripEligible(trip),
            payment: RiderCheckoutPaymentReadError(error.failure),
          ),
        );
      }
    } on Object {
      if (!_isCurrent(generation, owner)) return;
      _set(
        RiderCheckoutState(
          trip: RiderCheckoutTripEligible(trip),
          payment: const RiderCheckoutPaymentReadError(
            RiderCheckoutPaymentReadFailure.unavailable,
          ),
        ),
      );
    }
  }

  bool _isCurrent(int generation, SessionState? owner) =>
      !_disposed &&
      generation == _generation &&
      owner != null &&
      identical(_readSession(), owner) &&
      _authenticatedRiderId(owner) != null;

  String? _authenticatedRiderId(SessionState? session) {
    final user = session?.user;
    if (session?.status != SessionStatus.authenticated ||
        session?.role != RideRole.rider ||
        user == null ||
        user.isBlocked ||
        !isCanonicalTripId(user.id)) {
      return null;
    }
    return user.id;
  }

  void _set(RiderCheckoutState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionEpoch++;
    _generation++;
    _pending = null;
    _handoffPending = null;
    _handoffToken = null;
    _attemptedHandoffKey = null;
    _ownerSession = null;
    _lastTrip = null;
    _lastPayment = null;
    super.dispose();
  }
}
