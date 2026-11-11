import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/booking_handoff.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_matching_request.dart';
import 'package:ridex/core/models/rider_booking_search.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/rider_booking_cancellation_repository.dart';
import 'package:ridex/core/repositories/rider_booking_search_repository.dart';
import 'package:ridex/core/repositories/rider_matching_request_repository.dart';
import 'package:ridex/core/services/rider_cancellation/rider_cancellation_coordinator.dart';
import 'package:ridex/features/booking/application/rider_search_controller.dart';

import 'helpers/fake_rider_booking_search_repository.dart';
import 'helpers/fake_rider_trip_tracking_repository.dart';

const _rider = AppUser(
  id: riderIdFixture,
  name: 'Test Rider',
  email: 'rider@example.com',
  role: RideRole.rider,
);
const _quoteId = '99999999-9999-4999-8999-999999999999';

ConfirmedBookingReference _reference() => ConfirmedBookingReference(
      command: PendingFareLock(
        bookingRequestId: riderBookingIdFixture,
        expectedBookingVersion: 1,
        fareQuoteId: _quoteId,
        expectedQuoteVersion: 1,
        riderId: riderIdFixture,
        status: PendingLockRecoveryStatus.uncertain,
        createdAt: DateTime.utc(2026),
      ),
      quote: FareQuote(
        id: _quoteId,
        bookingRequestId: riderBookingIdFixture,
        quoteVersion: 1,
        pricingVersion: 1,
        fixedFareFils: 1000,
        breakdown: const FareBreakdown(
          baseFareFils: 1000,
          distanceFils: 0,
          durationFils: 0,
          stopsFils: 0,
          subtotalFils: 1000,
          minimumFareFils: 1000,
          roundingIncrementFils: 50,
          fixedFareFils: 1000,
        ),
        status: FareQuoteStatus.locked,
        expiresAt: DateTime.utc(2030),
        createdAt: DateTime.utc(2026),
        routeDistanceMeters: 1000,
        routeDurationSeconds: 100,
      ),
    );

class _MatchingFake implements RiderMatchingRequestRepository {
  _MatchingFake(this.run);
  final Future<RiderMatchingRequestResult> Function(int version) run;
  final versions = <int>[];

  @override
  Future<RiderMatchingRequestResult> requestMatching(
    ConfirmedBookingReference reference, {
    required int expectedBookingVersion,
  }) {
    versions.add(expectedBookingVersion);
    return run(expectedBookingVersion);
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this._callback);
  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _tick++;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  bool get isPeriodic => false;

  @override
  int get tick => _tick;
}

RiderMatchingRequestResult _result(RiderMatchingState state) =>
    RiderMatchingRequestResult(
      bookingRequestId: riderBookingIdFixture,
      fareQuoteId: _quoteId,
      state: state,
    );

