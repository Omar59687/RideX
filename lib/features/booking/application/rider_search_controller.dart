import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_assigned_trip.dart';
import 'package:ridex/core/models/rider_booking_cancellation.dart';
import 'package:ridex/core/models/rider_booking_search.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/rider_booking_search_repository.dart';
import 'package:ridex/core/repositories/rider_trip_tracking_repository.dart';
import 'package:ridex/core/services/rider_cancellation/rider_cancellation_coordinator.dart';

enum RiderSearchPhase {
  loading,
  waiting,
  searching,
  timedOut,
  unresolved,
  unavailable,
  expired,
  failed,
  cancelled,
  assignmentPending,
}

/// Read-only outcome of verifying the assigned Trip behind a matched booking.
///
/// The Trip version is never compared with the BookingRequest version.
enum RiderAssignmentVerification {
  notRequested,
  loading,
  verified,
  unverified,
  unavailable,
  invalid,
}

class RiderSearchViewState {
  const RiderSearchViewState(
    this.phase, {
    this.booking,
    this.cancellation = RiderCancellationPhase.idle,
    this.rejection,
    this.assignment = RiderAssignmentVerification.notRequested,
  });

  final RiderSearchPhase phase;
  final RiderBookingSearchSnapshot? booking;

  /// Cancellation uncertainty is kept separate from ordinary read failure.
  final RiderCancellationPhase cancellation;
  final RiderCancellationRejection? rejection;
  final RiderAssignmentVerification assignment;
}

/// Read-only state for one BookingRequest and one immutable session epoch.
/// Recreate it after a session change; it never initiates a new booking.
class RiderSearchController extends ChangeNotifier {
  RiderSearchController({
    required this.bookingRequestId,
    required RiderBookingSearchRepository repository,
    required RiderCancellationCoordinator cancellationCoordinator,
    required SessionState Function() readSession,
    RiderTripTrackingRepository? tripTrackingRepository,
    Duration softTimeout = const Duration(seconds: 90),
    Duration readDeadline = const Duration(seconds: 15),
    Timer Function(Duration, void Function())? scheduleTimeout,
    Timer Function(Duration, void Function())? scheduleReadDeadline,
  })  : _repository = repository,
        _cancellationCoordinator = cancellationCoordinator,
        _tripRepository = tripTrackingRepository,
        _readSession = readSession,
        _ownerSession = readSession(),
        _softTimeout = softTimeout,
        _readDeadline = readDeadline,
        _scheduleTimeout = scheduleTimeout ?? Timer.new,
        _scheduleReadDeadline = scheduleReadDeadline ?? Timer.new {
    if (softTimeout <= Duration.zero) {
      throw ArgumentError.value(
          softTimeout, 'softTimeout', 'Must be positive.');
    }
    if (readDeadline <= Duration.zero) {
      throw ArgumentError.value(
          readDeadline, 'readDeadline', 'Must be positive.');
    }
    _cancellationCoordinator.addListener(_onCancellationChanged);
    _listeningToCancellation = true;
    _onCancellationChanged();
  }

  final String bookingRequestId;
  final RiderBookingSearchRepository _repository;
  final RiderCancellationCoordinator _cancellationCoordinator;
  final RiderTripTrackingRepository? _tripRepository;
  final SessionState Function() _readSession;
  final SessionState _ownerSession;
  final Duration _softTimeout;
  final Duration _readDeadline;
  final Timer Function(Duration, void Function()) _scheduleTimeout;
  final Timer Function(Duration, void Function()) _scheduleReadDeadline;

  RiderSearchViewState _state =
      const RiderSearchViewState(RiderSearchPhase.loading);
  RiderSearchViewState get state => _state;

  Future<void>? _pending;
  Timer? _timeout;
  Timer? _readTimer;
  Completer<RiderBookingSearchSnapshot?>? _abortRead;
  Timer? _assignmentTimer;
  Completer<_AssignmentOutcome>? _abortAssignment;
  RiderBookingSearchSnapshot? _lastVerified;
  RiderAssignedTrip? _lastVerifiedTrip;
  RiderCancellationRejection? _clientRejection;
  bool _acceptedContradiction = false;
  RiderAssignmentVerification _assignment =
      RiderAssignmentVerification.notRequested;
  int _generation = 0;
  bool _disposed = false;
  bool _sessionInvalidated = false;
  bool _listeningToCancellation = false;
  bool get isSessionInvalidated => _sessionInvalidated;

