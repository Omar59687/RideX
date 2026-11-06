import 'dart:async';

import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/trip_realtime.dart';
import 'package:ridex/core/services/trips/trip_realtime_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef TripRealtimeAuthStreamFactory = Stream<Object?> Function();
typedef TripRealtimeChannelFactory = RealtimeChannel Function(String topic);
typedef TripRealtimeChannelRemover = Future<void> Function(
  RealtimeChannel channel,
);

/// Realtime notifications plus canonical reads, both through the same
/// authenticated Supabase client. The channel filters reduce traffic; RLS and
/// the adapter's participant check remain the authorization boundary.
final class SupabaseTripRealtimeSource implements TripRealtimeSource {
  SupabaseTripRealtimeSource(
    SupabaseClient client, {
    TripRealtimeAuthStreamFactory? authStreamFactory,
    TripRealtimeChannelFactory? channelFactory,
    TripRealtimeChannelRemover? channelRemover,
    void Function()? beforeHandlerRegistration,
    void Function()? beforeSubscribe,
  })  : _client = client,
        _authStreamFactory =
            authStreamFactory ?? (() => client.auth.onAuthStateChange),
        _channelFactory = channelFactory ?? client.channel,
        _channelRemover = channelRemover ??
            ((channel) async {
              await client.removeChannel(channel);
            }),
        _beforeHandlerRegistration = beforeHandlerRegistration,
        _beforeSubscribe = beforeSubscribe;

  final SupabaseClient _client;
  final TripRealtimeAuthStreamFactory _authStreamFactory;
  final TripRealtimeChannelFactory _channelFactory;
  final TripRealtimeChannelRemover _channelRemover;
  final void Function()? _beforeHandlerRegistration;
  final void Function()? _beforeSubscribe;
  int _channelCounter = 0;

  @override
  String? get authenticatedUserId => _client.auth.currentUser?.id;

  @override
  Object? get authenticatedSessionIdentity => _client.auth.currentSession;

  @override
  Stream<TripRealtimeSourceSignal> watchTrip(String tripId) {
    if (!isCanonicalTripId(tripId)) {
      return Stream<TripRealtimeSourceSignal>.error(
        const TripRealtimeException(TripRealtimeFailure.invalidTripId),
      );
    }

    return Stream<TripRealtimeSourceSignal>.multi((controller) {
      var active = true;
      var consumerCancelled = false;
      Future<void>? cleanupFuture;
      StreamSubscription<Object?>? authSubscription;
      RealtimeChannel? channel;

      Future<void> performCleanup() async {
        active = false;
        final auth = authSubscription;
        if (auth != null) {
          try {
            await auth.cancel();
          } on Object {
            // Continue channel cleanup if auth-listener cancellation fails.
          }
        }
        final currentChannel = channel;
        if (currentChannel != null) {
          try {
            await _channelRemover(currentChannel);
          } on Object {
            // Cancellation is best-effort and never leaks transport details.
          }
        }
      }

      Future<void> cleanup() {
        final existingCleanup = cleanupFuture;
        if (existingCleanup != null) return existingCleanup;
        final nextCleanup = performCleanup();
        cleanupFuture = nextCleanup;
        return nextCleanup;
      }

      // Install cleanup before creating any resource so both cancellation and
      // setup failures can safely release whichever resources exist so far.
      controller.onCancel = () {
        consumerCancelled = true;
        return cleanup();
      };

      Future<void> failSetup() async {
        await cleanup();
        if (!consumerCancelled) {
          controller.addError(
            const TripRealtimeException(TripRealtimeFailure.sourceUnavailable),
          );
          unawaited(controller.close());
        }
      }

      try {
        final sessionIdentity = authenticatedSessionIdentity;
        authSubscription = _authStreamFactory().listen((_) {
          if (active &&
              !identical(authenticatedSessionIdentity, sessionIdentity)) {
            controller.add(const TripRealtimeSessionChangedSignal());
          }
        });
      } on Object {
        unawaited(failSetup());
        return;
      }

      final topic = 'ridex:trip:${tripId.toLowerCase()}:${_channelCounter++}';
      try {
        final createdChannel = _channelFactory(topic);
        channel = createdChannel;
        _beforeHandlerRegistration?.call();
        void onTripRowChange(PostgresChangePayload payload) {
          final rowId = payload.newRecord['id'] ?? payload.oldRecord['id'];
          if (!active || rowId is! String) return;
          controller.add(
            TripRealtimeChangeSignal(
              tripId: rowId,
              source: TripRealtimeChangeSource.tripRow,
            ),
          );
        }

        final tripRowFilter = PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: tripId,
        );
        createdChannel
          ..onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'trips',
            filter: tripRowFilter,
            callback: onTripRowChange,
          )
          ..onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'trips',
            filter: tripRowFilter,
            callback: onTripRowChange,
          )
          ..onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'trip_status_events',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'trip_id',
              value: tripId,
            ),
            callback: (payload) {
              final row = payload.newRecord;
              final rowTripId = row['trip_id'];
              if (!active || rowTripId is! String) return;
              final sequence = row['sequence'];
              controller.add(
                TripRealtimeChangeSignal(
                  tripId: rowTripId,
                  source: TripRealtimeChangeSource.statusHistory,
                  statusEventSequence: sequence is int ? sequence : null,
                ),
              );
            },
          );

        controller.add(
          const TripRealtimeChannelSignal(TripRealtimeChannelStatus.connecting),
        );
        _beforeSubscribe?.call();
        createdChannel.subscribe((status, error) {
          if (!active) return;
          // Raw SDK errors can contain server details. Consumers receive only
          // a bounded status enum; canonical state is read separately.
          controller.add(TripRealtimeChannelSignal(_mapStatus(status)));
        });
      } on Object {
        // Do not depend on downstream cancellation after a failed synchronous
        // setup step: release partial resources before reporting the failure.
        unawaited(failSetup());
      }
    }, isBroadcast: false);
  }

  @override
  Future<TripRealtimeTrip?> readCanonicalTrip(String tripId) async {
    if (!isCanonicalTripId(tripId)) {
      throw const TripRealtimeException(TripRealtimeFailure.invalidTripId);
    }
    try {
      final row = await _client
          .from('trips')
          .select('id,rider_id,driver_id,status,version')
          .eq('id', tripId)
          .maybeSingle();
      if (row == null) return null;
      try {
        return TripRealtimeTrip.fromRow(row);
      } on FormatException {
        throw const TripRealtimeException(
          TripRealtimeFailure.malformedCanonicalState,
        );
      } on ArgumentError {
        throw const TripRealtimeException(
          TripRealtimeFailure.malformedCanonicalState,
        );
      }
    } on TripRealtimeException {
      rethrow;
    } on Object {
      throw const TripRealtimeException(
        TripRealtimeFailure.sourceUnavailable,
      );
    }
  }

  TripRealtimeChannelStatus _mapStatus(RealtimeSubscribeStatus status) =>
      switch (status) {
        RealtimeSubscribeStatus.subscribed =>
          TripRealtimeChannelStatus.subscribed,
        RealtimeSubscribeStatus.channelError =>
          TripRealtimeChannelStatus.channelError,
        RealtimeSubscribeStatus.closed => TripRealtimeChannelStatus.closed,
        RealtimeSubscribeStatus.timedOut => TripRealtimeChannelStatus.timedOut,
      };
}
