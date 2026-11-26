import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The subset actually returned by `user_trip_history_v1`. This intentionally
/// does not pretend the RPC contains booking, route, fare, or Rider fields.
final class RiderHistorySummary {
  RiderHistorySummary({
    required this.tripId,
    required this.version,
    required this.status,
    required this.createdAt,
    required this.paymentId,
    required this.paymentVersion,
    required this.paymentMethod,
  }) {
    if (!isCanonicalTripId(tripId) || version < 1 ||
        (paymentId != null && !isCanonicalTripId(paymentId!)) ||
        (paymentVersion != null && paymentVersion! < 1) ||
        ((paymentId == null) != (paymentVersion == null)) ||
        (paymentId != null && paymentMethod == null)) {
      throw const FormatException('Invalid Rider history summary.');
    }
  }

  final String tripId;
  final int version;
  final DriverTripLifecycleStatus status;
  final DateTime createdAt;
  final String? paymentId;
  final int? paymentVersion;
  final PaymentMethod? paymentMethod;
}

final class RiderHistorySummaryCursor {
  const RiderHistorySummaryCursor({
    required this.createdAt,
    required this.tripId,
  });
  final DateTime createdAt;
  final String tripId;
}

final class RiderHistorySummaryPage {
  RiderHistorySummaryPage({
    required List<RiderHistorySummary> rows,
    this.nextCursor,
  }) : rows = List.unmodifiable(rows);
  final List<RiderHistorySummary> rows;
  final RiderHistorySummaryCursor? nextCursor;
}

final class RiderHistorySummarySessionChanged implements Exception {
  const RiderHistorySummarySessionChanged();
}

abstract interface class RiderHistorySummaryReader {
  Future<RiderHistorySummaryPage> readPage({
    int limit = 20,
    RiderHistorySummaryCursor? cursor,
  });
  Future<RiderHistorySummary?> readExactTrip(String tripId);
}

