import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/rider_booking_cancellation.dart';
import 'package:ridex/core/models/rider_booking_search.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/rider_booking_cancellation_repository.dart';
import 'package:ridex/core/repositories/rider_booking_search_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Participant-scoped status read for one BookingRequest. The ID is only a
/// locator; both the authenticated Rider profile and row ownership are checked.
final class SupabaseRiderBookingSearchRepository
    implements RiderBookingSearchRepository {
  SupabaseRiderBookingSearchRepository(
    this._client, {
    required SessionState Function() readSession,
  }) : _readSession = readSession;

  final SupabaseClient _client;
  final SessionState Function() _readSession;

  @override
  Future<RiderBookingSearchSnapshot?> readBooking({
    required String bookingRequestId,
  }) async {
    if (!isCanonicalTripId(bookingRequestId)) {
      throw ArgumentError.value(bookingRequestId, 'bookingRequestId');
    }
    final owner = _captureOwner();
    try {
      await _verifyProfile(owner);
      final row = await _client
          .from('booking_requests')
          .select('id,rider_id,version,status,payment_method')
          .eq('id', bookingRequestId)
          .eq('rider_id', owner.riderId)
          .maybeSingle();
      _requireCurrent(owner);
      await _verifyProfile(owner);
      if (row == null) return null;
      if (row['id'] != bookingRequestId ||
          row['rider_id'] != owner.riderId ||
          row['version'] is! int ||
          row['status'] is! String ||
          row['payment_method'] != PaymentMethod.cash.backendValue) {
        throw const RiderBookingSearchReadException(
          RiderBookingSearchReadFailure.invalidResponse,
        );
      }
      return RiderBookingSearchSnapshot(
        bookingRequestId: row['id'] as String,
        riderId: row['rider_id'] as String,
        version: row['version'] as int,
        status: RiderBookingSearchStatus.fromBackendValue(
          row['status'] as String,
        ),
        paymentMethod: PaymentMethod.fromBackendValue(
          row['payment_method'] as String,
        ),
      );
    } on RiderBookingSearchReadException {
      rethrow;
    } on Object {
      _requireCurrent(owner);
      throw const RiderBookingSearchReadException(
        RiderBookingSearchReadFailure.unavailable,
      );
    }
  }

  _RiderReadOwner _captureOwner() {
    final session = _readSession();
    final riderId = session.user?.id;
    final sdkSession = _client.auth.currentSession;
    if (session.status != SessionStatus.authenticated ||
        session.role != RideRole.rider ||
        session.user == null ||
        session.user!.isBlocked ||
        riderId == null ||
        !isCanonicalTripId(riderId) ||
        _client.auth.currentUser?.id != riderId ||
        sdkSession == null ||
        sdkSession.isExpired) {
      throw const RiderBookingSearchReadException(
        RiderBookingSearchReadFailure.unavailable,
      );
    }
    return _RiderReadOwner(session, riderId, sdkSession);
  }

  void _requireCurrent(_RiderReadOwner owner) {
    if (!identical(_readSession(), owner.session) ||
        _client.auth.currentUser?.id != owner.riderId ||
        !identical(_client.auth.currentSession, owner.sdkSession)) {
      throw const RiderBookingSearchReadException(
        RiderBookingSearchReadFailure.unavailable,
      );
    }
  }

  Future<void> _verifyProfile(_RiderReadOwner owner) async {
    _requireCurrent(owner);
    final profile = await _client
        .from('users')
        .select('id,role,is_blocked')
        .eq('id', owner.riderId)
        .maybeSingle();
    _requireCurrent(owner);
    if (profile == null ||
        profile['id'] != owner.riderId ||
        profile['role'] != 'rider' ||
        profile['is_blocked'] != false) {
      throw const RiderBookingSearchReadException(
        RiderBookingSearchReadFailure.unavailable,
      );
    }
  }
}

