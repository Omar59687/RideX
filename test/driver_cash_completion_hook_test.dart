import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/trips/presentation/screens/driver_active_trip_screen.dart';
import 'package:ridex/features/trips/presentation/screens/trip_completion_screen.dart';

/// P6-07 mock-only driver cash-completion hook.
///
/// The controller calls the repository completion operation (single-flight),
/// applies the returned trip only after identity + completion validation,
/// and never declares payment state. The trusted Supabase operation is
/// `driver_transition_trip`; no RPC caller exists in this slice and the
/// repository signature still needs P6-01/P6-02 (expected version,
/// idempotency key).
void main() {
  MockTrip inProgressTrip() =>
      MockData.sampleTrip(status: TripStatus.inProgress);

  ProviderContainer containerWith({
    required MockTrip? seed,
    required TripsRepositoryDouble repository,
  }) {
    final container = ProviderContainer(
      overrides: [
        tripsRepositoryProvider.overrideWith((ref) => repository),
        if (seed != null)
          activeTripControllerProvider.overrideWith(
            () => _SeededActiveTripController(seed),
          ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpDriverTrip(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final router = GoRouter(
      initialLocation: '/driver/trip',
      routes: [
        GoRoute(
          path: '/driver/trip',
          builder: (_, __) => const DriverActiveTripScreen(),
        ),
        GoRoute(
          path: '/driver/completed',
          builder: (_, __) => const TripCompletionScreen(isDriverView: true),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ActiveTripController.completeTrip', () {
    test('applies the repository completed trip', () async {
      final repository = TripsRepositoryDouble();
      final container = containerWith(
        seed: inProgressTrip(),
        repository: repository,
      );

      await container
          .read(activeTripControllerProvider.notifier)
          .completeTrip();

      final trip = container.read(activeTripControllerProvider);
      expect(trip?.status, TripStatus.completed);
      expect(trip?.id, 'trip-1');
      expect(trip?.finalFare, inProgressTrip().finalFare);
      expect(repository.completeCalls, 1);
      expect(repository.lastCompleted?.status, TripStatus.inProgress);
    });

    test('repository failure preserves the previous trip', () async {
      final repository = TripsRepositoryDouble()
        ..failNext = StateError('network unavailable');
      final container = containerWith(
        seed: inProgressTrip(),
        repository: repository,
      );

      await expectLater(
        container.read(activeTripControllerProvider.notifier).completeTrip(),
        throwsStateError,
      );
      expect(
        container.read(activeTripControllerProvider),
        inProgressTrip(),
      );
      expect(repository.completeCalls, 1);
    });

    final interveningChanges =
        <String, void Function(ActiveTripController, MockTrip)>{
      'same-ID cancellation': (controller, trip) => controller.setTrip(
            trip.copyWith(status: TripStatus.cancelledByDriver),
          ),
      'same-ID replacement': (controller, trip) => controller.setTrip(
            trip.copyWith(finalFare: trip.finalFare + 1),
          ),
      'equal same-ID replacement': (controller, trip) =>
          controller.setTrip(trip.copyWith()),
      'different-ID replacement': (controller, trip) => controller.setTrip(
            MockData.sampleTrip(
              id: 'other-trip',
              status: TripStatus.inProgress,
            ),
          ),
      'reset': (controller, trip) => controller.reset(),
      'reset and reseed': (controller, trip) {
        controller.reset();
        controller.setTrip(trip);
      },
      'intervening status update': (controller, trip) =>
          controller.setStatus(TripStatus.completed),
      'overlapping updates returning to the original state':
          (controller, trip) {
        controller.setTrip(trip.copyWith(finalFare: trip.finalFare + 1));
        controller.setTrip(trip);
      },
    };

    for (final change in interveningChanges.entries) {
      test('discards pending completion after ${change.key}', () async {
        final gate = Completer<void>();
        final repository = TripsRepositoryDouble()..gate = gate;
        final seed = inProgressTrip();
        final container = containerWith(seed: seed, repository: repository);
        final controller =
            container.read(activeTripControllerProvider.notifier);

        final pending = controller.completeTrip();
        expect(repository.completeCalls, 1);
        change.value(controller, seed);
        final latest = container.read(activeTripControllerProvider);
        // State changes must not release the existing single-flight operation.
        final overlapping = controller.completeTrip();
        expect(identical(pending, overlapping), isTrue);
        expect(repository.completeCalls, 1);

        gate.complete();
        await Future.wait([pending, overlapping]);

        expect(container.read(activeTripControllerProvider), same(latest));
        expect(repository.completeCalls, 1);
      });
    }

    test('failure preserves newer state and subsequent retry succeeds',
        () async {
      final gate = Completer<void>();
      final repository = TripsRepositoryDouble()
        ..gate = gate
        ..failNext = StateError('network unavailable');
      final container = containerWith(
        seed: inProgressTrip(),
        repository: repository,
      );
      final controller = container.read(activeTripControllerProvider.notifier);
      final pending = controller.completeTrip();
      final failure = expectLater(pending, throwsStateError);
      final replacement = inProgressTrip().copyWith(finalFare: 25);
      controller.setTrip(replacement);
      gate.complete();
      await failure;

      expect(container.read(activeTripControllerProvider), same(replacement));
      await controller.completeTrip();

      expect(repository.completeCalls, 2);
      expect(repository.lastCompleted, same(replacement));
      expect(
        container.read(activeTripControllerProvider),
        replacement.copyWith(status: TripStatus.completed),
      );
    });

    for (final sameId in [true, false]) {
      test(
          'replacement with ${sameId ? "same" : "different"} ID completes '
          'after stale success is discarded', () async {
        final firstGate = Completer<void>();
        final repository = TripsRepositoryDouble()..gate = firstGate;
        final seed = inProgressTrip();
        final container = containerWith(seed: seed, repository: repository);
        final controller =
            container.read(activeTripControllerProvider.notifier);
        final pending = controller.completeTrip();
        final replacement = sameId
            ? seed.copyWith(finalFare: 25)
            : MockData.sampleTrip(
                id: 'replacement', status: TripStatus.inProgress);
        controller.setTrip(replacement);
        expect(identical(pending, controller.completeTrip()), isTrue);
        expect(repository.completeCalls, 1);
        firstGate.complete();
        await pending;
        expect(container.read(activeTripControllerProvider), same(replacement));

        final retryGate = Completer<void>();
        repository.gate = retryGate;
        final retry = controller.completeTrip();
        expect(identical(retry, controller.completeTrip()), isTrue);
        expect(repository.completeCalls, 2);
        expect(repository.lastCompleted, same(replacement));
        retryGate.complete();
        await retry;
        expect(container.read(activeTripControllerProvider),
            replacement.copyWith(status: TripStatus.completed));
        await controller.completeTrip();
        expect(repository.completeCalls, 2);
      });
    }

    for (final creationFirst in [true, false]) {
      test(
          'gated creation and completion settle with '
          '${creationFirst ? "creation" : "completion"} first', () async {
        final completionGate = Completer<void>();
        final creationGate = Completer<MockTrip>();
        final repository = TripsRepositoryDouble()
          ..gate = completionGate
          ..creationGate = creationGate;
        final seed = inProgressTrip();
        final created =
            seed.copyWith(status: TripStatus.searching, finalFare: 25);
        final container = containerWith(seed: seed, repository: repository);
        final controller =
            container.read(activeTripControllerProvider.notifier);
        final completion = controller.completeTrip();
        final creation = controller.createTrip();
        expect(identical(creation, controller.createTrip()), isTrue);
        expect(identical(completion, controller.completeTrip()), isTrue);
        expect(repository.createCalls, 1);
        expect(repository.completeCalls, 1);

        if (creationFirst) {
          creationGate.complete(created);
          await creation;
          expect(container.read(activeTripControllerProvider), same(created));
          completionGate.complete();
          await completion;
        } else {
          completionGate.complete();
          await completion;
          expect(container.read(activeTripControllerProvider)?.status,
              TripStatus.completed);
          creationGate.complete(created);
          await creation;
        }
        expect(
          container.read(activeTripControllerProvider),
          creationFirst
              ? same(created)
              : seed.copyWith(status: TripStatus.completed),
        );
        expect(repository.createCalls, 1);
        expect(repository.completeCalls, 1);
      });
    }

    for (final rebuildFirst in [true, false]) {
      test(
          'provider invalidation discards completion '
          '${rebuildFirst ? "after" : "before"} a same-ID rebuild', () async {
        final gate = Completer<void>();
        final repository = TripsRepositoryDouble()..gate = gate;
        final seed = inProgressTrip();
        final container = containerWith(seed: seed, repository: repository);
        final controller =
            container.read(activeTripControllerProvider.notifier);
        final pending = controller.completeTrip();
        container.invalidate(activeTripControllerProvider);
        // The seeded build returns the same identity and value. Invalidation
        // must still retire the response from the previous provider lifecycle.
        if (rebuildFirst) {
          expect(container.read(activeTripControllerProvider), same(seed));
        }
        gate.complete();
        await pending;
        expect(container.read(activeTripControllerProvider), same(seed));
        await container
            .read(activeTripControllerProvider.notifier)
            .completeTrip();
        expect(container.read(activeTripControllerProvider)?.status,
            TripStatus.completed);
        expect(repository.completeCalls, 2);
      });
    }

    test('container disposal safely discards pending successful completion',
        () async {
      final gate = Completer<void>();
      final repository = TripsRepositoryDouble()..gate = gate;
      final seededController = _SeededActiveTripController(inProgressTrip());
      final container = ProviderContainer(overrides: [
        tripsRepositoryProvider.overrideWith((ref) => repository),
        activeTripControllerProvider.overrideWith(() => seededController),
      ]);
      var disposed = false;
      addTearDown(() {
        if (!disposed) container.dispose();
      });
      final controller = container.read(activeTripControllerProvider.notifier);
      final pending = controller.completeTrip();
      expect(seededController.stateAssignments, 0);
      container.dispose();
      disposed = true;
      gate.complete();
      await expectLater(pending, completes);
      expect(repository.completeCalls, 1);
      expect(seededController.stateAssignments, 0);
    });

    test('concurrent calls share one repository operation', () async {
      final gate = Completer<void>();
      final repository = TripsRepositoryDouble()..gate = gate;
      final container = containerWith(
        seed: inProgressTrip(),
        repository: repository,
      );
      final controller = container.read(activeTripControllerProvider.notifier);

      final first = controller.completeTrip();
      final second = controller.completeTrip();
      expect(repository.completeCalls, 1);
      gate.complete();
      await Future.wait([first, second]);

      expect(
        container.read(activeTripControllerProvider)?.status,
        TripStatus.completed,
      );
      expect(repository.completeCalls, 1);
    });

    test('duplicate call after completion creates no new mutation', () async {
      final repository = TripsRepositoryDouble();
      final container = containerWith(
        seed: inProgressTrip(),
        repository: repository,
      );
      final controller = container.read(activeTripControllerProvider.notifier);

      await controller.completeTrip();
      await controller.completeTrip();

      expect(repository.completeCalls, 1);
      expect(
        container.read(activeTripControllerProvider)?.status,
        TripStatus.completed,
      );
    });

    test('returned trip for another id is discarded', () async {
      final repository = TripsRepositoryDouble()
        ..completeWith = (_) => MockData.sampleTrip(
              id: 'other-trip',
              status: TripStatus.completed,
            );
      final container = containerWith(
        seed: inProgressTrip(),
        repository: repository,
      );

      await container
          .read(activeTripControllerProvider.notifier)
          .completeTrip();

      expect(
        container.read(activeTripControllerProvider),
        inProgressTrip(),
      );
    });

    test('returned trip without completed status is discarded', () async {
      final repository = TripsRepositoryDouble()
        ..completeWith = (active) => active;
      final container = containerWith(
        seed: inProgressTrip(),
        repository: repository,
      );

      await container
          .read(activeTripControllerProvider.notifier)
          .completeTrip();

      expect(
        container.read(activeTripControllerProvider),
        inProgressTrip(),
      );
    });

    test('completion from a non-in-progress trip never calls the repository',
        () async {
      final repository = TripsRepositoryDouble();
      final container = containerWith(
        seed: MockData.sampleTrip(status: TripStatus.accepted),
        repository: repository,
      );

      await container
          .read(activeTripControllerProvider.notifier)
          .completeTrip();

      expect(repository.completeCalls, 0);
      expect(
        container.read(activeTripControllerProvider)?.status,
        TripStatus.accepted,
      );
    });
  });

  group('DriverActiveTripScreen completion', () {
    testWidgets('completes once and navigates without payment claims',
        (tester) async {
      final repository = TripsRepositoryDouble();
      final container = containerWith(
        seed: inProgressTrip(),
        repository: repository,
      );
      await pumpDriverTrip(tester, container);

      await tester.tap(find.text('Complete trip'));
      await tester.pumpAndSettle();

      expect(find.text('Ride finished successfully'), findsOneWidget);
      expect(repository.completeCalls, 1);
      expect(find.textContaining('Paid'), findsNothing);
      expect(find.textContaining('receipt'), findsNothing);
      expect(find.textContaining('Cash'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rapid repeated taps complete exactly once', (tester) async {
      final gate = Completer<void>();
      final repository = TripsRepositoryDouble()..gate = gate;
      final container = containerWith(
        seed: inProgressTrip(),
        repository: repository,
      );
      await pumpDriverTrip(tester, container);

      await tester.tap(find.text('Complete trip'));
      await tester.pump();
      await tester.tap(find.text('Complete trip'));
      await tester.pump();
      expect(repository.completeCalls, 1);
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Ride finished successfully'), findsOneWidget);
      expect(repository.completeCalls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('failure stays on the trip with an honest message',
        (tester) async {
      final repository = TripsRepositoryDouble()
        ..failNext = StateError('network unavailable');
      final container = containerWith(
        seed: inProgressTrip(),
        repository: repository,
      );
      await pumpDriverTrip(tester, container);

      await tester.tap(find.text('Complete trip'));
      await tester.pumpAndSettle();

      expect(find.text('Drive to destination'), findsOneWidget);
      expect(
        find.text('Could not complete the trip. Try again.'),
        findsOneWidget,
      );
      expect(
        container.read(activeTripControllerProvider)?.status,
        TripStatus.inProgress,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

class _SeededActiveTripController extends ActiveTripController {
  _SeededActiveTripController(this.trip);

  final MockTrip trip;
  int stateAssignments = 0;

  @override
  set state(MockTrip? value) {
    stateAssignments++;
    super.state = value;
  }

  @override
  MockTrip? build() {
    super.build();
    return trip;
  }
}

/// Scriptable [MockTripsRepository] for hook tests.
class TripsRepositoryDouble extends MockTripsRepository {
  int createCalls = 0;
  Completer<MockTrip>? creationGate;
  int completeCalls = 0;
  MockTrip? lastCompleted;
  Object? failNext;
  Completer<void>? gate;
  MockTrip Function(MockTrip active)? completeWith;

  @override
  Future<MockTrip> createTrip(BookingDraft draft) {
    createCalls++;
    return creationGate?.future ?? super.createTrip(draft);
  }

  @override
  Future<MockTrip> completeTrip(MockTrip trip) async {
    completeCalls++;
    lastCompleted = trip;
    final pendingGate = gate;
    if (pendingGate != null) {
      gate = null;
      await pendingGate.future;
    }
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    final override = completeWith;
    if (override != null) return override(trip);
    return super.completeTrip(trip);
  }
}
