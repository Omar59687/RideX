import 'dart:async';

import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/rider_trip_location.dart';
import 'package:ridex/core/models/trip_realtime.dart';
import 'package:ridex/core/services/trips/rider_trip_location_source.dart';
import 'package:ridex/core/services/trips/trip_realtime_adapter.dart';

typedef RiderTripLocationDelay = Future<void> Function(Duration duration);

/// Rider-only location stream layered on D02's canonical Trip verification.
/// Every snapshot comes from an exact Trip/Driver read; transport payloads are
/// used only to trigger a reread.
final class RiderTripLocationAdapter {
  RiderTripLocationAdapter({
    required TripRealtimeAdapter trips,
    required RiderTripLocationSource locations,
    DateTime Function()? clock,
    RiderTripLocationDelay? delay,
    this.maximumLocationAge = const Duration(seconds: 45),
  })  : _trips = trips,
        _locations = locations,
        _clock = clock ?? DateTime.now,
        _delay = delay ?? ((duration) => Future<void>.delayed(duration)) {
    if (maximumLocationAge <= Duration.zero) {
      throw ArgumentError.value(maximumLocationAge, 'maximumLocationAge');
    }
  }

  final TripRealtimeAdapter _trips;
  final RiderTripLocationSource _locations;
  final DateTime Function() _clock;
  final RiderTripLocationDelay _delay;
  final Duration maximumLocationAge;

