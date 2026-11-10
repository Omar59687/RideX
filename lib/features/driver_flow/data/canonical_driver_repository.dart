import 'dart:async';

import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/repositories/driver_eligibility_repository.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';

/// Borrowed, authenticated access. IDs locate rows; they never grant access.
/// Implementations must use the same normal-user client for eligibility, reads
/// and commands. A missing delivery adapter must not invent offer observations.
abstract interface class CanonicalDriverPort
    implements DriverEligibilityTransport {
  Object? get sessionIdentity;
  Future<Map<String, Object?>?> readAvailability();
  Future<Map<String, Object?>?> readOffer(String offerId);
  Future<Map<String, Object?>?> readBooking(String bookingId);
  Future<Map<String, Object?>?> readTrip(String tripId);
  Future<Map<String, Object?>?> readTripForBooking(String bookingId);
  Future<Object?> acceptOffer(String offerId, int version, String key);
  Future<Object?> declineOffer(String offerId, int version, String key);
}

enum CanonicalDriverOutcome {
  observed,
  accepted,
  declined,
  expired,
  stale,
  unauthorized,
  unavailable,
  unknown,
  unsupported,
}

enum CanonicalOfferDecision { accept, decline }

/// Minimal canonical identity. No fabricated journey, fare, or UI projection.
final class CanonicalDriverOffer {
  CanonicalDriverOffer._(Map<String, Object?> row)
      : id = _id(row['id']),
        driverId = _id(row['driver_id']),
        bookingId = _id(row['booking_request_id']),
        quoteId = _id(row['fare_quote_id']),
        vehicleId = _id(row['vehicle_id']),
        version = _version(row['version']),
        status = _text(row['status']),
        expiresAt = _date(row['expires_at']) {
    if (!{'offered', 'accepted', 'declined', 'expired', 'cancelled'}
        .contains(status)) {
      throw const FormatException('Invalid canonical offer.');
    }
  }
  final String id, driverId, bookingId, quoteId, vehicleId, status;
  final int version;
  final DateTime expiresAt;

  bool _sameJourney(CanonicalDriverOffer other) =>
      id == other.id &&
      driverId == other.driverId &&
      bookingId == other.bookingId &&
      quoteId == other.quoteId &&
      vehicleId == other.vehicleId &&
      expiresAt == other.expiresAt;
}

final class CanonicalDriverTrip {
  CanonicalDriverTrip._(Map<String, Object?> row)
      : id = _id(row['id']),
        driverId = _id(row['driver_id']),
        riderId = _id(row['rider_id']),
        bookingId = _id(row['booking_request_id']),
        quoteId = _id(row['fare_quote_id']),
        vehicleId = _id(row['vehicle_id']),
        version = _version(row['version']),
        status =
            DriverTripLifecycleStatus.fromBackendValue(_text(row['status'])) {
    if (row['payment_method'] != 'cash') {
      throw const FormatException('Only canonical Cash reads are supported.');
    }
  }
  final String id, driverId, riderId, bookingId, quoteId, vehicleId;
  final int version;
  final DriverTripLifecycleStatus status;
}

/// Revocable point-in-time read, not a UI authorization lease. A future host
/// must listen to shared auth invalidation and dispose all copied display data.
final class CanonicalDriverResult {
  CanonicalDriverResult._(this._outcome, this._current,
      {DriverFlowAvailability? availability,
      CanonicalDriverOffer? offer,
      CanonicalDriverTrip? trip})
      : _availability = availability,
        _offer = offer,
        _trip = trip;
  final CanonicalDriverOutcome _outcome;
  final bool Function() _current;
  final DriverFlowAvailability? _availability;
  final CanonicalDriverOffer? _offer;
  final CanonicalDriverTrip? _trip;
  CanonicalDriverOutcome get outcome =>
      _current() ? _outcome : CanonicalDriverOutcome.unauthorized;
  DriverFlowAvailability? get availability => _current() ? _availability : null;
  CanonicalDriverOffer? get offer => _current() ? _offer : null;
  CanonicalDriverTrip? get trip => _current() ? _trip : null;
}

