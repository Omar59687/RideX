import 'package:equatable/equatable.dart';

/// Typed failures for route-based fixed-fare work.
///
/// Mirrors the existing typed-failure style ([RouteFailure]/[PlaceFailure]):
/// repositories throw [FareException] with a [FareFailure] and surfaces
/// render sanitized, user-facing messages. Backend details are never
/// surfaced.
enum FareFailure {
  unavailable,
  networkFailure,
  timedOut,
  unauthorized,
  forbidden,
  notFound,
  versionConflict,
  pricingUnavailable,
  expired,
  invalidResponse,
}

class FareException implements Exception {
  const FareException(this.failure);

  final FareFailure failure;
}

/// Backend fare-quote status (`public.fare_quote_status`).
enum FareQuoteStatus { calculated, locked, expired, superseded }

/// Authoritative fare breakdown computed by the backend
/// (`backend_calculate_fare_quote`, `007:920-929`).
///
/// All amounts are integer fils. Flutter never calculates fares: it only
/// formats and displays these backend-computed values.
class FareBreakdown extends Equatable {
  const FareBreakdown({
    required this.baseFareFils,
    required this.distanceFils,
    required this.durationFils,
    required this.stopsFils,
    required this.subtotalFils,
    required this.minimumFareFils,
    required this.roundingIncrementFils,
    required this.fixedFareFils,
  });

  final int baseFareFils;
  final int distanceFils;
  final int durationFils;
  final int stopsFils;
  final int subtotalFils;
  final int minimumFareFils;
  final int roundingIncrementFils;
  final int fixedFareFils;

  /// Whether the backend minimum fare lifted the subtotal.
  bool get minimumApplied => subtotalFils < minimumFareFils;

  factory FareBreakdown.fromJson(Map<String, dynamic> json) {
    return FareBreakdown(
      baseFareFils: _fils(json['base_fare_fils']),
      distanceFils: _fils(json['distance_fils']),
      durationFils: _fils(json['duration_fils']),
      stopsFils: _fils(json['stops_fils']),
      subtotalFils: _fils(json['subtotal_fils']),
      minimumFareFils: _fils(json['minimum_fare_fils']),
      roundingIncrementFils: _positiveInt(json['rounding_increment_fils']),
      fixedFareFils: _fils(json['fixed_fare_fils']),
    );
  }

  Map<String, dynamic> toJson() => {
        'base_fare_fils': baseFareFils,
        'distance_fils': distanceFils,
        'duration_fils': durationFils,
        'stops_fils': stopsFils,
        'subtotal_fils': subtotalFils,
        'minimum_fare_fils': minimumFareFils,
        'rounding_increment_fils': roundingIncrementFils,
        'fixed_fare_fils': fixedFareFils,
      };

  @override
  List<Object?> get props => [
        baseFareFils,
        distanceFils,
        durationFils,
        stopsFils,
        subtotalFils,
        minimumFareFils,
        roundingIncrementFils,
        fixedFareFils,
      ];
}

/// A persistent backend fare quote (`public.fare_quotes`).
///
/// All money is integer fils in JOD. Flutter formats via [formatFareFils]
/// only; no fare arithmetic happens on the client.
class FareQuote extends Equatable {
  const FareQuote({
    required this.id,
    required this.bookingRequestId,
    required this.quoteVersion,
    required this.pricingVersion,
    required this.fixedFareFils,
    required this.breakdown,
    required this.status,
    required this.expiresAt,
    this.currency = 'JOD',
    this.createdAt,
    this.routeDistanceMeters,
    this.routeDurationSeconds,
  });

  final String id;
  final String bookingRequestId;
  final int quoteVersion;
  final int pricingVersion;
  final int fixedFareFils;
  final FareBreakdown breakdown;
  final FareQuoteStatus status;
  final DateTime expiresAt;
  final String currency;
  final DateTime? createdAt;
  final int? routeDistanceMeters;
  final int? routeDurationSeconds;

  /// Usable for display as the current total: calculated and unexpired.
  bool isUsableAt(DateTime now) {
    return status == FareQuoteStatus.calculated && !isExpiredAt(now);
  }