  Stream<RiderTripLocationUpdate> watchTrip(String tripId) =>
      Stream<RiderTripLocationUpdate>.multi((controller) {
        if (!isCanonicalTripId(tripId)) {
          controller.addError(
            const RiderTripLocationException(
              RiderTripLocationFailure.invalidTripId,
            ),
          );
          unawaited(controller.close());
          return;
        }

        final ownerId = _locations.authenticatedUserId;
        final sessionIdentity = _locations.authenticatedSessionIdentity;
        if (ownerId == null ||
            !isCanonicalTripId(ownerId) ||
            sessionIdentity == null) {
          controller.addError(
            const RiderTripLocationException(
              RiderTripLocationFailure.unauthenticated,
            ),
          );
          unawaited(controller.close());
          return;
        }

        final normalizedTripId = tripId.toLowerCase();
        final normalizedOwnerId = ownerId.toLowerCase();
        var cancelled = false;
        var terminated = false;
        var tripSubscriptionReady = false;
        var sourceGeneration = 0;
        var retryGeneration = 0;
        var retryPending = false;
        var retryAttempt = 0;
        var latestTripVersion = 0;
        var locationReadEpoch = 0;
        var locationReadInFlight = false;
        int? connectedSourceGeneration;
        int? pendingReadGeneration;
        String? assignedDriverId;
        RiderTripLocation? latestLocation;
        var highestLocationSequence = 0;
        DateTime? highestReceivedAt;
        DateTime? highestRecordedAt;
        StreamSubscription<TripRealtimeUpdate>? tripSubscription;
        StreamSubscription<RiderTripLocationSourceSignal>? locationSubscription;
        Future<void>? stopAllFuture;
        var queue = Future<void>.value();
        final pending = <Future<void> Function()>[];

        bool isActive() => !cancelled && !terminated;

        bool sessionIsCurrent() =>
            _locations.authenticatedUserId?.toLowerCase() ==
                normalizedOwnerId &&
            identical(
              _locations.authenticatedSessionIdentity,
              sessionIdentity,
            );

        void emit(RiderTripLocationUpdate update) {
          if (isActive()) controller.add(update);
        }

        Future<void> stopLocationSource() async {
          sourceGeneration++;
          retryGeneration++;
          retryPending = false;
          final subscription = locationSubscription;
          locationSubscription = null;
          if (subscription != null) await subscription.cancel();
        }

        Future<void> stopAll() async {
          final existing = stopAllFuture;
          if (existing != null) {
            await existing;
            return;
          }
          final cleanup = () async {
            await stopLocationSource();
            final subscription = tripSubscription;
            tripSubscription = null;
            if (subscription != null) await subscription.cancel();
          }();
          stopAllFuture = cleanup;
          await cleanup;
        }

        void terminate(RiderTripLocationClearReason reason) {
          if (!isActive()) return;
          locationReadEpoch++;
          pendingReadGeneration = null;
          connectedSourceGeneration = null;
          if (latestLocation != null || assignedDriverId != null) {
            controller.add(RiderTripLocationCleared(reason));
          }
          latestLocation = null;
          assignedDriverId = null;
          terminated = true;
          unawaited(stopAll());
          unawaited(controller.close());
        }

        void clearStaleLocation() {
          if (latestLocation == null) return;
          latestLocation = null;
          emit(const RiderTripLocationCleared(
            RiderTripLocationClearReason.staleLocation,
          ));
        }

        void fail(RiderTripLocationFailure failure) {
          if (!isActive()) return;
          locationReadEpoch++;
          pendingReadGeneration = null;
          connectedSourceGeneration = null;
          if (latestLocation != null || assignedDriverId != null) {
            controller.add(RiderTripLocationCleared(
              failure == RiderTripLocationFailure.sessionChanged
                  ? RiderTripLocationClearReason.sessionChanged
                  : RiderTripLocationClearReason.authorizationRevoked,
            ));
          }
          latestLocation = null;
          assignedDriverId = null;
          terminated = true;
          controller.addError(RiderTripLocationException(failure));
          unawaited(stopAll());
          unawaited(controller.close());
        }

        void enqueue(Future<void> Function() action) {
          queue = queue.then((_) async {
            if (!isActive()) return;
            try {
              await action();
            } on RiderTripLocationException catch (error) {
              if (error.failure == RiderTripLocationFailure.sourceUnavailable ||
                  error.failure == RiderTripLocationFailure.malformedLocation) {
                emit(RiderTripLocationVerificationUpdate(error.failure));
              } else {
                fail(error.failure);
              }
            } on TripRealtimeException catch (error) {
              fail(error.failure == TripRealtimeFailure.sessionChanged
                  ? RiderTripLocationFailure.sessionChanged
                  : RiderTripLocationFailure.notAuthorized);
            } on Object {
              if (isActive()) {
                emit(const RiderTripLocationVerificationUpdate(
                  RiderTripLocationFailure.sourceUnavailable,
                ));
              }
            }
          });
        }

        void schedule(Future<void> Function() action) {
          if (!tripSubscriptionReady) {
            pending.add(action);
          } else {
            enqueue(action);
          }
        }

        bool isReadCurrent(int generation, int readEpoch) =>
            isActive() &&
            readEpoch == locationReadEpoch &&
            generation == sourceGeneration &&
            connectedSourceGeneration == generation;

        Future<void> verifyCanonicalLocation({
          required String expectedTripId,
          required String expectedDriverId,
          required int generation,
          required int readEpoch,
        }) async {
          if (!isReadCurrent(generation, readEpoch)) return;
          if (!sessionIsCurrent()) {
            throw const RiderTripLocationException(
              RiderTripLocationFailure.sessionChanged,
            );
          }
          final location = await _locations.readLatestTripLocation(
            tripId: expectedTripId,
            driverId: expectedDriverId,
          );
          if (!isReadCurrent(generation, readEpoch)) return;
          if (!sessionIsCurrent()) {
            throw const RiderTripLocationException(
              RiderTripLocationFailure.sessionChanged,
            );
          }
          if (location == null) {
            clearStaleLocation();
            return;
          }
          if (location.tripId.toLowerCase() != expectedTripId.toLowerCase() ||
              location.driverId.toLowerCase() !=
                  expectedDriverId.toLowerCase()) {
            return;
          }
          final now = _clock().toUtc();
          final age = now.difference(location.receivedAt);
          if (location.receivedAt.isAfter(now) ||
              location.recordedAt.isAfter(now) ||
              age > maximumLocationAge ||
              age.isNegative) {
            clearStaleLocation();
            return;
          }
          final previousReceivedAt = highestReceivedAt;
          final previousRecordedAt = highestRecordedAt;
          if (location.sequence <= highestLocationSequence ||
              (previousReceivedAt != null &&
                  !location.receivedAt.isAfter(previousReceivedAt)) ||
              (previousRecordedAt != null &&
                  location.recordedAt.isBefore(previousRecordedAt))) {
            return;
          }
          latestLocation = location;
          highestLocationSequence = location.sequence;
          highestReceivedAt = location.receivedAt;
          highestRecordedAt = location.recordedAt;
          emit(RiderTripLocationSnapshot(location));
        }

        void handleLocationReadFailure(
          Object error,
          int generation,
          int readEpoch,
        ) {
          if (!isReadCurrent(generation, readEpoch)) return;
          if (error is RiderTripLocationException) {
            if (error.failure == RiderTripLocationFailure.sourceUnavailable ||
                error.failure == RiderTripLocationFailure.malformedLocation) {
              emit(RiderTripLocationVerificationUpdate(error.failure));
            } else {
              fail(error.failure);
            }
            return;
          }
          if (error is TripRealtimeException) {
            fail(error.failure == TripRealtimeFailure.sessionChanged
                ? RiderTripLocationFailure.sessionChanged
                : RiderTripLocationFailure.notAuthorized);
            return;
          }
          emit(const RiderTripLocationVerificationUpdate(
            RiderTripLocationFailure.sourceUnavailable,
          ));
        }

        void requestCanonicalLocationRead({
          required String expectedTripId,
          required String expectedDriverId,
          required int generation,
        }) {
          if (!isActive() || connectedSourceGeneration != generation) return;
          if (locationReadInFlight) {
            // Keep only the latest requested generation while a prior read is
            // unresolved. A reconnect can proceed without starting unbounded
            // concurrent database reads.
            pendingReadGeneration = generation;
            return;
          }
          locationReadInFlight = true;
          final readEpoch = locationReadEpoch;
          unawaited(() async {
            try {
              await verifyCanonicalLocation(
                expectedTripId: expectedTripId,
                expectedDriverId: expectedDriverId,
                generation: generation,
                readEpoch: readEpoch,
              );
            } on Object catch (error) {
              handleLocationReadFailure(error, generation, readEpoch);
            } finally {
              locationReadInFlight = false;
              final pendingGeneration = pendingReadGeneration;
              pendingReadGeneration = null;
              if (pendingGeneration != null &&
                  isActive() &&
                  connectedSourceGeneration == pendingGeneration &&
                  sourceGeneration == pendingGeneration) {
                final driverId = assignedDriverId;
                if (driverId != null) {
                  requestCanonicalLocationRead(
                    expectedTripId: normalizedTripId,
                    expectedDriverId: driverId,
                    generation: pendingGeneration,
                  );
                }
              }
            }
          }());
        }

        void scheduleRetry(
          int generation,
          Future<void> Function() reconnect,
        ) {
          if (!isActive() || generation != sourceGeneration || retryPending) {
            return;
          }
          retryPending = true;
          final attempt = retryAttempt++;
          final exponent = attempt > 5 ? 5 : attempt;
          final seconds = 1 << exponent;
          final delay = Duration(seconds: seconds > 30 ? 30 : seconds);
          final currentRetry = ++retryGeneration;
          unawaited(() async {
            try {
              await _delay(delay);
            } on Object {
              // A failed injected delay cannot bypass lifecycle checks.
            }
            if (!isActive() ||
                generation != sourceGeneration ||
                currentRetry != retryGeneration ||
                !retryPending) {
              return;
            }
            final previous = locationSubscription;
            locationSubscription = null;
            if (previous != null) await previous.cancel();
            if (isActive() &&
                generation == sourceGeneration &&
                currentRetry == retryGeneration &&
                retryPending) {
              retryPending = false;
              await reconnect();
            }
          }());
        }

        void handleTerminalTripUpdate(VerifiedTripRealtimeEvent update) {
          if (!isActive()) return;
          if (!sessionIsCurrent()) {
            terminate(RiderTripLocationClearReason.sessionChanged);
            return;
          }
          final trip = update.trip;
          if (trip.tripId.toLowerCase() != normalizedTripId ||
              trip.riderId.toLowerCase() != normalizedOwnerId) {
            fail(RiderTripLocationFailure.notAuthorized);
            return;
          }
          if (trip.version < latestTripVersion) return;
          final currentDriverId = assignedDriverId;
          if (currentDriverId != null &&
              currentDriverId.toLowerCase() != trip.driverId.toLowerCase()) {
            terminate(RiderTripLocationClearReason.assignmentChanged);
            return;
          }
          latestTripVersion = trip.version;
          assignedDriverId = trip.driverId;
          terminate(RiderTripLocationClearReason.terminalTrip);
        }

        Future<void> startLocationSource() async {
          final currentDriverId = assignedDriverId;
          if (!isActive() ||
              currentDriverId == null ||
              locationSubscription != null) {
            return;
          }
          final generation = ++sourceGeneration;
          final expectedDriverId = currentDriverId;
          try {
            final subscription = _locations
                .watchTripLocation(normalizedTripId)
                .listen(
                  (signal) {
                    if (!isActive() || generation != sourceGeneration) return;
                    if (signal is RiderTripLocationSessionChangedSignal ||
                        !sessionIsCurrent()) {
                      terminate(RiderTripLocationClearReason.sessionChanged);
                      return;
                    }
                    if (signal
                        case RiderTripLocationChannelSignal(:final status)) {
                      if (status == RiderTripLocationChannelStatus.subscribed) {
                        connectedSourceGeneration = generation;
                        retryPending = false;
                        retryAttempt = 0;
                        retryGeneration++;
                        emit(RiderTripLocationConnectionUpdate(status));
                        schedule(() async {
                          if (isReadCurrent(generation, locationReadEpoch)) {
                            requestCanonicalLocationRead(
                              expectedTripId: normalizedTripId,
                              expectedDriverId: expectedDriverId,
                              generation: generation,
                            );
                          }
                        });
                      } else {
                        connectedSourceGeneration = null;
                        locationReadEpoch++;
                        pendingReadGeneration = null;
                        clearStaleLocation();
                        emit(RiderTripLocationConnectionUpdate(status));
                        if (status ==
                                RiderTripLocationChannelStatus.channelError ||
                            status == RiderTripLocationChannelStatus.closed ||
                            status ==
                                RiderTripLocationChannelStatus.timedOut) {
                          scheduleRetry(generation, startLocationSource);
                        }
                      }
                      return;
                    }
                    if (signal is RiderTripLocationChangedSignal &&
                        connectedSourceGeneration != generation) {
                      return;
                    }
                    schedule(() async {
                      if (!isActive() || generation != sourceGeneration) return;
                      if (signal
                          case RiderTripLocationChangedSignal change) {
                        if (change.tripId.toLowerCase() != normalizedTripId ||
                            change.driverId.toLowerCase() !=
                                expectedDriverId.toLowerCase()) {
                          return;
                        }
                        requestCanonicalLocationRead(
                          expectedTripId: normalizedTripId,
                          expectedDriverId: expectedDriverId,
                          generation: generation,
                        );
                      }
                    });
                  },
                  onError: (Object _) {
                    if (!isActive() || generation != sourceGeneration) return;
                    if (!sessionIsCurrent()) {
                      terminate(RiderTripLocationClearReason.sessionChanged);
                      return;
                    }
                    connectedSourceGeneration = null;
                    locationReadEpoch++;
                    pendingReadGeneration = null;
                    clearStaleLocation();
                    emit(const RiderTripLocationConnectionUpdate(
                      RiderTripLocationChannelStatus.channelError,
                    ));
                    scheduleRetry(generation, startLocationSource);
                  },
                  onDone: () {
                    if (!isActive() || generation != sourceGeneration) return;
                    connectedSourceGeneration = null;
                    locationReadEpoch++;
                    pendingReadGeneration = null;
                    clearStaleLocation();
                    emit(const RiderTripLocationConnectionUpdate(
                      RiderTripLocationChannelStatus.closed,
                    ));
                    scheduleRetry(generation, startLocationSource);
                  },
            );
            if (isActive() && generation == sourceGeneration) {
              locationSubscription = subscription;
            } else {
              unawaited(subscription.cancel());
            }
          } on Object {
            connectedSourceGeneration = null;
            locationReadEpoch++;
            pendingReadGeneration = null;
            clearStaleLocation();
            emit(const RiderTripLocationConnectionUpdate(
              RiderTripLocationChannelStatus.channelError,
            ));
            scheduleRetry(generation, startLocationSource);
          }
        }

        Future<void> handleTripUpdate(TripRealtimeUpdate update) async {
          if (!sessionIsCurrent()) {
            terminate(RiderTripLocationClearReason.sessionChanged);
            return;
          }
          if (update is! VerifiedTripRealtimeEvent) return;
          final trip = update.trip;
          if (trip.tripId.toLowerCase() != normalizedTripId ||
              trip.riderId.toLowerCase() != normalizedOwnerId) {
            fail(RiderTripLocationFailure.notAuthorized);
            return;
          }
          if (trip.version < latestTripVersion) return;
          if (trip.version == latestTripVersion && latestTripVersion > 0) {
            final currentDriver = assignedDriverId;
            if (currentDriver != null &&
                currentDriver.toLowerCase() != trip.driverId.toLowerCase()) {
              fail(RiderTripLocationFailure.notAuthorized);
            }
            return;
          }
          final currentDriverId = assignedDriverId;
          if (currentDriverId != null &&
              currentDriverId.toLowerCase() != trip.driverId.toLowerCase()) {
            terminate(RiderTripLocationClearReason.assignmentChanged);
            return;
          }
          latestTripVersion = trip.version;
          assignedDriverId = trip.driverId;

          if (isRiderTripLocationTerminal(trip.status)) {
            terminate(RiderTripLocationClearReason.terminalTrip);
            return;
          }
          if (!isRiderTripLocationActive(trip.status)) {
            terminate(RiderTripLocationClearReason.noLongerActive);
            return;
          }
          await startLocationSource();
        }

        void handleTripStreamUpdate(TripRealtimeUpdate update) {
          if (!isActive()) return;
          if (!sessionIsCurrent()) {
            terminate(RiderTripLocationClearReason.sessionChanged);
            return;
          }
          if (update is VerifiedTripRealtimeEvent) {
            final trip = update.trip;
            if (trip.tripId.toLowerCase() != normalizedTripId ||
                trip.riderId.toLowerCase() != normalizedOwnerId) {
              fail(RiderTripLocationFailure.notAuthorized);
              return;
            }
            if (trip.version < latestTripVersion) return;
            if (isRiderTripLocationTerminal(trip.status)) {
              handleTerminalTripUpdate(update);
              return;
            }
            final currentDriverId = assignedDriverId;
            if (currentDriverId != null &&
                currentDriverId.toLowerCase() != trip.driverId.toLowerCase()) {
              terminate(RiderTripLocationClearReason.assignmentChanged);
              return;
            }
          }
          schedule(() => handleTripUpdate(update));
        }

        controller.onCancel = () async {
          if (!cancelled) {
            cancelled = true;
            locationReadEpoch++;
            pendingReadGeneration = null;
            connectedSourceGeneration = null;
            retryGeneration++;
          }
          await stopAll();
        };

        tripSubscription = _trips.watchTrip(tripId).listen(
          handleTripStreamUpdate,
          onError: (Object error) {
            if (!isActive()) return;
            if (!sessionIsCurrent() ||
                (error is TripRealtimeException &&
                    error.failure == TripRealtimeFailure.sessionChanged)) {
              terminate(RiderTripLocationClearReason.sessionChanged);
              return;
            }
            schedule(() async {
              final failure = error is TripRealtimeException &&
                      error.failure == TripRealtimeFailure.sessionChanged
                  ? RiderTripLocationFailure.sessionChanged
                  : RiderTripLocationFailure.notAuthorized;
              fail(failure);
            });
          },
          onDone: () => schedule(() async {
            if (isActive()) fail(RiderTripLocationFailure.sourceUnavailable);
          }),
        );
        tripSubscriptionReady = true;
        for (final action in pending) {
          enqueue(action);
        }
        pending.clear();
      }, isBroadcast: false);
}