  RiderCancellationAttempt? get _attempt {
    if (_disposed || _sessionInvalidated) return null;
    final riderId = _ownerSession.user?.id;
    if (riderId == null) return null;
    return _cancellationCoordinator.attemptFor(
      riderId: riderId,
      bookingRequestId: bookingRequestId,
    );
  }

  RiderCancellationPhase get _cancellation {
    if (_clientRejection != null) return RiderCancellationPhase.rejected;
    if (_acceptedContradiction) return RiderCancellationPhase.uncertain;
    return switch (_attempt?.phase) {
      RiderCancellationAttemptPhase.pending =>
        RiderCancellationPhase.cancelling,
      RiderCancellationAttemptPhase.accepted ||
      RiderCancellationAttemptPhase.verifiedCancelled =>
        RiderCancellationPhase.idle,
      RiderCancellationAttemptPhase.rejected => RiderCancellationPhase.rejected,
      RiderCancellationAttemptPhase.uncertain =>
        RiderCancellationPhase.uncertain,
      null => RiderCancellationPhase.idle,
    };
  }

  RiderCancellationRejection? get _rejection =>
      _clientRejection ?? _attempt?.rejection;

  bool get canRetry =>
      !_disposed &&
      !_sessionInvalidated &&
      _attempt?.phase != RiderCancellationAttemptPhase.pending &&
      _state.phase != RiderSearchPhase.loading &&
      _validRiderSession(_ownerSession) &&
      identical(_readSession(), _ownerSession) &&
      isCanonicalTripId(bookingRequestId);

  /// Authorizes only the single cancellation retained after the last verified
  /// read; an uncertain outcome permanently blocks a second dispatch.
  bool get canCancel {
    if (_disposed || _sessionInvalidated || _pending != null) return false;
    if (_clientRejection != null || _acceptedContradiction) return false;
    final attempt = _attempt;
    if (attempt != null &&
        attempt.phase != RiderCancellationAttemptPhase.rejected) {
      return false;
    }
    if (attempt != null &&
        attempt.rejection != RiderCancellationRejection.staleVersion) {
      return false;
    }
    if (!_validRiderSession(_ownerSession) ||
        !identical(_readSession(), _ownerSession) ||
        !isCanonicalTripId(bookingRequestId)) {
      return false;
    }
    final booking = _state.booking;
    if (booking == null ||
        booking.bookingRequestId.toLowerCase() !=
            bookingRequestId.toLowerCase() ||
        booking.riderId.toLowerCase() != _ownerSession.user!.id.toLowerCase() ||
        booking.paymentMethod != PaymentMethod.cash) {
      return false;
    }
    if (attempt != null && booking.version <= attempt.expectedVersion) {
      return false;
    }
    return isCancellableBookingStatus(booking.status);
  }

  /// Rechecks the *same* booking. Repeated calls share one in-flight read.
  Future<void> refresh() {
    if (_disposed ||
        _sessionInvalidated ||
        _attempt?.phase == RiderCancellationAttemptPhase.pending) {
      return Future<void>.value();
    }
    return _requestRefresh();
  }

  Future<void> _requestRefresh() {
    if (_disposed || _sessionInvalidated) return Future<void>.value();
    final pending = _pending;
    if (pending != null) return pending;
    final operation = Future<void>.microtask(_load);
    return _pending = operation.whenComplete(() => _pending = null);
  }