  /// Expiry is authoritative: an expired quote must never back a total.
  /// Callers re-quote instead of displaying a stale total.
  bool isExpiredAt(DateTime now) {
    return status == FareQuoteStatus.expired || !expiresAt.isAfter(now);
  }

  factory FareQuote.fromJson(Map<String, dynamic> json) {
    final breakdownValue = json['breakdown'];
    if (breakdownValue is! Map) {
      throw const FareException(FareFailure.invalidResponse);
    }
    final breakdown = FareBreakdown.fromJson(
      breakdownValue.map((key, value) => MapEntry(key.toString(), value)),
    );
    final currency = json['currency'];
    if (currency is! String || currency != 'JOD') {
      throw const FareException(FareFailure.invalidResponse);
    }
    return FareQuote(
      id: _nonEmptyString(json['id']),
      bookingRequestId: _nonEmptyString(json['booking_request_id']),
      quoteVersion: _positiveInt(json['quote_version']),
      pricingVersion: _positiveInt(json['pricing_version']),
      fixedFareFils: _fils(json['fixed_fare_fils']),
      breakdown: breakdown,
      status: _status(json['status']),
      expiresAt: _dateTime(json['expires_at']),
      currency: currency,
      createdAt: _optionalDateTime(json['created_at']),
      routeDistanceMeters: _optionalNonNegativeInt(
        json['route_distance_meters'],
      ),
      routeDurationSeconds: _optionalNonNegativeInt(
        json['route_duration_seconds'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'booking_request_id': bookingRequestId,
        'quote_version': quoteVersion,
        'pricing_version': pricingVersion,
        'fixed_fare_fils': fixedFareFils,
        'breakdown': breakdown.toJson(),
        'currency': currency,
        'status': status.name,
        'expires_at': expiresAt.toIso8601String(),
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (routeDistanceMeters != null)
          'route_distance_meters': routeDistanceMeters,
        if (routeDurationSeconds != null)
          'route_duration_seconds': routeDurationSeconds,
      };

  @override
  List<Object?> get props => [
        id,
        bookingRequestId,
        quoteVersion,
        pricingVersion,
        fixedFareFils,
        breakdown,
        status,
        expiresAt,
        currency,
        createdAt,
        routeDistanceMeters,
        routeDurationSeconds,
      ];
}

/// Formats integer fils as JOD text using integer arithmetic only.
///
/// 1 JOD = 1000 fils = 100 piasters; display rounds to the nearest piaster
/// (two decimals). This is presentation formatting, not fare calculation.
String formatFareFils(int fils) {
  if (fils < 0) {
    throw ArgumentError.value(fils, 'fils', 'Must be nonnegative.');
  }
  final piasters = (fils + 5) ~/ 10;
  final dinars = piasters ~/ 100;
  final remainder = (piasters % 100).toString().padLeft(2, '0');
  return 'JOD $dinars.$remainder';
}

int _fils(Object? value) {
  if (value is! int || value < 0) {
    throw const FareException(FareFailure.invalidResponse);
  }
  return value;
}

int _positiveInt(Object? value) {
  if (value is! int || value <= 0) {
    throw const FareException(FareFailure.invalidResponse);
  }
  return value;
}

int? _optionalNonNegativeInt(Object? value) {
  if (value == null) return null;
  if (value is! int || value < 0) {
    throw const FareException(FareFailure.invalidResponse);
  }
  return value;
}

String _nonEmptyString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FareException(FareFailure.invalidResponse);
  }
  return value;
}

FareQuoteStatus _status(Object? value) {
  if (value is! String) {
    throw const FareException(FareFailure.invalidResponse);
  }
  return switch (value) {
    'calculated' => FareQuoteStatus.calculated,
    'locked' => FareQuoteStatus.locked,
    'expired' => FareQuoteStatus.expired,
    'superseded' => FareQuoteStatus.superseded,
    _ => throw const FareException(FareFailure.invalidResponse),
  };
}

DateTime _dateTime(Object? value) {
  if (value is! String) {
    throw const FareException(FareFailure.invalidResponse);
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const FareException(FareFailure.invalidResponse);
  }
  return parsed;
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null) return null;
  return _dateTime(value);
}
