import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';

void main() {
  MockTrip seedTrip() => MockData.sampleTrip(status: TripStatus.inProgress);

  ProviderContainer containerWith(
    _GatedTripsRepository repository, {
    _ObservedActiveTripController? controller,
  }) {
    final container = ProviderContainer(overrides: [
      tripsRepositoryProvider.overrideWith((ref) => repository),
      if (controller != null)
        activeTripControllerProvider.overrideWith(() => controller),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('ActiveTripController.createTrip lifecycle', () {
    test('normal creation applies the result and concurrent calls share it',
        () async {
      final repository = _GatedTripsRepository();
      final container = containerWith(repository);
      final controller = container.read(activeTripControllerProvider.notifier);
      final draft = container.read(bookingControllerProvider);
      final created = seedTrip().copyWith(status: TripStatus.searching);

      final pending = controller.createTrip();
      expect(controller.createTrip(), same(pending));
      expect(repository.createCalls, 1);
      expect(repository.lastDraft, same(draft));
      expect(container.read(activeTripControllerProvider), isNull);
      repository.gate.complete(created);
      await pending;
      expect(container.read(activeTripControllerProvider), same(created));
    });

    final changes = <String, void Function(ActiveTripController, MockTrip)>{
      'reset': (controller, seed) => controller.reset(),
      'same-ID replacement': (controller, seed) =>
          controller.setTrip(seed.copyWith(finalFare: 25)),
      'equal same-ID replacement': (controller, seed) =>
          controller.setTrip(seed.copyWith()),
      'different-ID replacement': (controller, seed) => controller.setTrip(
            MockData.sampleTrip(id: 'new-trip', status: TripStatus.inProgress),
          ),
      'reset and reseed': (controller, seed) {
        controller.reset();
        controller.setTrip(seed);
      },
      'completion status update': (controller, seed) =>
          controller.setStatus(TripStatus.completed),
      'updates returning to the original state': (controller, seed) {
        controller.setTrip(seed.copyWith(finalFare: 25));
        controller.setTrip(seed);
      },
    };

    for (final change in changes.entries) {
      test('discards creation after ${change.key}', () async {
        final repository = _GatedTripsRepository();
        final seed = seedTrip();
        final container = containerWith(repository,
            controller: _ObservedActiveTripController(seed));
        final controller =
            container.read(activeTripControllerProvider.notifier);
        final pending = controller.createTrip();
        change.value(controller, seed);
        final latest = container.read(activeTripControllerProvider);
        expect(controller.createTrip(), same(pending));
        expect(repository.createCalls, 1);

        repository.gate.complete(seed.copyWith(status: TripStatus.searching));
        await pending;
        expect(container.read(activeTripControllerProvider), same(latest));
      });
    }

    for (final rebuildFirst in [true, false]) {
      test(
          'invalidation discards creation ${rebuildFirst ? "after" : "before"} '
          'same-ID rebuild and allows a retry', () async {
        final repository = _GatedTripsRepository();
        final seed = seedTrip();
        final observed = _ObservedActiveTripController(seed);
        final container = containerWith(repository, controller: observed);
        final controller =
            container.read(activeTripControllerProvider.notifier);
        final pending = controller.createTrip();
        container.invalidate(activeTripControllerProvider);
        if (rebuildFirst) {
          expect(container.read(activeTripControllerProvider), same(seed));
          expect(observed.buildCalls, 2);
          expect(container.read(activeTripControllerProvider.notifier),
              same(controller));
          expect(controller.createTrip(), same(pending));
        } else {
          expect(observed.buildCalls, 1);
        }

        final created = seed.copyWith(status: TripStatus.searching);
        repository.gate.complete(created);
        await pending;
        expect(observed.stateAssignments, 0);
        expect(container.read(activeTripControllerProvider), same(seed));
        expect(observed.buildCalls, 2);

        repository.gate = Completer<MockTrip>();
        final retry = controller.createTrip();
        expect(repository.createCalls, 2);
        repository.gate.complete(created);
        await retry;
        expect(container.read(activeTripControllerProvider), same(created));
      });
    }

    test('disposal discards creation without attempting state assignment',
        () async {
      final repository = _GatedTripsRepository();
      final observed = _ObservedActiveTripController(null);
      final container = ProviderContainer(overrides: [
        tripsRepositoryProvider.overrideWith((ref) => repository),
        activeTripControllerProvider.overrideWith(() => observed),
      ]);
      var disposed = false;
      addTearDown(() {
        if (!disposed) container.dispose();
      });
      final pending =
          container.read(activeTripControllerProvider.notifier).createTrip();
      container.dispose();
      disposed = true;
      repository.gate.complete(seedTrip());
      await expectLater(pending, completes);
      expect(repository.createCalls, 1);
      expect(observed.stateAssignments, 0);
    });

    for (final replace in [false, true]) {
      test(
          'failure preserves ${replace ? "replacement" : "original"} state '
          'and allows a retry', () async {
        final repository = _GatedTripsRepository();
        final seed = seedTrip();
        final container = containerWith(repository,
            controller: _ObservedActiveTripController(seed));
        final controller =
            container.read(activeTripControllerProvider.notifier);
        final pending = controller.createTrip();
        expect(controller.createTrip(), same(pending));
        final failure = expectLater(pending, throwsStateError);
        if (replace) controller.setTrip(seed.copyWith(finalFare: 25));
        final latest = container.read(activeTripControllerProvider);
        repository.gate.completeError(StateError('creation unavailable'));
        await failure;
        expect(container.read(activeTripControllerProvider), same(latest));

        repository.gate = Completer<MockTrip>();
        final retry = controller.createTrip();
        expect(controller.createTrip(), same(retry));
        expect(repository.createCalls, 2);
        final created = seed.copyWith(status: TripStatus.searching);
        repository.gate.complete(created);
        await retry;
        expect(container.read(activeTripControllerProvider), same(created));
      });
    }

    test(
        'discarded stale success releases single-flight for a legitimate retry',
        () async {
      final repository = _GatedTripsRepository();
      final container = containerWith(repository);
      final controller = container.read(activeTripControllerProvider.notifier);
      final pending = controller.createTrip();
      controller.reset();
      repository.gate.complete(seedTrip());
      await pending;
      expect(container.read(activeTripControllerProvider), isNull);

      repository.gate = Completer<MockTrip>();
      final retry = controller.createTrip();
      expect(controller.createTrip(), same(retry));
      expect(repository.createCalls, 2);
      final created = seedTrip().copyWith(status: TripStatus.searching);
      repository.gate.complete(created);
      await retry;
      expect(container.read(activeTripControllerProvider), same(created));
    });
  });
}

class _ObservedActiveTripController extends ActiveTripController {
  _ObservedActiveTripController(this.seed);

  final MockTrip? seed;
  int stateAssignments = 0;
  int buildCalls = 0;

  @override
  set state(MockTrip? value) {
    stateAssignments++;
    super.state = value;
  }

  @override
  MockTrip? build() {
    super.build();
    buildCalls++;
    return seed;
  }
}

class _GatedTripsRepository extends MockTripsRepository {
  Completer<MockTrip> gate = Completer<MockTrip>();
  int createCalls = 0;
  BookingDraft? lastDraft;

  @override
  Future<MockTrip> createTrip(BookingDraft draft) {
    createCalls++;
    lastDraft = draft;
    return gate.future;
  }
}
