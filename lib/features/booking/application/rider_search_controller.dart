import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_booking_search.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/rider_booking_search_repository.dart';

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

class RiderSearchViewState {
  const RiderSearchViewState(this.phase, {this.booking});

  final RiderSearchPhase phase;
  final RiderBookingSearchSnapshot? booking;
}

/// Read-only state for one BookingRequest and one immutable session epoch.
/// Recreate it after a session change; it never initiates a new booking.
class RiderSearchController extends ChangeNotifier {
  RiderSearchController({
    required this.bookingRequestId,
    required RiderBookingSearchRepository repository,
    required SessionState Function() readSession,
    Duration softTimeout = const Duration(seconds: 90),
    Duration readDeadline = const Duration(seconds: 15),
    Timer Function(Duration, void Function())? scheduleTimeout,
    Timer Function(Duration, void Function())? scheduleReadDeadline,
  })  : _repository = repository,
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
  }

  final String bookingRequestId;
  final RiderBookingSearchRepository _repository;
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
  RiderBookingSearchSnapshot? _lastVerified;
  int _generation = 0;
  bool _disposed = false;
  bool _sessionInvalidated = false;
  bool get isSessionInvalidated => _sessionInvalidated;
  bool get canRetry =>
      !_disposed &&
      !_sessionInvalidated &&
      _state.phase != RiderSearchPhase.loading &&
      _validRiderSession(_ownerSession) &&
      identical(_readSession(), _ownerSession) &&
      isCanonicalTripId(bookingRequestId);

  /// Rechecks the *same* booking. Repeated calls share one in-flight read.
  Future<void> refresh() {
    if (_disposed || _sessionInvalidated) return Future<void>.value();
    final pending = _pending;
    if (pending != null) return pending;
    final operation = Future<void>.microtask(_load);
    return _pending = operation.whenComplete(() => _pending = null);
  }

  /// An old controller never starts reading on behalf of a new session.
  void sessionChanged(SessionState next) {
    if (_disposed || identical(next, _ownerSession)) return;
    invalidate();
  }

  /// Retires the session epoch, including an in-flight read and both timers.
  void invalidate() {
    if (_disposed || _sessionInvalidated) return;
    _sessionInvalidated = true;
    _generation++;
    _timeout?.cancel();
    _abandonRead();
    _lastVerified = null;
    _set(const RiderSearchViewState(RiderSearchPhase.unresolved));
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _timeout?.cancel();
    if (!_isCurrent(generation) ||
        !_validRiderSession(_ownerSession) ||
        !isCanonicalTripId(bookingRequestId)) {
      _set(const RiderSearchViewState(RiderSearchPhase.unresolved));
      return;
    }
    _set(const RiderSearchViewState(RiderSearchPhase.loading));
    try {
      final booking = await _readWithDeadline();
      if (!_isCurrent(generation)) return;
      if (booking == null ||
          booking.bookingRequestId.toLowerCase() !=
              bookingRequestId.toLowerCase() ||
          booking.riderId.toLowerCase() !=
              _ownerSession.user!.id.toLowerCase()) {
        _set(const RiderSearchViewState(RiderSearchPhase.unresolved));
        return;
      }
      final previous = _lastVerified;
      if (previous != null &&
          (booking.version < previous.version ||
              (booking.version == previous.version &&
                  booking.status != previous.status) ||
              (booking.version > previous.version &&
                  !_canFollow(previous.status, booking.status)))) {
        _set(const RiderSearchViewState(RiderSearchPhase.unresolved));
        return;
      }
      _lastVerified = booking;
      final phase = switch (booking.status) {
        RiderBookingSearchStatus.confirmed => RiderSearchPhase.waiting,
        RiderBookingSearchStatus.searching => RiderSearchPhase.searching,
        RiderBookingSearchStatus.matched => RiderSearchPhase.assignmentPending,
        RiderBookingSearchStatus.cancelled => RiderSearchPhase.cancelled,
        RiderBookingSearchStatus.expired => RiderSearchPhase.expired,
        RiderBookingSearchStatus.failed => RiderSearchPhase.failed,
        RiderBookingSearchStatus.draft => RiderSearchPhase.unresolved,
      };
      _set(RiderSearchViewState(phase, booking: booking));
      if (_isCurrent(generation) &&
          (phase == RiderSearchPhase.waiting ||
              phase == RiderSearchPhase.searching)) {
        _timeout = _scheduleTimeout(_softTimeout, () {
          if (_isCurrent(generation) &&
              (_state.phase == RiderSearchPhase.waiting ||
                  _state.phase == RiderSearchPhase.searching)) {
            _set(RiderSearchViewState(RiderSearchPhase.timedOut,
                booking: booking));
          }
        });
      }
    } on RiderBookingSearchReadException catch (error) {
      if (!_isCurrent(generation)) return;
      _set(RiderSearchViewState(
        error.failure == RiderBookingSearchReadFailure.invalidResponse
            ? RiderSearchPhase.unresolved
            : RiderSearchPhase.unavailable,
      ));
    } on Object {
      if (_isCurrent(generation)) {
        _set(const RiderSearchViewState(RiderSearchPhase.unavailable));
      }
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

  void _abandonRead() {
    _readTimer?.cancel();
    final abort = _abortRead;
    if (abort != null && !abort.isCompleted) abort.complete(null);
  }

  bool _isCurrent(int generation) =>
      !_disposed &&
      !_sessionInvalidated &&
      generation == _generation &&
      identical(_readSession(), _ownerSession) &&
      _validRiderSession(_ownerSession);

  bool _validRiderSession(SessionState session) =>
      session.status == SessionStatus.authenticated &&
      session.role == RideRole.rider &&
      session.user != null &&
      !session.user!.isBlocked &&
      isCanonicalTripId(session.user!.id);

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
    _abandonRead();
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
