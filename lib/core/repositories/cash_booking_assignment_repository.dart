import 'dart:convert';

import 'package:ridex/core/models/booking_handoff.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Epoch must advance for every logout/account/lifecycle replacement, including
/// A-B-A. Namespace and SDK Session independently prevent cross-backend results.
final class RiderAssignmentOwner {
  const RiderAssignmentOwner(
      this.riderId, this.namespace, this.epoch, this.session);
  final String? riderId;
  final String namespace;
  final int epoch;
  final Object? session;
  bool same(RiderAssignmentOwner other) =>
      riderId == other.riderId &&
      namespace == other.namespace &&
      epoch == other.epoch &&
      identical(session, other.session);
  bool get usable =>
      riderId != null &&
      isCanonicalTripId(riderId!) &&
      namespace.isNotEmpty &&
      epoch >= 0 &&
      session != null;
}

abstract interface class CashAssignmentReadTransport {
  RiderAssignmentOwner get owner;
  Future<Map<String, dynamic>?> readOwnedBooking(String bookingId);
}

enum CashAssignmentFailure {
  unauthorized,
  invalidReference,
  invalidResponse,
  unavailable
}

final class CashAssignmentException implements Exception {
  const CashAssignmentException(this.failure);
  final CashAssignmentFailure failure;
}

/// Lineage only. No Payment ID, settlement/receipt claim or dispatch authority.
final class AssignedCashTrip {
  const AssignedCashTrip._(
      this.tripId,
      this.offerId,
      this.driverId,
      this.vehicleId,
      this.tripVersion,
      this.status,
      this.bookingId,
      this.fareQuoteId,
      this.lockedFareFils,
      this.owner);
  final String tripId,
      offerId,
      driverId,
      vehicleId,
      status,
      bookingId,
      fareQuoteId;
  final int tripVersion, lockedFareFils;
  final RiderAssignmentOwner owner;
}

/// Unwired boundary for Realtime/Driver UI/Rider tracking owners. A notification
/// should cause a reread, never become assignment evidence by itself.
final class CashBookingAssignmentRepository {
  CashBookingAssignmentRepository(this._transport);
  final CashAssignmentReadTransport _transport;
  static final _states = {
    for (final status in DriverTripLifecycleStatus.values) status.backendValue,
  };

  Future<AssignedCashTrip?> read(ConfirmedBookingReference reference) async {
    final owner = _transport.owner;
    final command = reference.command;
    if (!owner.usable || owner.riderId != command.riderId) {
      throw const CashAssignmentException(CashAssignmentFailure.unauthorized);
    }
    if (!isCanonicalTripId(command.bookingRequestId) ||
        !isCanonicalTripId(command.fareQuoteId) ||
        reference.quote.id != command.fareQuoteId ||
        reference.quote.bookingRequestId != command.bookingRequestId ||
        reference.quote.quoteVersion != command.expectedQuoteVersion ||
        !validLockedSnapshot(reference.quote)) {
      throw const CashAssignmentException(
          CashAssignmentFailure.invalidReference);
    }
    void current() {
      if (!owner.same(_transport.owner) || !_transport.owner.usable) {
        throw const CashAssignmentException(CashAssignmentFailure.unauthorized);
      }
    }

    try {
      final b = await _transport
          .readOwnedBooking(command.bookingRequestId)
          .timeout(const Duration(seconds: 15));
      current();
      if (b == null) {
        throw const CashAssignmentException(CashAssignmentFailure.unavailable);
      }
      if (b['id'] != command.bookingRequestId ||
          b['rider_id'] != owner.riderId) {
        throw const CashAssignmentException(CashAssignmentFailure.unauthorized);
      }
      _require(b['payment_method'] == 'cash' &&
          b['fare_quote_id'] == command.fareQuoteId &&
          b['version'] is int &&
          (b['version'] as int) >= command.expectedBookingVersion + 2 &&
          {'confirmed', 'searching', 'matched'}.contains(b['status']));
      final quotes = _rows(b['fare_quotes'])
          .where((q) => q['id'] == command.fareQuoteId)
          .toList();
      _require(quotes.length == 1);
      final q = quotes.single;
      _require(q['rider_id'] == owner.riderId &&
          q['booking_request_id'] == b['id'] &&
          q['locked_at'] is String &&
          DateTime.tryParse(q['locked_at'] as String) != null &&
          FareQuote.fromJson(q) == reference.quote &&
          _equal(q['pickup'], b['pickup']) &&
          _equal(q['destination'], b['destination']) &&
          q['vehicle_type_code'] == b['vehicle_type_code'] &&
          q['ordered_stops'] is List &&
          _equal(q['ordered_stops'], _stops(b['booking_stops'])));
      final trips = _rows(b['trips']);
      if (b['status'] != 'matched') {
        _require(trips.isEmpty);
        return null; // confirmed/searching is not an assigned Trip.
      }
      _require(trips.length == 1);
      final t = trips.single;
      final offers = _rows(b['driver_match_offers'])
          .where((o) => o['status'] == 'accepted')
          .toList();
      _require(offers.length == 1);
      final o = offers.single;
      for (final id in [t['id'], t['driver_id'], t['vehicle_id'], o['id']]) {
        _require(id is String && isCanonicalTripId(id));
      }
      _require(t['booking_request_id'] == b['id'] &&
          t['fare_quote_id'] == q['id'] &&
          t['rider_id'] == owner.riderId &&
          t['driver_id'] == b['matched_driver_id'] &&
          t['vehicle_id'] == b['matched_vehicle_id'] &&
          t['payment_method'] == 'cash' &&
          t['currency'] == 'JOD' &&
          t['original_fare_fils'] == q['fixed_fare_fils'] &&
          t['version'] is int &&
          (t['version'] as int) > 0 &&
          _states.contains(t['status']) &&
          o['booking_request_id'] == b['id'] &&
          o['fare_quote_id'] == q['id'] &&
          o['driver_id'] == t['driver_id'] &&
          o['vehicle_id'] == t['vehicle_id'] &&
          _equal(t['pickup'], q['pickup']) &&
          _equal(t['destination'], q['destination']) &&
          t['route_distance_meters'] == q['route_distance_meters'] &&
          t['route_duration_seconds'] == q['route_duration_seconds'] &&
          t['route_geometry_reference'] == q['route_geometry_reference'] &&
          _equal(_stops(t['trip_stops']), q['ordered_stops']));
      current();
      return AssignedCashTrip._(
          t['id'],
          o['id'],
          t['driver_id'],
          t['vehicle_id'],
          t['version'],
          t['status'],
          b['id'],
          q['id'],
          q['fixed_fare_fils'],
          owner);
    } on Object catch (error) {
      current();
      if (error is CashAssignmentException) rethrow;
      throw const CashAssignmentException(CashAssignmentFailure.unavailable);
    }
  }
}

