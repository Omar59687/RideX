import 'package:ridex/core/models/fare_lock_recovery.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';

/// Canonical lineage for review/confirmation, never a local replacement draft.
class BookingHandoff {
  const BookingHandoff(
      {required this.command, required this.booking, required this.quote});
  final PendingFareLock command;
  final CanonicalFareBooking booking;
  final FareQuote quote;
  bool get isConfirmed => booking.status == 'confirmed';

  static BookingHandoff? classify(
      PendingFareLock command, List<CanonicalFareBooking> rows) {
    // Keep Slice 2's lock-recovery semantics unchanged. Confirmation adds
    // exactly one optimistic booking version and does not change the quote.
    if (rows.length != 1) return null;
    final booking = rows.single;
    final confirmed = booking.status == 'confirmed' &&
        booking.version == command.expectedBookingVersion + 2;
    final draft = confirmed
        ? CanonicalFareBooking(
            id: booking.id,
            riderId: booking.riderId,
            version: booking.version - 1,
            status: 'draft',
            fareQuoteId: booking.fareQuoteId,
            quotes: booking.quotes)
        : booking;
    final lock = FareLockRecovery.classify(command, [draft]);
    if (lock.status != FareLockRecoveryStatus.confirmed) return null;
    if (!validLockedSnapshot(lock.quote!)) return null;
    return BookingHandoff(
        command: command, booking: booking, quote: lock.quote!);
  }
}

/// A locator and immutable snapshot, not server authority. Re-entry reads RLS
/// protected canonical state. The original command also acts as a tombstone.
class ConfirmedBookingReference {
  const ConfirmedBookingReference({required this.command, required this.quote});
  final PendingFareLock command;
  final FareQuote quote;

  factory ConfirmedBookingReference.fromJson(Map<String, dynamic> json) {
    final command = PendingFareLock.fromJson(
        Map<String, dynamic>.from(json['command'] as Map));
    final quote =
        FareQuote.fromJson(Map<String, dynamic>.from(json['quote'] as Map));
    if (quote.id != command.fareQuoteId ||
        quote.bookingRequestId != command.bookingRequestId ||
        quote.quoteVersion != command.expectedQuoteVersion ||
        !validLockedSnapshot(quote)) {
      throw const FareException(FareFailure.invalidResponse);
    }
    return ConfirmedBookingReference(command: command, quote: quote);
  }
  Map<String, dynamic> toJson() =>
      {'command': command.toJson(), 'quote': quote.toJson()};
}

bool validLockedSnapshot(FareQuote quote) {
  try {
    final parsed = FareQuote.fromJson(quote.toJson());
    return parsed == quote &&
        quote.status == FareQuoteStatus.locked &&
        quote.fixedFareFils == quote.breakdown.fixedFareFils;
  } on Object {
    return false;
  }
}
