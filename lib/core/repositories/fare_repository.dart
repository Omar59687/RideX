import 'package:equatable/equatable.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/fare_lock_recovery.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';

/// Route-location JSON sent to the draft RPCs
/// (`private.is_valid_route_location`: latitude/longitude with an optional
/// 1-200 character label).
class FareRouteLocation extends Equatable {
  const FareRouteLocation({
    required this.latitude,
    required this.longitude,
    this.label,
  });

  final double latitude;
  final double longitude;
  final String? label;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(),
      };

  @override
  List<Object?> get props => [latitude, longitude, label];
}

/// Ordered stop JSON sent to the draft RPCs
/// (`private.is_valid_ordered_stops`: at most three entries).
class FareStopInput extends Equatable {
  const FareStopInput({required this.location, this.label});

  final FareRouteLocation location;
  final String? label;

  Map<String, dynamic> toJson() => {
        'location': location.toJson(),
        if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(),
      };

  @override
  List<Object?> get props => [location, label];
}

/// Persisted draft booking reference (`public.booking_requests` id/version).
class FareBookingRef extends Equatable {
  const FareBookingRef({required this.bookingRequestId, required this.version});

  final String bookingRequestId;
  final int version;

  @override
  List<Object?> get props => [bookingRequestId, version];
}

/// Transport-level failure carrier.
///
/// The Supabase wiring (see `repositories_providers.dart`) catches
/// SDK exceptions and throws this provider-neutral carrier instead, so
/// this repository stays free of provider SDK imports. [code] is a backend
/// error code (Postgres errcode such as `40001`, or the Edge `fare`
/// sanitized code such as `version_conflict`); [status] is the HTTP-ish
/// status when one exists.
class FareTransportFailure implements Exception {
  const FareTransportFailure({this.status, this.code});

  final int? status;
  final String? code;
}

typedef FareRpcCaller = Future<Map<String, dynamic>> Function({
  required String name,
  required Map<String, dynamic> params,
});

typedef FareEdgeCaller = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> body,
);

typedef FareCanonicalReader = Future<List<Map<String, dynamic>>> Function({
  required String bookingRequestId,
  required String riderId,
});

/// Runs the actual draft dispatch under the shared pending-lock owner.
typedef BookingMutationGate = Future<Map<String, dynamic>> Function(
  Future<Map<String, dynamic>> Function() dispatch,
);

typedef FareBookingConfirmer = Future<Map<String, dynamic>> Function({
  required String bookingRequestId,
  required int expectedVersion,
  required String idempotencyKey,
  required String riderId,
});

abstract interface class BookingConfirmationRepository {
  Future<void> confirmLockedBooking(
      {required String bookingRequestId,
      required int expectedVersion,
      required String idempotencyKey,
      required String riderId});
}

/// Optional read-only capability; existing fare doubles and demo mode keep
/// their existing contract. Recovery never substitutes draft/quote mutations.
abstract interface class FareLockRecoveryRepository {
  Future<List<CanonicalFareBooking>> readCanonicalFareLock({
    required String bookingRequestId,
    required String riderId,
  });
}

/// Provider-neutral fare contract.
///
/// Flutter calls `rider_create_booking_draft` / `rider_update_booking_draft`
/// directly via PostgREST RPC (granted to `authenticated`) and reaches the
/// `service_role`-only `backend_calculate_fare_quote` exclusively through
/// the `fare` Edge function (`quote` operation). Flutter never calculates
/// fares: route metrics passed to [fetchQuote] are local display context only
/// and are deliberately not sent to the fare service. The Edge function reloads
/// the canonical booking and requests trusted route metrics server-side.
///
/// Updating a draft supersedes its `calculated` quotes server-side, so
/// callers re-quote after every draft change.
abstract class FareRepository {
  Future<FareBookingRef> createBookingDraft({
    required FareRouteLocation pickup,
    required FareRouteLocation destination,
    required String vehicleTypeCode,
    required String paymentMethod,
    List<FareStopInput> stops = const [],
  });

