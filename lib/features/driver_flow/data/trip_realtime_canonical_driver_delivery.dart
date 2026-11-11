import 'dart:async';

import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/trip_realtime.dart';
import 'package:ridex/core/services/trips/trip_realtime_adapter.dart';
import 'package:ridex/core/services/trips/trip_realtime_source.dart';
import 'package:ridex/features/driver_flow/domain/canonical_driver_delivery.dart';

/// Bridges advisory D02 Trip observations into B08's existing Driver delivery
/// seam. [tripId] must already be pinned by a B07 canonical read; this class
/// cannot discover offers, assign Trips, or establish Driver authorization.
final class TripRealtimeCanonicalDriverDelivery
    implements CanonicalDriverDelivery {
  TripRealtimeCanonicalDriverDelivery({
    required TripRealtimeSource source,
    required String tripId,
    required String assignedDriverId,
  })  : _source = source,
        _tripId = tripId.toLowerCase(),
        _assignedDriverId = assignedDriverId.toLowerCase() {
    if (!isCanonicalTripId(_tripId) ||
        !isCanonicalTripId(_assignedDriverId)) {
      throw ArgumentError('Canonical Trip and Driver IDs are required.');
    }
  }

  final TripRealtimeSource _source;
  final String _tripId;
  final String _assignedDriverId;
  int _revision = 0;

  @override
  Stream<CanonicalDriverDeliverySignal> get signals =>
      Stream<CanonicalDriverDeliverySignal>.multi((controller) {
        final userId = _source.authenticatedUserId?.toLowerCase();
        final session = _source.authenticatedSessionIdentity;
        if (userId != _assignedDriverId || session == null) {
          controller.add(CanonicalDriverConnectionHint(
            _revision++,
            connected: false,
          ));
          unawaited(controller.close());
          return;
        }

        final adapter = TripRealtimeAdapter(_source);
        StreamSubscription<TripRealtimeUpdate>? subscription;
        var active = true;
        var cancelPending = false;

        void cancelSource() {
          active = false;
          final current = subscription;
          if (current == null) {
            cancelPending = true;
          } else {
            unawaited(current.cancel());
          }
        }

        void emitConnection(bool connected) {
          if (active) {
            controller.add(CanonicalDriverConnectionHint(
              _revision++,
              connected: connected,
            ));
          }
        }

        controller.onCancel = () async {
          active = false;
          await subscription?.cancel();
        };

        try {
          final createdSubscription = adapter.watchTrip(_tripId).listen((update) {
            if (!active ||
                _source.authenticatedUserId?.toLowerCase() != userId ||
                !identical(_source.authenticatedSessionIdentity, session)) {
              emitConnection(false);
              cancelSource();
              unawaited(controller.close());
              return;
            }
            if (update case TripRealtimeConnectionUpdate(:final status)) {
              emitConnection(status == TripRealtimeChannelStatus.subscribed);
              return;
            }
            if (update case VerifiedTripRealtimeEvent(:final trip)) {
              if (trip.tripId.toLowerCase() != _tripId ||
                  trip.driverId.toLowerCase() != _assignedDriverId ||
                  _source.authenticatedUserId?.toLowerCase() !=
                      _assignedDriverId) {
                emitConnection(false);
                cancelSource();
                unawaited(controller.close());
                return;
              }
              controller.add(CanonicalDriverTripHint(
                _revision++,
                _tripId,
              ));
            }
          }, onError: (Object _, StackTrace __) {
            emitConnection(false);
            cancelSource();
            unawaited(controller.close());
          }, onDone: () {
            emitConnection(false);
            cancelSource();
            unawaited(controller.close());
          });
          subscription = createdSubscription;
          if (cancelPending) unawaited(createdSubscription.cancel());
        } on Object {
          emitConnection(false);
          cancelSource();
          unawaited(controller.close());
        }
      }, isBroadcast: false);
}