  /// Dispatches at most one cancellation for the last verified snapshot.
  ///
  /// A successful result is re-validated before it can enter the cancelled
  /// phase. A rejected attempt is never replayed automatically. An unknown
  /// outcome blocks every later dispatch in this session epoch, even after a
  /// successful status reread.
  Future<void> cancelBooking({required String reasonCode}) {
    if (_disposed || _sessionInvalidated) return Future<void>.value();
    final riderId = _ownerSession.user?.id;
    if (riderId == null) return Future<void>.value();
    final attempt = _attempt;
    if (attempt?.phase == RiderCancellationAttemptPhase.pending) {
      return _cancellationCoordinator.cancel(
        riderId: riderId,
        bookingRequestId: bookingRequestId,
        expectedVersion: attempt!.expectedVersion,
        observedStatus: attempt.observedStatus,
        reasonCode: reasonCode,
      );
    }
    if (_pending != null || !canCancel) return Future<void>.value();
    final reason = reasonCode.trim();
    if (!isValidCancellationReason(reason)) {
      _clientRejection = RiderCancellationRejection.reasonInvalid;
      _set(_currentView(_state.phase, booking: _state.booking));
      return Future<void>.value();
    }
    final booking = _state.booking!;
    if (!isCancellableBookingStatus(booking.status)) {
      return Future<void>.value();
    }
    _timeout?.cancel();
    _timeout = null;
    return _cancellationCoordinator.cancel(
      riderId: riderId,
      bookingRequestId: bookingRequestId,
      expectedVersion: booking.version,
      observedStatus: booking.status,
      reasonCode: reason,
    );
  }

  /// An old controller never starts reading on behalf of a new session.
  void sessionChanged(SessionState next) {
    if (_disposed || identical(next, _ownerSession)) return;
    invalidate();
  }

  /// Retires the session epoch, including in-flight work and every timer.
  void invalidate() {
    if (_disposed || _sessionInvalidated) return;
    _sessionInvalidated = true;
    _generation++;
    _timeout?.cancel();
    _timeout = null;
    _abandonRead();
    _abandonAssignment();
    _lastVerified = null;
    _lastVerifiedTrip = null;
    _clientRejection = null;
    _acceptedContradiction = false;
    _assignment = RiderAssignmentVerification.notRequested;
    _detachCancellationListener();
    _set(_currentView(RiderSearchPhase.unresolved));
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _timeout?.cancel();
    _timeout = null;
    if (!_isCurrent(generation) ||
        !_validRiderSession(_ownerSession) ||
        !isCanonicalTripId(bookingRequestId)) {
      _set(_currentView(RiderSearchPhase.unresolved));
      return;
    }
    _set(_currentView(RiderSearchPhase.loading));
    try {
      final booking = await _readWithDeadline();
      if (!_isCurrent(generation)) return;
      if (booking == null ||
          booking.bookingRequestId.toLowerCase() !=
              bookingRequestId.toLowerCase() ||
          booking.riderId.toLowerCase() !=
              _ownerSession.user!.id.toLowerCase()) {
        _set(_currentView(RiderSearchPhase.unresolved));
        return;
      }
      final previous = _lastVerified;
      if (previous != null &&
          (booking.version < previous.version ||
              (booking.version == previous.version &&
                  booking.status != previous.status) ||
              (booking.version > previous.version &&
                  !_canFollow(previous.status, booking.status)))) {
        _set(_currentView(RiderSearchPhase.unresolved));
        return;
      }
      _lastVerified = booking;
      if (booking.status == RiderBookingSearchStatus.cancelled) {
        _clientRejection = null;
        _acceptedContradiction = false;
      }
      if (booking.status != RiderBookingSearchStatus.matched) {
        _assignment = RiderAssignmentVerification.notRequested;
        _lastVerifiedTrip = null;
        _abandonAssignment();
      }
      final phase = switch (booking.status) {
        RiderBookingSearchStatus.confirmed => RiderSearchPhase.waiting,
        RiderBookingSearchStatus.searching => RiderSearchPhase.searching,
        RiderBookingSearchStatus.matched => RiderSearchPhase.assignmentPending,
        RiderBookingSearchStatus.cancelled => RiderSearchPhase.cancelled,
        RiderBookingSearchStatus.expired => RiderSearchPhase.expired,
        RiderBookingSearchStatus.failed => RiderSearchPhase.failed,
        RiderBookingSearchStatus.draft => RiderSearchPhase.unresolved,
      };
      _set(_currentView(phase, booking: booking));
      if (booking.status == RiderBookingSearchStatus.cancelled) {
        _cancellationCoordinator.reconcileTerminalBooking(
          riderId: _ownerSession.user!.id,
          bookingRequestId: bookingRequestId,
          booking: booking,
        );
      }
      if (_isCurrent(generation) &&
          (phase == RiderSearchPhase.waiting ||
              phase == RiderSearchPhase.searching)) {
        _timeout = _scheduleTimeout(_softTimeout, () {
          if (_isCurrent(generation) &&
              (_state.phase == RiderSearchPhase.waiting ||
                  _state.phase == RiderSearchPhase.searching)) {
            _set(_currentView(
              RiderSearchPhase.timedOut,
              booking: booking,
            ));
          }
        });
      }
      if (_isCurrent(generation) &&
          phase == RiderSearchPhase.assignmentPending &&
          _tripRepository != null) {
        unawaited(_verifyAssignment(generation, _tripRepository));
      }
    } on RiderBookingSearchReadException catch (error) {
      if (!_isCurrent(generation)) return;
      _set(_currentView(
        error.failure == RiderBookingSearchReadFailure.invalidResponse
            ? RiderSearchPhase.unresolved
            : RiderSearchPhase.unavailable,
      ));
    } on Object {
      if (_isCurrent(generation)) {
        _set(_currentView(RiderSearchPhase.unavailable));
      }
    }
  }

