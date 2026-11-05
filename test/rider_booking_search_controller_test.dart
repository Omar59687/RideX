import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_booking_search.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/rider_booking_cancellation_repository.dart';
import 'package:ridex/core/repositories/rider_booking_search_repository.dart';
import 'package:ridex/core/services/rider_cancellation/rider_cancellation_coordinator.dart';
import 'package:ridex/features/booking/application/rider_search_controller.dart';

import 'helpers/fake_rider_booking_search_repository.dart';
import 'helpers/fake_rider_trip_tracking_repository.dart';

RiderCancellationCoordinator _newCancellationCoordinator() {
  final coordinator = RiderCancellationCoordinator(
    repository: const UnavailableRiderBookingCancellationRepository(),
  );
  addTearDown(coordinator.dispose);
  return coordinator;
}

const _rider = AppUser(
  id: riderIdFixture,
  name: 'Test Rider',
  email: 'rider@example.com',
  role: RideRole.rider,
);

void main() {
  group('canonical booking-search contract', () {
    test('maps only exact backend statuses', () {
      for (final status in RiderBookingSearchStatus.values) {
        expect(RiderBookingSearchStatus.fromBackendValue(status.backendValue),
            status);
      }
      expect(
        () => RiderBookingSearchStatus.fromBackendValue('noDriverFound'),
        throwsArgumentError,
      );
      expect(
        () => RiderBookingSearchStatus.fromBackendValue('timeout'),
        throwsArgumentError,
      );
    });

    test('requires canonical IDs, a positive version, and Cash', () {
      expect(
        () => riderBookingSearchFixture(bookingRequestId: 'booking-1'),
        throwsArgumentError,
      );
      expect(
        () => riderBookingSearchFixture(riderId: 'rider-1'),
        throwsArgumentError,
      );
      expect(() => riderBookingSearchFixture(version: 0), throwsArgumentError);
      expect(
        () => riderBookingSearchFixture(paymentMethod: PaymentMethod.card),
        throwsArgumentError,
      );
    });

    test('default repository fails closed instead of returning demo data',
        () async {
      const repository = UnavailableRiderBookingSearchRepository();
      await expectLater(
        repository.readBooking(bookingRequestId: riderBookingIdFixture),
        throwsA(isA<RiderBookingSearchReadException>().having(
          (error) => error.failure,
          'failure',
          RiderBookingSearchReadFailure.unavailable,
        )),
      );
    });
  });

  group('RiderSearchController', () {
    test('reads waiting, searching, and verified terminal states only',
        () async {
      final repository = FakeRiderBookingSearchRepository(
        authenticatedRiderId: riderIdFixture,
        booking: riderBookingSearchFixture(
          status: RiderBookingSearchStatus.confirmed,
        ),
      );
      final session = SessionState.fromUser(_rider);
      final controller = RiderSearchController(
        bookingRequestId: riderBookingIdFixture,
        repository: repository,
        readSession: () => session,
        cancellationCoordinator: _newCancellationCoordinator(),
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      expect(controller.state.phase, RiderSearchPhase.waiting);
      for (final (status, phase) in [
        (RiderBookingSearchStatus.searching, RiderSearchPhase.searching),
        (RiderBookingSearchStatus.expired, RiderSearchPhase.expired),
        (RiderBookingSearchStatus.failed, RiderSearchPhase.failed),
        (RiderBookingSearchStatus.cancelled, RiderSearchPhase.cancelled),
        (RiderBookingSearchStatus.matched, RiderSearchPhase.assignmentPending),
        (RiderBookingSearchStatus.draft, RiderSearchPhase.unresolved),
      ]) {
        repository.booking = riderBookingSearchFixture(status: status);
        final current = RiderSearchController(
          bookingRequestId: riderBookingIdFixture,
          repository: repository,
          readSession: () => session,
          cancellationCoordinator: _newCancellationCoordinator(),
        );
        await current.refresh();
        expect(current.state.phase, phase);
        expect(current.state.booking!.status, status);
        current.dispose();
      }
      expect(
          repository.requestedBookingIds, everyElement(riderBookingIdFixture));
    });

    test('soft timeout retains canonical status and retry only rereads',
        () async {
      final timers = <_ManualTimer>[];
      final repository = FakeRiderBookingSearchRepository(
        authenticatedRiderId: riderIdFixture,
        booking: riderBookingSearchFixture(),
      );
      final session = SessionState.fromUser(_rider);
      final controller = RiderSearchController(
        bookingRequestId: riderBookingIdFixture,
        repository: repository,
        readSession: () => session,
        cancellationCoordinator: _newCancellationCoordinator(),
        scheduleTimeout: (_, callback) {
          final timer = _ManualTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      expect(controller.state.phase, RiderSearchPhase.searching);
      timers.single.fire();
      expect(controller.state.phase, RiderSearchPhase.timedOut);
      expect(
          controller.state.booking!.status, RiderBookingSearchStatus.searching);
      expect(repository.readCount, 1);
      await controller.refresh();
      expect(controller.state.phase, RiderSearchPhase.searching);
      expect(repository.requestedBookingIds,
          [riderBookingIdFixture, riderBookingIdFixture]);
      expect(timers, hasLength(2));
    });

    test('older or conflicting same-version reads never regress state',
        () async {
      final repository = FakeRiderBookingSearchRepository(
        authenticatedRiderId: riderIdFixture,
        booking: riderBookingSearchFixture(version: 5),
      );
      final session = SessionState.fromUser(_rider);
      final controller = RiderSearchController(
        bookingRequestId: riderBookingIdFixture,
        repository: repository,
        readSession: () => session,
        cancellationCoordinator: _newCancellationCoordinator(),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.state.phase, RiderSearchPhase.searching);

      repository.booking = riderBookingSearchFixture(
        version: 4,
        status: RiderBookingSearchStatus.confirmed,
      );
      await controller.refresh();
      expect(controller.state.phase, RiderSearchPhase.unresolved);
      repository.booking = riderBookingSearchFixture(
        version: 5,
        status: RiderBookingSearchStatus.confirmed,
      );
      await controller.refresh();
      expect(controller.state.phase, RiderSearchPhase.unresolved);

      repository.booking = riderBookingSearchFixture(
        version: 6,
        status: RiderBookingSearchStatus.expired,
      );
      await controller.refresh();
      expect(controller.state.phase, RiderSearchPhase.expired);
      expect(controller.state.booking!.version, 6);
    });

    test('skipped forward lifecycle observations remain valid', () async {
      final repository = FakeRiderBookingSearchRepository(
        authenticatedRiderId: riderIdFixture,
        booking: riderBookingSearchFixture(
          version: 3,
          status: RiderBookingSearchStatus.confirmed,
        ),
      );
      final session = SessionState.fromUser(_rider);
      final controller = RiderSearchController(
        bookingRequestId: riderBookingIdFixture,
        repository: repository,
        readSession: () => session,
        cancellationCoordinator: _newCancellationCoordinator(),
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      repository.booking = riderBookingSearchFixture(
        version: 5,
        status: RiderBookingSearchStatus.matched,
      );
      await controller.refresh();
      expect(controller.state.phase, RiderSearchPhase.assignmentPending);
      expect(controller.state.booking!.version, 5);
    });

    test('higher versions cannot reopen terminal or regress active bookings',
        () async {
      final session = SessionState.fromUser(_rider);
      for (final terminal in [
        RiderBookingSearchStatus.cancelled,
        RiderBookingSearchStatus.expired,
        RiderBookingSearchStatus.failed,
        RiderBookingSearchStatus.matched,
      ]) {
        final repository = FakeRiderBookingSearchRepository(
          authenticatedRiderId: riderIdFixture,
          booking: riderBookingSearchFixture(version: 5, status: terminal),
        );
        final controller = RiderSearchController(
          bookingRequestId: riderBookingIdFixture,
          repository: repository,
          readSession: () => session,
          cancellationCoordinator: _newCancellationCoordinator(),
        );
        await controller.refresh();
        repository.booking = riderBookingSearchFixture(
          version: 6,
          status: RiderBookingSearchStatus.searching,
        );
        await controller.refresh();
        expect(controller.state.phase, RiderSearchPhase.unresolved,
            reason: '$terminal cannot return to searching');
        expect(controller.state.booking, isNull);
        controller.dispose();
      }
      for (final (previous, backward) in [
        (
          RiderBookingSearchStatus.searching,
          RiderBookingSearchStatus.confirmed
        ),
        (RiderBookingSearchStatus.confirmed, RiderBookingSearchStatus.draft),
      ]) {
        final repository = FakeRiderBookingSearchRepository(
          authenticatedRiderId: riderIdFixture,
          booking: riderBookingSearchFixture(version: 5, status: previous),
        );
        final controller = RiderSearchController(
          bookingRequestId: riderBookingIdFixture,
          repository: repository,
          readSession: () => session,
          cancellationCoordinator: _newCancellationCoordinator(),
        );
        await controller.refresh();
        repository.booking = riderBookingSearchFixture(
          version: 8,
          status: backward,
        );
        await controller.refresh();
        expect(controller.state.phase, RiderSearchPhase.unresolved);
        controller.dispose();
      }
    });

    for (final lateError in [false, true]) {
      test(
          'read deadline releases retry and ignores late old '
          '${lateError ? 'error' : 'success'}', () async {
        final oldRead = Completer<RiderBookingSearchSnapshot?>();
        final newRead = Completer<RiderBookingSearchSnapshot?>();
        final deadlines = <_ManualTimer>[];
        final feedback = <_ManualTimer>[];
        var calls = 0;
        final repository = FakeRiderBookingSearchRepository(
          authenticatedRiderId: riderIdFixture,
          onRead: (_) => ++calls == 1 ? oldRead.future : newRead.future,
        );
        final session = SessionState.fromUser(_rider);
        final controller = RiderSearchController(
          bookingRequestId: riderBookingIdFixture,
          repository: repository,
          readSession: () => session,
          cancellationCoordinator: _newCancellationCoordinator(),
          readDeadline: const Duration(seconds: 5),
          softTimeout: const Duration(seconds: 60),
          scheduleReadDeadline: (_, callback) {
            final timer = _ManualTimer(callback);
            deadlines.add(timer);
            return timer;
          },
          scheduleTimeout: (_, callback) {
            final timer = _ManualTimer(callback);
            feedback.add(timer);
            return timer;
          },
        );
        addTearDown(controller.dispose);

        final abandoned = controller.refresh();
        await Future<void>.delayed(Duration.zero);
        expect(repository.readCount, 1);
        expect(deadlines.single.isActive, isTrue);
        expect(feedback, isEmpty);
        deadlines.single.fire();
        await abandoned;
        expect(controller.state.phase, RiderSearchPhase.unavailable);
        expect(controller.canRetry, isTrue);

        final fresh = controller.refresh();
        await Future<void>.delayed(Duration.zero);
        expect(repository.requestedBookingIds,
            [riderBookingIdFixture, riderBookingIdFixture]);
        if (lateError) {
          oldRead.completeError(StateError('late response failure'));
        } else {
          oldRead.complete(riderBookingSearchFixture(
            version: 9,
            status: RiderBookingSearchStatus.failed,
          ));
        }
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.phase, RiderSearchPhase.loading);

        newRead.complete(riderBookingSearchFixture());
        await fresh;
        expect(controller.state.phase, RiderSearchPhase.searching);
        expect(controller.state.booking!.version, 3);
        expect(deadlines.last.isActive, isFalse);
        expect(feedback, hasLength(1));
      });
    }

    test('session invalidation and disposal cancel both timer kinds', () async {
      var session = SessionState.fromUser(_rider);
      final deadlines = <_ManualTimer>[];
      final feedback = <_ManualTimer>[];
      final pendingRead = Completer<RiderBookingSearchSnapshot?>();
      final repository = FakeRiderBookingSearchRepository(
        authenticatedRiderId: riderIdFixture,
        onRead: (_) => pendingRead.future,
      );
      final controller = RiderSearchController(
        bookingRequestId: riderBookingIdFixture,
        repository: repository,
        readSession: () => session,
        cancellationCoordinator: _newCancellationCoordinator(),
        scheduleReadDeadline: (_, callback) {
          final timer = _ManualTimer(callback);
          deadlines.add(timer);
          return timer;
        },
        scheduleTimeout: (_, callback) {
          final timer = _ManualTimer(callback);
          feedback.add(timer);
          return timer;
        },
      );

      final pending = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      session = SessionState.fromUser(_rider);
      controller.sessionChanged(session);
      await pending;
      expect(deadlines.single.isActive, isFalse);
      pendingRead.completeError(StateError('late after session replacement'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.phase, RiderSearchPhase.unresolved);
      controller.dispose();

      final activeRepository = FakeRiderBookingSearchRepository(
        authenticatedRiderId: riderIdFixture,
        booking: riderBookingSearchFixture(),
      );
      final active = RiderSearchController(
        bookingRequestId: riderBookingIdFixture,
        repository: activeRepository,
        readSession: () => session,
        cancellationCoordinator: _newCancellationCoordinator(),
        scheduleTimeout: (_, callback) {
          final timer = _ManualTimer(callback);
          feedback.add(timer);
          return timer;
        },
      );
      await active.refresh();
      expect(feedback.single.isActive, isTrue);
      active.dispose();
      expect(feedback.single.isActive, isFalse);
      feedback.single.fire();
    });

    test('repeated refresh requests share one in-flight read', () async {
      final gate = Completer<RiderBookingSearchSnapshot?>();
      final repository = FakeRiderBookingSearchRepository(
        authenticatedRiderId: riderIdFixture,
        onRead: (_) => gate.future,
      );
      final session = SessionState.fromUser(_rider);
      final controller = RiderSearchController(
        bookingRequestId: riderBookingIdFixture,
        repository: repository,
        readSession: () => session,
        cancellationCoordinator: _newCancellationCoordinator(),
      );
      addTearDown(controller.dispose);

      final first = controller.refresh();
      final second = controller.refresh();
      expect(identical(first, second), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(repository.readCount, 1);
      gate.complete(riderBookingSearchFixture());
      await Future.wait([first, second]);
      expect(controller.state.phase, RiderSearchPhase.searching);
    });

    test('distinguishes unavailable from missing and malformed responses',
        () async {
      final repository = FakeRiderBookingSearchRepository(
        authenticatedRiderId: riderIdFixture,
      );
      final session = SessionState.fromUser(_rider);
      final controller = RiderSearchController(
        bookingRequestId: riderBookingIdFixture,
        repository: repository,
        readSession: () => session,
        cancellationCoordinator: _newCancellationCoordinator(),
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      expect(controller.state.phase, RiderSearchPhase.unresolved);
      repository.onRead =
          (_) async => throw const RiderBookingSearchReadException(
                RiderBookingSearchReadFailure.unavailable,
              );
      await controller.refresh();
      expect(controller.state.phase, RiderSearchPhase.unavailable);
      repository.onRead =
          (_) async => throw const RiderBookingSearchReadException(
                RiderBookingSearchReadFailure.invalidResponse,
              );
      await controller.refresh();
      expect(controller.state.phase, RiderSearchPhase.unresolved);
      repository.onRead = (_) async => riderBookingSearchFixture(
            bookingRequestId: secondaryRiderBookingIdFixture,
          );
      await controller.refresh();
      expect(controller.state.phase, RiderSearchPhase.unresolved);
      repository.onRead = (_) async => riderBookingSearchFixture(
            riderId: unrelatedRiderIdFixture,
          );
      await controller.refresh();
      expect(controller.state.phase, RiderSearchPhase.unresolved);
      expect(controller.state.booking, isNull);
    });

    test('same-Rider session refresh rejects delayed results and future reads',
        () async {
      var session = SessionState.fromUser(_rider);
      final gate = Completer<RiderBookingSearchSnapshot?>();
      final repository = FakeRiderBookingSearchRepository(
        authenticatedRiderId: riderIdFixture,
        onRead: (_) => gate.future,
      );
      final controller = RiderSearchController(
        bookingRequestId: riderBookingIdFixture,
        repository: repository,
        readSession: () => session,
        cancellationCoordinator: _newCancellationCoordinator(),
      );
      addTearDown(controller.dispose);

      final pending = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      session = SessionState.fromUser(_rider);
      controller.sessionChanged(session);
      gate.complete(riderBookingSearchFixture());
      await pending;

      expect(controller.state.phase, RiderSearchPhase.unresolved);
      expect(controller.state.booking, isNull);
      expect(controller.canRetry, isFalse);
      await controller.refresh();
      expect(repository.readCount, 1);
    });

    test('logout and wrong-role sessions cannot retain or read booking data',
        () async {
      var session = SessionState.fromUser(_rider);
      final repository = FakeRiderBookingSearchRepository(
        authenticatedRiderId: riderIdFixture,
        booking: riderBookingSearchFixture(),
      );
      final controller = RiderSearchController(
        bookingRequestId: riderBookingIdFixture,
        repository: repository,
        readSession: () => session,
        cancellationCoordinator: _newCancellationCoordinator(),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      session = const SessionState.unauthenticated();
      controller.sessionChanged(session);
      expect(controller.state.booking, isNull);
      expect(controller.canRetry, isFalse);

      final driverSession = SessionState.fromUser(const AppUser(
        id: riderIdFixture,
        name: 'Driver',
        email: 'driver@example.com',
        role: RideRole.driver,
      ));
      final driverController = RiderSearchController(
        bookingRequestId: riderBookingIdFixture,
        repository: repository,
        readSession: () => driverSession,
        cancellationCoordinator: _newCancellationCoordinator(),
      );
      addTearDown(driverController.dispose);
      await driverController.refresh();
      expect(driverController.state.phase, RiderSearchPhase.unresolved);
      expect(repository.readCount, 1);
    });

    test('Rider ownership change clears a displayed booking and blocks reads',
        () async {
      var session = SessionState.fromUser(_rider);
      final repository = FakeRiderBookingSearchRepository(
        authenticatedRiderId: riderIdFixture,
        booking: riderBookingSearchFixture(),
      );
      final controller = RiderSearchController(
        bookingRequestId: riderBookingIdFixture,
        repository: repository,
        readSession: () => session,
        cancellationCoordinator: _newCancellationCoordinator(),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.state.booking, isNotNull);

      session = SessionState.fromUser(const AppUser(
        id: unrelatedRiderIdFixture,
        name: 'Other Rider',
        email: 'other@example.com',
        role: RideRole.rider,
      ));
      controller.sessionChanged(session);
      expect(controller.state.phase, RiderSearchPhase.unresolved);
      expect(controller.state.booking, isNull);
      await controller.refresh();
      expect(repository.readCount, 1);

      final blocked = SessionState.fromUser(const AppUser(
        id: riderIdFixture,
        name: 'Blocked Rider',
        email: 'blocked@example.com',
        role: RideRole.rider,
        isBlocked: true,
      ));
      final blockedController = RiderSearchController(
        bookingRequestId: riderBookingIdFixture,
        repository: repository,
        readSession: () => blocked,
        cancellationCoordinator: _newCancellationCoordinator(),
      );
      addTearDown(blockedController.dispose);
      await blockedController.refresh();
      expect(blockedController.state.phase, RiderSearchPhase.unresolved);
      expect(repository.readCount, 1);
    });

    test('invalid booking IDs never reach the repository', () async {
      final repository = FakeRiderBookingSearchRepository(
        authenticatedRiderId: riderIdFixture,
      );
      final session = SessionState.fromUser(_rider);
      final controller = RiderSearchController(
        bookingRequestId: 'booking-1',
        repository: repository,
        readSession: () => session,
        cancellationCoordinator: _newCancellationCoordinator(),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.state.phase, RiderSearchPhase.unresolved);
      expect(repository.readCount, 0);
      expect(controller.canRetry, isFalse);
    });
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
