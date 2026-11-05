import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/rider_booking_cancellation.dart';
import 'package:ridex/core/models/rider_booking_search.dart';
import 'package:ridex/core/repositories/rider_booking_cancellation_repository.dart';

enum RiderCancellationAttemptPhase {
  pending,
  accepted,
  verifiedCancelled,
  rejected,
  uncertain,
}

/// Immutable evidence for one Rider/BookingRequest cancellation attempt.
///
/// This object is application-owned and survives screen or controller
/// recreation. It is process-local and is never restored after an app restart.
@immutable
class RiderCancellationAttempt {
  const RiderCancellationAttempt({
    required this.riderId,
    required this.bookingRequestId,
    required this.phase,
    required this.expectedVersion,
    required this.observedStatus,
    this.rejection,
    this.acceptedBooking,
  });

  final String riderId;
  final String bookingRequestId;
  final RiderCancellationAttemptPhase phase;
  final int expectedVersion;
  final RiderBookingSearchStatus observedStatus;
  final RiderCancellationRejection? rejection;

  /// Authoritative cancelled evidence from the command or a verified read.
  final RiderBookingSearchSnapshot? acceptedBooking;
}

/// Application-owned cancellation ownership for the current process.
///
/// Exactly one attempt may exist for a Rider/BookingRequest key. The pending
/// claim is installed synchronously before repository dispatch, so a controller
/// recreated while the command is unresolved cannot dispatch a duplicate.
class RiderCancellationCoordinator extends ChangeNotifier {
  RiderCancellationCoordinator({
    required RiderBookingCancellationRepository repository,
    Duration cancellationDeadline = const Duration(seconds: 15),
    Timer Function(Duration, void Function())? scheduleDeadline,
  })  : _repository = repository,
        _cancellationDeadline = cancellationDeadline,
        _scheduleDeadline = scheduleDeadline ?? Timer.new {
    if (cancellationDeadline <= Duration.zero) {
      throw ArgumentError.value(
        cancellationDeadline,
        'cancellationDeadline',
        'Must be positive.',
      );
    }
  }

  final RiderBookingCancellationRepository _repository;
  final Duration _cancellationDeadline;
  final Timer Function(Duration, void Function()) _scheduleDeadline;
  final Map<String, _AttemptEntry> _attempts = {};
  bool _disposed = false;

  int get retainedAttemptCount => _attempts.length;

  RiderCancellationAttempt? attemptFor({
    required String riderId,
    required String bookingRequestId,
  }) {
    final key = _keyFor(riderId, bookingRequestId);
    return key == null ? null : _attempts[key]?.attempt;
  }

  /// Claims and dispatches one cancellation, or returns the existing attempt.
  ///
  /// A `staleVersion` rejection may be retried only with a strict version
  /// increase and a currently cancellable observed status. Accepted, uncertain,
  /// pending, and every other rejection stay blocked.
  Future<void> cancel({
    required String riderId,
    required String bookingRequestId,
    required int expectedVersion,
    required RiderBookingSearchStatus observedStatus,
    required String reasonCode,
  }) {
    if (_disposed || expectedVersion <= 0) return Future<void>.value();
    final key = _keyFor(riderId, bookingRequestId);
    if (key == null) return Future<void>.value();
    final existing = _attempts[key];
    if (existing != null) {
      switch (existing.attempt.phase) {
        case RiderCancellationAttemptPhase.pending:
          return existing.completion.future;
        case RiderCancellationAttemptPhase.accepted:
        case RiderCancellationAttemptPhase.verifiedCancelled:
        case RiderCancellationAttemptPhase.uncertain:
          return Future<void>.value();
        case RiderCancellationAttemptPhase.rejected:
          if (existing.attempt.rejection !=
                  RiderCancellationRejection.staleVersion ||
              !isCancellableBookingStatus(observedStatus) ||
              expectedVersion <= existing.attempt.expectedVersion) {
            return Future<void>.value();
          }
      }
    }
    final reason = reasonCode.trim();
    if (!isValidCancellationReason(reason) ||
        !isCancellableBookingStatus(observedStatus)) {
      return Future<void>.value();
    }
    final entry = _AttemptEntry(
      attempt: RiderCancellationAttempt(
        riderId: riderId,
        bookingRequestId: bookingRequestId,
        phase: RiderCancellationAttemptPhase.pending,
        expectedVersion: expectedVersion,
        observedStatus: observedStatus,
      ),
    );
    _attempts[key] = entry;
    notifyListeners();
    unawaited(_perform(key, entry, reason));
    return entry.completion.future;
  }

  /// Retains a terminal guard when a verified read proves cancellation.
  ///
  /// Other terminal statuses do not prove cancellation and deliberately retain
  /// their unresolved evidence. The caller's snapshot must be owned, Cash, and
  /// newer than the attempted version; no status-only signal can erase an
  /// in-flight or uncertain attempt. The guard lasts until provider disposal.
  void reconcileTerminalBooking({
    required String riderId,
    required String bookingRequestId,
    required RiderBookingSearchSnapshot booking,
  }) {
    if (_disposed || booking.status != RiderBookingSearchStatus.cancelled) {
      return;
    }
    final key = _keyFor(riderId, bookingRequestId);
    if (key == null) return;
    final entry = _attempts[key];
    if (entry == null) return;
    final attempt = entry.attempt;
    if (booking.bookingRequestId.toLowerCase() !=
            bookingRequestId.toLowerCase() ||
        booking.riderId.toLowerCase() != riderId.toLowerCase() ||
        booking.paymentMethod != PaymentMethod.cash ||
        booking.version <= attempt.expectedVersion ||
        (attempt.acceptedBooking != null &&
            booking.version < attempt.acceptedBooking!.version)) {
      return;
    }
    if (attempt.phase == RiderCancellationAttemptPhase.verifiedCancelled &&
        booking.version == attempt.acceptedBooking?.version) {
      return;
    }
    _retire(entry);
    entry.attempt = RiderCancellationAttempt(
      riderId: attempt.riderId,
      bookingRequestId: attempt.bookingRequestId,
      phase: RiderCancellationAttemptPhase.verifiedCancelled,
      expectedVersion: attempt.expectedVersion,
      observedStatus: attempt.observedStatus,
      acceptedBooking: booking,
    );
    notifyListeners();
  }