  void _onCancellationChanged() {
    if (_disposed ||
        _sessionInvalidated ||
        !_validRiderSession(_ownerSession)) {
      return;
    }
    final attempt = _attempt;
    if (attempt == null) {
      _set(_currentView(_state.phase, booking: _state.booking));
      return;
    }
    switch (attempt.phase) {
      case RiderCancellationAttemptPhase.pending:
      case RiderCancellationAttemptPhase.uncertain:
        _set(_currentView(_state.phase, booking: _state.booking));
      case RiderCancellationAttemptPhase.accepted:
      case RiderCancellationAttemptPhase.verifiedCancelled:
        final booking = attempt.acceptedBooking;
        if (booking == null) {
          _acceptedContradiction = true;
          _set(_currentView(_state.phase, booking: _state.booking));
        } else {
          _applyAcceptedCancellation(booking);
        }
      case RiderCancellationAttemptPhase.rejected:
        _set(_currentView(_state.phase, booking: _state.booking));
        final rejection = attempt.rejection;
        if (rejection == RiderCancellationRejection.staleVersion ||
            rejection == RiderCancellationRejection.notCancellable) {
          unawaited(_requestRefresh());
        }
    }
    // A recreated controller has no booking yet. If the retained attempt has
    // finished, read this same booking so the screen cannot remain stuck in
    // loading with its retry control disabled.
    if (attempt.phase != RiderCancellationAttemptPhase.pending &&
        _state.booking == null &&
        _state.phase == RiderSearchPhase.loading) {
      unawaited(_requestRefresh());
    }
  }

  void _applyAcceptedCancellation(RiderBookingSearchSnapshot snapshot) {
    final owner = _ownerSession.user;
    final previous = _lastVerified;
    final sameCancelled = previous != null &&
        previous.status == RiderBookingSearchStatus.cancelled &&
        previous.version == snapshot.version &&
        previous.bookingRequestId.toLowerCase() ==
            snapshot.bookingRequestId.toLowerCase() &&
        previous.riderId.toLowerCase() == snapshot.riderId.toLowerCase() &&
        previous.paymentMethod == snapshot.paymentMethod;
    final valid = owner != null &&
        snapshot.bookingRequestId.toLowerCase() ==
            bookingRequestId.toLowerCase() &&
        snapshot.riderId.toLowerCase() == owner.id.toLowerCase() &&
        snapshot.status == RiderBookingSearchStatus.cancelled &&
        snapshot.paymentMethod == PaymentMethod.cash &&
        (previous == null ||
            sameCancelled ||
            (snapshot.version > previous.version &&
                _canFollow(previous.status, snapshot.status)));
    if (!valid) {
      _acceptedContradiction = true;
      _set(_currentView(_state.phase, booking: _state.booking));
      return;
    }
    if (sameCancelled) {
      _acceptedContradiction = false;
      if (_state.cancellation != RiderCancellationPhase.idle) {
        _set(_currentView(_state.phase, booking: _state.booking));
      }
      return;
    }
    _generation++;
    _timeout?.cancel();
    _timeout = null;
    _abandonRead();
    _lastVerified = snapshot;
    _lastVerifiedTrip = null;
    _clientRejection = null;
    _acceptedContradiction = false;
    _assignment = RiderAssignmentVerification.notRequested;
    _abandonAssignment();
    _set(_currentView(RiderSearchPhase.cancelled, booking: snapshot));
  }

