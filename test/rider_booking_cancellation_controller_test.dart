import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_assigned_trip.dart';
import 'package:ridex/core/models/rider_booking_cancellation.dart';
import 'package:ridex/core/models/rider_booking_search.dart';
import 'package:ridex/core/models/rider_trip_tracking_event.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/rider_booking_cancellation_repository.dart';
import 'package:ridex/core/repositories/rider_trip_tracking_repository.dart';
import 'package:ridex/core/services/rider_cancellation/rider_cancellation_coordinator.dart';
import 'package:ridex/features/booking/application/rider_search_controller.dart';

import 'helpers/fake_rider_booking_cancellation_repository.dart';
import 'helpers/fake_rider_booking_search_repository.dart';
import 'helpers/fake_rider_trip_tracking_repository.dart';

const _rider = AppUser(
  id: riderIdFixture,
  name: 'Test Rider',
  email: 'rider@example.com',
  role: RideRole.rider,
);

RiderSearchController _controller({
  required SessionState Function() readSession,
  required FakeRiderBookingSearchRepository reads,
  FakeRiderBookingCancellationRepository? cancels,
  RiderCancellationCoordinator? coordinator,
  RiderTripTrackingRepository? trips,
  Duration readDeadline = const Duration(seconds: 15),
  Timer Function(Duration, void Function())? scheduleReadDeadline,
  Timer Function(Duration, void Function())? scheduleTimeout,
}) {
  final cancellationCoordinator = coordinator ??
      RiderCancellationCoordinator(
        repository: cancels ?? FakeRiderBookingCancellationRepository(),
      );
  if (coordinator == null) {
    addTearDown(cancellationCoordinator.dispose);
  }
  return RiderSearchController(
    bookingRequestId: riderBookingIdFixture,
    repository: reads,
    cancellationCoordinator: cancellationCoordinator,
    tripTrackingRepository: trips,
    readSession: readSession,
    readDeadline: readDeadline,
    scheduleReadDeadline: scheduleReadDeadline,
    scheduleTimeout: scheduleTimeout,
  );
}

