import 'package:equatable/equatable.dart';

/// Recovery status of a staged fare-lock command.
///
/// Slice 1 only ever stages `uncertain`: the commit outcome is unknown from
/// the moment the lock request is sent. Later slices add terminal
/// classifications produced by canonical recovery (committed replay,
/// safe-to-abandon). A resolved command is removed from its owner rather
/// than kept with a terminal status.
enum PendingLockRecoveryStatus { uncertain }

/// Immutable fare-lock command staged before a potentially committing lock
/// RPC is dispatched.
///
/// Carries the ORIGINAL booking/quote identifiers and versions so an
/// ambiguous response can replay the exact request (migration 026), plus
/// the authenticated rider that owns it for session isolation. Identity
/// fields are validated at construction and never mutated afterwards.
class PendingFareLock extends Equatable {
  PendingFareLock({
    required this.bookingRequestId,
    required this.expectedBookingVersion,
    required this.fareQuoteId,
    required this.expectedQuoteVersion,
    required this.riderId,
    required this.status,
    required this.createdAt,
  }) {
    if (bookingRequestId.trim().isEmpty) {
      throw ArgumentError.value(
        bookingRequestId,
        'bookingRequestId',
        'Must be nonempty.',
      );
    }
    if (fareQuoteId.trim().isEmpty) {
      throw ArgumentError.value(
        fareQuoteId,
        'fareQuoteId',
        'Must be nonempty.',
      );
    }
    if (riderId.trim().isEmpty) {
      throw ArgumentError.value(riderId, 'riderId', 'Must be nonempty.');
    }
    if (expectedBookingVersion < 1) {
      throw ArgumentError.value(
        expectedBookingVersion,
        'expectedBookingVersion',
        'Must be positive.',
      );
    }
    if (expectedQuoteVersion < 1) {
      throw ArgumentError.value(
        expectedQuoteVersion,
        'expectedQuoteVersion',
        'Must be positive.',
      );
    }
  }

  final String bookingRequestId;
  final int expectedBookingVersion;
  final String fareQuoteId;
  final int expectedQuoteVersion;
  final String riderId;
  final PendingLockRecoveryStatus status;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'booking_request_id': bookingRequestId,
        'expected_booking_version': expectedBookingVersion,
        'fare_quote_id': fareQuoteId,
        'expected_quote_version': expectedQuoteVersion,
        'rider_id': riderId,
        'status': status.name,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory PendingFareLock.fromJson(Map<String, dynamic> json) {
    final parsed = tryParse(json);
    if (parsed == null) {
      throw ArgumentError.value(json, 'json', 'Not a valid pending lock.');
    }
    return parsed;
  }

  /// Returns null for absent or malformed records instead of throwing, so a
  /// corrupt recovery hint degrades to "no command" rather than crashing
  /// recovery. Callers must treat null as unknown, never as proof of a
  /// non-commit.
  static PendingFareLock? tryParse(Map<String, dynamic> json) {
    try {
      final statusRaw = json['status'];
      if (statusRaw != PendingLockRecoveryStatus.uncertain.name) return null;
      final createdRaw = json['created_at'];
      final createdAt =
          createdRaw is String ? DateTime.tryParse(createdRaw) : null;
      if (createdAt == null) return null;
      final bookingVersion = json['expected_booking_version'];
      final quoteVersion = json['expected_quote_version'];
      if (bookingVersion is! int || quoteVersion is! int) return null;
      return PendingFareLock(
        bookingRequestId: json['booking_request_id'] as String,
        expectedBookingVersion: bookingVersion,
        fareQuoteId: json['fare_quote_id'] as String,
        expectedQuoteVersion: quoteVersion,
        riderId: json['rider_id'] as String,
        status: PendingLockRecoveryStatus.uncertain,
        createdAt: createdAt,
      );
    } on ArgumentError {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  List<Object?> get props => [
        bookingRequestId,
        expectedBookingVersion,
        fareQuoteId,
        expectedQuoteVersion,
        riderId,
        status,
        createdAt,
      ];

  /// Identity tuple for exclusive pending-command ownership (Slice 1).
  ///
  /// Two commands are the same lineage only when the original booking
  /// id/version, quote id/version, and owning rider all match. `status` is
  /// always `uncertain` in Slice 1 and `createdAt` is lineage metadata, so
  /// neither participates in exclusivity: an exact replay carries the same
  /// tuple even if it was re-created with a fresh timestamp.
  bool hasSameLockIdentity(PendingFareLock other) {
    return bookingRequestId == other.bookingRequestId &&
        expectedBookingVersion == other.expectedBookingVersion &&
        fareQuoteId == other.fareQuoteId &&
        expectedQuoteVersion == other.expectedQuoteVersion &&
        riderId == other.riderId;
  }
}

/// Thrown when staging would overwrite a different unresolved pending
/// command. The existing memory and persisted evidence are preserved.
class PendingFareLockConflictException implements Exception {
  const PendingFareLockConflictException([
    this.message =
        'A different pending fare lock is already staged and must not be overwritten.',
  ]);

  final String message;

  @override
  String toString() => 'PendingFareLockConflictException: $message';
}

/// Thrown when persisted recovery evidence is present but unreadable or
/// attributable to a different rider namespace. The suspicious record is
/// preserved; callers must surface a safe blocked state, never treat it as
/// absent.
class PendingFareLockCorruptException implements Exception {
  const PendingFareLockCorruptException([
    this.message =
        'Persisted fare-lock evidence is unreadable and must not be overwritten.',
  ]);

  final String message;

  @override
  String toString() => 'PendingFareLockCorruptException: $message';
}

/// Thrown when staging cannot be attributed to the currently authenticated
/// rider (signed out, wrong role/status, rider mismatch, session changed
/// mid-operation, or provider disposed). Persisted evidence for the original
/// rider is preserved; nothing is published into the new session.
class PendingFareLockOwnershipException implements Exception {
  const PendingFareLockOwnershipException([
    this.message =
        'Pending fare-lock staging requires the owning authenticated rider session.',
  ]);

  final String message;

  @override
  String toString() => 'PendingFareLockOwnershipException: $message';
}