void main() {
  test('confirmed Cash booking invokes matching once at canonical version',
      () async {
    final matchingDone = Completer<void>();
    final matching = _MatchingFake((_) async {
      matchingDone.complete();
      return _result(RiderMatchingState.noCandidates);
    });
    final booking = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      booking: riderBookingSearchFixture(
        status: RiderBookingSearchStatus.confirmed,
        version: 3,
      ),
    );
    final session = SessionState.fromUser(_rider);
    final controller = RiderSearchController(
      bookingRequestId: riderBookingIdFixture,
      repository: booking,
      matchingRepository: matching,
      readConfirmedReference: _reference,
      cancellationCoordinator: RiderCancellationCoordinator(
        repository: const UnavailableRiderBookingCancellationRepository(),
      ),
      readSession: () => session,
    );
    addTearDown(controller.dispose);
    final noCandidates = Completer<void>();
    controller.addListener(() {
      if (controller.state.phase == RiderSearchPhase.noCandidates &&
          !noCandidates.isCompleted) noCandidates.complete();
    });

    await controller.refresh();
    await matchingDone.future;
    await noCandidates.future;
    expect(matching.versions, [3]);
    expect(controller.state.matchingResult?.state,
        RiderMatchingState.noCandidates);
    await controller.refresh();
    expect(matching.versions, [3]);
    expect(controller.state.phase, RiderSearchPhase.noCandidates);
  });

  test('assignment locator never substitutes for canonical Trip reread',
      () async {
    final matchingDone = Completer<void>();
    final assignmentHintApplied = Completer<void>();
    final matching = _MatchingFake((_) async {
      matchingDone.complete();
      return RiderMatchingRequestResult(
        bookingRequestId: riderBookingIdFixture,
        fareQuoteId: _quoteId,
        state: RiderMatchingState.assigned,
        tripId: riderTripIdFixture,
      );
    });
    final booking = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      booking: riderBookingSearchFixture(
        status: RiderBookingSearchStatus.confirmed,
        version: 3,
      ),
    );
    final trips = FakeRiderTripTrackingRepository();
    addTearDown(trips.close);
    final session = SessionState.fromUser(_rider);
    final controller = RiderSearchController(
      bookingRequestId: riderBookingIdFixture,
      repository: booking,
      matchingRepository: matching,
      readConfirmedReference: _reference,
      tripTrackingRepository: trips,
      cancellationCoordinator: RiderCancellationCoordinator(
        repository: const UnavailableRiderBookingCancellationRepository(),
      ),
      readSession: () => session,
    );
    addTearDown(controller.dispose);
    controller.addListener(() {
      if (controller.state.matchingResult?.state ==
              RiderMatchingState.assigned &&
          !assignmentHintApplied.isCompleted) assignmentHintApplied.complete();
    });
    await controller.refresh();
    await matchingDone.future;
    await assignmentHintApplied.future;
    // The adapter-reported Trip locator is not used to populate assignment.
    expect(controller.state.verifiedTrip, isNull);
    expect(controller.state.assignment,
        RiderAssignmentVerification.notRequested);
    expect(controller.state.phase, RiderSearchPhase.waiting);
    expect(trips.requestedTripIds, isEmpty);
  });

  test('session replacement fences a late matching response', () async {
    final result = Completer<RiderMatchingRequestResult>();
    final called = Completer<void>();
    final matching = _MatchingFake((_) {
      called.complete();
      return result.future;
    });
    final booking = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      booking: riderBookingSearchFixture(
        status: RiderBookingSearchStatus.confirmed,
        version: 3,
      ),
    );
    var session = SessionState.fromUser(_rider);
    final controller = RiderSearchController(
      bookingRequestId: riderBookingIdFixture,
      repository: booking,
      matchingRepository: matching,
      readConfirmedReference: _reference,
      cancellationCoordinator: RiderCancellationCoordinator(
        repository: const UnavailableRiderBookingCancellationRepository(),
      ),
      readSession: () => session,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await called.future;
    session = const SessionState.unauthenticated();
    controller.sessionChanged(session);
    result.complete(_result(RiderMatchingState.noCandidates));
    await result.future;
    await Future<void>.value();
    expect(controller.isSessionInvalidated, isTrue);
    expect(controller.state.phase, RiderSearchPhase.unresolved);
    expect(controller.state.matchingResult, isNull);
    expect(matching.versions, [3]);
  });

  test('matching timeout withholds a late result and blocks automatic replay',
      () async {
    final result = Completer<RiderMatchingRequestResult>();
    final called = Completer<void>();
    final timers = <_ManualTimer>[];
    final matching = _MatchingFake((_) {
      called.complete();
      return result.future;
    });
    final booking = FakeRiderBookingSearchRepository(
      authenticatedRiderId: riderIdFixture,
      booking: riderBookingSearchFixture(
        status: RiderBookingSearchStatus.confirmed,
        version: 3,
      ),
    );
    final session = SessionState.fromUser(_rider);
    final controller = RiderSearchController(
      bookingRequestId: riderBookingIdFixture,
      repository: booking,
      matchingRepository: matching,
      readConfirmedReference: _reference,
      cancellationCoordinator: RiderCancellationCoordinator(
        repository: const UnavailableRiderBookingCancellationRepository(),
      ),
      readSession: () => session,
      scheduleReadDeadline: (_, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await called.future;
    timers.last.fire();
    expect(controller.state.matchingFailure, RiderMatchingFailure.unavailable);
    expect(controller.state.matchingResult, isNull);
    expect(controller.canRetryMatching, isFalse);
    result.complete(_result(RiderMatchingState.noCandidates));
    await result.future;
    await Future<void>.value();
    // The completed late response is fenced and cannot restore state.
    expect(controller.state.matchingResult, isNull);
    expect(matching.versions, [3]);
  });
}
