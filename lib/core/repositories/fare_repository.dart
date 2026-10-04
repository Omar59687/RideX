import 'package:equatable/equatable.dart';
import 'package:ridex/core/models/fare_quote.dart';
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

/// Provider-neutral fare contract.
///
/// Flutter calls `rider_create_booking_draft` / `rider_update_booking_draft`
/// directly via PostgREST RPC (granted to `authenticated`) and reaches the
/// `service_role`-only `backend_calculate_fare_quote` exclusively through
/// the `fare` Edge function (`quote` operation). Flutter never calculates
/// fares: [fetchQuote] returns the backend-computed [FareQuote].
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
}

class SupabaseFareRepository implements FareRepository {
  const SupabaseFareRepository({
    required FareRpcCaller rpc,
    required FareEdgeCaller quoteEdge,
    AppErrorReporter errorReporter = const NoopAppErrorReporter(),
  })  : _rpc = rpc,
        _quoteEdge = quoteEdge,
        _errorReporter = errorReporter;

  final FareRpcCaller _rpc;
  final FareEdgeCaller _quoteEdge;
  final AppErrorReporter _errorReporter;

  @override
  Future<FareBookingRef> createBookingDraft({
    required FareRouteLocation pickup,
    required FareRouteLocation destination,
    required String vehicleTypeCode,
    required String paymentMethod,
    List<FareStopInput> stops = const [],
  }) async {
    try {
      final row = await _rpc(
        name: 'rider_create_booking_draft',
        params: {
          'requested_pickup': pickup.toJson(),
          'requested_destination': destination.toJson(),
          'requested_vehicle_type': vehicleTypeCode,
          'requested_payment_method': paymentMethod,
          'requested_stops': [for (final stop in stops) stop.toJson()],
        },
      );
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
      final row = await _rpc(
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
      );
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
        'route_distance_meters': routeDistanceMeters,
        'route_duration_seconds': routeDurationSeconds,
      });
      final data = envelope['data'];
      if (data is! Map) {
        throw const FareException(FareFailure.invalidResponse);
      }
      return FareQuote.fromJson(
        data.map((key, value) => MapEntry(key.toString(), value)),
      );
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
      '42501' || 'forbidden' => FareFailure.forbidden,
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
  FakeFareRepository({FareQuote? seedQuote}) {
    if (seedQuote != null) {
      _quotes[seedQuote.bookingRequestId] = [seedQuote];
      final version = _bookingVersions[seedQuote.bookingRequestId] ?? 1;
      _bookingVersions[seedQuote.bookingRequestId] = version;
    }
  }

  final List<String> calls = [];
  final Map<String, int> _bookingVersions = {};
  final Map<String, List<FareQuote>> _quotes = {};
  final Map<String, bool> _pendingSeed = {};
  FareException? _nextFailure;
  int _bookingSequence = 0;
  int _quoteSequence = 0;

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
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      routeDistanceMeters: routeDistanceMeters,
      routeDurationSeconds: routeDurationSeconds,
    );
    _quotes.putIfAbsent(bookingRequestId, () => []).add(quote);
    return quote;
  }
}
