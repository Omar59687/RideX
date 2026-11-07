import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_assigned_trip.dart';
import 'package:ridex/core/models/rider_trip_lifecycle_state.dart';
import 'package:ridex/core/models/rider_trip_tracking_event.dart';
import 'package:ridex/core/providers/rider_trip_tracking_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/rider_trip_tracking_repository.dart';
import 'package:ridex/core/services/rider_trip_lifecycle_signals.dart';

import 'helpers/fake_rider_trip_tracking_repository.dart';
import 'helpers/fake_rider_trip_lifecycle_signals.dart';

const _otherRiderId = unrelatedRiderIdFixture;
final _verifiedAt = DateTime.utc(2026, 11, 6, 12);

void main() {
  group('RiderTripLifecycleController canonical authority', () {
    test(
      'initial read verifies canonical data without a watch snapshot',
      () async {
        final repository = FakeRiderTripTrackingRepository(
          trip: riderAssignedTripFixture(),
          clock: () => _verifiedAt,
        );
        final rig = _LifecycleRig(repository);
        await _settle();

        final state = rig.state;
        expect(state.phase, RiderTripLifecyclePhase.verified);
        expect(state.trip, riderAssignedTripFixture());
        expect(state.canonicalTripVersion, 3);
        expect(state.verifiedAt, _verifiedAt);
        expect(state.latestEventSequence, isNull);
        expect(repository.tripLoadCount, 1);
        expect(repository.watchCount, 1);

        await rig.dispose();
        await repository.close();
      },
    );

    test('duplicate status events are idempotent and do not reread', () async {
      final next = _trip(
        version: 4,
        status: DriverTripLifecycleStatus.driverArriving,
      );
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );
      final rig = _LifecycleRig(repository);
      await _settle();
      repository.trip = next;

      repository.emitStatus(
        tripVersion: 4,
        eventSequence: 1,
        status: DriverTripLifecycleStatus.driverArriving,
      );
      await _settle();
      expect(rig.state.phase, RiderTripLifecyclePhase.verified);
      expect(rig.state.trip, next);
      expect(rig.state.latestEventSequence, 1);
      expect(repository.tripLoadCount, 2);

      repository.emitStatus(
        tripVersion: 4,
        eventSequence: 1,
        status: DriverTripLifecycleStatus.driverArriving,
      );
      await _settle();
      expect(rig.state.trip, next);
      expect(repository.tripLoadCount, 2);

      await rig.dispose();
      await repository.close();
    });

    test('out-of-order status events cannot regress canonical state', () async {
      final latest = _trip(
        version: 7,
        status: DriverTripLifecycleStatus.inProgress,
      );
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );
      final rig = _LifecycleRig(repository);
      await _settle();
      repository.trip = latest;

      repository.emitStatus(
        tripVersion: 7,
        eventSequence: 2,
        status: DriverTripLifecycleStatus.inProgress,
      );
      await _settle();
      expect(rig.state.trip, latest);
      expect(rig.state.canonicalTripVersion, 7);

      repository.emitStatus(
        tripVersion: 5,
        eventSequence: 1,
        status: DriverTripLifecycleStatus.driverArrived,
      );
      await _settle();
      expect(rig.state.phase, RiderTripLifecyclePhase.verified);
      expect(rig.state.trip, latest);
      expect(rig.state.latestEventSequence, 2);
      expect(repository.tripLoadCount, 2);

      await rig.dispose();
      await repository.close();
    });

    test(
        'stale canonical reads hide prior details and keep a private version barrier',
        () async {
      final latest = _trip(
        version: 7,
        status: DriverTripLifecycleStatus.inProgress,
      );
      final repository = FakeRiderTripTrackingRepository(trip: latest);
      final rig = _LifecycleRig(repository);
      await _settle();
      repository.trip = _trip(
        version: 4,
        status: DriverTripLifecycleStatus.driverArriving,
      );

      await rig.controller.reconcileAfterResume();

      expect(rig.state.phase, RiderTripLifecyclePhase.stale);
      expect(rig.state.failure, RiderTripLifecycleFailure.staleCanonicalRead);
      expect(rig.state.trip, isNull);
      expect(rig.state.canonicalTripVersion, isNull);
      expect(rig.state.isVerified, isFalse);

      repository.trip = _trip(
        version: 6,
        status: DriverTripLifecycleStatus.driverArriving,
      );
      await rig.controller.reconcileAfterResume();
      expect(rig.state.phase, RiderTripLifecyclePhase.stale);
      expect(rig.state.failure, RiderTripLifecycleFailure.staleCanonicalRead);
      expect(rig.state.trip, isNull);

      final recovered = _trip(
        version: 8,
        status: DriverTripLifecycleStatus.completed,
      );
      repository.trip = recovered;
      await rig.controller.reconcileAfterReconnect();
      expect(rig.state.phase, RiderTripLifecyclePhase.terminal);
      expect(rig.state.trip, recovered);

      await rig.dispose();
      await repository.close();
    });

    test(
      'equal-version conflicting canonical status is never verified',
      () async {
        final current = _trip(
          version: 5,
          status: DriverTripLifecycleStatus.inProgress,
        );
        final repository = FakeRiderTripTrackingRepository(trip: current);
        final rig = _LifecycleRig(repository);
        await _settle();
        repository.trip = _trip(
          version: 5,
          status: DriverTripLifecycleStatus.driverArrived,
        );

        await rig.controller.reconcileAfterResume();

        expect(rig.state.phase, RiderTripLifecyclePhase.stale);
        expect(
          rig.state.failure,
          RiderTripLifecycleFailure.conflictingCanonicalVersion,
        );
        expect(rig.state.trip, isNull);
        expect(rig.state.isVerified, isFalse);

        final recovered = _trip(
          version: 6,
          status: DriverTripLifecycleStatus.completed,
        );
        repository.trip = recovered;
        await rig.controller.reconcileAfterReconnect();
        expect(rig.state.phase, RiderTripLifecyclePhase.terminal);
        expect(rig.state.trip, recovered);

        await rig.dispose();
        await repository.close();
      },
    );

    test(
      'higher-version canonical read may skip intermediate statuses',
      () async {
        final latest = _trip(
          version: 7,
          status: DriverTripLifecycleStatus.inProgress,
        );
        final repository = FakeRiderTripTrackingRepository(
          trip: riderAssignedTripFixture(),
        );
        final rig = _LifecycleRig(repository);
        await _settle();
        repository.trip = latest;

        repository.emitStatus(
          tripVersion: 7,
          eventSequence: 4,
          status: DriverTripLifecycleStatus.inProgress,
        );
        await _settle();

        expect(rig.state.phase, RiderTripLifecyclePhase.verified);
        expect(rig.state.trip, latest);
        expect(rig.state.canonicalTripVersion, 7);

        await rig.dispose();
        await repository.close();
      },
    );

    test(
      'disconnect and failed refresh hide Trip data until a valid reread',
      () async {
        final initial = riderAssignedTripFixture();
        final repository = FakeRiderTripTrackingRepository(trip: initial);
        final rig = _LifecycleRig(repository);
        await _settle();

        repository.emitDisconnected(reason: 'network');
        await _settle();
        expect(rig.state.phase, RiderTripLifecyclePhase.stale);
        expect(rig.state.failure, RiderTripLifecycleFailure.disconnected);
        expect(rig.state.trip, isNull);
        expect(rig.state.isVerified, isFalse);

        repository.tripLoadError = StateError('private transport detail');
        await rig.controller.reconcileAfterReconnect();
        expect(rig.state.phase, RiderTripLifecyclePhase.stale);
        expect(rig.state.failure, RiderTripLifecycleFailure.readFailed);
        expect(rig.state.trip, isNull);
        expect(
          rig.state.toString(),
          isNot(contains('private transport detail')),
        );

        final recovered = _trip(
          version: 4,
          status: DriverTripLifecycleStatus.driverArriving,
        );
        repository.tripLoadError = null;
        repository.trip = recovered;
        await rig.controller.reconcileAfterReconnect();
        expect(rig.state.phase, RiderTripLifecyclePhase.verified);
        expect(rig.state.trip, recovered);

        await rig.dispose();
        await repository.close();
      },
    );

    test(
      'repeated concurrent refresh requests coalesce with one trailing read',
      () async {
        final repository = _DelayedTripRepository();
        final rig = _LifecycleRig(repository);
        await _settle();
        expect(repository.pendingReads, hasLength(1));

        final first = rig.controller.reconcileAfterReconnect();
        final second = rig.controller.reconcileAfterResume();
        expect(repository.pendingReads, hasLength(1));

        repository.completeRead(0, riderAssignedTripFixture(version: 4));
        await _settle();
        expect(repository.pendingReads, hasLength(2));
        repository.completeRead(1, riderAssignedTripFixture(version: 5));
        await Future.wait([first, second]);

        expect(rig.state.phase, RiderTripLifecyclePhase.verified);
        expect(rig.state.canonicalTripVersion, 5);
        expect(repository.requestedTripIds, [
          riderTripIdFixture,
          riderTripIdFixture,
        ]);

        await rig.dispose();
      },
    );

    test(
      'reconnect supersedes a read started before the reconnect signal',
      () async {
        final initial = riderAssignedTripFixture();
        final latest = _trip(
          version: 4,
          status: DriverTripLifecycleStatus.driverArriving,
        );
        final repository = _GatedTripRepository(trip: initial);
        final rig = _LifecycleRig(repository);
        await _settle();
        expect(rig.state.phase, RiderTripLifecyclePhase.verified);

        repository.delayReads = true;
        final resumeRead = rig.controller.reconcileAfterResume();
        await _settle();
        expect(repository.pendingReads, hasLength(1));

        repository.trip = latest;
        final reconnectRead = rig.controller.reconcileAfterReconnect();
        await _settle();
        expect(rig.state.phase, RiderTripLifecyclePhase.stale);

        repository.completeRead(0, initial);
        await _settle();
        expect(repository.pendingReads, hasLength(2));
        expect(rig.state.phase, RiderTripLifecyclePhase.stale);
        expect(rig.state.trip, isNull);

        repository.completeRead(1, latest);
        await Future.wait([resumeRead, reconnectRead]);
        expect(rig.state.phase, RiderTripLifecyclePhase.verified);
        expect(rig.state.trip, latest);

        await rig.dispose();
        await repository.close();
      },
    );

    test(
      'logout during an in-flight read clears and suppresses its result',
      () async {
        final repository = _DelayedTripRepository();
        final rig = _LifecycleRig(repository);
        await _settle();
        expect(repository.pendingReads, hasLength(1));

        rig.sessionController.setSession(const SessionState.unauthenticated());
        expect(rig.state.phase, RiderTripLifecyclePhase.unavailable);
        expect(rig.state.trip, isNull);
        repository.completeRead(0, riderAssignedTripFixture(version: 9));
        await _settle();

        expect(rig.state.phase, RiderTripLifecyclePhase.unavailable);
        expect(
          rig.state.failure,
          RiderTripLifecycleFailure.authorizationUnavailable,
        );
        expect(rig.state.trip, isNull);

        await rig.dispose();
      },
    );

    test('only an active, unblocked canonical Rider session may read',
        () async {
      final rejectedSessions = [
        const SessionState.unauthenticated(),
        SessionState.fromUser(
          const AppUser(
            id: riderIdFixture,
            name: 'Blocked Rider',
            email: 'blocked@example.invalid',
            role: RideRole.rider,
            isBlocked: true,
          ),
        ),
        SessionState.fromUser(
          const AppUser(
            id: riderIdFixture,
            name: 'Driver',
            email: 'driver@example.invalid',
            role: RideRole.driver,
          ),
        ),
        SessionState.fromUser(
          const AppUser(
            id: 'mock-rider',
            name: 'Mock Rider',
            email: 'mock@example.invalid',
            role: RideRole.rider,
          ),
        ),
      ];

      for (final session in rejectedSessions) {
        final repository = FakeRiderTripTrackingRepository(
          trip: riderAssignedTripFixture(),
        );
        final rig = _LifecycleRig(repository, session: session);
        await _settle();
        expect(rig.state.phase, RiderTripLifecyclePhase.unavailable);
        expect(
          rig.state.failure,
          RiderTripLifecycleFailure.authorizationUnavailable,
        );
        expect(repository.tripLoadCount, 0);
        expect(repository.watchCount, 0);
        await rig.dispose();
        await repository.close();
      }
    });

    test(
      'A to B to A invalidates each generation and only latest read publishes',
      () async {
        final repository = _DelayedTripRepository();
        final rig = _LifecycleRig(repository);
        await _settle();
        expect(repository.pendingReads, hasLength(1));

        rig.sessionController.setSession(_sessionFor(_otherRiderId));
        await _settle();
        expect(repository.pendingReads, hasLength(2));
        rig.sessionController.setSession(_sessionFor(riderIdFixture));
        await _settle();
        expect(repository.pendingReads, hasLength(3));

        repository.completeRead(
          0,
          riderAssignedTripFixture(
            version: 11,
            status: DriverTripLifecycleStatus.inProgress,
          ),
        );
        repository.completeRead(
          1,
          riderAssignedTripFixture(riderId: _otherRiderId, version: 8),
        );
        await _settle();
        expect(rig.state.phase, RiderTripLifecyclePhase.loading);
        expect(rig.state.trip, isNull);

        repository.completeRead(2, riderAssignedTripFixture(version: 3));
        await _settle();
        expect(rig.state.phase, RiderTripLifecyclePhase.verified);
        expect(rig.state.trip?.riderId, riderIdFixture);
        expect(rig.state.canonicalTripVersion, 3);

        await rig.dispose();
      },
    );

    test('A to B to A clears private canonical version history', () async {
      final repository = _DelayedTripRepository();
      final rig = _LifecycleRig(repository);
      await _settle();
      repository.completeRead(
        0,
        riderAssignedTripFixture(
          version: 11,
          status: DriverTripLifecycleStatus.inProgress,
        ),
      );
      await _settle();
      expect(rig.state.phase, RiderTripLifecyclePhase.verified);

      rig.sessionController.setSession(_sessionFor(_otherRiderId));
      await _settle();
      repository.completeRead(
        1,
        riderAssignedTripFixture(
          riderId: _otherRiderId,
          version: 8,
          status: DriverTripLifecycleStatus.accepted,
        ),
      );
      await _settle();
      expect(rig.state.trip?.riderId, _otherRiderId);

      rig.sessionController.setSession(_sessionFor(riderIdFixture));
      await _settle();
      repository.completeRead(2, riderAssignedTripFixture(version: 3));
      await _settle();

      expect(rig.state.phase, RiderTripLifecyclePhase.verified);
      expect(rig.state.trip?.riderId, riderIdFixture);
      expect(rig.state.canonicalTripVersion, 3);

      await rig.dispose();
    });

    test('logout clears private canonical version history', () async {
      final repository = _DelayedTripRepository();
      final rig = _LifecycleRig(repository);
      await _settle();
      repository.completeRead(
        0,
        riderAssignedTripFixture(
          version: 11,
          status: DriverTripLifecycleStatus.inProgress,
        ),
      );
      await _settle();
      expect(rig.state.phase, RiderTripLifecyclePhase.verified);

      rig.sessionController.setSession(const SessionState.unauthenticated());
      expect(rig.state.trip, isNull);
      rig.sessionController.setSession(_sessionFor(riderIdFixture));
      await _settle();
      repository.completeRead(1, riderAssignedTripFixture(version: 3));
      await _settle();

      expect(rig.state.phase, RiderTripLifecyclePhase.verified);
      expect(rig.state.canonicalTripVersion, 3);
      await rig.dispose();
    });

    test('repository replacement clears private canonical version history',
        () async {
      final firstRepository = FakeRiderTripTrackingRepository(
        trip: _trip(
          version: 11,
          status: DriverTripLifecycleStatus.inProgress,
        ),
      );
      final secondTrip = riderAssignedTripFixture(version: 3);
      final secondRepository = FakeRiderTripTrackingRepository(
        trip: secondTrip,
      );
      final repositorySource = StateProvider<RiderTripTrackingRepository?>(
        (ref) => firstRepository,
      );
      final container = ProviderContainer(
        overrides: [
          riderTripTrackingRepositoryProvider.overrideWith(
            (ref) => ref.watch(repositorySource),
          ),
          riderTripAppLifecycleSignalSourceProvider.overrideWithValue(
            const NoopRiderTripAppLifecycleSignalSource(),
          ),
          riderTripConnectionSignalSourceProvider.overrideWithValue(
            const NoopRiderTripConnectionSignalSource(),
          ),
          sessionControllerProvider.overrideWith(
            () => _MutableSessionController(_sessionFor(riderIdFixture)),
          ),
          riderTripLifecycleClockProvider.overrideWithValue(() => _verifiedAt),
        ],
      );
      final subscription = container.listen(
        riderTripLifecycleControllerProvider(_request()),
        (_, __) {},
      );
      container.read(riderTripLifecycleControllerProvider(_request()));
      await _settle();
      expect(
        container
            .read(riderTripLifecycleControllerProvider(_request()))
            .canonicalTripVersion,
        11,
      );

      container.read(repositorySource.notifier).state = secondRepository;
      await _settle();
      final nextState =
          container.read(riderTripLifecycleControllerProvider(_request()));
      expect(nextState.phase, RiderTripLifecyclePhase.verified);
      expect(nextState.trip, secondTrip);
      expect(nextState.canonicalTripVersion, 3);
      expect(firstRepository.hasListener, isFalse);

      subscription.close();
      container.dispose();
      await _settle();
      await firstRepository.close();
      await secondRepository.close();
    });

    test('Trip replacement retires the old pending result', () async {
      final repository = _DelayedTripRepository();
      final firstRequest = _request();
      final container = _container(repository);
      final firstStates = <RiderTripLifecycleState>[];
      final firstSubscription = container.listen(
        riderTripLifecycleControllerProvider(firstRequest),
        (_, next) => firstStates.add(next),
      );
      container.read(riderTripLifecycleControllerProvider(firstRequest));
      await _settle();
      expect(repository.pendingReads, hasLength(1));
      final firstStateCount = firstStates.length;

      firstSubscription.close();
      await _settle();
      final secondRequest = _request(
        tripId: secondaryRiderTripIdFixture,
        bookingRequestId: secondaryRiderBookingIdFixture,
      );
      final secondStates = <RiderTripLifecycleState>[];
      final secondSubscription = container.listen(
        riderTripLifecycleControllerProvider(secondRequest),
        (_, next) => secondStates.add(next),
      );
      container.read(riderTripLifecycleControllerProvider(secondRequest));
      await _settle();
      expect(repository.pendingReads, hasLength(2));

      repository.completeRead(
        0,
        riderAssignedTripFixture(
          version: 10,
          status: DriverTripLifecycleStatus.inProgress,
        ),
      );
      await _settle();
      expect(firstStates, hasLength(firstStateCount));
      expect(
        secondStates.any((state) => state.trip?.tripId == riderTripIdFixture),
        isFalse,
      );

      repository.completeRead(
        1,
        riderAssignedTripFixture(
          tripId: secondaryRiderTripIdFixture,
          bookingRequestId: secondaryRiderBookingIdFixture,
        ),
      );
      await _settle();
      final secondState = container.read(
        riderTripLifecycleControllerProvider(secondRequest),
      );
      expect(secondState.phase, RiderTripLifecyclePhase.verified);
      expect(secondState.trip?.tripId, secondaryRiderTripIdFixture);

      secondSubscription.close();
      container.dispose();
      await _settle();
    });

    test('Trip replacement does not inherit the previous version barrier',
        () async {
      final repository = _DelayedTripRepository();
      final container = _container(repository);
      final firstRequest = _request();
      final firstSubscription = container.listen(
        riderTripLifecycleControllerProvider(firstRequest),
        (_, __) {},
      );
      container.read(riderTripLifecycleControllerProvider(firstRequest));
      await _settle();
      repository.completeRead(
        0,
        riderAssignedTripFixture(
          version: 11,
          status: DriverTripLifecycleStatus.inProgress,
        ),
      );
      await _settle();
      expect(
        container
            .read(riderTripLifecycleControllerProvider(firstRequest))
            .phase,
        RiderTripLifecyclePhase.verified,
      );

      firstSubscription.close();
      await _settle();
      final secondRequest = _request(
        tripId: secondaryRiderTripIdFixture,
        bookingRequestId: secondaryRiderBookingIdFixture,
      );
      final secondSubscription = container.listen(
        riderTripLifecycleControllerProvider(secondRequest),
        (_, __) {},
      );
      container.read(riderTripLifecycleControllerProvider(secondRequest));
      await _settle();
      repository.completeRead(
        1,
        riderAssignedTripFixture(
          tripId: secondaryRiderTripIdFixture,
          bookingRequestId: secondaryRiderBookingIdFixture,
          version: 3,
        ),
      );
      await _settle();

      final secondState = container.read(
        riderTripLifecycleControllerProvider(secondRequest),
      );
      expect(secondState.phase, RiderTripLifecyclePhase.verified);
      expect(secondState.trip?.tripId, secondaryRiderTripIdFixture);
      expect(secondState.canonicalTripVersion, 3);

      secondSubscription.close();
      container.dispose();
      await _settle();
      await repository.close();
    });

    test('disposed controller does not retain private Trip version history',
        () async {
      final repository = FakeRiderTripTrackingRepository(
        trip: _trip(
          version: 11,
          status: DriverTripLifecycleStatus.inProgress,
        ),
      );
      final container = _container(repository);
      final request = _request();
      final firstSubscription = container.listen(
        riderTripLifecycleControllerProvider(request),
        (_, __) {},
      );
      container.read(riderTripLifecycleControllerProvider(request));
      await _settle();
      expect(
        container
            .read(riderTripLifecycleControllerProvider(request))
            .canonicalTripVersion,
        11,
      );

      firstSubscription.close();
      await _settle();
      repository.trip = _trip(version: 3);
      final secondSubscription = container.listen(
        riderTripLifecycleControllerProvider(request),
        (_, __) {},
      );
      container.read(riderTripLifecycleControllerProvider(request));
      await _settle();

      final state =
          container.read(riderTripLifecycleControllerProvider(request));
      expect(state.phase, RiderTripLifecyclePhase.verified);
      expect(state.canonicalTripVersion, 3);

      secondSubscription.close();
      container.dispose();
      await _settle();
      await repository.close();
    });

    test(
      'late event from a replaced subscription cannot affect new generation',
      () async {
        final repository = _LateEventRepository(
          trip: riderAssignedTripFixture(),
        );
        final rig = _LifecycleRig(repository);
        await _settle();
        expect(repository.watchStreams, hasLength(1));

        rig.sessionController.setSession(_sessionFor(_otherRiderId));
        await _settle();
        rig.sessionController.setSession(_sessionFor(riderIdFixture));
        await _settle();
        expect(repository.watchStreams, hasLength(3));
        expect(rig.state.phase, RiderTripLifecyclePhase.verified);
        final readsBeforeLateEvent = repository.tripLoadCount;

        repository.watchStreams.first.emitLate(
          RiderTripSnapshot(
            riderAssignedTripFixture(
              version: 99,
              status: DriverTripLifecycleStatus.inProgress,
            ),
          ),
        );
        await _settle();

        expect(repository.tripLoadCount, readsBeforeLateEvent);
        expect(rig.state.phase, RiderTripLifecyclePhase.verified);
        expect(rig.state.canonicalTripVersion, 3);

        await rig.dispose();
      },
    );

    test(
      'all canonical terminal statuses are verified terminal outcomes',
      () async {
        for (final status in [
          DriverTripLifecycleStatus.completed,
          DriverTripLifecycleStatus.cancelledByRider,
          DriverTripLifecycleStatus.cancelledByDriver,
          DriverTripLifecycleStatus.cancelledByAdmin,
          DriverTripLifecycleStatus.failed,
        ]) {
          final repository = FakeRiderTripTrackingRepository(
            trip: _trip(version: 4, status: status),
          );
          final rig = _LifecycleRig(repository);
          await _settle();

          expect(rig.state.phase, RiderTripLifecyclePhase.terminal);
          expect(rig.state.isVerified, isTrue);
          expect(rig.state.isTerminal, isTrue);
          expect(rig.state.trip?.status, status);
          expect(repository.hasListener, isFalse);

          await rig.dispose();
          await repository.close();
        }
      },
    );

    test(
      'terminal canonical Trip cannot regress to a nonterminal status',
      () async {
        final completed = _trip(
          version: 5,
          status: DriverTripLifecycleStatus.completed,
        );
        final repository = FakeRiderTripTrackingRepository(trip: completed);
        final rig = _LifecycleRig(repository);
        await _settle();
        repository.trip = _trip(
          version: 6,
          status: DriverTripLifecycleStatus.inProgress,
        );

        await rig.controller.reconcileAfterResume();

        expect(rig.state.phase, RiderTripLifecyclePhase.stale);
        expect(
          rig.state.failure,
          RiderTripLifecycleFailure.invalidStatusTransition,
        );
        expect(rig.state.trip, isNull);

        repository.trip = completed;
        await rig.controller.reconcileAfterReconnect();
        expect(rig.state.phase, RiderTripLifecyclePhase.terminal);
        expect(rig.state.trip, completed);
        expect(repository.watchCount, 1);

        await rig.dispose();
        await repository.close();
      },
    );

    test(
      'missing and foreign Trips are indistinguishable and unavailable',
      () async {
        final missingRepository = FakeRiderTripTrackingRepository();
        final missingRig = _LifecycleRig(missingRepository);
        await _settle();
        expect(missingRig.state.phase, RiderTripLifecyclePhase.unavailable);
        expect(
          missingRig.state.failure,
          RiderTripLifecycleFailure.tripUnavailable,
        );
        expect(missingRig.state.trip, isNull);
        await missingRig.dispose();
        await missingRepository.close();

        final foreignRepository = FakeRiderTripTrackingRepository(
          trip: riderAssignedTripFixture(),
          authenticatedRiderId: _otherRiderId,
        );
        final foreignRig = _LifecycleRig(foreignRepository);
        await _settle();
        expect(foreignRig.state.phase, RiderTripLifecyclePhase.unavailable);
        expect(
          foreignRig.state.failure,
          RiderTripLifecycleFailure.tripUnavailable,
        );
        expect(foreignRig.state.trip, isNull);
        await foreignRig.dispose();
        await foreignRepository.close();
      },
    );

    test(
      'Card and malformed canonical identity/version responses fail closed',
      () async {
        final valid = riderAssignedTripFixture();
        final invalidResponses = [
          _ForgedAssignedTrip(
            valid,
            paymentMethodOverride: PaymentMethod.card,
          ),
          _ForgedAssignedTrip(
            valid,
            tripIdOverride: secondaryRiderTripIdFixture,
          ),
          _ForgedAssignedTrip(
            valid,
            bookingRequestIdOverride: secondaryRiderBookingIdFixture,
          ),
          _ForgedAssignedTrip(valid, riderIdOverride: _otherRiderId),
          _ForgedAssignedTrip(valid, versionOverride: 0),
        ];

        for (final invalid in invalidResponses) {
          final repository = _ResponseTripRepository(
            response: invalid,
            trip: valid,
          );
          final rig = _LifecycleRig(repository);
          await _settle();
          expect(rig.state.phase, RiderTripLifecyclePhase.unavailable);
          expect(
            rig.state.failure,
            RiderTripLifecycleFailure.invalidCanonicalData,
          );
          expect(rig.state.trip, isNull);
          await rig.dispose();
          await repository.close();
        }
      },
    );

    test(
      'disposal with pending asynchronous read suppresses publication',
      () async {
        final repository = _DelayedTripRepository();
        final rig = _LifecycleRig(repository);
        await _settle();
        expect(repository.pendingReads, hasLength(1));
        final priorNotifications = rig.notifications.length;

        await rig.dispose();
        repository.completeRead(0, riderAssignedTripFixture(version: 9));
        await _settle();

        expect(rig.notifications, hasLength(priorNotifications));
      },
    );

    test('resume edge reconciles once and keeps pending data private',
        () async {
      final initial = riderAssignedTripFixture();
      final next = _trip(
        version: 4,
        status: DriverTripLifecycleStatus.driverArriving,
      );
      final repository = _GatedTripRepository(trip: initial);
      final signals = FakeRiderTripLifecycleSignals();
      final rig = _LifecycleRig(repository, signals: signals);
      await _settle();
      expect(rig.state.trip, initial);
      expect(repository.tripLoadCount, 1);

      repository.delayReads = true;
      repository.trip = next;
      signals.background();
      signals.resume();
      expect(rig.state.phase, RiderTripLifecyclePhase.stale);
      expect(rig.state.trip, isNull);
      await _settle();
      expect(repository.pendingReads, hasLength(1));

      // The source only emits on a real non-resumed -> resumed edge.
      signals.resume();
      await _settle();
      expect(repository.pendingReads, hasLength(1));

      repository.completeRead(0, next);
      await _settle();
      expect(rig.state.phase, RiderTripLifecyclePhase.verified);
      expect(rig.state.trip, next);
      expect(repository.tripLoadCount, 2);
      expect(repository.watchCount, 2);

      await rig.dispose();
    });

    test(
      'only confirmed current-generation restoration reconciles',
      () async {
        final initial = riderAssignedTripFixture();
        final next = _trip(
          version: 4,
          status: DriverTripLifecycleStatus.driverArriving,
        );
        final repository = _GatedTripRepository(trip: initial);
        final signals = FakeRiderTripLifecycleSignals();
        final rig = _LifecycleRig(repository, signals: signals);
        await _settle();

        repository.delayReads = true;
        repository.trip = next;
        signals.connectivityAvailable();
        signals.connecting(1);
        await _settle();
        expect(repository.tripLoadCount, 1);
        expect(rig.state.trip, initial);

        signals.interrupted(1);
        expect(rig.state.phase, RiderTripLifecyclePhase.stale);
        expect(rig.state.trip, isNull);
        signals.connectivityAvailable();
        signals.connecting(2);
        signals.confirmedRestoration(1); // Old attempt.
        await _settle();
        expect(repository.tripLoadCount, 1);
        expect(repository.pendingReads, isEmpty);

        signals.confirmedRestoration(2);
        await _settle();
        expect(repository.pendingReads, hasLength(1));
        repository.completeRead(0, next);
        await _settle();
        expect(rig.state.trip, next);
        expect(repository.tripLoadCount, 2);

        // A duplicate restoration and an old interruption cannot cause a read
        // or stale the newly verified state.
        signals.confirmedRestoration(2);
        signals.interrupted(1);
        signals.connectivityAvailable();
        await _settle();
        expect(repository.tripLoadCount, 2);
        expect(rig.state.phase, RiderTripLifecyclePhase.verified);
        expect(rig.state.trip, next);

        await rig.dispose();
      },
    );

    test(
      'duplicate prior restore cannot consume a newer interruption',
      () async {
        final initial = riderAssignedTripFixture();
        final recovered = _trip(
          version: 4,
          status: DriverTripLifecycleStatus.driverArriving,
        );
        final nextRecovery = _trip(
          version: 5,
          status: DriverTripLifecycleStatus.driverArrived,
        );
        final repository = _GatedTripRepository(trip: initial);
        final signals = FakeRiderTripLifecycleSignals();
        final rig = _LifecycleRig(repository, signals: signals);
        await _settle();
        expect(rig.state.trip, initial);

        repository.delayReads = true;
        repository.trip = recovered;
        signals.confirmedRestoration(1);
        await _settle();
        expect(repository.tripLoadCount, 1);
        expect(rig.state.trip, initial);

        signals.interrupted(1);
        expect(rig.state.phase, RiderTripLifecyclePhase.stale);
        expect(rig.state.trip, isNull);
        signals.confirmedRestoration(1);
        await _settle();
        expect(repository.tripLoadCount, 1);
        expect(repository.pendingReads, isEmpty);
        expect(rig.state.phase, RiderTripLifecyclePhase.stale);
        expect(rig.state.trip, isNull);

        signals.connecting(2);
        signals.confirmedRestoration(2);
        await _settle();
        expect(repository.tripLoadCount, 2);
        expect(repository.pendingReads, hasLength(1));
        expect(rig.state.phase, RiderTripLifecyclePhase.stale);
        expect(rig.state.trip, isNull);

        repository.completeRead(0, recovered);
        await _settle();
        expect(rig.state.phase, RiderTripLifecyclePhase.verified);
        expect(rig.state.trip, recovered);
        signals.confirmedRestoration(2);
        await _settle();
        expect(repository.tripLoadCount, 2);

        // A restored status in the interrupted attempt itself is not a new
        // transport attempt, even if no earlier restoration used generation 3.
        repository.trip = nextRecovery;
        signals.connecting(3);
        signals.interrupted(3);
        signals.confirmedRestoration(3);
        await _settle();
        expect(repository.tripLoadCount, 2);
        expect(rig.state.phase, RiderTripLifecyclePhase.stale);
        expect(rig.state.trip, isNull);

        signals.connecting(4);
        signals.confirmedRestoration(4);
        await _settle();
        expect(repository.tripLoadCount, 3);
        expect(repository.pendingReads, hasLength(2));
        expect(rig.state.phase, RiderTripLifecyclePhase.stale);
        expect(rig.state.trip, isNull);
        repository.completeRead(1, nextRecovery);
        await _settle();
        expect(rig.state.phase, RiderTripLifecyclePhase.verified);
        expect(rig.state.trip, nextRecovery);
        signals.confirmedRestoration(4);
        await _settle();
        expect(repository.tripLoadCount, 3);

        await rig.dispose();
      },
    );

    test(
      'resume and restoration coalesce and supersede the older read',
      () async {
        final initial = riderAssignedTripFixture();
        final latest = _trip(
          version: 5,
          status: DriverTripLifecycleStatus.driverArrived,
        );
        final repository = _DelayedTripRepository();
        final signals = FakeRiderTripLifecycleSignals();
        final rig = _LifecycleRig(repository, signals: signals);
        await _settle();
        repository.completeRead(0, initial);
        await _settle();
        expect(rig.state.trip, initial);

        signals.background();
        signals.resume();
        await _settle();
        expect(repository.pendingReads, hasLength(2));
        signals.interrupted(1);
        signals.connecting(2);
        signals.confirmedRestoration(2);
        await _settle();
        expect(rig.state.trip, isNull);

        repository.completeRead(1, initial);
        await _settle();
        expect(repository.pendingReads, hasLength(3));
        expect(rig.state.trip, isNull);
        repository.completeRead(2, latest);
        await _settle();

        expect(repository.tripLoadCount, 3);
        expect(rig.state.phase, RiderTripLifecyclePhase.verified);
        expect(rig.state.trip, latest);
        expect(repository.watchCount, 3);
        expect(repository.hasListener, isTrue);
        await rig.dispose();
      },
    );

    test('A to B to A rejects late lifecycle and connection callbacks',
        () async {
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );
      final signals = FakeRiderTripLifecycleSignals();
      final rig = _LifecycleRig(repository, signals: signals);
      await _settle();
      expect(rig.state.trip, riderAssignedTripFixture());

      rig.sessionController.setSession(_sessionFor(_otherRiderId));
      await _settle();
      rig.sessionController.setSession(_sessionFor(riderIdFixture));
      await _settle();
      expect(rig.state.trip, riderAssignedTripFixture());
      final readsBeforeLateSignals = repository.tripLoadCount;

      signals.emitLateResumeSignal();
      signals.emitLateConnectionSignal(
        RiderTripConnectionStatusChanged(
          status: RiderTripConnectionStatus.interrupted,
          generation: 1,
        ),
      );
      await _settle();

      expect(repository.tripLoadCount, readsBeforeLateSignals);
      expect(rig.state.phase, RiderTripLifecyclePhase.verified);
      expect(rig.state.trip?.riderId, riderIdFixture);

      rig.sessionController.setSession(const SessionState.unauthenticated());
      await _settle();
      final readsAfterLogout = repository.tripLoadCount;
      signals.emitLateResumeSignal();
      signals.emitLateConnectionSignal(
        RiderTripConnectionStatusChanged(
          status: RiderTripConnectionStatus.restored,
          generation: 2,
        ),
      );
      await _settle();
      expect(repository.tripLoadCount, readsAfterLogout);
      expect(rig.state.phase, RiderTripLifecyclePhase.unavailable);
      expect(rig.state.trip, isNull);
      await rig.dispose();
    });

    test('repository replacement retires its old signal callbacks', () async {
      final firstRepository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(
          version: 5,
          status: DriverTripLifecycleStatus.inProgress,
        ),
      );
      final secondTrip = riderAssignedTripFixture(version: 3);
      final secondRepository = FakeRiderTripTrackingRepository(
        trip: secondTrip,
      );
      final signals = FakeRiderTripLifecycleSignals();
      final repositorySource = StateProvider<RiderTripTrackingRepository?>(
        (ref) => firstRepository,
      );
      final container = ProviderContainer(
        overrides: [
          riderTripTrackingRepositoryProvider.overrideWith(
            (ref) => ref.watch(repositorySource),
          ),
          riderTripAppLifecycleSignalSourceProvider.overrideWithValue(signals),
          riderTripConnectionSignalSourceProvider.overrideWithValue(signals),
          sessionControllerProvider.overrideWith(
            () => _MutableSessionController(_sessionFor(riderIdFixture)),
          ),
          riderTripLifecycleClockProvider.overrideWithValue(() => _verifiedAt),
        ],
      );
      final request = _request();
      final subscription = container.listen(
        riderTripLifecycleControllerProvider(request),
        (_, __) {},
      );
      container.read(riderTripLifecycleControllerProvider(request));
      await _settle();
      expect(
        container.read(riderTripLifecycleControllerProvider(request)).trip,
        firstRepository.trip,
      );

      container.read(repositorySource.notifier).state = secondRepository;
      await _settle();
      expect(
        container.read(riderTripLifecycleControllerProvider(request)).trip,
        secondTrip,
      );
      final readsAfterReplacement = secondRepository.tripLoadCount;

      signals.emitLateResumeSignal();
      signals.emitLateConnectionSignal(
        RiderTripConnectionStatusChanged(
          status: RiderTripConnectionStatus.interrupted,
          generation: 1,
        ),
      );
      await _settle();
      expect(secondRepository.tripLoadCount, readsAfterReplacement);
      expect(
        container.read(riderTripLifecycleControllerProvider(request)).trip,
        secondTrip,
      );

      subscription.close();
      container.dispose();
      await _settle();
      await signals.dispose();
      await firstRepository.close();
      await secondRepository.close();
    });

    test('Trip replacement and disposal reject late signal callbacks',
        () async {
      final repository = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
        additionalTrips: [
          riderAssignedTripFixture(
            tripId: secondaryRiderTripIdFixture,
            bookingRequestId: secondaryRiderBookingIdFixture,
          ),
        ],
      );
      final signals = FakeRiderTripLifecycleSignals();
      final container = ProviderContainer(
        overrides: [
          riderTripTrackingRepositoryProvider.overrideWithValue(repository),
          riderTripAppLifecycleSignalSourceProvider.overrideWithValue(signals),
          riderTripConnectionSignalSourceProvider.overrideWithValue(signals),
          sessionControllerProvider.overrideWith(
            () => _MutableSessionController(_sessionFor(riderIdFixture)),
          ),
          riderTripLifecycleClockProvider.overrideWithValue(() => _verifiedAt),
        ],
      );
      final firstRequest = _request();
      final firstSubscription = container.listen(
        riderTripLifecycleControllerProvider(firstRequest),
        (_, __) {},
      );
      container.read(riderTripLifecycleControllerProvider(firstRequest));
      await _settle();
      expect(
        container.read(riderTripLifecycleControllerProvider(firstRequest)).trip,
        isNotNull,
      );

      firstSubscription.close();
      await _settle();
      final secondRequest = _request(
        tripId: secondaryRiderTripIdFixture,
        bookingRequestId: secondaryRiderBookingIdFixture,
      );
      final secondSubscription = container.listen(
        riderTripLifecycleControllerProvider(secondRequest),
        (_, __) {},
      );
      container.read(riderTripLifecycleControllerProvider(secondRequest));
      await _settle();
      final readsForSecondTrip = repository.tripLoadCount;
      expect(
        container
            .read(riderTripLifecycleControllerProvider(secondRequest))
            .trip
            ?.tripId,
        secondaryRiderTripIdFixture,
      );

      signals.emitLateResumeSignal();
      signals.emitLateConnectionSignal(
        RiderTripConnectionStatusChanged(
          status: RiderTripConnectionStatus.interrupted,
          generation: 1,
        ),
      );
      await _settle();
      expect(repository.tripLoadCount, readsForSecondTrip);
      expect(
        container
            .read(riderTripLifecycleControllerProvider(secondRequest))
            .trip
            ?.tripId,
        secondaryRiderTripIdFixture,
      );

      secondSubscription.close();
      await _settle();
      final notificationsAfterDispose = repository.tripLoadCount;
      signals.emitLateResumeSignal();
      signals.emitLateConnectionSignal(
        RiderTripConnectionStatusChanged(
          status: RiderTripConnectionStatus.interrupted,
          generation: 2,
        ),
      );
      await _settle();
      expect(repository.tripLoadCount, notificationsAfterDispose);

      container.dispose();
      await signals.dispose();
      await repository.close();
    });

    test('terminal lifecycle signals never restart its watcher', () async {
      final terminal = _trip(
        version: 4,
        status: DriverTripLifecycleStatus.completed,
      );
      final repository = FakeRiderTripTrackingRepository(trip: terminal);
      final signals = FakeRiderTripLifecycleSignals();
      final rig = _LifecycleRig(repository, signals: signals);
      await _settle();
      expect(rig.state.isTerminal, isTrue);
      final watcherCount = repository.watchCount;
      expect(watcherCount, 1);
      expect(repository.hasListener, isFalse);

      signals.background();
      signals.resume();
      await _settle();
      signals.interrupted(1);
      signals.confirmedRestoration(2);
      await _settle();

      expect(rig.state.isTerminal, isTrue);
      expect(rig.state.trip, terminal);
      expect(repository.tripLoadCount, 3);
      expect(repository.watchCount, watcherCount);
      expect(repository.hasListener, isFalse);
      await rig.dispose();
    });
  });
}

