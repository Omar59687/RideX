import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';

/// One canonical booking row and its quotes, read in one SELECT snapshot.
/// No client draft or persisted hint is used to populate these fields.
class CanonicalFareBooking {
  CanonicalFareBooking({
    required this.id,
    required this.riderId,
    required this.version,
    required this.status,
    required this.fareQuoteId,
    required List<CanonicalFareQuote> quotes,
  }) : quotes = List.unmodifiable(quotes);

  final String id;
  final String riderId;
  final int version;
  final String status;
  final String? fareQuoteId;
  final List<CanonicalFareQuote> quotes;

  factory CanonicalFareBooking.fromJson(Map<String, dynamic> row) {
    const statuses = {
      'draft',
      'confirmed',
      'searching',
      'matched',
      'cancelled',
      'expired',
      'failed',
    };
    final version = row['version'];
    final status = row['status'];
    final linkedId = row['fare_quote_id'];
    final quotes = row['fare_quotes'];
    if (version is! int ||
        version < 1 ||
        !statuses.contains(status) ||
        (linkedId != null && (linkedId is! String || linkedId.isEmpty)) ||
        quotes is! List) {
      throw const FareException(FareFailure.invalidResponse);
    }
    return CanonicalFareBooking(
      id: _identifier(row['id']),
      riderId: _identifier(row['rider_id']),
      version: version,
      status: status as String,
      fareQuoteId: linkedId as String?,
      quotes: [
        for (final quote in quotes) CanonicalFareQuote.fromJson(_map(quote))
      ],
    );
  }
}

class CanonicalFareQuote {
  const CanonicalFareQuote(
      {required this.riderId, required this.quote, required this.lockedAt});

  final String riderId;
  final FareQuote quote;
  final DateTime? lockedAt;

  factory CanonicalFareQuote.fromJson(Map<String, dynamic> row) {
    final raw = row['locked_at'];
    final lockedAt = raw is String ? DateTime.tryParse(raw) : null;
    if (raw != null && lockedAt == null) {
      throw const FareException(FareFailure.invalidResponse);
    }
    return CanonicalFareQuote(
        riderId: _identifier(row['rider_id']),
        quote: FareQuote.fromJson(row),
        lockedAt: lockedAt);
  }
}

enum FareLockRecoveryStatus { confirmed, uncertain, suspended }

class FareLockRecovery {
  const FareLockRecovery(
      {required this.command,
      required this.status,
      this.booking,
      this.quote,
      this.failure});

  final PendingFareLock command;
  final FareLockRecoveryStatus status;
  final CanonicalFareBooking? booking;
  final FareQuote? quote;
  final FareFailure? failure;

  /// Migration 026's exact linked-lock replay condition. Expiry after a
  /// committed lock does not undo the lock. Advanced versions, other locked
  /// candidates, or missing/inconsistent rows never authorize abandonment.
  static FareLockRecovery classify(
      PendingFareLock command, List<CanonicalFareBooking> rows) {
    FareLockRecovery uncertain() => FareLockRecovery(
        command: command, status: FareLockRecoveryStatus.uncertain);
    if (rows.length != 1) return uncertain();
    final booking = rows.single;
    if (booking.id != command.bookingRequestId ||
        booking.riderId != command.riderId ||
        booking.version != command.expectedBookingVersion + 1 ||
        booking.status != 'draft' ||
        booking.fareQuoteId != command.fareQuoteId) {
      return uncertain();
    }
    final ids = <String>{};
    final versions = <int>{};
    for (final row in booking.quotes) {
      if (row.riderId != command.riderId ||
          row.quote.bookingRequestId != command.bookingRequestId ||
          !ids.add(row.quote.id) ||
          !versions.add(row.quote.quoteVersion)) {
        return uncertain();
      }
    }
    final originals = booking.quotes
        .where((row) => row.quote.id == command.fareQuoteId)
        .toList();
    final locked = booking.quotes
        .where((row) => row.quote.status == FareQuoteStatus.locked)
        .toList();
    if (originals.length != 1 || locked.length != 1) return uncertain();
    final original = originals.single;
    final quote = original.quote;
    if (quote.status != FareQuoteStatus.locked ||
        original.lockedAt == null ||
        quote.quoteVersion != command.expectedQuoteVersion) {
      return uncertain();
    }
    return FareLockRecovery(
        command: command,
        status: FareLockRecoveryStatus.confirmed,
        booking: booking,
        quote: quote);
  }
}

String _identifier(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FareException(FareFailure.invalidResponse);
  }
  return value;
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) throw const FareException(FareFailure.invalidResponse);
  return Map<String, dynamic>.from(value);
}
