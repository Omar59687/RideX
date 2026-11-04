import 'dart:async';

import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/rider_trip_location.dart';
import 'package:ridex/core/services/trips/rider_trip_location_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef RiderLocationAuthStreamFactory = Stream<Object?> Function();
typedef RiderLocationChannelFactory = RealtimeChannel Function(String topic);
typedef RiderLocationChannelRemover = Future<void> Function(
  RealtimeChannel channel,
);

/// Read-only `driver_locations` adapter. Notifications only trigger a
/// participant-scoped canonical reread in [RiderTripLocationAdapter].
final class SupabaseRiderTripLocationSource
    implements RiderTripLocationSource {
  SupabaseRiderTripLocationSource(
    SupabaseClient client, {
    RiderLocationAuthStreamFactory? authStreamFactory,
    RiderLocationChannelFactory? channelFactory,
    RiderLocationChannelRemover? channelRemover,
    void Function()? beforeHandlerRegistration,
    void Function()? beforeSubscribe,
  })  : _client = client,
        _authStreamFactory =
            authStreamFactory ?? (() => client.auth.onAuthStateChange),
        _channelFactory = channelFactory ?? client.channel,
        _channelRemover = channelRemover ??
            ((channel) async => client.removeChannel(channel)),
        _beforeHandlerRegistration = beforeHandlerRegistration,
        _beforeSubscribe = beforeSubscribe;

  final SupabaseClient _client;
  final RiderLocationAuthStreamFactory _authStreamFactory;
  final RiderLocationChannelFactory _channelFactory;
  final RiderLocationChannelRemover _channelRemover;
  final void Function()? _beforeHandlerRegistration;
  final void Function()? _beforeSubscribe;
  int _channelCounter = 0;

  @override
  String? get authenticatedUserId => _client.auth.currentUser?.id;

  @override
  Object? get authenticatedSessionIdentity => _client.auth.currentSession;

  @override
  Stream<RiderTripLocationSourceSignal> watchTripLocation(String tripId) {
    if (!isCanonicalTripId(tripId)) {
      return Stream<RiderTripLocationSourceSignal>.error(
        const RiderTripLocationException(RiderTripLocationFailure.invalidTripId),
      );
    }

    return Stream<RiderTripLocationSourceSignal>.multi((controller) {
      var active = true;
      var consumerCancelled = false;
      Future<void>? cleanupFuture;
      StreamSubscription<Object?>? authSubscription;
      RealtimeChannel? channel;

      Future<void> cleanupResources() async {
        active = false;
        final auth = authSubscription;
        if (auth != null) {
          try {
            await auth.cancel();
          } on Object {
            // Attempt channel removal even if auth listener cleanup fails.
          }
        }
        final partialChannel = channel;
        if (partialChannel != null) {
          try {
            await _channelRemover(partialChannel);
          } on Object {
            // Do not expose transport details to consumers.
          }
        }
      }

      Future<void> cleanup() => cleanupFuture ??= cleanupResources();

      // Install cleanup before registering auth or creating the channel.
      controller.onCancel = () {
        consumerCancelled = true;
        return cleanup();
      };

      Future<void> failSetup() async {
        await cleanup();
        if (!consumerCancelled) {
          controller.addError(
            const RiderTripLocationException(
              RiderTripLocationFailure.sourceUnavailable,
            ),
          );
          unawaited(controller.close());
        }
      }

      try {
        final userId = authenticatedUserId;
        final session = authenticatedSessionIdentity;
        authSubscription = _authStreamFactory().listen((_) {
          if (active &&
              (authenticatedUserId != userId ||
                  !identical(authenticatedSessionIdentity, session))) {
            controller.add(const RiderTripLocationSessionChangedSignal());
          }
        }, onError: (Object _) {
          if (active) {
            controller.add(const RiderTripLocationSessionChangedSignal());
          }
        });
      } on Object {
        unawaited(failSetup());
        return;
      }

      try {
        final createdChannel = _channelFactory(
          'ridex:driver-location:${tripId.toLowerCase()}:${_channelCounter++}',
        );
        channel = createdChannel;
        _beforeHandlerRegistration?.call();
        createdChannel.onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'driver_locations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'trip_id',
            value: tripId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            final rowTripId = row['trip_id'];
            final driverId = row['driver_id'];
            if (!active || rowTripId is! String || driverId is! String) {
              return;
            }
            controller.add(
              RiderTripLocationChangedSignal(
                tripId: rowTripId,
                driverId: driverId,
              ),
            );
          },
        );
        controller.add(
          const RiderTripLocationChannelSignal(
            RiderTripLocationChannelStatus.connecting,
          ),
        );
        _beforeSubscribe?.call();
        createdChannel.subscribe((status, error) {
          if (!active) return;
          controller.add(
            RiderTripLocationChannelSignal(_mapStatus(status)),
          );
        });
      } on Object {
        unawaited(failSetup());
      }
    }, isBroadcast: false);
  }

  @override
  Future<RiderTripLocation?> readLatestTripLocation({
    required String tripId,
    required String driverId,
  }) async {
    if (!isCanonicalTripId(tripId) || !isCanonicalTripId(driverId)) {
      throw const RiderTripLocationException(
        RiderTripLocationFailure.invalidTripId,
      );
    }
    try {
      final row = await _client
          .from('driver_locations')
          .select(
            'trip_id, driver_id, sequence, latitude, longitude, '
            'accuracy_meters, heading_degrees, speed_meters_per_second, '
            'recorded_at, received_at',
          )
          .eq('trip_id', tripId)
          .eq('driver_id', driverId)
          .order('sequence', ascending: false)
          .limit(1)
          .maybeSingle();
      return row == null ? null : RiderTripLocation.fromRow(row);
    } on RiderTripLocationException {
      rethrow;
    } on Object {
      throw const RiderTripLocationException(
        RiderTripLocationFailure.sourceUnavailable,
      );
    }
  }

  static RiderTripLocationChannelStatus _mapStatus(
    RealtimeSubscribeStatus status,
  ) => switch (status) {
        RealtimeSubscribeStatus.subscribed =>
          RiderTripLocationChannelStatus.subscribed,
        RealtimeSubscribeStatus.channelError =>
          RiderTripLocationChannelStatus.channelError,
        RealtimeSubscribeStatus.closed => RiderTripLocationChannelStatus.closed,
        RealtimeSubscribeStatus.timedOut =>
          RiderTripLocationChannelStatus.timedOut,
      };
}
