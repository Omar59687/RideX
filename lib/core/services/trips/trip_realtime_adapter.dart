import 'dart:async';

import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/trip_realtime.dart';
import 'package:ridex/core/services/trips/trip_realtime_source.dart';

/// Converts untrusted Realtime notifications into canonical, participant-
/// verified Trip snapshots. Does not own GPS, UI, payment, or Trip mutations.
final class TripRealtimeAdapter {
  TripRealtimeAdapter(this._source);

  final TripRealtimeSource _source;

  /// An authenticated canonical reread, independent of channel availability.
  Future<TripRealtimeTrip> readVerifiedTrip(String tripId) async {
    final owner = _source.authenticatedUserId;
    final session = _source.authenticatedSessionIdentity;
    if (!isCanonicalTripId(tripId) || owner == null || session == null) {
      throw const TripRealtimeException(TripRealtimeFailure.unauthenticated);
    }
    return _readVerified(
      tripId: tripId.toLowerCase(),
      ownerId: owner.toLowerCase(),
      sessionIdentity: session,
    );
  }

  Stream<TripRealtimeUpdate> watchTrip(
    String tripId,
  ) =>
      Stream<TripRealtimeUpdate>.multi((controller) {
        if (!isCanonicalTripId(tripId)) {
          controller.addError(
            const TripRealtimeException(TripRealtimeFailure.invalidTripId),
          );
          unawaited(controller.close());
          return;
        }

        final ownerId = _source.authenticatedUserId;
        final sessionIdentity = _source.authenticatedSessionIdentity;
        if (ownerId == null ||
            !isCanonicalTripId(ownerId) ||
            sessionIdentity == null) {
          controller.addError(
            const TripRealtimeException(TripRealtimeFailure.unauthenticated),
          );
          unawaited(controller.close());
          return;
        }

        final normalizedTripId = tripId.toLowerCase();
        final normalizedOwnerId = ownerId.toLowerCase();
        var cancelled = false;
        var terminal = false;
        var initializationQueued = false;
        var lastStatusSequence = 0;
        var wasDisconnected = false;
        late TripRealtimeTrip latest;
        StreamSubscription<TripRealtimeSourceSignal>? sourceSubscription;
        var processing = Future<void>.value();
        final bufferedActions = <Future<void> Function()>[];

        void emit(TripRealtimeUpdate update) {
          if (!cancelled && !terminal) controller.add(update);
        }

        void fail(Object error, [StackTrace? stackTrace]) {
          if (cancelled || terminal) return;
          terminal = true;
          final safeError = error is TripRealtimeException
              ? error
              : const TripRealtimeException(
                  TripRealtimeFailure.sourceUnavailable);
          controller.addError(safeError, stackTrace);
          unawaited(controller.close());
          final subscription = sourceSubscription;
          if (subscription != null) unawaited(subscription.cancel());
        }

        void enqueue(Future<void> Function() action) {
          processing = processing.then((_) async {
            if (cancelled || terminal) return;
            try {
              await action();
            } on Object catch (error, stackTrace) {
              fail(error, stackTrace);
            }
          });
        }

        void schedule(Future<void> Function() action) {
          if (!initializationQueued) {
            bufferedActions.add(action);
          } else {
            enqueue(action);
          }
        }

        Future<void> processSignal(TripRealtimeSourceSignal signal) async {
          if (signal is TripRealtimeSessionChangedSignal) {
            throw const TripRealtimeException(
                TripRealtimeFailure.sessionChanged);
          }
          if (signal case TripRealtimeChannelSignal(:final status)) {
            emit(TripRealtimeConnectionUpdate(status));
            if (_isDisconnected(status)) {
              wasDisconnected = true;
              return;
            }
            if (status != TripRealtimeChannelStatus.subscribed) return;

            // Supabase may rejoin a channel after a socket interruption.
            // Reread canonical state so missed notifications cannot go stale.
            final recovered = wasDisconnected;
            wasDisconnected = false;
            final snapshot = await _tryReadVerified(
              tripId: tripId,
              ownerId: normalizedOwnerId,
              sessionIdentity: sessionIdentity,
            );
            if (snapshot == null) {
              emit(
                const TripRealtimeVerificationUpdate(
                  TripRealtimeFailure.sourceUnavailable,
                ),
              );
              return;
            }
            final event = _eventForSnapshot(
              snapshot: snapshot,
              previous: latest,
              cause: TripRealtimeEventCause.connectionRestored,
              forceResync: recovered,
            );
            if (event != null) {
              latest = snapshot;
              emit(event);
            }
            return;
          }

          if (signal case TripRealtimeChangeSignal changeSignal) {
            final update = await _verifyChange(
              signal: changeSignal,
              tripId: normalizedTripId,
              ownerId: normalizedOwnerId,
              sessionIdentity: sessionIdentity,
              latest: latest,
              lastStatusSequence: lastStatusSequence,
            );
            if (update != null) {
              latest = update.trip;
              lastStatusSequence = update.lastStatusSequence;
              final event = update.event;
              if (event != null) emit(event);
            }
          }
        }

        emit(
          const TripRealtimeConnectionUpdate(
              TripRealtimeChannelStatus.connecting),
        );
        try {
          sourceSubscription = _source.watchTrip(tripId).listen(
                (signal) => schedule(() => processSignal(signal)),
                onError: (Object _) => schedule(() async {
                  wasDisconnected = true;
                  emit(
                    const TripRealtimeConnectionUpdate(
                      TripRealtimeChannelStatus.channelError,
                    ),
                  );
                }),
                onDone: () => schedule(() async {
                  if (cancelled || terminal) return;
                  emit(
                    const TripRealtimeConnectionUpdate(
                      TripRealtimeChannelStatus.closed,
                    ),
                  );
                  terminal = true;
                  unawaited(controller.close());
                }),
              );
        } on Object catch (error, stackTrace) {
          fail(error, stackTrace);
          return;
        }

        // The source listener is attached before the first canonical read.
        // Synchronous source events are buffered and processed after that read.
        enqueue(() async {
          latest = await _readVerified(
            tripId: tripId,
            ownerId: normalizedOwnerId,
            sessionIdentity: sessionIdentity,
          );
          emit(
            VerifiedTripRealtimeEvent(
              trip: latest,
              cause: TripRealtimeEventCause.initialCanonicalRead,
            ),
          );
        });
        initializationQueued = true;
        for (final action in bufferedActions) {
          enqueue(action);
        }
        bufferedActions.clear();

        controller.onCancel = () async {
          cancelled = true;
          final subscription = sourceSubscription;
          if (subscription != null) await subscription.cancel();
        };
      }, isBroadcast: false);