  Future<void> _verifyAssignment(
    int generation,
    RiderTripTrackingRepository repository,
  ) {
    if (_disposed || _sessionInvalidated) return Future<void>.value();
    _abandonAssignment();
    _setAssignment(RiderAssignmentVerification.loading);
    return _performAssignment(generation, repository);
  }

  Future<void> _performAssignment(
    int generation,
    RiderTripTrackingRepository repository,
  ) async {
    final outcome = await _readAssignmentWithDeadline(repository);
    if (!_isCurrentAssignment(generation)) return;
    switch (outcome.kind) {
      case _AssignmentOutcomeKind.timedOut:
      case _AssignmentOutcomeKind.unavailable:
        _setAssignment(RiderAssignmentVerification.unavailable);
      case _AssignmentOutcomeKind.absent:
        _setAssignment(RiderAssignmentVerification.unverified);
      case _AssignmentOutcomeKind.trip:
        final trip = outcome.trip;
        final ownerId = _ownerSession.user?.id.toLowerCase();
        final previous = _lastVerifiedTrip;
        final identityValid = trip != null &&
            ownerId != null &&
            trip.bookingRequestId.toLowerCase() ==
                bookingRequestId.toLowerCase() &&
            trip.riderId.toLowerCase() == ownerId &&
            trip.paymentMethod == PaymentMethod.cash;
        final regressed = identityValid &&
            previous != null &&
            (trip.tripId.toLowerCase() != previous.tripId.toLowerCase() ||
                trip.version < previous.version);
        final valid = identityValid && !regressed;
        if (valid) _lastVerifiedTrip = trip;
        _setAssignment(
          valid
              ? RiderAssignmentVerification.verified
              : RiderAssignmentVerification.invalid,
        );
    }
  }

  Future<RiderBookingSearchSnapshot?> _readWithDeadline() async {
    final abort = Completer<RiderBookingSearchSnapshot?>();
    _abortRead = abort;
    Timer? timer;
    try {
      timer = _scheduleReadDeadline(_readDeadline, () {
        if (!abort.isCompleted) {
          abort.completeError(const RiderBookingSearchReadException(
            RiderBookingSearchReadFailure.unavailable,
          ));
        }
      });
      _readTimer = timer;
      // Future.any observes late failures from the abandoned read as well.
      return await Future.any([
        _repository.readBooking(bookingRequestId: bookingRequestId),
        abort.future,
      ]);
    } finally {
      timer?.cancel();
      if (identical(_abortRead, abort)) {
        _abortRead = null;
        _readTimer = null;
      }
    }
  }

  Future<_AssignmentOutcome> _readAssignmentWithDeadline(
    RiderTripTrackingRepository repository,
  ) async {
    final abort = Completer<_AssignmentOutcome>();
    _abortAssignment = abort;
    Timer? timer;
    try {
      timer = _scheduleReadDeadline(_readDeadline, () {
        if (!abort.isCompleted) {
          abort.complete(const _AssignmentOutcome.timedOut());
        }
      });
      _assignmentTimer = timer;
      return await Future.any([
        _safeFindByBooking(repository),
        abort.future,
      ]);
    } finally {
      timer?.cancel();
      if (identical(_abortAssignment, abort)) {
        _abortAssignment = null;
        _assignmentTimer = null;
      }
    }
  }