/// Uses the existing owner/version-protected `rider_cancel_booking` RPC.
/// A response is reported as accepted only if it is the same owned Cash
/// BookingRequest and its canonical status/version prove cancellation.
final class SupabaseRiderBookingCancellationRepository
    implements RiderBookingCancellationRepository {
  SupabaseRiderBookingCancellationRepository(
    this._client, {
    required SessionState Function() readSession,
  }) : _readSession = readSession;

  final SupabaseClient _client;
  final SessionState Function() _readSession;

  @override
  Future<RiderBookingCancellationResult> cancelBooking({
    required String bookingRequestId,
    required int expectedVersion,
    required String reasonCode,
  }) async {
    final owner = _captureOwner();
    if (owner == null) return const RiderBookingCancellationUnknown();
    if (!isCanonicalTripId(bookingRequestId) ||
        expectedVersion < 1 ||
        !isValidCancellationReason(reasonCode)) {
      return const RiderBookingCancellationRejected(
        RiderCancellationRejection.reasonInvalid,
      );
    }
    try {
      final response = await _client.rpc('rider_cancel_booking', params: {
        'target_booking_request_id': bookingRequestId,
        'expected_version': expectedVersion,
        'reason_code': reasonCode.trim(),
      });
      _requireCurrent(owner);
      if (response is! Map) return const RiderBookingCancellationUnknown();
      final row = Map<String, dynamic>.from(response);
      if (row['id'] != bookingRequestId ||
          row['rider_id'] != owner.riderId ||
          row['payment_method'] != 'cash' ||
          row['status'] != 'cancelled' ||
          row['version'] is! int ||
          (row['version'] as int) <= expectedVersion) {
        return const RiderBookingCancellationUnknown();
      }
      return RiderBookingCancellationAccepted(
        RiderBookingSearchSnapshot(
          bookingRequestId: row['id'] as String,
          riderId: row['rider_id'] as String,
          version: row['version'] as int,
          status: RiderBookingSearchStatus.cancelled,
          paymentMethod: PaymentMethod.cash,
        ),
      );
    } on PostgrestException catch (error) {
      if (!_isCurrent(owner)) return const RiderBookingCancellationUnknown();
      return RiderBookingCancellationRejected(_mapCancellationCode(error.code));
    } on Object {
      if (!_isCurrent(owner)) return const RiderBookingCancellationUnknown();
      return const RiderBookingCancellationUnknown();
    }
  }

  _RiderReadOwner? _captureOwner() {
    final session = _readSession();
    final riderId = session.user?.id;
    final sdkSession = _client.auth.currentSession;
    if (session.status != SessionStatus.authenticated ||
        session.role != RideRole.rider ||
        session.user == null ||
        session.user!.isBlocked ||
        riderId == null ||
        !isCanonicalTripId(riderId) ||
        _client.auth.currentUser?.id != riderId ||
        sdkSession == null ||
        sdkSession.isExpired) {
      return null;
    }
    return _RiderReadOwner(session, riderId, sdkSession);
  }

  bool _isCurrent(_RiderReadOwner owner) =>
      identical(_readSession(), owner.session) &&
      _client.auth.currentUser?.id == owner.riderId &&
      identical(_client.auth.currentSession, owner.sdkSession);

  void _requireCurrent(_RiderReadOwner owner) {
    if (!_isCurrent(owner)) throw const RiderBookingCancellationUnknown();
  }

  RiderCancellationRejection _mapCancellationCode(String? code) => switch (code) {
        '40001' => RiderCancellationRejection.staleVersion,
        '55000' => RiderCancellationRejection.notCancellable,
        'P0002' => RiderCancellationRejection.notFound,
        '22023' => RiderCancellationRejection.reasonInvalid,
        '42501' => RiderCancellationRejection.blockedOrDenied,
        _ => RiderCancellationRejection.backend,
      };
}

final class _RiderReadOwner {
  const _RiderReadOwner(this.session, this.riderId, this.sdkSession);
  final SessionState session;
  final String riderId;
  final Session sdkSession;
}