  Future<_VerifiedChange?> _verifyChange({
    required TripRealtimeChangeSignal signal,
    required String tripId,
    required String ownerId,
    required Object sessionIdentity,
    required TripRealtimeTrip latest,
    required int lastStatusSequence,
  }) async {
    if (signal.tripId.toLowerCase() != tripId) return null;
    var nextStatusSequence = lastStatusSequence;
    final sequence = signal.statusEventSequence;
    if (signal.source == TripRealtimeChangeSource.statusHistory &&
        sequence != null) {
      if (sequence <= 0 || sequence <= lastStatusSequence) return null;
    }

    final snapshot = await _tryReadVerified(
      tripId: tripId,
      ownerId: ownerId,
      sessionIdentity: sessionIdentity,
    );
    if (snapshot == null) return null;
    // The notification may arrive before its canonical row is visible. Do not
    // consume its sequence until the authoritative snapshot catches up.
    if (snapshot.version < latest.version) return null;
    if (sequence != null &&
        sequence > lastStatusSequence &&
        snapshot.version > latest.version) {
      nextStatusSequence = sequence;
    }
    final cause = signal.source == TripRealtimeChangeSource.tripRow
        ? TripRealtimeEventCause.tripRowChanged
        : TripRealtimeEventCause.statusHistoryChanged;
    final event = _eventForSnapshot(
      snapshot: snapshot,
      previous: latest,
      cause: cause,
      statusEventSequence: sequence,
    );
    if (event == null) {
      return _VerifiedChange(latest, nextStatusSequence, null);
    }
    return _VerifiedChange(snapshot, nextStatusSequence, event);
  }

