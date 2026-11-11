import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_trip_cancellation.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/rider_trip_tracking_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The assigned-Trip command path is deliberately distinct from the pending
/// BookingRequest cancellation repository. A positive RPC acknowledgement is
/// followed by an authorized canonical read before the result is accepted.
final class SupabaseRiderTripCancellationRepository
    implements RiderTripCancellationRepository {
  SupabaseRiderTripCancellationRepository(
    this._client, {
    required SessionState Function() readSession,
    required RiderTripTrackingRepository tripRepository,
  })  : _readSession = readSession,
        _tripRepository = tripRepository;

  final SupabaseClient _client;
  final SessionState Function() _readSession;
  final RiderTripTrackingRepository _tripRepository;

  @override
  Future<RiderTripCancellationResult> cancelTrip({
    required String tripId,
    required int expectedVersion,
    required String reasonCode,
  }) async {
    final owner = _captureOwner();
    if (owner == null ||
        !isCanonicalTripId(tripId) ||
        expectedVersion < 1 ||
        reasonCode.trim().isEmpty ||
        reasonCode.trim().length > 100) {
      return const RiderTripCancellationUnknown();
    }
    try {
      await _verifyProfile(owner);
      final response = await _client.rpc('rider_cancel_trip', params: {
        'target_trip_id': tripId,
        'expected_version': expectedVersion,
        'reason_code': reasonCode.trim(),
      });
      _requireCurrent(owner);
      if (response is! Map) return const RiderTripCancellationUnknown();
      final row = Map<String, dynamic>.from(response);
      if (row['id'] != tripId ||
          row['rider_id'] != owner.riderId ||
          row['payment_method'] != 'cash' ||
          row['version'] is! int ||
          (row['version'] as int) <= expectedVersion) {
        return const RiderTripCancellationUnknown();
      }
      final latest = await _tripRepository.findByTrip(tripId: tripId);
      _requireCurrent(owner);
      if (latest == null ||
          latest.tripId.toLowerCase() != tripId.toLowerCase() ||
          latest.riderId.toLowerCase() != owner.riderId.toLowerCase() ||
          latest.status != DriverTripLifecycleStatus.cancelledByRider ||
          latest.version <= expectedVersion) {
        return const RiderTripCancellationUnknown();
      }
      return RiderTripCancellationAccepted(latest);
    } on PostgrestException catch (error) {
      if (!_isCurrent(owner)) return const RiderTripCancellationUnknown();
      return RiderTripCancellationRejected(_mapCode(error.code));
    } on Object {
      if (!_isCurrent(owner)) return const RiderTripCancellationUnknown();
      return const RiderTripCancellationUnknown();
    }
  }

  _TripCancelOwner? _captureOwner() {
    final app = _readSession();
    final riderId = app.user?.id;
    final sdk = _client.auth.currentSession;
    if (app.status != SessionStatus.authenticated ||
        app.role != RideRole.rider ||
        app.user == null ||
        app.user!.isBlocked ||
        riderId == null ||
        !isCanonicalTripId(riderId) ||
        _client.auth.currentUser?.id != riderId ||
        sdk == null ||
        sdk.isExpired) {
      return null;
    }
    return _TripCancelOwner(app, riderId, sdk);
  }

  bool _isCurrent(_TripCancelOwner owner) =>
      identical(_readSession(), owner.appSession) &&
      _client.auth.currentUser?.id == owner.riderId &&
      identical(_client.auth.currentSession, owner.sdkSession);

  void _requireCurrent(_TripCancelOwner owner) {
    if (!_isCurrent(owner)) throw const _SessionReplaced();
  }

  Future<void> _verifyProfile(_TripCancelOwner owner) async {
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
      throw const _SessionReplaced();
    }
  }

  RiderTripCancellationRejection _mapCode(String? code) => switch (code) {
        '40001' => RiderTripCancellationRejection.staleVersion,
        '55000' => RiderTripCancellationRejection.notCancellable,
        'P0002' => RiderTripCancellationRejection.notFound,
        '42501' => RiderTripCancellationRejection.blockedOrDenied,
        _ => RiderTripCancellationRejection.backend,
      };
}

final class _TripCancelOwner {
  const _TripCancelOwner(this.appSession, this.riderId, this.sdkSession);
  final SessionState appSession;
  final String riderId;
  final Session sdkSession;
}

final class _SessionReplaced implements Exception {
  const _SessionReplaced();
}