  Future<FareBookingRef> updateBookingDraft({
    required String bookingRequestId,
    required int expectedBookingVersion,
    required FareRouteLocation pickup,
    required FareRouteLocation destination,
    required String vehicleTypeCode,
    required String paymentMethod,
    List<FareStopInput> stops = const [],
  });

  Future<FareQuote> fetchQuote({
    required String bookingRequestId,
    required int expectedBookingVersion,
    required int routeDistanceMeters,
    required int routeDurationSeconds,
  });

  Future<FareQuote> lockQuote({
    required String bookingRequestId,
    required String fareQuoteId,
    required int expectedBookingVersion,
    required int expectedQuoteVersion,
  });
}

class SupabaseFareRepository
    implements
        FareRepository,
        FareLockRecoveryRepository,
        BookingConfirmationRepository {
  const SupabaseFareRepository({
    required BookingMutationGate bookingMutationGate,
    required FareRpcCaller rpc,
    required FareEdgeCaller quoteEdge,
    FareCanonicalReader? canonicalReader,
    FareBookingConfirmer? bookingConfirmer,
    AppErrorReporter errorReporter = const NoopAppErrorReporter(),
  })  : _bookingMutationGate = bookingMutationGate,
        _rpc = rpc,
        _quoteEdge = quoteEdge,
        _canonicalReader = canonicalReader,
        _bookingConfirmer = bookingConfirmer,
        _errorReporter = errorReporter;

  final FareRpcCaller _rpc;
  final BookingMutationGate _bookingMutationGate;
  final FareEdgeCaller _quoteEdge;
  final FareCanonicalReader? _canonicalReader;
  final FareBookingConfirmer? _bookingConfirmer;
  final AppErrorReporter _errorReporter;

  @override
  Future<void> confirmLockedBooking(
      {required String bookingRequestId,
      required int expectedVersion,
      required String idempotencyKey,
      required String riderId}) async {
    final confirmer = _bookingConfirmer;
    if (confirmer == null) throw const FareException(FareFailure.unavailable);
    try {
      final result = await confirmer(
          bookingRequestId: bookingRequestId,
          expectedVersion: expectedVersion,
          idempotencyKey: idempotencyKey,
          riderId: riderId);
      if (result['booking_request_id'] != bookingRequestId ||
          result['status'] != 'confirmed' ||
          result.containsKey('error')) {
        throw const FareException(FareFailure.invalidResponse);
      }
    } on FareTransportFailure catch (error) {
      throw FareException(_mapTransport(error));
    } on FareException {
      rethrow;
    } on Object catch (error, stackTrace) {
      _report('confirming the locked booking', error, stackTrace);
      throw const FareException(FareFailure.networkFailure);
    }
  }

  @override
  Future<List<CanonicalFareBooking>> readCanonicalFareLock({
    required String bookingRequestId,
    required String riderId,
  }) async {
    final reader = _canonicalReader;
    if (reader == null) throw const FareException(FareFailure.unavailable);
    try {
      final rows =
          await reader(bookingRequestId: bookingRequestId, riderId: riderId);
      final bookings = rows.map(CanonicalFareBooking.fromJson).toList();
      for (final booking in bookings) {
        if (booking.id != bookingRequestId ||
            booking.riderId != riderId ||
            booking.quotes.any((row) =>
                row.riderId != riderId ||
                row.quote.bookingRequestId != bookingRequestId)) {
          throw const FareException(FareFailure.invalidResponse);
        }
      }
      return List.unmodifiable(bookings);
    } on FareTransportFailure catch (error) {
      throw FareException(_mapTransport(error));
    } on FareException catch (error, stackTrace) {
      _reportInvalidResponse(error, stackTrace);
      rethrow;
    } on Object catch (error, stackTrace) {
      _report('reading canonical fare-lock state', error, stackTrace);
      throw const FareException(FareFailure.networkFailure);
    }
  }

  @override
  Future<FareBookingRef> createBookingDraft({
    required FareRouteLocation pickup,
    required FareRouteLocation destination,
    required String vehicleTypeCode,
    required String paymentMethod,
    List<FareStopInput> stops = const [],
  }) async {
    try {
      final row = await _bookingMutationGate(() => _rpc(
            name: 'rider_create_booking_draft',
            params: {
              'requested_pickup': pickup.toJson(),
              'requested_destination': destination.toJson(),
              'requested_vehicle_type': vehicleTypeCode,
              'requested_payment_method': paymentMethod,
              'requested_stops': [for (final stop in stops) stop.toJson()],
            },
          ));
      return _bookingRef(row);
    } on FareTransportFailure catch (error) {
      throw FareException(_mapTransport(error));
    } on FareException catch (error, stackTrace) {
      _reportInvalidResponse(error, stackTrace);
      rethrow;
    } on Object catch (error, stackTrace) {
      _report('persisting a booking draft', error, stackTrace);
      throw const FareException(FareFailure.networkFailure);
    }
  }

  @override
  Future<FareBookingRef> updateBookingDraft({
    required String bookingRequestId,
    required int expectedBookingVersion,
    required FareRouteLocation pickup,
    required FareRouteLocation destination,
    required String vehicleTypeCode,
    required String paymentMethod,
    List<FareStopInput> stops = const [],
  }) async {
    try {
      final row = await _bookingMutationGate(() => _rpc(
            name: 'rider_update_booking_draft',
            params: {
              'target_booking_request_id': bookingRequestId,
              'expected_version': expectedBookingVersion,
              'requested_pickup': pickup.toJson(),
              'requested_destination': destination.toJson(),
              'requested_vehicle_type': vehicleTypeCode,
              'requested_payment_method': paymentMethod,
              'requested_stops': [for (final stop in stops) stop.toJson()],
            },
          ));
      return _bookingRef(row);
    } on FareTransportFailure catch (error) {
      throw FareException(_mapTransport(error));
    } on FareException catch (error, stackTrace) {
      _reportInvalidResponse(error, stackTrace);
      rethrow;
    } on Object catch (error, stackTrace) {
      _report('updating a booking draft', error, stackTrace);
      throw const FareException(FareFailure.networkFailure);
    }
  }

  @override
  Future<FareQuote> fetchQuote({
    required String bookingRequestId,
    required int expectedBookingVersion,
    required int routeDistanceMeters,
    required int routeDurationSeconds,
  }) async {
    try {
      final envelope = await _quoteEdge({
        'operation': 'quote',
        'booking_request_id': bookingRequestId,
        'expected_booking_version': expectedBookingVersion,
      });
      final data = envelope['data'];
      if (data is! Map) {
        throw const FareException(FareFailure.invalidResponse);
      }
      final quote = FareQuote.fromJson(
        data.map((key, value) => MapEntry(key.toString(), value)),
      );
      // A quote for another booking must never back this booking's total.
      if (quote.bookingRequestId != bookingRequestId) {
        throw const FareException(FareFailure.invalidResponse);
      }
      return quote;
    } on FareTransportFailure catch (error) {
      throw FareException(_mapTransport(error));
    } on FareException catch (error, stackTrace) {
      _reportInvalidResponse(error, stackTrace);
      rethrow;
    } on Object catch (error, stackTrace) {
      _report('requesting a fare quote', error, stackTrace);
      throw const FareException(FareFailure.networkFailure);
    }
  }

  @override
  Future<FareQuote> lockQuote({
    required String bookingRequestId,
    required String fareQuoteId,
    required int expectedBookingVersion,
    required int expectedQuoteVersion,
  }) async {
    try {
      final row = await _rpc(
        name: 'rider_lock_fare_quote',
        params: {
          'target_booking_request_id': bookingRequestId,
          'target_fare_quote_id': fareQuoteId,
          'expected_booking_version': expectedBookingVersion,
          'expected_quote_version': expectedQuoteVersion,
        },
      );
      final quote = FareQuote.fromJson(row);
      // The lock response must be the requested quote, at the requested
      // version, and actually locked. Anything else is backend confusion,
      // never a fare the rider may rely on.
      if (quote.bookingRequestId != bookingRequestId ||
          quote.id != fareQuoteId ||
          quote.quoteVersion != expectedQuoteVersion ||
          quote.status != FareQuoteStatus.locked) {
        throw const FareException(FareFailure.invalidResponse);
      }
      return quote;
    } on FareTransportFailure catch (error) {
      throw FareException(_mapTransport(error));
    } on FareException catch (error, stackTrace) {
      _reportInvalidResponse(error, stackTrace);
      rethrow;
    } on Object catch (error, stackTrace) {
      _report('locking a fare quote', error, stackTrace);
      throw const FareException(FareFailure.networkFailure);
    }
  }

  static FareBookingRef _bookingRef(Map<String, dynamic> row) {
    final id = row['id'];
    final version = row['version'];
    if (id is! String || id.isEmpty || version is! int || version < 1) {
      throw const FareException(FareFailure.invalidResponse);
    }
    return FareBookingRef(bookingRequestId: id, version: version);
  }

  static FareFailure _mapTransport(FareTransportFailure error) {
    return switch (error.code) {
      '40001' || 'version_conflict' => FareFailure.versionConflict,
      'P0002' || 'not_found' => FareFailure.notFound,
      '42501' || '403' || 'forbidden' => FareFailure.forbidden,
      '401' ||
      'PGRST301' ||
      'PGRST302' ||
      'PGRST303' =>
        FareFailure.unauthorized,
      'no_pricing_configuration' => FareFailure.pricingUnavailable,
      'quote_expired' => FareFailure.expired,
      'provider_timeout' => FareFailure.timedOut,
      _ => switch (error.status) {
          401 => FareFailure.unauthorized,
          403 => FareFailure.forbidden,
          404 => FareFailure.notFound,
          409 => FareFailure.versionConflict,
          410 => FareFailure.expired,
          504 => FareFailure.timedOut,
          null => FareFailure.networkFailure,
          _ => FareFailure.unavailable,
        },
    };
  }

  void _reportInvalidResponse(FareException error, StackTrace stackTrace) {
    if (error.failure != FareFailure.invalidResponse) return;
    _errorReporter.report(
      operation: 'parsing a fare response',
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _report(String operation, Object error, StackTrace stackTrace) {
    _errorReporter.report(
      operation: operation,
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// Demo-mode placeholder used when the backend is unconfigured.
///
/// The fare screen keeps the current deterministic demo fare path in that
/// mode and never calls this repository; every method throws
/// [FareFailure.unavailable] if reached.
class UnavailableFareRepository implements FareRepository {
  const UnavailableFareRepository();

  @override
  Future<FareBookingRef> createBookingDraft({
    required FareRouteLocation pickup,
    required FareRouteLocation destination,
    required String vehicleTypeCode,
    required String paymentMethod,
    List<FareStopInput> stops = const [],
  }) async {
    throw const FareException(FareFailure.unavailable);
  }

  @override
  Future<FareBookingRef> updateBookingDraft({
    required String bookingRequestId,
    required int expectedBookingVersion,
    required FareRouteLocation pickup,
    required FareRouteLocation destination,
    required String vehicleTypeCode,
    required String paymentMethod,
    List<FareStopInput> stops = const [],
  }) async {
    throw const FareException(FareFailure.unavailable);
  }

  @override
  Future<FareQuote> fetchQuote({
    required String bookingRequestId,
    required int expectedBookingVersion,
    required int routeDistanceMeters,
    required int routeDurationSeconds,
  }) async {
    throw const FareException(FareFailure.unavailable);
  }

  @override
  Future<FareQuote> lockQuote({
    required String bookingRequestId,
    required String fareQuoteId,
    required int expectedBookingVersion,
    required int expectedQuoteVersion,
  }) async {
    throw const FareException(FareFailure.unavailable);
  }
}

/// Scriptable fake for tests.
///
/// [createBookingDraft] mints sequential booking ids at version 1;
/// [updateBookingDraft] bumps the version (mirroring the server-side
/// supersede of `calculated` quotes: previously issued quotes stay stored
/// but new [fetchQuote] calls return the newly issued quote version).
/// Preload quotes with [seedQuote]; fail the next call with [failNext].
/// [calls] logs `create`/`update`/`quote` entries for re-quote verification.
class FakeFareRepository implements FareRepository {
  FakeFareRepository({FareQuote? seedQuote, DateTime Function()? clock})
      : _clock = clock {
    if (seedQuote != null) {
      _quotes[seedQuote.bookingRequestId] = [seedQuote];
      final version = _bookingVersions[seedQuote.bookingRequestId] ?? 1;
      _bookingVersions[seedQuote.bookingRequestId] = version;
    }
  }

  final List<String> calls = [];
  final Map<String, int> _bookingVersions = {};
  // Booking ids whose lock committed, mirroring migration 026: a committed
  // lock links the booking to the locked quote and bumps the booking
  // version by exactly one, so an exact replay stays valid.
  final Map<String, String> _lockedQuoteIds = {};
  final Map<String, List<FareQuote>> _quotes = {};
  final Map<String, bool> _pendingSeed = {};
  FareException? _nextFailure;
  int _bookingSequence = 0;
  int _quoteSequence = 0;

  /// Test-only clock for expiry boundaries. Defaults to wall-clock time;
  /// tests control it to model replay after the original quote's expiry,
  /// which migration 026 still accepts for the linked lock.
  final DateTime Function()? _clock;

  DateTime get _now => (_clock?.call() ?? DateTime.now()).toUtc();

  void failNext(FareException failure) {
    _nextFailure = failure;
  }

  void seedQuote(FareQuote quote) {
    _quotes.putIfAbsent(quote.bookingRequestId, () => []).add(quote);
    _pendingSeed[quote.bookingRequestId] = true;
  }

  List<FareQuote> quotesFor(String bookingRequestId) {
    return List.unmodifiable(_quotes[bookingRequestId] ?? const []);
  }

  void _throwIfScripted(String call) {
    calls.add(call);
    final failure = _nextFailure;
    if (failure != null) {
      _nextFailure = null;
      throw failure;
    }
  }

  @override
  Future<FareBookingRef> createBookingDraft({
    required FareRouteLocation pickup,
    required FareRouteLocation destination,
    required String vehicleTypeCode,
    required String paymentMethod,
    List<FareStopInput> stops = const [],
  }) async {
    _throwIfScripted('create');
    _bookingSequence++;
    final id = 'booking-fake-$_bookingSequence';
    _bookingVersions[id] = 1;
    return FareBookingRef(bookingRequestId: id, version: 1);
  }

  @override
  Future<FareBookingRef> updateBookingDraft({
    required String bookingRequestId,
    required int expectedBookingVersion,
    required FareRouteLocation pickup,
    required FareRouteLocation destination,
    required String vehicleTypeCode,
    required String paymentMethod,
    List<FareStopInput> stops = const [],
  }) async {
    _throwIfScripted('update $bookingRequestId@$expectedBookingVersion');
    final current = _bookingVersions[bookingRequestId];
    if (current == null) {
      throw const FareException(FareFailure.notFound);
    }
    if (current != expectedBookingVersion) {
      throw const FareException(FareFailure.versionConflict);
    }
    final next = current + 1;
    _bookingVersions[bookingRequestId] = next;
    // A new draft lineage starts: a previously committed lock no longer
    // authorizes replays for this booking.
    _lockedQuoteIds.remove(bookingRequestId);
    return FareBookingRef(bookingRequestId: bookingRequestId, version: next);
  }

  @override
  Future<FareQuote> fetchQuote({
    required String bookingRequestId,
    required int expectedBookingVersion,
    required int routeDistanceMeters,
    required int routeDurationSeconds,
  }) async {
    _throwIfScripted(
      'quote $bookingRequestId@$expectedBookingVersion '
      '${routeDistanceMeters}m/${routeDurationSeconds}s',
    );
    final current = _bookingVersions[bookingRequestId];
    if (current == null) {
      throw const FareException(FareFailure.notFound);
    }
    if (current != expectedBookingVersion) {
      throw const FareException(FareFailure.versionConflict);
    }
    // A seeded quote is returned once (e.g. an expired fixture); every
    // other fetch mints a new quote version, mirroring the backend where
    // each calculation supersedes the previous `calculated` quote.
    if (_pendingSeed[bookingRequestId] == true) {
      _pendingSeed[bookingRequestId] = false;
      return _quotes[bookingRequestId]!.last;
    }
    final stored = _quotes[bookingRequestId] ?? const [];
    _quoteSequence++;
    final breakdown = FareBreakdown(
      baseFareFils: 500,
      distanceFils: 1200,
      durationFils: 300,
      stopsFils: 0,
      subtotalFils: 2000,
      minimumFareFils: 1000,
      roundingIncrementFils: 50,
      fixedFareFils: 2000,
    );
    final quote = FareQuote(
      id: 'quote-fake-$_quoteSequence',
      bookingRequestId: bookingRequestId,
      quoteVersion: stored.length + 1,
      pricingVersion: 1,
      fixedFareFils: 2000,
      breakdown: breakdown,
      status: FareQuoteStatus.calculated,
      expiresAt: _now.add(const Duration(minutes: 10)),
      routeDistanceMeters: routeDistanceMeters,
      routeDurationSeconds: routeDurationSeconds,
    );
    _quotes.putIfAbsent(bookingRequestId, () => []).add(quote);
    return quote;
  }

  @override
  Future<FareQuote> lockQuote({
    required String bookingRequestId,
    required String fareQuoteId,
    required int expectedBookingVersion,
    required int expectedQuoteVersion,
  }) async {
    _throwIfScripted(
      'lock $bookingRequestId@$expectedBookingVersion '
      '$fareQuoteId@$expectedQuoteVersion',
    );
    final current = _bookingVersions[bookingRequestId];
    if (current == null) {
      throw const FareException(FareFailure.notFound);
    }
    final quotes = _quotes[bookingRequestId] ?? const [];
    FareQuote? selected;
    for (final quote in quotes) {
      if (quote.id == fareQuoteId) selected = quote;
    }
    if (selected == null) {
      throw const FareException(FareFailure.notFound);
    }
    if (selected.quoteVersion != expectedQuoteVersion) {
      throw const FareException(FareFailure.versionConflict);
    }
    // Migration 026 accepts only an exact replay of the currently linked
    // lock. A replay stays valid even after the original quote's expiry,
    // mirroring the deployed contract, which returns the linked locked row
    // before any other version check.
    if (selected.status == FareQuoteStatus.locked) {
      if (_lockedQuoteIds[bookingRequestId] == selected.id &&
          current == expectedBookingVersion + 1) {
        return selected;
      }
      throw const FareException(FareFailure.versionConflict);
    }
    if (current != expectedBookingVersion) {
      throw const FareException(FareFailure.versionConflict);
    }
    if (!selected.isUsableAt(_now)) {
      throw const FareException(FareFailure.expired);
    }
    final locked = FareQuote(
      id: selected.id,
      bookingRequestId: selected.bookingRequestId,
      quoteVersion: selected.quoteVersion,
      pricingVersion: selected.pricingVersion,
      fixedFareFils: selected.fixedFareFils,
      breakdown: selected.breakdown,
      status: FareQuoteStatus.locked,
      expiresAt: selected.expiresAt,
      currency: selected.currency,
      createdAt: selected.createdAt,
      routeDistanceMeters: selected.routeDistanceMeters,
      routeDurationSeconds: selected.routeDurationSeconds,
    );
    _quotes[bookingRequestId] = [
      for (final quote in quotes)
        if (quote.id == fareQuoteId) locked else quote,
    ];
    _bookingVersions[bookingRequestId] = current + 1;
    _lockedQuoteIds[bookingRequestId] = locked.id;
    return locked;
  }
}