/// Inactive preparation seam. Not a DriverFlowRepository: simulated B01-B06
/// results cannot become canonical authority. No runtime provider constructs it.
/// Writes require explicit reviewed composition; the default is read-only.
final class CanonicalDriverRepository {
  CanonicalDriverRepository(this._port,
      {this.offerCommandsEnabled = false,
      DateTime Function()? clock,
      this.readTimeout = const Duration(seconds: 10),
      this.commandTimeout = const Duration(seconds: 15)})
      : _owner = _port.currentOwner,
        _session = _port.sessionIdentity,
        _clock = clock ?? DateTime.now;

  final CanonicalDriverPort _port;
  final DriverAuthorityOwner _owner;
  final Object? _session;
  final DateTime Function() _clock;
  final bool offerCommandsEnabled;
  final Duration readTimeout, commandTimeout;
  bool _disposed = false;
  bool _revoked = false;
  _OfferAttempt? _attempt;
  final Map<String, CanonicalDriverOffer> _offers = {};
  final Map<String, CanonicalDriverTrip> _trips = {};
  final Set<String> _staleOffers = {};
  final Set<String> _staleTrips = {};

  bool get _current {
    try {
      return !_disposed &&
          !_revoked &&
          _owner.isUsable &&
          _session != null &&
          _port.currentOwner.isUsable &&
          _owner.sameOwner(_port.currentOwner) &&
          identical(_session, _port.sessionIdentity);
    } on Object {
      return false;
    }
  }

  void dispose() {
    _disposed = true;
    _offers.clear();
    _trips.clear();
  }

  CanonicalDriverResult _result(CanonicalDriverOutcome outcome,
          {DriverFlowAvailability? availability,
          CanonicalDriverOffer? offer,
          CanonicalDriverTrip? trip}) =>
      CanonicalDriverResult._(outcome, () => _current,
          availability: availability, offer: offer, trip: trip);

  Future<void> _authorize() async {
    _check();
    final eligibility = await DriverEligibilityRepository(_port)
        .validate()
        .timeout(readTimeout);
    _check();
    if (eligibility is! DriverEligible ||
        !_owner.sameOwner(eligibility.owner)) {
      if (eligibility is DriverIneligible &&
          eligibility.failure ==
              DriverEligibilityFailure.transportUnavailable) {
        throw const _Failure(CanonicalDriverOutcome.unavailable);
      }
      _revoked = true;
      throw const _Failure(CanonicalDriverOutcome.unauthorized);
    }
  }

  void _check() {
    if (!_current) {
      throw const _Failure(CanonicalDriverOutcome.unauthorized);
    }
  }

  Future<Map<String, Object?>?> _read(
      Future<Map<String, Object?>?> Function() action) async {
    _check();
    final row = await action().timeout(readTimeout);
    _check();
    return row;
  }

  Future<DriverFlowAvailability> _availability() async {
    final row = await _read(_port.readAvailability);
    if (row == null) throw const _Failure(CanonicalDriverOutcome.unavailable);
    if (_id(row['driver_id']) != _owner.driverId?.toLowerCase()) {
      throw const _Failure(CanonicalDriverOutcome.unauthorized);
    }
    final value = DriverFlowAvailability(
      state: DriverAvailabilityStateX.fromDatabase(_text(row['state'])),
      version: _version(row['version']),
      vehicleId: _nullableId(row['vehicle_id']),
      bookingId: _nullableId(row['reserved_booking_request_id']),
      tripId: _nullableId(row['active_trip_id']),
    );
    if (value.state == DriverAvailabilityState.offline &&
        value.vehicleId != null) {
      throw const FormatException('Invalid offline availability.');
    }
    return value;
  }

  Future<CanonicalDriverOffer> _offer(String id) async {
    if (_staleOffers.contains(id)) {
      throw const _Failure(CanonicalDriverOutcome.stale);
    }
    final row = await _read(() => _port.readOffer(id));
    if (row == null) throw const _Failure(CanonicalDriverOutcome.unavailable);
    final value = CanonicalDriverOffer._(row);
    if (value.id != id || value.driverId != _owner.driverId?.toLowerCase()) {
      throw const _Failure(CanonicalDriverOutcome.unauthorized);
    }
    final prior = _offers[id];
    if (prior != null &&
        (!prior._sameJourney(value) ||
            value.version < prior.version ||
            (value.version == prior.version && value.status != prior.status))) {
      _staleOffers.add(id);
      throw const _Failure(CanonicalDriverOutcome.stale);
    }
    _offers[id] = value;
    return value;
  }