/// Read-only production adapter for the reviewed A04 history RPC and exact
/// participant-RLS Trip query. All reads use the authenticated app client.
final class SupabaseRiderHistorySummaryRepository
    implements RiderHistorySummaryReader {
  SupabaseRiderHistorySummaryRepository({
    required this.client,
    required this.riderId,
    required this.readSession,
    required this.isCurrent,
  }) : _sdkSession = client.auth.currentSession;

  final SupabaseClient client;
  final String riderId;
  final SessionState Function() readSession;
  final bool Function() isCurrent;
  final Session? _sdkSession;

  bool get _authorized => _sdkSession != null &&
      !_sdkSession.isExpired &&
      _sdkSession.user.id == riderId &&
      identical(client.auth.currentSession, _sdkSession) &&
      isCurrent() &&
      _isRider(readSession(), riderId);

  @override
  Future<RiderHistorySummaryPage> readPage({
    int limit = 20,
    RiderHistorySummaryCursor? cursor,
  }) async {
    if (limit < 1 ||
        limit > 50 ||
        !_authorized ||
        (cursor != null &&
            (!isCanonicalTripId(cursor.tripId) || !cursor.createdAt.isUtc))) {
      throw const FormatException('Rider history is unavailable.');
    }
    await _verifyProfile();
    final response = await client.rpc(
      'user_trip_history_v1',
      params: {
        'page_size': limit,
        'before_created_at': cursor?.createdAt.toUtc().toIso8601String(),
        'before_trip_id': cursor?.tripId,
      },
    );
    if (!_authorized) throw const RiderHistorySummarySessionChanged();
    await _verifyProfile();
    if (response is! List || response.length > limit) {
      throw const FormatException('Invalid Rider history page.');
    }
    final rows = response.map(_parseRow).toList(growable: false);
    RiderHistorySummary? previous;
    for (final row in rows) {
      if (previous != null && !_isBefore(row, previous)) {
        throw const FormatException('Rider history order is invalid.');
      }
      if (cursor != null && !_isBefore(row, RiderHistorySummary(
            tripId: cursor.tripId,
            version: 1,
            status: DriverTripLifecycleStatus.accepted,
            createdAt: cursor.createdAt,
            paymentId: null,
            paymentVersion: null,
            paymentMethod: null,
          ))) {
        throw const FormatException('Rider history cursor was ignored.');
      }
      previous = row;
    }
    final next = rows.length == limit && rows.isNotEmpty
        ? RiderHistorySummaryCursor(
            createdAt: rows.last.createdAt,
            tripId: rows.last.tripId,
          )
        : null;
    return RiderHistorySummaryPage(rows: rows, nextCursor: next);
  }

  @override
  Future<RiderHistorySummary?> readExactTrip(String tripId) async {
    if (!_authorized || !isCanonicalTripId(tripId)) {
      throw const RiderHistorySummarySessionChanged();
    }
    await _verifyProfile();
    final row = await client
        .from('trips')
        .select('id,rider_id,version,status,created_at,payment_method')
        .eq('id', tripId)
        .eq('rider_id', riderId)
        .maybeSingle();
    if (!_authorized) throw const RiderHistorySummarySessionChanged();
    await _verifyProfile();
    if (row == null) return null;
    if (row['id'] != tripId || row['rider_id'] != riderId) {
      throw const FormatException('Trip ownership mismatch.');
    }
    return RiderHistorySummary(
      tripId: tripId,
      version: _positiveInt(row['version']),
      status: _status(row['status']),
      createdAt: _timestamp(row['created_at']),
      paymentId: null,
      paymentVersion: null,
      paymentMethod: _method(row['payment_method']),
    );
  }

  Future<void> _verifyProfile() async {
    if (!_authorized) throw const RiderHistorySummarySessionChanged();
    final row = await client
        .from('users')
        .select('id,role,is_blocked')
        .eq('id', riderId)
        .maybeSingle();
    if (!_authorized || row == null || row['id'] != riderId ||
        row['role'] != 'rider' || row['is_blocked'] != false) {
      throw const RiderHistorySummarySessionChanged();
    }
  }

  RiderHistorySummary _parseRow(Object? value) {
    if (value is! Map) throw const FormatException('Invalid history row.');
    final row = Map<String, Object?>.from(value);
    if (row['contract_version'] != 1) {
      throw const FormatException('Unsupported history contract.');
    }
    final tripId = _uuid(row['trip_id']);
    final paymentId = row['payment_id'] == null
        ? null
        : _uuid(row['payment_id']);
    final paymentVersion = row['payment_version'] == null
        ? null
        : _positiveInt(row['payment_version']);
    final paymentMethod = _method(row['payment_method']);
    if ((paymentId == null) != (paymentVersion == null) ||
        (paymentId == null) != (paymentMethod == null)) {
      throw const FormatException('Incomplete history Payment linkage.');
    }
    return RiderHistorySummary(
      tripId: tripId,
      version: _positiveInt(row['trip_version']),
      status: _status(row['trip_status']),
      createdAt: _timestamp(row['created_at']),
      paymentId: paymentId,
      paymentVersion: paymentVersion,
      paymentMethod: paymentMethod,
    );
  }
}

bool _isRider(SessionState state, String riderId) =>
    state.status == SessionStatus.authenticated &&
    state.role == RideRole.rider &&
    state.user?.id == riderId &&
    state.user?.isBlocked == false;

String _uuid(Object? value) {
  if (value is! String || !isCanonicalTripId(value)) {
    throw const FormatException('Invalid history UUID.');
  }
  return value;
}

int _positiveInt(Object? value) {
  if (value is! int || value < 1 || value > 2147483647) {
    throw const FormatException('Invalid history version.');
  }
  return value;
}

DateTime _timestamp(Object? value) {
  if (value is! String) throw const FormatException('Invalid history time.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw const FormatException('Invalid history time.');
  }
  return parsed;
}

DriverTripLifecycleStatus _status(Object? value) {
  if (value is! String) throw const FormatException('Invalid history status.');
  try {
    return DriverTripLifecycleStatus.fromBackendValue(value);
  } on ArgumentError {
    throw const FormatException('Invalid history status.');
  }
}

PaymentMethod? _method(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Invalid payment method.');
  try {
    return PaymentMethod.fromBackendValue(value);
  } on ArgumentError {
    throw const FormatException('Invalid payment method.');
  }
}

bool _isBefore(RiderHistorySummary left, RiderHistorySummary right) =>
    left.createdAt.isBefore(right.createdAt) ||
    (left.createdAt.isAtSameMomentAs(right.createdAt) &&
        left.tripId.compareTo(right.tripId) < 0);