Never _bad() =>
    throw const CashAssignmentException(CashAssignmentFailure.invalidResponse);
void _require(bool condition) {
  if (!condition) _bad();
}

List<Map<String, dynamic>> _rows(Object? value) {
  if (value == null) return [];
  if (value is Map) return [Map<String, dynamic>.from(value)];
  if (value is! List) _bad();
  return value.map((v) {
    if (v is! Map) _bad();
    return Map<String, dynamic>.from(v);
  }).toList();
}

List<Object?> _stops(Object? value) {
  _require(value is List);
  final rows = _rows(value)
    ..sort((a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int));
  return [for (var i = 0; i < rows.length; i++) _stop(rows[i], i + 1)];
}

Map<String, dynamic> _stop(Map<String, dynamic> row, int sequence) {
  _require(row['sequence'] == sequence && row['location'] is Map);
  return {
    'location': row['location'],
    if (row['label'] != null) 'label': row['label'],
    if (row['rider_note'] != null) 'rider_note': row['rider_note']
  };
}

Object? _canonical(Object? value) {
  if (value is List) return value.map(_canonical).toList();
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {
      for (final k in keys)
        if (value[k] != null) k: _canonical(value[k])
    };
  }
  return value;
}

bool _equal(Object? a, Object? b) =>
    jsonEncode(_canonical(a)) == jsonEncode(_canonical(b));

/// RLS-only SELECT transport. No privileged RPCs, HTTP matching dispatch, service
/// credential, Payment query or new provider/state owner. Caller supplies epoch.
final class SupabaseCashAssignmentReadTransport
    implements CashAssignmentReadTransport {
  SupabaseCashAssignmentReadTransport(
      this._client, this._namespace, this._epoch);
  final SupabaseClient _client;
  final String _namespace;
  final int Function() _epoch;
  @override
  RiderAssignmentOwner get owner {
    final s = _client.auth.currentSession;
    return RiderAssignmentOwner(
        s != null && !s.isExpired ? s.user.id : null, _namespace, _epoch(), s);
  }

  @override
  Future<Map<String, dynamic>?> readOwnedBooking(String bookingId) async {
    final captured = owner;
    void current() {
      if (!captured.usable || !captured.same(owner)) {
        throw const CashAssignmentException(CashAssignmentFailure.unauthorized);
      }
    }

    Future<void> profile() async {
      current();
      final p = await _client
          .from('users')
          .select('id,role,is_blocked')
          .eq('id', captured.riderId!)
          .maybeSingle();
      current();
      if (p == null ||
          p['id'] != captured.riderId ||
          p['role'] != 'rider' ||
          p['is_blocked'] != false) {
        throw const CashAssignmentException(CashAssignmentFailure.unauthorized);
      }
    }

    await profile();
    final row = await _client
        .from('booking_requests')
        .select(
            '*,booking_stops(*),fare_quotes!fare_quotes_booking_rider_fk(*),'
            'trips!trips_booking_request_id_fkey(*,trip_stops(*)),'
            'driver_match_offers!driver_match_offers_booking_request_id_fkey(*)')
        .eq('id', bookingId)
        .eq('rider_id', captured.riderId!)
        .maybeSingle();
    current();
    await profile();
    current();
    return row;
  }
}