  CanonicalDriverTrip _trip(Map<String, Object?> row) {
    final value = CanonicalDriverTrip._(row);
    if (value.driverId != _owner.driverId?.toLowerCase()) {
      throw const _Failure(CanonicalDriverOutcome.unauthorized);
    }
    if (_staleTrips.contains(value.id)) {
      throw const _Failure(CanonicalDriverOutcome.stale);
    }
    final prior = _trips[value.id];
    if (prior != null &&
        (value.bookingId != prior.bookingId ||
            value.quoteId != prior.quoteId ||
            value.vehicleId != prior.vehicleId ||
            value.riderId != prior.riderId ||
            value.version < prior.version ||
            (value.version == prior.version && value.status != prior.status))) {
      _staleTrips.add(value.id);
      throw const _Failure(CanonicalDriverOutcome.stale);
    }
    _trips[value.id] = value;
    return value;
  }

  /// Exact offer ID must come from a separately approved delivery owner.
  Future<CanonicalDriverResult> observe({String? offerId}) async {
    try {
      if (offerId != null) _id(offerId);
      await _authorize();
      final availability = await _availability();
      final offer =
          offerId == null ? null : await _offer(offerId.toLowerCase());
      await _authorize();
      return _result(CanonicalDriverOutcome.observed,
          availability: availability, offer: offer);
    } on Object catch (error) {
      return _failure(error);
    }
  }

  Future<CanonicalDriverResult> readTrip(String tripId,
      {int? expectedVersion}) async {
    try {
      final id = _id(tripId);
      await _authorize();
      final row = await _read(() => _port.readTrip(id));
      if (row == null) return _result(CanonicalDriverOutcome.unavailable);
      final trip = _trip(row);
      if (trip.id != id) return _result(CanonicalDriverOutcome.unauthorized);
      if (expectedVersion != null && trip.version != expectedVersion) {
        return _result(CanonicalDriverOutcome.stale);
      }
      await _authorize();
      return _result(CanonicalDriverOutcome.observed, trip: trip);
    } on Object catch (error) {
      return _failure(error);
    }
  }

  /// No fabricated Realtime/offer delivery. One-shot observe/read remain usable.
  Stream<CanonicalDriverResult> watch() =>
      Stream.value(_result(CanonicalDriverOutcome.unavailable));

  /// No progression/completion/settlement/receipt/payment command surface.
  CanonicalDriverResult unsupportedCommand() =>
      _result(CanonicalDriverOutcome.unsupported);

  Future<CanonicalDriverResult> decideOffer(CanonicalDriverOffer observed,
      CanonicalOfferDecision decision, String idempotencyKey) {
    if (!_current) {
      return Future.value(_result(CanonicalDriverOutcome.unauthorized));
    }
    if (!offerCommandsEnabled) {
      return Future.value(_result(CanonicalDriverOutcome.unavailable));
    }
    if (idempotencyKey.trim() != idempotencyKey ||
        idempotencyKey.isEmpty ||
        idempotencyKey.length > 200) {
      return Future.value(_result(CanonicalDriverOutcome.unavailable));
    }
    final existing = _attempt;
    if (existing != null) {
      if (existing.matches(observed, decision, idempotencyKey)) {
        return existing.pending ?? Future.value(existing.result!);
      }
      // UNKNOWN, stale, pending or completed attempts never authorize another
      // write through a new key. This preparation instance handles one intent.
      return Future.value(_result(CanonicalDriverOutcome.unknown));
    }
    final attempt = _OfferAttempt(observed, decision, idempotencyKey);
    _attempt = attempt;
    return attempt.pending = _decide(attempt).then((result) {
      attempt.result = result;
      attempt.pending = null;
      return result;
    });
  }

