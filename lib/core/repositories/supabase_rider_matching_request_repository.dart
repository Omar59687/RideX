import 'package:ridex/core/models/booking_handoff.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/rider_matching_request.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin authenticated client for the existing server-only A05 composition.
/// The app sends locators and an optimistic version only; service credentials
/// never enter Flutter and an Edge result is never accepted as Trip authority.
final class SupabaseRiderMatchingRequestRepository
    implements RiderMatchingRequestRepository {
  SupabaseRiderMatchingRequestRepository(
    this._client, {
    required SessionState Function() readSession,
  }) : _readSession = readSession;

  final SupabaseClient _client;
  final SessionState Function() _readSession;

  @override
  Future<RiderMatchingRequestResult> requestMatching(
    ConfirmedBookingReference reference, {
    required int expectedBookingVersion,
  }
  ) async {
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
      throw const RiderMatchingException(RiderMatchingFailure.unauthorized);
    }
    final command = reference.command;
    final quote = reference.quote;
    if (command.riderId.toLowerCase() != riderId.toLowerCase() ||
        command.bookingRequestId.toLowerCase() !=
            quote.bookingRequestId.toLowerCase() ||
        command.fareQuoteId.toLowerCase() != quote.id.toLowerCase() ||
        quote.status != FareQuoteStatus.locked ||
        quote.currency != 'JOD' ||
        quote.fixedFareFils < 0 ||
        !validLockedSnapshot(quote)) {
      throw const RiderMatchingException(
        RiderMatchingFailure.invalidReference,
      );
    }
    if (expectedBookingVersion < command.expectedBookingVersion + 2 ||
        expectedBookingVersion <= 0) {
      throw const RiderMatchingException(
        RiderMatchingFailure.invalidReference,
      );
    }

    try {
      final response = await _client.functions.invoke(
        'cash-matching',
        body: {
          'booking_request_id': command.bookingRequestId,
          'fare_quote_id': command.fareQuoteId,
          'expected_booking_version': expectedBookingVersion,
        },
      );
      if (!_sameOwner(session, riderId, sdkSession)) {
        throw const RiderMatchingException(RiderMatchingFailure.unauthorized);
      }
      final envelope = response.data;
      if (envelope is! Map || envelope['data'] is! Map) {
        throw const RiderMatchingException(
          RiderMatchingFailure.invalidResponse,
        );
      }
      return riderMatchingResultFromJson(
        envelope['data'] as Map,
        expectedBookingId: command.bookingRequestId,
        expectedQuoteId: command.fareQuoteId,
      );
    } on RiderMatchingException {
      rethrow;
    } on FunctionException catch (error) {
      if (!_sameOwner(session, riderId, sdkSession)) {
        throw const RiderMatchingException(RiderMatchingFailure.unauthorized);
      }
      throw RiderMatchingException(_failureFromFunction(error));
    } on Object {
      if (!_sameOwner(session, riderId, sdkSession)) {
        throw const RiderMatchingException(RiderMatchingFailure.unauthorized);
      }
      throw const RiderMatchingException(RiderMatchingFailure.unavailable);
    }
  }

  bool _sameOwner(SessionState session, String riderId, Object sdkSession) {
    final current = _client.auth.currentSession;
    return identical(_readSession(), session) &&
        _client.auth.currentUser?.id == riderId &&
        current != null &&
        identical(current, sdkSession);
  }

  RiderMatchingFailure _failureFromFunction(FunctionException error) {
    final details = error.details;
    final dynamic raw = details is Map
        ? (details['error'] is Map
            ? details['error']['code']
            : details['code'])
        : null;
    return switch (raw) {
      'unauthorized' || 'forbidden' => RiderMatchingFailure.unauthorized,
      'invalid_request' => RiderMatchingFailure.invalidReference,
      'conflict' || 'version_conflict' => RiderMatchingFailure.conflict,
      'invalid_state' || 'invalid_response' =>
        RiderMatchingFailure.invalidResponse,
      _ => RiderMatchingFailure.unavailable,
    };
  }
}