RiderTripLifecycleRequest _request({
  String tripId = riderTripIdFixture,
  String bookingRequestId = riderBookingIdFixture,
}) =>
    RiderTripLifecycleRequest(
      tripId: tripId,
      bookingRequestId: bookingRequestId,
    );

RiderAssignedTrip _trip({
  String tripId = riderTripIdFixture,
  String bookingRequestId = riderBookingIdFixture,
  String riderId = riderIdFixture,
  int version = 3,
  DriverTripLifecycleStatus status = DriverTripLifecycleStatus.accepted,
}) =>
    riderAssignedTripFixture(
      tripId: tripId,
      bookingRequestId: bookingRequestId,
      riderId: riderId,
      version: version,
      status: status,
    );

SessionState _sessionFor(String riderId) => SessionState.fromUser(
      AppUser(
        id: riderId,
        name: 'Local Rider',
        email: 'rider@example.invalid',
        role: RideRole.rider,
      ),
    );

ProviderContainer _container(RiderTripTrackingRepository repository) {
  return ProviderContainer(
    overrides: [
      riderTripTrackingRepositoryProvider.overrideWithValue(repository),
      riderTripAppLifecycleSignalSourceProvider.overrideWithValue(
        const NoopRiderTripAppLifecycleSignalSource(),
      ),
      riderTripConnectionSignalSourceProvider.overrideWithValue(
        const NoopRiderTripConnectionSignalSource(),
      ),
      sessionControllerProvider.overrideWith(
        () => _MutableSessionController(_sessionFor(riderIdFixture)),
      ),
      riderTripLifecycleClockProvider.overrideWithValue(() => _verifiedAt),
    ],
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _LifecycleRig {
  _LifecycleRig(
    this.repository, {
    RiderTripLifecycleRequest? request,
    SessionState? session,
    this.signals,
  })  : request = request ?? _request(),
        initialSession = session ?? _sessionFor(riderIdFixture) {
    container = ProviderContainer(
      overrides: [
        riderTripTrackingRepositoryProvider.overrideWithValue(repository),
        riderTripAppLifecycleSignalSourceProvider.overrideWithValue(
          signals ?? const NoopRiderTripAppLifecycleSignalSource(),
        ),
        riderTripConnectionSignalSourceProvider.overrideWithValue(
          signals ?? const NoopRiderTripConnectionSignalSource(),
        ),
        sessionControllerProvider.overrideWith(() {
          sessionController = _MutableSessionController(
            initialSession,
          );
          return sessionController;
        }),
        riderTripLifecycleClockProvider.overrideWithValue(() => _verifiedAt),
      ],
    );
    subscription = container.listen(
      riderTripLifecycleControllerProvider(this.request),
      (_, next) => notifications.add(next),
    );
    controller = container.read(
      riderTripLifecycleControllerProvider(this.request).notifier,
    );
  }

  final RiderTripTrackingRepository repository;
  final RiderTripLifecycleRequest request;
  final SessionState initialSession;
  final FakeRiderTripLifecycleSignals? signals;
  final notifications = <RiderTripLifecycleState>[];
  late final ProviderContainer container;
  late final ProviderSubscription<RiderTripLifecycleState> subscription;
  late final RiderTripLifecycleController controller;
  late final _MutableSessionController sessionController;

  RiderTripLifecycleState get state =>
      container.read(riderTripLifecycleControllerProvider(request));

  Future<void> dispose() async {
    subscription.close();
    container.dispose();
    await _settle();
    await signals?.dispose();
  }
}

class _MutableSessionController extends SessionController {
  _MutableSessionController(this._initial);

  final SessionState _initial;

  @override
  SessionState build() => _initial;

  void setSession(SessionState next) => state = next;
}

class _DelayedTripRepository extends FakeRiderTripTrackingRepository {
  _DelayedTripRepository() : super(trip: riderAssignedTripFixture());

  final pendingReads = <Completer<RiderAssignedTrip?>>[];

  @override
  Future<RiderAssignedTrip?> findByTrip({required String tripId}) {
    tripLoadCount++;
    requestedTripIds.add(tripId);
    final pending = Completer<RiderAssignedTrip?>();
    pendingReads.add(pending);
    return pending.future;
  }

  void completeRead(int index, RiderAssignedTrip? trip) {
    pendingReads[index].complete(trip);
  }
}

class _GatedTripRepository extends FakeRiderTripTrackingRepository {
  _GatedTripRepository({required RiderAssignedTrip trip}) : super(trip: trip);

  bool delayReads = false;
  final pendingReads = <Completer<RiderAssignedTrip?>>[];

  @override
  Future<RiderAssignedTrip?> findByTrip({required String tripId}) {
    if (!delayReads) return super.findByTrip(tripId: tripId);
    tripLoadCount++;
    requestedTripIds.add(tripId);
    final pending = Completer<RiderAssignedTrip?>();
    pendingReads.add(pending);
    return pending.future;
  }

  void completeRead(int index, RiderAssignedTrip? trip) {
    pendingReads[index].complete(trip);
  }
}

class _ResponseTripRepository extends FakeRiderTripTrackingRepository {
  _ResponseTripRepository({
    required this.response,
    required RiderAssignedTrip trip,
  }) : super(trip: trip);

  final RiderAssignedTrip? response;

  @override
  Future<RiderAssignedTrip?> findByTrip({required String tripId}) async {
    tripLoadCount++;
    requestedTripIds.add(tripId);
    return response;
  }
}

class _ForgedAssignedTrip extends Equatable implements RiderAssignedTrip {
  const _ForgedAssignedTrip(
    this.source, {
    this.tripIdOverride,
    this.bookingRequestIdOverride,
    this.riderIdOverride,
    this.versionOverride,
    this.paymentMethodOverride,
  });

  final RiderAssignedTrip source;
  final String? tripIdOverride;
  final String? bookingRequestIdOverride;
  final String? riderIdOverride;
  final int? versionOverride;
  final PaymentMethod? paymentMethodOverride;

  @override
  String get tripId => tripIdOverride ?? source.tripId;

  @override
  String get bookingRequestId =>
      bookingRequestIdOverride ?? source.bookingRequestId;

  @override
  String get riderId => riderIdOverride ?? source.riderId;

  @override
  int get version => versionOverride ?? source.version;

  @override
  DriverTripLifecycleStatus get status => source.status;

  @override
  PaymentMethod get paymentMethod =>
      paymentMethodOverride ?? source.paymentMethod;

  @override
  RiderTripPlace get pickup => source.pickup;

  @override
  RiderTripPlace get destination => source.destination;

  @override
  List<RiderTripPlace> get stops => source.stops;

  @override
  int get routeDistanceMeters => source.routeDistanceMeters;

  @override
  int get routeDurationSeconds => source.routeDurationSeconds;

  @override
  String? get routeGeometryReference => source.routeGeometryReference;

  @override
  int get originalFareFils => source.originalFareFils;

  @override
  int get currentFareFils => source.currentFareFils;

  @override
  String get currency => source.currency;

  @override
  RiderDriverSummary get driver => source.driver;

  @override
  RiderVehicleSummary get vehicle => source.vehicle;

  @override
  DateTime get acceptedAt => source.acceptedAt;

  @override
  DateTime get updatedAt => source.updatedAt;

  @override
  bool get isTerminal => source.isTerminal;

  @override
  List<Object?> get props => [
        tripId,
        bookingRequestId,
        riderId,
        version,
        status,
        paymentMethod,
        pickup,
        destination,
        stops,
        routeDistanceMeters,
        routeDurationSeconds,
        routeGeometryReference,
        originalFareFils,
        currentFareFils,
        currency,
        driver,
        vehicle,
        acceptedAt,
        updatedAt,
      ];
}

class _LateEventRepository extends FakeRiderTripTrackingRepository {
  _LateEventRepository({required RiderAssignedTrip trip}) : super(trip: trip);

  final watchStreams = <_LeakyEventStream>[];

  @override
  Stream<RiderTripTrackingEvent> watch({required String tripId}) {
    watchCount++;
    watchedTripIds.add(tripId);
    final stream = _LeakyEventStream();
    watchStreams.add(stream);
    return stream;
  }
}

class _LeakyEventStream extends Stream<RiderTripTrackingEvent> {
  final _subscriptions = <_LeakyEventSubscription>[];

  void emitLate(RiderTripTrackingEvent event) {
    for (final subscription in _subscriptions) {
      subscription.emitIgnoringCancellation(event);
    }
  }

  @override
  StreamSubscription<RiderTripTrackingEvent> listen(
    void Function(RiderTripTrackingEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = _LeakyEventSubscription(
      onDataCallback: onData,
      onErrorCallback: onError,
      onDoneCallback: onDone,
    );
    _subscriptions.add(subscription);
    return subscription;
  }
}

class _LeakyEventSubscription
    implements StreamSubscription<RiderTripTrackingEvent> {
  _LeakyEventSubscription({
    required this.onDataCallback,
    required this.onErrorCallback,
    required this.onDoneCallback,
  });

  void Function(RiderTripTrackingEvent)? onDataCallback;
  Function? onErrorCallback;
  void Function()? onDoneCallback;
  bool _cancelled = false;
  bool _paused = false;

  void emitIgnoringCancellation(RiderTripTrackingEvent event) {
    // Simulate a buggy transport callback already queued before cancellation.
    onDataCallback?.call(event);
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
  }

  @override
  void onData(void Function(RiderTripTrackingEvent)? handleData) {
    onDataCallback = handleData;
  }

  @override
  void onError(Function? handleError) {
    onErrorCallback = handleError;
  }

  @override
  void onDone(void Function()? handleDone) {
    onDoneCallback = handleDone;
  }

  @override
  void pause([Future<void>? resumeSignal]) {
    _paused = true;
    resumeSignal?.whenComplete(resume);
  }

  @override
  void resume() => _paused = false;

  @override
  bool get isPaused => _paused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => Completer<E>().future;

  bool get isCancelled => _cancelled;
}