  Future<TripRealtimeTrip> _readVerified({
    required String tripId,
    required String ownerId,
    required Object sessionIdentity,
  }) async {
    if (!_isSameSession(ownerId, sessionIdentity)) {
      throw const TripRealtimeException(TripRealtimeFailure.sessionChanged);
    }
    final TripRealtimeTrip? snapshot;
    try {
      snapshot = await _source.readCanonicalTrip(tripId);
    } on TripRealtimeException {
      rethrow;
    } on Object {
      if (!_isSameSession(ownerId, sessionIdentity)) {
        throw const TripRealtimeException(TripRealtimeFailure.sessionChanged);
      }
      throw const TripRealtimeException(TripRealtimeFailure.sourceUnavailable);
    }
    if (!_isSameSession(ownerId, sessionIdentity)) {
      throw const TripRealtimeException(TripRealtimeFailure.sessionChanged);
    }
    if (snapshot == null) {
      throw const TripRealtimeException(TripRealtimeFailure.notVisible);
    }
    _validateParticipant(snapshot, tripId, ownerId);
    return snapshot;
  }

  bool _isSameSession(String ownerId, Object sessionIdentity) =>
      _source.authenticatedUserId?.toLowerCase() == ownerId &&
      identical(_source.authenticatedSessionIdentity, sessionIdentity);

  Future<TripRealtimeTrip?> _tryReadVerified({
    required String tripId,
    required String ownerId,
    required Object sessionIdentity,
  }) async {
    try {
      return await _readVerified(
        tripId: tripId,
        ownerId: ownerId,
        sessionIdentity: sessionIdentity,
      );
    } on TripRealtimeException catch (error) {
      if (error.failure == TripRealtimeFailure.notVisible ||
          error.failure == TripRealtimeFailure.sessionChanged ||
          error.failure == TripRealtimeFailure.malformedCanonicalState) {
        rethrow;
      }
      return null;
    } on Object {
      return null;
    }
  }

  void _validateParticipant(
    TripRealtimeTrip snapshot,
    String expectedTripId,
    String ownerId,
  ) {
    if (snapshot.tripId.toLowerCase() != expectedTripId ||
        !isCanonicalTripId(snapshot.riderId) ||
        !isCanonicalTripId(snapshot.driverId) ||
        snapshot.version <= 0) {
      throw const TripRealtimeException(
        TripRealtimeFailure.malformedCanonicalState,
      );
    }
    if (snapshot.riderId.toLowerCase() != ownerId &&
        snapshot.driverId.toLowerCase() != ownerId) {
      throw const TripRealtimeException(TripRealtimeFailure.notVisible);
    }
  }

  VerifiedTripRealtimeEvent? _eventForSnapshot({
    required TripRealtimeTrip snapshot,
    required TripRealtimeTrip previous,
    required TripRealtimeEventCause cause,
    int? statusEventSequence,
    bool forceResync = false,
  }) {
    if (snapshot.tripId.toLowerCase() != previous.tripId.toLowerCase()) {
      throw const TripRealtimeException(
        TripRealtimeFailure.malformedCanonicalState,
      );
    }
    if (snapshot.version < previous.version) return null;
    if (snapshot.version == previous.version) {
      if (!snapshot.hasSameStateAs(previous)) {
        throw const TripRealtimeException(
          TripRealtimeFailure.inconsistentVersion,
        );
      }
      if (!forceResync) return null;
    }
    return VerifiedTripRealtimeEvent(
      trip: snapshot,
      cause: cause,
      statusEventSequence: statusEventSequence,
    );
  }

  static bool _isDisconnected(TripRealtimeChannelStatus status) =>
      status == TripRealtimeChannelStatus.channelError ||
      status == TripRealtimeChannelStatus.closed ||
      status == TripRealtimeChannelStatus.timedOut;
}

final class _VerifiedChange {
  const _VerifiedChange(this.trip, this.lastStatusSequence, this.event);

  final TripRealtimeTrip trip;
  final int lastStatusSequence;
  final VerifiedTripRealtimeEvent? event;
}