  Future<void> _perform(
    String key,
    _AttemptEntry entry,
    String reason,
  ) async {
    final abort = Completer<RiderBookingCancellationResult>();
    entry.abort = abort;
    Timer? timer;
    try {
      timer = _scheduleDeadline(_cancellationDeadline, () {
        if (!abort.isCompleted) {
          abort.complete(const RiderBookingCancellationUnknown());
        }
      });
      entry.timer = timer;
      final result = await Future.any([
        _safeCancel(entry, reason),
        abort.future,
      ]);
      if (!_isCurrent(key, entry)) return;
      switch (result) {
        case RiderBookingCancellationAccepted(:final booking):
          entry.attempt = _acceptedAttempt(entry, booking);
        case RiderBookingCancellationRejected(:final rejection):
          entry.attempt = _withPhase(
            entry.attempt,
            RiderCancellationAttemptPhase.rejected,
            rejection: rejection,
          );
        case RiderBookingCancellationUnknown():
          entry.attempt = _withPhase(
            entry.attempt,
            RiderCancellationAttemptPhase.uncertain,
          );
      }
      notifyListeners();
    } finally {
      timer?.cancel();
      if (identical(entry.timer, timer)) entry.timer = null;
      if (identical(entry.abort, abort)) entry.abort = null;
      if (!entry.completion.isCompleted) entry.completion.complete();
    }
  }

  Future<RiderBookingCancellationResult> _safeCancel(
    _AttemptEntry entry,
    String reason,
  ) async {
    try {
      return await _repository.cancelBooking(
        bookingRequestId: entry.attempt.bookingRequestId,
        expectedVersion: entry.attempt.expectedVersion,
        reasonCode: reason,
      );
    } on Object {
      return const RiderBookingCancellationUnknown();
    }
  }

  RiderCancellationAttempt _acceptedAttempt(
    _AttemptEntry entry,
    RiderBookingSearchSnapshot booking,
  ) {
    final attempt = entry.attempt;
    final valid = booking.bookingRequestId.toLowerCase() ==
            attempt.bookingRequestId.toLowerCase() &&
        booking.riderId.toLowerCase() == attempt.riderId.toLowerCase() &&
        booking.paymentMethod == PaymentMethod.cash &&
        booking.status == RiderBookingSearchStatus.cancelled &&
        booking.version > attempt.expectedVersion &&
        isCancellableBookingStatus(entry.observedStatus);
    return valid
        ? RiderCancellationAttempt(
            riderId: attempt.riderId,
            bookingRequestId: attempt.bookingRequestId,
            phase: RiderCancellationAttemptPhase.accepted,
            expectedVersion: attempt.expectedVersion,
            observedStatus: attempt.observedStatus,
            acceptedBooking: booking,
          )
        : _withPhase(attempt, RiderCancellationAttemptPhase.uncertain);
  }

  RiderCancellationAttempt _withPhase(
    RiderCancellationAttempt attempt,
    RiderCancellationAttemptPhase phase, {
    RiderCancellationRejection? rejection,
  }) =>
      RiderCancellationAttempt(
        riderId: attempt.riderId,
        bookingRequestId: attempt.bookingRequestId,
        phase: phase,
        expectedVersion: attempt.expectedVersion,
        observedStatus: attempt.observedStatus,
        rejection: rejection,
      );

  void _retire(_AttemptEntry entry) {
    entry.removed = true;
    entry.timer?.cancel();
    entry.timer = null;
    final abort = entry.abort;
    if (abort != null && !abort.isCompleted) {
      abort.complete(const RiderBookingCancellationUnknown());
    }
    entry.abort = null;
    if (!entry.completion.isCompleted) entry.completion.complete();
  }

  bool _isCurrent(String key, _AttemptEntry entry) =>
      !_disposed && !entry.removed && identical(_attempts[key], entry);

  String? _keyFor(String riderId, String bookingRequestId) {
    if (!isCanonicalTripId(riderId) || !isCanonicalTripId(bookingRequestId)) {
      return null;
    }
    return '${riderId.toLowerCase()}|${bookingRequestId.toLowerCase()}';
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final entry in _attempts.values) {
      _retire(entry);
    }
    _attempts.clear();
    super.dispose();
  }
}

class _AttemptEntry {
  _AttemptEntry({required this.attempt});

  RiderCancellationAttempt attempt;
  final Completer<void> completion = Completer<void>();
  RiderBookingSearchStatus get observedStatus => attempt.observedStatus;
  Completer<RiderBookingCancellationResult>? abort;
  Timer? timer;
  bool removed = false;
}