  Future<_AssignmentOutcome> _safeFindByBooking(
    RiderTripTrackingRepository repository,
  ) async {
    try {
      final trip = await repository.findByBooking(
        bookingRequestId: bookingRequestId,
      );
      return trip == null
          ? const _AssignmentOutcome.absent()
          : _AssignmentOutcome.trip(trip);
    } on Object {
      return const _AssignmentOutcome.unavailable();
    }
  }

  void _abandonRead() {
    _readTimer?.cancel();
    _readTimer = null;
    final abort = _abortRead;
    if (abort != null && !abort.isCompleted) abort.complete(null);
    _abortRead = null;
  }

  void _detachCancellationListener() {
    if (!_listeningToCancellation) return;
    _cancellationCoordinator.removeListener(_onCancellationChanged);
    _listeningToCancellation = false;
  }

  void _abandonAssignment() {
    _assignmentTimer?.cancel();
    _assignmentTimer = null;
    final abort = _abortAssignment;
    if (abort != null && !abort.isCompleted) {
      abort.complete(const _AssignmentOutcome.timedOut());
    }
    _abortAssignment = null;
  }

  bool _isCurrent(int generation) =>
      !_disposed &&
      !_sessionInvalidated &&
      generation == _generation &&
      identical(_readSession(), _ownerSession) &&
      _validRiderSession(_ownerSession);

  bool _isCurrentAssignment(int generation) =>
      _isCurrent(generation) &&
      _state.phase == RiderSearchPhase.assignmentPending &&
      _state.booking?.status == RiderBookingSearchStatus.matched &&
      _state.booking?.bookingRequestId.toLowerCase() ==
          bookingRequestId.toLowerCase();

  bool _validRiderSession(SessionState session) =>
      session.status == SessionStatus.authenticated &&
      session.role == RideRole.rider &&
      session.user != null &&
      !session.user!.isBlocked &&
      isCanonicalTripId(session.user!.id);

  RiderSearchViewState _currentView(
    RiderSearchPhase phase, {
    RiderBookingSearchSnapshot? booking,
  }) =>
      RiderSearchViewState(
        phase,
        booking: booking,
        cancellation: _cancellation,
        rejection: _rejection,
        assignment: _assignment,
      );

  void _setAssignment(RiderAssignmentVerification assignment) {
    if (_disposed) return;
    _assignment = assignment;
    _set(_currentView(_state.phase, booking: _state.booking));
  }

  void _set(RiderSearchViewState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timeout?.cancel();
    _timeout = null;
    _abandonRead();
    _abandonAssignment();
    _detachCancellationListener();
    super.dispose();
  }
}

/// Reachability in migration 007's `enforce_booking_request_transition`.
/// Intermediate versions may be missed, but terminal bookings never reopen.
bool _canFollow(
    RiderBookingSearchStatus previous, RiderBookingSearchStatus next) {
  if (previous == next) return true;
  return switch (previous) {
    RiderBookingSearchStatus.draft => true,
    RiderBookingSearchStatus.confirmed =>
      next != RiderBookingSearchStatus.draft,
    RiderBookingSearchStatus.searching =>
      next == RiderBookingSearchStatus.matched ||
          next == RiderBookingSearchStatus.cancelled ||
          next == RiderBookingSearchStatus.expired ||
          next == RiderBookingSearchStatus.failed,
    RiderBookingSearchStatus.matched ||
    RiderBookingSearchStatus.cancelled ||
    RiderBookingSearchStatus.expired ||
    RiderBookingSearchStatus.failed =>
      false,
  };
}

enum _AssignmentOutcomeKind { trip, absent, unavailable, timedOut }

class _AssignmentOutcome {
  const _AssignmentOutcome.absent()
      : kind = _AssignmentOutcomeKind.absent,
        trip = null;

  const _AssignmentOutcome.unavailable()
      : kind = _AssignmentOutcomeKind.unavailable,
        trip = null;

  const _AssignmentOutcome.timedOut()
      : kind = _AssignmentOutcomeKind.timedOut,
        trip = null;

  const _AssignmentOutcome.trip(RiderAssignedTrip this.trip)
      : kind = _AssignmentOutcomeKind.trip;

  final _AssignmentOutcomeKind kind;
  final RiderAssignedTrip? trip;
}