  Future<CanonicalDriverResult> _decide(_OfferAttempt attempt) async {
    try {
      await _authorize();
      final offer = await _offer(attempt.offer.id);
      if (!offer._sameJourney(attempt.offer) ||
          offer.version != attempt.offer.version ||
          offer.status != 'offered') {
        return _result(CanonicalDriverOutcome.stale);
      }
      final availability = await _availability();
      if (availability.state != DriverAvailabilityState.reserved ||
          availability.bookingId != offer.bookingId ||
          availability.vehicleId != offer.vehicleId) {
        return _result(CanonicalDriverOutcome.stale);
      }
      final booking = await _read(() => _port.readBooking(offer.bookingId));
      if (booking == null) return _result(CanonicalDriverOutcome.unavailable);
      if (_id(booking['id']) != offer.bookingId ||
          _id(booking['fare_quote_id']) != offer.quoteId ||
          booking['status'] != 'searching') {
        return _result(CanonicalDriverOutcome.stale);
      }
      if (booking['payment_method'] != 'cash') {
        return _result(CanonicalDriverOutcome.unsupported);
      }
      await _authorize();
      if (!_clock().toUtc().isBefore(offer.expiresAt)) {
        return _result(CanonicalDriverOutcome.expired);
      }
      _check();
      attempt.dispatched = true;
      try {
        // RPC response is an acknowledgement only, never assignment authority.
        await (attempt.decision == CanonicalOfferDecision.accept
                ? _port.acceptOffer(offer.id, offer.version, attempt.key)
                : _port.declineOffer(offer.id, offer.version, attempt.key))
            .timeout(commandTimeout);
      } on Object {
        // Timeout/network/server conflict may race a committed write. No replay.
      }
      _check();
      return await _reconcile(attempt);
    } on Object catch (error) {
      return attempt.dispatched && _current
          ? _result(CanonicalDriverOutcome.unknown)
          : _failure(error);
    }
  }

  /// Read-only recovery of the original attempt. Absence/RLS filtering, expiry,
  /// another offer, or an RPC reply alone never proves a negative outcome.
  Future<CanonicalDriverResult> reconcile() async {
    final attempt = _attempt;
    if (attempt == null || !attempt.dispatched) {
      return _result(CanonicalDriverOutcome.unavailable);
    }
    if (attempt.pending != null) return attempt.pending!;
    try {
      final result = await _reconcile(attempt);
      attempt.result = result;
      return result;
    } on Object catch (error) {
      return _current
          ? _result(CanonicalDriverOutcome.unknown)
          : _failure(error);
    }
  }

  Future<CanonicalDriverResult> _reconcile(_OfferAttempt attempt) async {
    await _authorize();
    final offer = await _offer(attempt.offer.id);
    if (!offer._sameJourney(attempt.offer) ||
        offer.version <= attempt.offer.version) {
      return _result(CanonicalDriverOutcome.unknown);
    }
    final row = await _read(() => _port.readTripForBooking(offer.bookingId));
    if (offer.status == 'accepted' && row != null) {
      final trip = _trip(row);
      if (trip.bookingId != offer.bookingId ||
          trip.quoteId != offer.quoteId ||
          trip.vehicleId != offer.vehicleId) {
        return _result(CanonicalDriverOutcome.unknown);
      }
      await _authorize();
      return _result(CanonicalDriverOutcome.accepted, offer: offer, trip: trip);
    }
    if (attempt.decision == CanonicalOfferDecision.decline &&
        offer.status == 'declined' &&
        row == null) {
      await _authorize();
      return _result(CanonicalDriverOutcome.declined, offer: offer);
    }
    return _result(CanonicalDriverOutcome.unknown);
  }

  CanonicalDriverResult _failure(Object error) => _result(
      error is _Failure ? error.outcome : CanonicalDriverOutcome.unavailable);
}

final class _OfferAttempt {
  _OfferAttempt(this.offer, this.decision, this.key);
  final CanonicalDriverOffer offer;
  final CanonicalOfferDecision decision;
  final String key;
  bool dispatched = false;
  Future<CanonicalDriverResult>? pending;
  CanonicalDriverResult? result;
  bool matches(CanonicalDriverOffer other, CanonicalOfferDecision action,
          String token) =>
      offer._sameJourney(other) &&
      offer.version == other.version &&
      action == decision &&
      token == key;
}

final class _Failure implements Exception {
  const _Failure(this.outcome);
  final CanonicalDriverOutcome outcome;
}

String _id(Object? value) {
  if (value is! String || !isCanonicalTripId(value)) {
    throw const FormatException('Canonical identity required.');
  }
  return value.toLowerCase();
}

String? _nullableId(Object? value) => value == null ? null : _id(value);
int _version(Object? value) {
  if (value is! int || value < 1) {
    throw const FormatException('Positive canonical version required.');
  }
  return value;
}

String _text(Object? value) {
  if (value is! String) {
    throw const FormatException('Canonical state required.');
  }
  return value;
}

DateTime _date(Object? value) {
  if (value is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw const FormatException('Canonical timestamp required.');
  }
  return DateTime.parse(value).toUtc();
}