FakeRiderBookingSearchRepository _reads({
  RiderBookingSearchStatus status = RiderBookingSearchStatus.searching,
  int version = 3,
}) {
  return FakeRiderBookingSearchRepository(
    authenticatedRiderId: riderIdFixture,
    booking: riderBookingSearchFixture(status: status, version: version),
  );
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('cancellation contract', () {
    test('default repository fails closed with an unknown outcome', () async {
      const repository = UnavailableRiderBookingCancellationRepository();
      final result = await repository.cancelBooking(
        bookingRequestId: riderBookingIdFixture,
        expectedVersion: 3,
        reasonCode: 'Changed my mind',
      );
      expect(result, isA<RiderBookingCancellationUnknown>());
    });

    test('reasons are bounded client-selected text', () {
      expect(riderCancellationReasonOptions, hasLength(4));
      expect(
        riderCancellationReasonOptions,
        containsAll([
          'Changed my mind',
          'Booked by mistake',
          'Driver took too long',
          'Other reason',
        ]),
      );
      expect(isValidCancellationReason('Changed my mind'), isTrue);
      expect(isValidCancellationReason('   '), isFalse);
      expect(isValidCancellationReason('a' * 100), isTrue);
      expect(isValidCancellationReason('a' * 101), isFalse);
    });

    test('only confirmed and searching bookings are cancellable', () {
      expect(
        isCancellableBookingStatus(RiderBookingSearchStatus.confirmed),
        isTrue,
      );
      expect(
        isCancellableBookingStatus(RiderBookingSearchStatus.searching),
        isTrue,
      );
      for (final status in [
        RiderBookingSearchStatus.draft,
        RiderBookingSearchStatus.matched,
        RiderBookingSearchStatus.cancelled,
        RiderBookingSearchStatus.expired,
        RiderBookingSearchStatus.failed,
      ]) {
        expect(isCancellableBookingStatus(status), isFalse,
            reason: status.name);
      }
    });
  });

  group('RiderSearchController cancellation', () {
    test('cancellation is authorized only from verified cancellable states',
        () async {
      final session = SessionState.fromUser(_rider);
      for (final (status, allowed) in [
        (RiderBookingSearchStatus.confirmed, true),
        (RiderBookingSearchStatus.searching, true),
        (RiderBookingSearchStatus.matched, false),
        (RiderBookingSearchStatus.cancelled, false),
        (RiderBookingSearchStatus.expired, false),
        (RiderBookingSearchStatus.failed, false),
        (RiderBookingSearchStatus.draft, false),
      ]) {
        final reads = _reads(status: status);
        final controller =
            _controller(readSession: () => session, reads: reads);
        await controller.refresh();
        expect(controller.canCancel, allowed, reason: status.name);
        controller.dispose();
      }
    });

    test('soft timeout retains cancellation eligibility', () async {
      final timers = <_ManualTimer>[];
      final session = SessionState.fromUser(_rider);
      final controller = _controller(
        readSession: () => session,
        reads: _reads(),
        scheduleTimeout: (_, callback) {
          final timer = _ManualTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      timers.single.fire();
      expect(controller.state.phase, RiderSearchPhase.timedOut);
      expect(controller.canCancel, isTrue);
    });

    test('poll timeout preserves advanced booking version for cancellation',
        () async {
      final session = SessionState.fromUser(_rider);
      final reads = _reads();
      reads.booking = riderBookingSearchFixture(
          status: RiderBookingSearchStatus.confirmed, version: 3);
      final cancels = FakeRiderBookingCancellationRepository();
      final timers = <_ManualTimer>[];
      final controller = _controller(
          readSession: () => session,
          reads: reads,
          cancels: cancels,
          scheduleTimeout: (_, callback) {
            final timer = _ManualTimer(callback);
            timers.add(timer);
            return timer;
          });
      addTearDown(controller.dispose);
      await controller.refresh();
      reads.booking = riderBookingSearchFixture(
          status: RiderBookingSearchStatus.searching, version: 4);
      await controller.refresh(allowMatching: false);
      expect(timers.length, 1);
      timers.single.fire();
      expect(controller.state.phase, RiderSearchPhase.timedOut);
      expect(controller.state.booking!.version, 4);
      expect(
          controller.state.booking!.status, RiderBookingSearchStatus.searching);
      await controller.cancelBooking(reasonCode: 'Changed my mind');
      expect(cancels.requests.single.expectedVersion, 4);
    });

    test('accepted cancellation confirms only a validated cancelled snapshot',
        () async {
      final session = SessionState.fromUser(_rider);
      final reads = _reads();
      final cancels = FakeRiderBookingCancellationRepository(
        result: RiderBookingCancellationAccepted(
          riderBookingSearchFixture(
            version: 4,
            status: RiderBookingSearchStatus.cancelled,
          ),
        ),
      );
      final controller = _controller(
        readSession: () => session,
        reads: reads,
        cancels: cancels,
      );
      addTearDown(controller.dispose);
      await controller.refresh();

      await controller.cancelBooking(reasonCode: '  Changed my mind  ');

      expect(cancels.cancelCount, 1);
      expect(cancels.requests.single.expectedVersion, 3);
      expect(cancels.requests.single.reasonCode, 'Changed my mind');
      expect(reads.readCount, 1);
      expect(controller.state.phase, RiderSearchPhase.cancelled);
      expect(controller.state.cancellation, RiderCancellationPhase.idle);
      expect(controller.state.booking!.version, 4);
      expect(controller.canCancel, isFalse);
    });

    test('foreign or regressed accepted evidence becomes uncertain', () async {
      final session = SessionState.fromUser(_rider);
      for (final accepted in [
        riderBookingSearchFixture(
          version: 4,
          status: RiderBookingSearchStatus.cancelled,
          riderId: unrelatedRiderIdFixture,
        ),
        riderBookingSearchFixture(
          version: 3,
          status: RiderBookingSearchStatus.cancelled,
        ),
      ]) {
        final controller = _controller(
          readSession: () => session,
          reads: _reads(),
          cancels: FakeRiderBookingCancellationRepository(
            result: RiderBookingCancellationAccepted(accepted),
          ),
        );
        await controller.refresh();
        await controller.cancelBooking(reasonCode: 'Booked by mistake');
        expect(
          controller.state.cancellation,
          RiderCancellationPhase.uncertain,
        );
        expect(controller.state.phase, isNot(RiderSearchPhase.cancelled));
        controller.dispose();
      }
    });

    test('stale version rereads once and never auto-redispatches', () async {
      final session = SessionState.fromUser(_rider);
      final reads = _reads();
      final cancels = FakeRiderBookingCancellationRepository(
        result: const RiderBookingCancellationRejected(
          RiderCancellationRejection.staleVersion,
        ),
      );
      final controller = _controller(
        readSession: () => session,
        reads: reads,
        cancels: cancels,
      );
      addTearDown(controller.dispose);
      await controller.refresh();

      reads.booking = riderBookingSearchFixture(version: 6);
      await controller.cancelBooking(reasonCode: 'Driver took too long');
      await _flush();

      expect(cancels.cancelCount, 1);
      expect(reads.readCount, 2);
      expect(controller.state.phase, RiderSearchPhase.searching);
      expect(controller.state.booking!.version, 6);
      expect(controller.state.cancellation, RiderCancellationPhase.rejected);
      expect(
        controller.state.rejection,
        RiderCancellationRejection.staleVersion,
      );
      expect(controller.canCancel, isTrue);

      cancels.result = RiderBookingCancellationAccepted(
        riderBookingSearchFixture(
          version: 7,
          status: RiderBookingSearchStatus.cancelled,
        ),
      );
      await controller.cancelBooking(reasonCode: 'Changed my mind');

      expect(cancels.cancelCount, 2);
      expect(cancels.requests.last.expectedVersion, 6);
      expect(controller.state.phase, RiderSearchPhase.cancelled);
    });

    test('equal or non-cancellable rereads never reauthorize a stale retry',
        () async {
      final session = SessionState.fromUser(_rider);
      final reads = _reads();
      final cancels = FakeRiderBookingCancellationRepository(
        result: const RiderBookingCancellationRejected(
          RiderCancellationRejection.staleVersion,
        ),
      );
      final coordinator = RiderCancellationCoordinator(repository: cancels);
      addTearDown(coordinator.dispose);
      final controller = _controller(
        readSession: () => session,
        reads: reads,
        coordinator: coordinator,
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.cancelBooking(reasonCode: 'Changed my mind');
      await _flush();

      expect(controller.state.booking!.version, 3);
      expect(controller.canCancel, isFalse);
      await controller.cancelBooking(reasonCode: 'Changed my mind');
      expect(cancels.cancelCount, 1);

      reads.booking = riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.matched,
      );
      await controller.refresh();
      expect(controller.canCancel, isFalse);
      await controller.cancelBooking(reasonCode: 'Changed my mind');
      expect(cancels.cancelCount, 1);

      reads.booking = null;
      await controller.refresh();
      expect(controller.state.booking, isNull);
      expect(controller.canCancel, isFalse);
      await controller.cancelBooking(reasonCode: 'Changed my mind');
      expect(cancels.cancelCount, 1);
    });

    test('two live controllers share one pending cancellation and result',
        () async {
      final session = SessionState.fromUser(_rider);
      final gate = Completer<RiderBookingCancellationResult>();
      final cancels = FakeRiderBookingCancellationRepository(
        onCancel: (_) => gate.future,
      );
      final coordinator = RiderCancellationCoordinator(repository: cancels);
      addTearDown(coordinator.dispose);
      final first = _controller(
        readSession: () => session,
        reads: _reads(),
        coordinator: coordinator,
      );
      final second = _controller(
        readSession: () => session,
        reads: _reads(),
        coordinator: coordinator,
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.refresh();
      await second.refresh();

      final firstCancel = first.cancelBooking(reasonCode: 'Changed my mind');
      final secondCancel = second.cancelBooking(reasonCode: 'Changed my mind');

      expect(identical(firstCancel, secondCancel), isTrue);
      expect(cancels.cancelCount, 1);
      expect(
        first.state.cancellation,
        RiderCancellationPhase.cancelling,
      );
      expect(
        second.state.cancellation,
        RiderCancellationPhase.cancelling,
      );

      gate.complete(RiderBookingCancellationAccepted(
        riderBookingSearchFixture(
          version: 4,
          status: RiderBookingSearchStatus.cancelled,
        ),
      ));
      await firstCancel;
      await _flush();

      expect(first.state.phase, RiderSearchPhase.cancelled);
      expect(second.state.phase, RiderSearchPhase.cancelled);
      expect(cancels.cancelCount, 1);
    });

    test('verified cancellation blocks stale siblings and repeated remounts',
        () async {
      var session = SessionState.fromUser(_rider);
      final readsA = _reads();
      final readsB = _reads();
      final cancels = FakeRiderBookingCancellationRepository(
        result: const RiderBookingCancellationUnknown(),
      );
      final coordinator = RiderCancellationCoordinator(repository: cancels);
      addTearDown(coordinator.dispose);
      final first = _controller(
        readSession: () => session,
        reads: readsA,
        coordinator: coordinator,
      );
      final second = _controller(
        readSession: () => session,
        reads: readsB,
        coordinator: coordinator,
      );
      await first.refresh();
      await second.refresh();
      await first.cancelBooking(reasonCode: 'Changed my mind');
      expect(second.state.cancellation, RiderCancellationPhase.uncertain);

      readsA.booking = riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.cancelled,
      );
      await first.refresh();

      expect(first.state.phase, RiderSearchPhase.cancelled);
      expect(second.state.phase, RiderSearchPhase.cancelled);
      expect(second.state.booking!.version, 4);
      expect(second.canCancel, isFalse);
      expect(readsB.readCount, 1);
      expect(
        coordinator
            .attemptFor(
              riderId: riderIdFixture,
              bookingRequestId: riderBookingIdFixture,
            )
            ?.phase,
        RiderCancellationAttemptPhase.verifiedCancelled,
      );
      await second.cancelBooking(reasonCode: 'Changed my mind');
      expect(cancels.cancelCount, 1);

      session = SessionState.fromUser(_rider);
      first.sessionChanged(session);
      second.sessionChanged(session);
      first.dispose();
      second.dispose();
      for (var remount = 0; remount < 2; remount++) {
        final current = _controller(
          readSession: () => session,
          reads: _reads(),
          coordinator: coordinator,
        );
        expect(current.state.phase, RiderSearchPhase.cancelled);
        expect(current.canCancel, isFalse);
        await current.cancelBooking(reasonCode: 'Changed my mind');
        expect(cancels.cancelCount, 1);
        session = SessionState.fromUser(_rider);
        current.sessionChanged(session);
        current.dispose();
      }
    });

    test('unrelated coordinator notifications preserve accepted cancellation',
        () async {
      final session = SessionState.fromUser(_rider);
      final cancels = FakeRiderBookingCancellationRepository(
        result: RiderBookingCancellationAccepted(
          riderBookingSearchFixture(
            version: 4,
            status: RiderBookingSearchStatus.cancelled,
          ),
        ),
      );
      final coordinator = RiderCancellationCoordinator(repository: cancels);
      addTearDown(coordinator.dispose);
      final controller = _controller(
        readSession: () => session,
        reads: _reads(),
        coordinator: coordinator,
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.cancelBooking(reasonCode: 'Changed my mind');
      expect(controller.state.phase, RiderSearchPhase.cancelled);

      cancels.result = const RiderBookingCancellationUnknown();
      await coordinator.cancel(
        riderId: riderIdFixture,
        bookingRequestId: secondaryRiderBookingIdFixture,
        expectedVersion: 3,
        observedStatus: RiderBookingSearchStatus.searching,
        reasonCode: 'Changed my mind',
      );

      expect(controller.state.phase, RiderSearchPhase.cancelled);
      expect(controller.state.cancellation, RiderCancellationPhase.idle);
      expect(controller.state.booking!.version, 4);
      expect(cancels.cancelCount, 2);
    });

    test('remount and same-Rider replacement retain the pending attempt',
        () async {
      final gate = Completer<RiderBookingCancellationResult>();
      final cancels = FakeRiderBookingCancellationRepository(
        onCancel: (_) => gate.future,
      );
      final coordinator = RiderCancellationCoordinator(repository: cancels);
      addTearDown(coordinator.dispose);
      final reads = _reads();
      final session = SessionState.fromUser(_rider);
      final first = _controller(
        readSession: () => session,
        reads: reads,
        coordinator: coordinator,
      );
      await first.refresh();
      final pending = first.cancelBooking(reasonCode: 'Changed my mind');
      first.sessionChanged(SessionState.fromUser(_rider));
      first.dispose();

      final second = _controller(
        readSession: () => session,
        reads: reads,
        coordinator: coordinator,
      );
      addTearDown(second.dispose);

      expect(
        second.state.cancellation,
        RiderCancellationPhase.cancelling,
      );
      await second.refresh();
      expect(reads.readCount, 1);
      final duplicate = second.cancelBooking(reasonCode: 'Changed my mind');
      expect(identical(pending, duplicate), isTrue);
      expect(cancels.cancelCount, 1);

      gate.complete(RiderBookingCancellationAccepted(
        riderBookingSearchFixture(
          version: 4,
          status: RiderBookingSearchStatus.cancelled,
        ),
      ));
      await pending;
      await _flush();

      expect(second.state.phase, RiderSearchPhase.cancelled);
      expect(second.state.booking!.version, 4);
    });

    test('remount after a pending cancellation resolves unknown by rereading',
        () async {
      final gate = Completer<RiderBookingCancellationResult>();
      final cancels = FakeRiderBookingCancellationRepository(
        onCancel: (_) => gate.future,
      );
      final coordinator = RiderCancellationCoordinator(repository: cancels);
      addTearDown(coordinator.dispose);
      final reads = _reads();
      final session = SessionState.fromUser(_rider);
      final first = _controller(
        readSession: () => session,
        reads: reads,
        coordinator: coordinator,
      );
      await first.refresh();
      final pending = first.cancelBooking(reasonCode: 'Changed my mind');
      first.sessionChanged(SessionState.fromUser(_rider));
      first.dispose();

      final second = _controller(
        readSession: () => session,
        reads: reads,
        coordinator: coordinator,
      );
      addTearDown(second.dispose);
      expect(
        second.state.cancellation,
        RiderCancellationPhase.cancelling,
      );

      gate.complete(const RiderBookingCancellationUnknown());
      await pending;
      await _flush();

      expect(second.state.cancellation, RiderCancellationPhase.uncertain);
      expect(second.state.phase, RiderSearchPhase.searching);
      expect(second.state.booking!.version, 3);
      expect(reads.readCount, 2);
      expect(cancels.cancelCount, 1);
    });

    test('not-cancellable rejection resolves matching without claiming success',
        () async {
      final session = SessionState.fromUser(_rider);
      final reads = _reads();
      final cancels = FakeRiderBookingCancellationRepository(
        result: const RiderBookingCancellationRejected(
          RiderCancellationRejection.notCancellable,
        ),
      );
      final controller = _controller(
        readSession: () => session,
        reads: reads,
        cancels: cancels,
      );
      addTearDown(controller.dispose);
      await controller.refresh();

      reads.booking = riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.matched,
      );
      await controller.cancelBooking(reasonCode: 'Other reason');
      await _flush();

      expect(cancels.cancelCount, 1);
      expect(controller.state.phase, RiderSearchPhase.assignmentPending);
      expect(controller.state.cancellation, RiderCancellationPhase.rejected);
      expect(
          controller.state.booking!.status, RiderBookingSearchStatus.matched);
      expect(controller.canCancel, isFalse);
    });

    test(
        'unknown outcome stays blocked after an authoritative searching reread',
        () async {
      final session = SessionState.fromUser(_rider);
      final reads = _reads();
      final cancels = FakeRiderBookingCancellationRepository(
        result: const RiderBookingCancellationUnknown(),
      );
      final controller = _controller(
        readSession: () => session,
        reads: reads,
        cancels: cancels,
      );
      addTearDown(controller.dispose);
      await controller.refresh();

      await controller.cancelBooking(reasonCode: 'Changed my mind');
      expect(controller.state.cancellation, RiderCancellationPhase.uncertain);
      expect(controller.state.phase, RiderSearchPhase.searching);
      expect(controller.canCancel, isFalse);

      await controller.refresh();
      expect(controller.state.phase, RiderSearchPhase.searching);
      expect(controller.state.cancellation, RiderCancellationPhase.uncertain);
      expect(controller.canCancel, isFalse);

      await controller.cancelBooking(reasonCode: 'Changed my mind');
      expect(cancels.cancelCount, 1);
      expect(reads.readCount, 2);

      reads.booking = riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.cancelled,
      );
      await controller.refresh();
      expect(controller.state.phase, RiderSearchPhase.cancelled);
      expect(controller.state.cancellation, RiderCancellationPhase.idle);
      expect(cancels.cancelCount, 1);
    });

    test('unknown outcome resolves a matched booking without success claim',
        () async {
      final session = SessionState.fromUser(_rider);
      final reads = _reads();
      final controller = _controller(
        readSession: () => session,
        reads: reads,
        cancels: FakeRiderBookingCancellationRepository(
          result: const RiderBookingCancellationUnknown(),
        ),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.cancelBooking(reasonCode: 'Changed my mind');

      reads.booking = riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.matched,
      );
      await controller.refresh();

      expect(controller.state.phase, RiderSearchPhase.assignmentPending);
      expect(controller.state.cancellation, RiderCancellationPhase.uncertain);
      expect(
          controller.state.booking!.status, RiderBookingSearchStatus.matched);
    });

    test('invalid or oversized reasons never reach the repository', () async {
      final session = SessionState.fromUser(_rider);
      for (final reason in ['   ', 'a' * 101]) {
        final cancels = FakeRiderBookingCancellationRepository();
        final controller = _controller(
          readSession: () => session,
          reads: _reads(),
          cancels: cancels,
        );
        await controller.refresh();
        await controller.cancelBooking(reasonCode: reason);
        expect(cancels.cancelCount, 0);
        expect(
          controller.state.cancellation,
          RiderCancellationPhase.rejected,
        );
        expect(
          controller.state.rejection,
          RiderCancellationRejection.reasonInvalid,
        );
        expect(controller.canCancel, isFalse);
        controller.dispose();
      }
    });

    test('repeated cancellation requests share one attempt', () async {
      final session = SessionState.fromUser(_rider);
      final gate = Completer<RiderBookingCancellationResult>();
      final cancels = FakeRiderBookingCancellationRepository(
        onCancel: (_) => gate.future,
      );
      final controller = _controller(
        readSession: () => session,
        reads: _reads(),
        cancels: cancels,
      );
      addTearDown(controller.dispose);
      await controller.refresh();

      final first = controller.cancelBooking(reasonCode: 'Changed my mind');
      final second = controller.cancelBooking(reasonCode: 'Changed my mind');
      expect(identical(first, second), isTrue);
      expect(cancels.cancelCount, 1);
      expect(controller.state.cancellation, RiderCancellationPhase.cancelling);

      gate.complete(RiderBookingCancellationAccepted(
        riderBookingSearchFixture(
          version: 4,
          status: RiderBookingSearchStatus.cancelled,
        ),
      ));
      await first;
      expect(controller.state.phase, RiderSearchPhase.cancelled);
    });

    test('session replacement during cancellation drops the late result',
        () async {
      var session = SessionState.fromUser(_rider);
      final gate = Completer<RiderBookingCancellationResult>();
      final controller = _controller(
        readSession: () => session,
        reads: _reads(),
        cancels: FakeRiderBookingCancellationRepository(
          onCancel: (_) => gate.future,
        ),
      );
      await controller.refresh();
      final pending = controller.cancelBooking(reasonCode: 'Changed my mind');

      session = SessionState.fromUser(_rider);
      controller.sessionChanged(session);
      gate.complete(RiderBookingCancellationAccepted(
        riderBookingSearchFixture(
          version: 4,
          status: RiderBookingSearchStatus.cancelled,
        ),
      ));
      await pending;

      expect(controller.state.phase, RiderSearchPhase.unresolved);
      expect(controller.state.booking, isNull);
      expect(controller.state.cancellation, RiderCancellationPhase.idle);
      controller.dispose();
    });

    test('disposal during cancellation drops the late result', () async {
      final session = SessionState.fromUser(_rider);
      final gate = Completer<RiderBookingCancellationResult>();
      final controller = _controller(
        readSession: () => session,
        reads: _reads(),
        cancels: FakeRiderBookingCancellationRepository(
          onCancel: (_) => gate.future,
        ),
      );
      await controller.refresh();
      final pending = controller.cancelBooking(reasonCode: 'Changed my mind');
      controller.dispose();

      gate.complete(RiderBookingCancellationAccepted(
        riderBookingSearchFixture(
          version: 4,
          status: RiderBookingSearchStatus.cancelled,
        ),
      ));
      await pending;
      expect(controller.state.phase, isNot(RiderSearchPhase.cancelled));
    });

    test('cancellation deadline becomes uncertain', () async {
      final timers = <_ManualTimer>[];
      final gate = Completer<RiderBookingCancellationResult>();
      final session = SessionState.fromUser(_rider);
      final coordinator = RiderCancellationCoordinator(
        repository: FakeRiderBookingCancellationRepository(
          onCancel: (_) => gate.future,
        ),
        scheduleDeadline: (_, callback) {
          final timer = _ManualTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      addTearDown(coordinator.dispose);
      final controller = _controller(
        readSession: () => session,
        reads: _reads(),
        coordinator: coordinator,
        scheduleReadDeadline: (_, callback) {
          final timer = _ManualTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      final pending = controller.cancelBooking(reasonCode: 'Changed my mind');
      await _flush();
      expect(timers, hasLength(2));

      timers.last.fire();
      await pending;
      expect(controller.state.cancellation, RiderCancellationPhase.uncertain);
      expect(controller.canCancel, isFalse);

      gate.complete(RiderBookingCancellationAccepted(
        riderBookingSearchFixture(
          version: 4,
          status: RiderBookingSearchStatus.cancelled,
        ),
      ));
      await _flush();
      expect(controller.state.cancellation, RiderCancellationPhase.uncertain);
      expect(controller.state.phase, isNot(RiderSearchPhase.cancelled));
    });
  });

  group('RiderSearchController assignment verification', () {
    test('a linked owned Cash Trip verifies without exposing Driver details',
        () async {
      final session = SessionState.fromUser(_rider);
      final controller = _controller(
        readSession: () => session,
        reads: _reads(
          status: RiderBookingSearchStatus.matched,
          version: 4,
        ),
        trips: FakeRiderTripTrackingRepository(
          trip: riderAssignedTripFixture(version: 9),
        ),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await _flush();

      expect(controller.state.phase, RiderSearchPhase.assignmentPending);
      expect(controller.state.assignment, RiderAssignmentVerification.verified);
      expect(controller.state.booking!.version, 4);
    });

    test('a lower or contradictory Trip version never verifies', () async {
      final session = SessionState.fromUser(_rider);
      final reads = _reads(
        status: RiderBookingSearchStatus.matched,
        version: 4,
      );
      final trips = _SequenceTripRepository([
        riderAssignedTripFixture(version: 9),
        riderAssignedTripFixture(version: 8),
        riderAssignedTripFixture(
          tripId: secondaryRiderTripIdFixture,
          version: 9,
        ),
      ]);
      final controller = _controller(
        readSession: () => session,
        reads: reads,
        trips: trips,
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      await _flush();
      expect(controller.state.assignment, RiderAssignmentVerification.verified);

      reads.booking = riderBookingSearchFixture(
        version: 5,
        status: RiderBookingSearchStatus.matched,
      );
      await controller.refresh();
      await _flush();
      expect(controller.state.assignment, RiderAssignmentVerification.invalid);

      reads.booking = riderBookingSearchFixture(
        version: 6,
        status: RiderBookingSearchStatus.matched,
      );
      await controller.refresh();
      await _flush();
      expect(controller.state.assignment, RiderAssignmentVerification.invalid);
    });

    test('absent Trip evidence is unverified', () async {
      final session = SessionState.fromUser(_rider);
      final controller = _controller(
        readSession: () => session,
        reads: _reads(status: RiderBookingSearchStatus.matched),
        trips: FakeRiderTripTrackingRepository(),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await _flush();

      expect(
        controller.state.assignment,
        RiderAssignmentVerification.unverified,
      );
    });

    test('foreign or mismatched Trip evidence is invalid', () async {
      final session = SessionState.fromUser(_rider);
      for (final trip in [
        riderAssignedTripFixture(riderId: unrelatedRiderIdFixture),
        riderAssignedTripFixture(
          bookingRequestId: secondaryRiderBookingIdFixture,
        ),
      ]) {
        final controller = _controller(
          readSession: () => session,
          reads: _reads(status: RiderBookingSearchStatus.matched),
          trips: _FixedTripRepository(trip),
        );
        await controller.refresh();
        await _flush();
        expect(
          controller.state.assignment,
          RiderAssignmentVerification.invalid,
        );
        controller.dispose();
      }
    });

    test('failing Trip read is unavailable', () async {
      final session = SessionState.fromUser(_rider);
      final trips = FakeRiderTripTrackingRepository()
        ..bookingLoadError = StateError('assignment read failed');
      final controller = _controller(
        readSession: () => session,
        reads: _reads(status: RiderBookingSearchStatus.matched),
        trips: trips,
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await _flush();

      expect(
        controller.state.assignment,
        RiderAssignmentVerification.unavailable,
      );
    });

    test('assignment read deadline is bounded', () async {
      final timers = <_ManualTimer>[];
      final pendingTrip = _PendingTripRepository();
      final session = SessionState.fromUser(_rider);
      final controller = _controller(
        readSession: () => session,
        reads: _reads(status: RiderBookingSearchStatus.matched),
        trips: pendingTrip,
        scheduleReadDeadline: (_, callback) {
          final timer = _ManualTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await _flush();
      expect(controller.state.assignment, RiderAssignmentVerification.loading);

      timers.last.fire();
      await _flush();
      expect(
        controller.state.assignment,
        RiderAssignmentVerification.unavailable,
      );

      pendingTrip.complete(riderAssignedTripFixture());
      await _flush();
      expect(
        controller.state.assignment,
        RiderAssignmentVerification.unavailable,
      );
    });

    test('session replacement during verification drops the late Trip',
        () async {
      var session = SessionState.fromUser(_rider);
      final pendingTrip = _PendingTripRepository();
      final controller = _controller(
        readSession: () => session,
        reads: _reads(status: RiderBookingSearchStatus.matched),
        trips: pendingTrip,
      );
      await controller.refresh();
      await _flush();
      expect(controller.state.assignment, RiderAssignmentVerification.loading);

      session = SessionState.fromUser(_rider);
      controller.sessionChanged(session);
      pendingTrip.complete(riderAssignedTripFixture());
      await _flush();

      expect(controller.state.phase, RiderSearchPhase.unresolved);
      expect(
        controller.state.assignment,
        RiderAssignmentVerification.notRequested,
      );
      controller.dispose();
    });

    test('no Trip repository leaves verification unrequested', () async {
      final session = SessionState.fromUser(_rider);
      final controller = _controller(
        readSession: () => session,
        reads: _reads(status: RiderBookingSearchStatus.matched),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await _flush();

      expect(
        controller.state.assignment,
        RiderAssignmentVerification.notRequested,
      );
    });
  });
}

class _FixedTripRepository implements RiderTripTrackingRepository {
  _FixedTripRepository(this.trip);

  final RiderAssignedTrip? trip;

  @override
  Future<RiderAssignedTrip?> findByBooking({
    required String bookingRequestId,
  }) async =>
      trip;

  @override
  Future<RiderAssignedTrip?> findByTrip({required String tripId}) async => null;

  @override
  Stream<RiderTripTrackingEvent> watch({required String tripId}) =>
      const Stream<RiderTripTrackingEvent>.empty();
}

class _SequenceTripRepository implements RiderTripTrackingRepository {
  _SequenceTripRepository(this.trips);

  final List<RiderAssignedTrip> trips;
  int _index = 0;

  @override
  Future<RiderAssignedTrip?> findByBooking({
    required String bookingRequestId,
  }) async {
    if (_index >= trips.length) return trips.last;
    return trips[_index++];
  }

  @override
  Future<RiderAssignedTrip?> findByTrip({required String tripId}) async => null;

  @override
  Stream<RiderTripTrackingEvent> watch({required String tripId}) =>
      const Stream<RiderTripTrackingEvent>.empty();
}

class _PendingTripRepository implements RiderTripTrackingRepository {
  final Completer<RiderAssignedTrip?> _completer =
      Completer<RiderAssignedTrip?>();

  void complete(RiderAssignedTrip trip) => _completer.complete(trip);

  @override
  Future<RiderAssignedTrip?> findByBooking({
    required String bookingRequestId,
  }) =>
      _completer.future;

  @override
  Future<RiderAssignedTrip?> findByTrip({required String tripId}) async => null;

  @override
  Stream<RiderTripTrackingEvent> watch({required String tripId}) =>
      const Stream<RiderTripTrackingEvent>.empty();
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
