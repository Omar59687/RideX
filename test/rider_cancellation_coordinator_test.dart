import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/rider_booking_cancellation.dart';
import 'package:ridex/core/models/rider_booking_search.dart';
import 'package:ridex/core/providers/rider_cancellation_providers.dart';
import 'package:ridex/core/services/rider_cancellation/rider_cancellation_coordinator.dart';

import 'helpers/fake_rider_booking_cancellation_repository.dart';
import 'helpers/fake_rider_booking_search_repository.dart';
import 'helpers/fake_rider_trip_tracking_repository.dart';

const _reason = 'Changed my mind';

RiderCancellationCoordinator _coordinator(
  FakeRiderBookingCancellationRepository repository, {
  Timer Function(Duration, void Function())? scheduleDeadline,
}) {
  final coordinator = RiderCancellationCoordinator(
    repository: repository,
    scheduleDeadline: scheduleDeadline,
  );
  addTearDown(coordinator.dispose);
  return coordinator;
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('atomically shares one pending dispatch for the Rider/booking key',
      () async {
    final gate = Completer<RiderBookingCancellationResult>();
    final repository = FakeRiderBookingCancellationRepository(
      onCancel: (_) => gate.future,
    );
    final coordinator = _coordinator(repository);
    var notifications = 0;
    coordinator.addListener(() => notifications++);

    final first = coordinator.cancel(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      expectedVersion: 3,
      observedStatus: RiderBookingSearchStatus.searching,
      reasonCode: _reason,
    );
    final second = coordinator.cancel(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      expectedVersion: 3,
      observedStatus: RiderBookingSearchStatus.searching,
      reasonCode: _reason,
    );

    expect(identical(first, second), isTrue);
    expect(repository.cancelCount, 1);
    expect(notifications, 1);
    expect(
      coordinator
          .attemptFor(
            riderId: riderIdFixture,
            bookingRequestId: riderBookingIdFixture,
          )
          ?.phase,
      RiderCancellationAttemptPhase.pending,
    );

    gate.complete(RiderBookingCancellationAccepted(
      riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.cancelled,
      ),
    ));
    await first;

    final attempt = coordinator.attemptFor(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
    );
    expect(attempt!.phase, RiderCancellationAttemptPhase.accepted);
    expect(attempt.acceptedBooking!.version, 4);
    expect(notifications, 2);
  });

  test('keeps different Rider and booking keys independent', () async {
    final gates = <String, Completer<RiderBookingCancellationResult>>{};
    final repository = FakeRiderBookingCancellationRepository(
      onCancel: (request) =>
          (gates[request.bookingRequestId] ??= Completer()).future,
    );
    final coordinator = _coordinator(repository);

    final first = coordinator.cancel(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      expectedVersion: 3,
      observedStatus: RiderBookingSearchStatus.searching,
      reasonCode: _reason,
    );
    final second = coordinator.cancel(
      riderId: riderIdFixture,
      bookingRequestId: secondaryRiderBookingIdFixture,
      expectedVersion: 3,
      observedStatus: RiderBookingSearchStatus.searching,
      reasonCode: _reason,
    );

    expect(identical(first, second), isFalse);
    expect(repository.cancelCount, 2);
    expect(coordinator.retainedAttemptCount, 2);
    expect(
      coordinator
          .attemptFor(
            riderId: riderIdFixture,
            bookingRequestId: secondaryRiderBookingIdFixture,
          )
          ?.phase,
      RiderCancellationAttemptPhase.pending,
    );

    gates[riderBookingIdFixture]!.complete(
      const RiderBookingCancellationRejected(
        RiderCancellationRejection.backend,
      ),
    );
    gates[secondaryRiderBookingIdFixture]!.complete(
      const RiderBookingCancellationRejected(
        RiderCancellationRejection.backend,
      ),
    );
    await Future.wait([first, second]);
  });

  test('accepted evidence must be owned, Cash, cancelled, and newer', () async {
    for (final booking in [
      riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.cancelled,
        riderId: unrelatedRiderIdFixture,
      ),
      riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.cancelled,
        bookingRequestId: secondaryRiderBookingIdFixture,
      ),
      riderBookingSearchFixture(
        version: 3,
        status: RiderBookingSearchStatus.cancelled,
      ),
      riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.searching,
      ),
    ]) {
      final coordinator = _coordinator(
        FakeRiderBookingCancellationRepository(
          result: RiderBookingCancellationAccepted(booking),
        ),
      );
      await coordinator.cancel(
        riderId: riderIdFixture,
        bookingRequestId: riderBookingIdFixture,
        expectedVersion: 3,
        observedStatus: RiderBookingSearchStatus.searching,
        reasonCode: _reason,
      );
      final attempt = coordinator.attemptFor(
        riderId: riderIdFixture,
        bookingRequestId: riderBookingIdFixture,
      );
      expect(
        attempt!.phase,
        RiderCancellationAttemptPhase.uncertain,
        reason: '$booking',
      );
      expect(attempt.acceptedBooking, isNull);
    }
  });

  test('stale retry requires a strictly newer cancellable observation',
      () async {
    final repository = FakeRiderBookingCancellationRepository(
      result: const RiderBookingCancellationRejected(
        RiderCancellationRejection.staleVersion,
      ),
    );
    final coordinator = _coordinator(repository);

    await coordinator.cancel(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      expectedVersion: 3,
      observedStatus: RiderBookingSearchStatus.searching,
      reasonCode: _reason,
    );
    expect(repository.cancelCount, 1);

    await coordinator.cancel(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      expectedVersion: 3,
      observedStatus: RiderBookingSearchStatus.searching,
      reasonCode: _reason,
    );
    expect(repository.cancelCount, 1);

    await coordinator.cancel(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      expectedVersion: 4,
      observedStatus: RiderBookingSearchStatus.cancelled,
      reasonCode: _reason,
    );
    expect(repository.cancelCount, 1);

    repository.result = RiderBookingCancellationAccepted(
      riderBookingSearchFixture(
        version: 5,
        status: RiderBookingSearchStatus.cancelled,
      ),
    );
    await coordinator.cancel(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      expectedVersion: 4,
      observedStatus: RiderBookingSearchStatus.searching,
      reasonCode: _reason,
    );
    expect(repository.cancelCount, 2);
    expect(
      coordinator
          .attemptFor(
            riderId: riderIdFixture,
            bookingRequestId: riderBookingIdFixture,
          )
          ?.phase,
      RiderCancellationAttemptPhase.accepted,
    );
  });

  test('accepted and uncertain attempts never dispatch again', () async {
    for (final result in [
      const RiderBookingCancellationUnknown(),
      RiderBookingCancellationAccepted(
        riderBookingSearchFixture(
          version: 4,
          status: RiderBookingSearchStatus.cancelled,
        ),
      ),
    ]) {
      final repository = FakeRiderBookingCancellationRepository(result: result);
      final coordinator = _coordinator(repository);
      await coordinator.cancel(
        riderId: riderIdFixture,
        bookingRequestId: riderBookingIdFixture,
        expectedVersion: 3,
        observedStatus: RiderBookingSearchStatus.searching,
        reasonCode: _reason,
      );
      await coordinator.cancel(
        riderId: riderIdFixture,
        bookingRequestId: riderBookingIdFixture,
        expectedVersion: 4,
        observedStatus: RiderBookingSearchStatus.searching,
        reasonCode: _reason,
      );
      expect(repository.cancelCount, 1);
    }
  });

  test('deadline becomes uncertain and ignores a late accepted result',
      () async {
    final timers = <_ManualTimer>[];
    final gate = Completer<RiderBookingCancellationResult>();
    final coordinator = _coordinator(
      FakeRiderBookingCancellationRepository(onCancel: (_) => gate.future),
      scheduleDeadline: (_, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    final pending = coordinator.cancel(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      expectedVersion: 3,
      observedStatus: RiderBookingSearchStatus.searching,
      reasonCode: _reason,
    );
    await _flush();
    timers.single.fire();
    await pending;

    expect(
      coordinator
          .attemptFor(
            riderId: riderIdFixture,
            bookingRequestId: riderBookingIdFixture,
          )
          ?.phase,
      RiderCancellationAttemptPhase.uncertain,
    );

    gate.complete(RiderBookingCancellationAccepted(
      riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.cancelled,
      ),
    ));
    await _flush();
    expect(
      coordinator
          .attemptFor(
            riderId: riderIdFixture,
            bookingRequestId: riderBookingIdFixture,
          )
          ?.phase,
      RiderCancellationAttemptPhase.uncertain,
    );
  });

  test('repository failures fail closed as uncertain', () async {
    final coordinator = _coordinator(
      FakeRiderBookingCancellationRepository(
        onCancel: (_) async => throw StateError('transport failed'),
      ),
    );
    await coordinator.cancel(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      expectedVersion: 3,
      observedStatus: RiderBookingSearchStatus.searching,
      reasonCode: _reason,
    );
    expect(
      coordinator
          .attemptFor(
            riderId: riderIdFixture,
            bookingRequestId: riderBookingIdFixture,
          )
          ?.phase,
      RiderCancellationAttemptPhase.uncertain,
    );
  });

  test('only newer owned cancelled evidence retains a terminal guard',
      () async {
    final gate = Completer<RiderBookingCancellationResult>();
    final repository = FakeRiderBookingCancellationRepository(
      onCancel: (_) => gate.future,
    );
    final coordinator = _coordinator(
      repository,
    );
    final pending = coordinator.cancel(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      expectedVersion: 3,
      observedStatus: RiderBookingSearchStatus.searching,
      reasonCode: _reason,
    );

    for (final status in [
      RiderBookingSearchStatus.searching,
      RiderBookingSearchStatus.matched,
      RiderBookingSearchStatus.expired,
      RiderBookingSearchStatus.failed,
    ]) {
      coordinator.reconcileTerminalBooking(
        riderId: riderIdFixture,
        bookingRequestId: riderBookingIdFixture,
        booking: riderBookingSearchFixture(version: 4, status: status),
      );
      expect(coordinator.retainedAttemptCount, 1, reason: status.name);
    }

    for (final booking in [
      riderBookingSearchFixture(
        version: 3,
        status: RiderBookingSearchStatus.cancelled,
      ),
      riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.cancelled,
        riderId: unrelatedRiderIdFixture,
      ),
      riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.cancelled,
        bookingRequestId: secondaryRiderBookingIdFixture,
      ),
    ]) {
      coordinator.reconcileTerminalBooking(
        riderId: riderIdFixture,
        bookingRequestId: riderBookingIdFixture,
        booking: booking,
      );
      expect(
        coordinator
            .attemptFor(
              riderId: riderIdFixture,
              bookingRequestId: riderBookingIdFixture,
            )
            ?.phase,
        RiderCancellationAttemptPhase.pending,
      );
    }

    final verified = riderBookingSearchFixture(
      version: 4,
      status: RiderBookingSearchStatus.cancelled,
    );
    coordinator.reconcileTerminalBooking(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      booking: verified,
    );
    expect(coordinator.retainedAttemptCount, 1);
    expect(
      coordinator
          .attemptFor(
            riderId: riderIdFixture,
            bookingRequestId: riderBookingIdFixture,
          )
          ?.phase,
      RiderCancellationAttemptPhase.verifiedCancelled,
    );
    coordinator.reconcileTerminalBooking(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      booking: verified,
    );
    await coordinator.cancel(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      expectedVersion: 5,
      observedStatus: RiderBookingSearchStatus.searching,
      reasonCode: _reason,
    );
    expect(repository.cancelCount, 1);
    await pending;

    gate.complete(RiderBookingCancellationAccepted(
      riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.cancelled,
      ),
    ));
    await _flush();
    expect(coordinator.retainedAttemptCount, 1);
    expect(
      coordinator
          .attemptFor(
            riderId: riderIdFixture,
            bookingRequestId: riderBookingIdFixture,
          )
          ?.acceptedBooking,
      verified,
    );
  });

  test('terminal guard remains scoped to one Rider and booking', () async {
    final repository = FakeRiderBookingCancellationRepository();
    final coordinator = _coordinator(repository);
    await coordinator.cancel(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      expectedVersion: 3,
      observedStatus: RiderBookingSearchStatus.searching,
      reasonCode: _reason,
    );
    coordinator.reconcileTerminalBooking(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      booking: riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.cancelled,
      ),
    );

    await coordinator.cancel(
      riderId: unrelatedRiderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      expectedVersion: 3,
      observedStatus: RiderBookingSearchStatus.searching,
      reasonCode: _reason,
    );
    await coordinator.cancel(
      riderId: riderIdFixture,
      bookingRequestId: secondaryRiderBookingIdFixture,
      expectedVersion: 3,
      observedStatus: RiderBookingSearchStatus.searching,
      reasonCode: _reason,
    );
    expect(repository.cancelCount, 3);
    expect(coordinator.retainedAttemptCount, 3);
    expect(
      coordinator
          .attemptFor(
            riderId: riderIdFixture,
            bookingRequestId: riderBookingIdFixture,
          )
          ?.phase,
      RiderCancellationAttemptPhase.verifiedCancelled,
    );
  });

  test('provider disposal retires pending command and ignores late response',
      () async {
    final gate = Completer<RiderBookingCancellationResult>();
    final repository = FakeRiderBookingCancellationRepository(
      onCancel: (_) => gate.future,
    );
    final container = ProviderContainer(overrides: [
      riderCancellationRepositoryProvider.overrideWithValue(repository),
    ]);
    final coordinator = container.read(riderCancellationCoordinatorProvider);
    final pending = coordinator.cancel(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      expectedVersion: 3,
      observedStatus: RiderBookingSearchStatus.searching,
      reasonCode: _reason,
    );

    container.dispose();
    await pending;
    gate.complete(RiderBookingCancellationAccepted(
      riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.cancelled,
      ),
    ));
    await _flush();
    expect(coordinator.retainedAttemptCount, 0);
    expect(repository.cancelCount, 1);
  });

  test('dispose retires pending work and ignores late results', () async {
    final gate = Completer<RiderBookingCancellationResult>();
    final coordinator = _coordinator(
      FakeRiderBookingCancellationRepository(onCancel: (_) => gate.future),
    );
    var notifications = 0;
    coordinator.addListener(() => notifications++);
    final pending = coordinator.cancel(
      riderId: riderIdFixture,
      bookingRequestId: riderBookingIdFixture,
      expectedVersion: 3,
      observedStatus: RiderBookingSearchStatus.searching,
      reasonCode: _reason,
    );
    coordinator.dispose();
    await pending;
    gate.complete(RiderBookingCancellationAccepted(
      riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.cancelled,
      ),
    ));
    await _flush();

    expect(coordinator.retainedAttemptCount, 0);
    expect(notifications, 1);
  });
}

class _ManualTimer implements Timer {
  _ManualTimer(this._callback);

  final void Function() _callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}
