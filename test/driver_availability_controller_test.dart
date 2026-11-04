import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_availability_controller.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_flow_repository_provider.dart';
import 'helpers/fake_driver_flow_repository.dart';

final fixtureRepository = StateProvider<DriverFlowRepository?>((ref) => null);
final fixtureScope = StateProvider<DriverAvailabilityScope?>((ref) =>
    DriverAvailabilityScope(
        DriverFlowSession('fake-driver', 1), 'fake-vehicle'));
DriverFlowSnapshot availabilitySnapshot(
        {int revision = 1,
        int version = 1,
        DriverFlowPhase phase = DriverFlowPhase.ready,
        DriverAvailabilityState value = DriverAvailabilityState.offline,
        DriverFlowSession? session}) =>
    driverFlowSnapshot(
        session: session,
        revision: revision,
        phase: phase,
        availability: DriverFlowAvailability(
            state: value,
            version: version,
            vehicleId: value == DriverAvailabilityState.offline
                ? null
                : 'fake-vehicle',
            bookingId:
                value == DriverAvailabilityState.reserved ? 'booking' : null,
            tripId: value == DriverAvailabilityState.onTrip ? 'trip' : null));
Future<void> flushAvailability() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeDriverFlowRepository fake;
  late ProviderContainer container;
  late ProviderSubscription<DriverAvailabilityView> listener;
  DriverAvailabilityView getView() =>
      container.read(driverAvailabilityControllerProvider);
  DriverAvailabilityController getController() =>
      container.read(driverAvailabilityControllerProvider.notifier);
  setUp(() {
    fake = FakeDriverFlowRepository(availabilitySnapshot(),
        now: () => driverFlowTestTime);
    container = ProviderContainer(overrides: [
      driverFlowRepositoryProvider
          .overrideWith((ref) => ref.watch(fixtureRepository) ?? fake),
      driverAvailabilityScopeProvider
          .overrideWith((ref) => ref.watch(fixtureScope))
    ]);
    listener =
        container.listen(driverAvailabilityControllerProvider, (_, __) {});
  });
  tearDown(() async {
    listener.close();
    container.dispose();
    await fake.dispose();
  });

  for (final replacement in ['scope', 'clear', 'repository']) {
    for (final phase in [DriverFlowPhase.ready, DriverFlowPhase.unauthorized]) {
      test('no-flush $replacement rejects old $phase event', () async {
        await container.pump();
        await Future<void>.value();
        fake.emit(availabilitySnapshot(revision: 2, version: 8));
        final session = replacement == 'scope'
            ? DriverFlowSession('driver-b', 2)
            : fake.current.session;
        final other = FakeDriverFlowRepository(
            availabilitySnapshot(session: session),
            now: () => driverFlowTestTime);
        addTearDown(other.dispose);

        // No await/pump/flush/controller read between replacement and old emit.
        if (replacement == 'clear') {
          container.read(fixtureScope.notifier).state = null;
        } else {
          if (replacement == 'scope') {
            container.read(fixtureScope.notifier).state =
                DriverAvailabilityScope(session, 'vehicle-b');
          }
          container.read(fixtureRepository.notifier).state = other;
        }
        fake.emit(availabilitySnapshot(
            revision: 3,
            version: 99,
            phase: phase,
            value: DriverAvailabilityState.available));

        // Inspect before the replacement's scheduled initial read can run.
        expect(getView().availability, isNull);
        expect(
            getView().phase,
            replacement == 'clear'
                ? DriverFlowPhase.unavailable
                : DriverFlowPhase.loading);
        await container.pump();
        await Future<void>.value();
        if (replacement == 'clear') {
          expect(getView().availability, isNull);
          expect(getView().canChange, isFalse);
        } else {
          expect(getView().phase, DriverFlowPhase.ready);
          expect(getView().availability!.version, 1);
          expect(getView().canChange, isTrue);
          await getController().setOnline(true);
          expect(other.commands, hasLength(1));
          final command = other.commands.single as DriverFlowSetAvailability;
          expect(command.session.sameSession(session), isTrue);
          expect(command.expectedVersion, 1);
          expect(command.vehicleId,
              replacement == 'scope' ? 'vehicle-b' : 'fake-vehicle');
        }
        expect(fake.commands, isEmpty);
      });
    }
  }

  for (final outcome in [
    DriverFlowOutcome.simulated,
    DriverFlowOutcome.unauthorized,
    DriverFlowOutcome.unknown
  ]) {
    test('no-flush command $outcome cannot change replacement scope', () async {
      await container.pump();
      await Future<void>.value();
      fake.emit(availabilitySnapshot(revision: 2, version: 8));
      final response = Completer<DriverFlowResult>();
      fake.nextCommand = response.future;
      final pending = getController().setOnline(true);
      final session = DriverFlowSession('driver-b', 2);
      final other = FakeDriverFlowRepository(
          availabilitySnapshot(session: session),
          now: () => driverFlowTestTime);
      addTearDown(other.dispose);
      final publications = <DriverAvailabilityView>[];
      final observation = container.listen(driverAvailabilityControllerProvider,
          (_, next) => publications.add(next));
      addTearDown(observation.close);

      // Complete in this turn: no provider read or pump after replacement.
      container.read(fixtureScope.notifier).state =
          DriverAvailabilityScope(session, 'vehicle-b');
      container.read(fixtureRepository.notifier).state = other;
      response.complete(DriverFlowResult(
          outcome,
          outcome == DriverFlowOutcome.simulated
              ? availabilitySnapshot(
                  revision: 3,
                  version: 99,
                  value: DriverAvailabilityState.available)
              : null));
      await pending;
      await container.pump();
      await Future<void>.value();
      expect(publications.any((view) => view.availability?.version == 99),
          isFalse);
      expect(
          publications
              .any((view) => view.phase == DriverFlowPhase.unauthorized),
          isFalse);
      expect(getView().phase, DriverFlowPhase.ready);
      expect(getView().availability!.version, 1);
      expect(getView().changing, isFalse);
      await getController().setOnline(true);
      expect(other.commands, hasLength(1));
      expect(fake.commands, hasLength(1));
      expect(
          (other.commands.single as DriverFlowSetAvailability)
              .session
              .sameSession(session),
          isTrue);
    });
  }

  for (final phase in [DriverFlowPhase.ready, DriverFlowPhase.unauthorized]) {
    test(
        'no-flush scope-only replacement rejects old $phase on same repository',
        () async {
      final repository =
          _ReplyOnlyAvailabilityRepository(availabilitySnapshot(version: 8));
      container.read(fixtureRepository.notifier).state = repository;
      await container.pump();
      await Future<void>.value();
      await getController().refresh();
      final oldSession = repository.snapshot.session;
      final session = DriverFlowSession('driver-b', 2);
      repository.snapshot = availabilitySnapshot(session: session);
      container.read(fixtureScope.notifier).state =
          DriverAvailabilityScope(session, 'vehicle-b');
      // Same repository; no pump/flush/read after replacing only the scope.
      repository.events.add(availabilitySnapshot(
          session: oldSession,
          revision: 3,
          version: 99,
          phase: phase,
          value: DriverAvailabilityState.available));
      expect(getView().availability, isNull);
      expect(getView().phase, DriverFlowPhase.loading);
      await container.pump();
      await Future<void>.value();
      expect(getView().phase, DriverFlowPhase.ready);
      expect(getView().availability!.version, 1);
      await getController().setOnline(true);
      final command = repository.commands.single as DriverFlowSetAvailability;
      expect(command.session.sameSession(session), isTrue);
      expect(command.expectedVersion, 1);
      expect(command.vehicleId, 'vehicle-b');
    });
  }

  test('no-flush retired stream error cannot change new scope', () async {
    final repository = _ReplyOnlyAvailabilityRepository(availabilitySnapshot());
    container.read(fixtureRepository.notifier).state = repository;
    await container.pump();
    await Future<void>.value();
    await getController().refresh();
    final session = DriverFlowSession('driver-b', 2);
    repository.snapshot = availabilitySnapshot(session: session);
    container.read(fixtureScope.notifier).state =
        DriverAvailabilityScope(session, 'vehicle-b');
    repository.events.addError(StateError('retired stream'));
    expect(getView().phase, DriverFlowPhase.loading);
    expect(getView().availability, isNull);
    await container.pump();
    await Future<void>.value();
    expect(getView().canChange, isTrue);
    expect(repository.commands, isEmpty);
  });

  for (final operation in ['read', 'command']) {
    for (final outcome in ['success', 'unauthorized', 'throw']) {
      test('no-flush reply-only $operation $outcome retires after state flush',
          () async {
        final first =
            _ReplyOnlyAvailabilityRepository(availabilitySnapshot(version: 8));
        container.read(fixtureRepository.notifier).state = first;
        await container.pump();
        await Future<void>.value();
        final response = Completer<DriverFlowResult>();
        if (operation == 'read') {
          first.nextRead = response.future;
        } else {
          first.nextCommand = response.future;
        }
        final pending = operation == 'read'
            ? getController().refresh()
            : getController().setOnline(true);
        final session = DriverFlowSession('driver-b', 2);
        final other = _ReplyOnlyAvailabilityRepository(
            availabilitySnapshot(session: session));
        final publications = <DriverAvailabilityView>[];
        final observation = container.listen(
            driverAvailabilityControllerProvider,
            (_, next) => publications.add(next));
        addTearDown(observation.close);
        // No await/pump/flush/controller read before completing the old Future.
        container.read(fixtureScope.notifier).state =
            DriverAvailabilityScope(session, 'vehicle-b');
        container.read(fixtureRepository.notifier).state = other;
        if (outcome == 'throw') {
          response.completeError(StateError('retired response'));
        } else {
          response.complete(DriverFlowResult(
              outcome == 'unauthorized'
                  ? DriverFlowOutcome.unauthorized
                  : operation == 'read'
                      ? DriverFlowOutcome.observed
                      : DriverFlowOutcome.simulated,
              outcome == 'success'
                  ? availabilitySnapshot(
                      revision: 3,
                      version: 99,
                      value: DriverAvailabilityState.available)
                  : null));
        }
        await pending;
        await container.pump();
        await Future<void>.value();
        expect(
            publications.any((v) =>
                v.availability?.version == 99 ||
                v.phase == DriverFlowPhase.unauthorized ||
                v.phase == DriverFlowPhase.unavailable),
            isFalse);
        expect(getView().availability!.version, 1);
        expect(getView().phase, DriverFlowPhase.ready);
        expect(getView().canChange, isTrue);
        expect(first.commands, hasLength(operation == 'read' ? 0 : 1));
        await getController().setOnline(true);
        final command = other.commands.single as DriverFlowSetAvailability;
        expect(command.session.sameSession(session), isTrue);
        expect(command.expectedVersion, 1);
        expect(command.vehicleId, 'vehicle-b');
      });
    }
  }

  test(
      'retired reply cleanup cannot unlock replacement pending or unknown attempt',
      () async {
    final first =
        _ReplyOnlyAvailabilityRepository(availabilitySnapshot(version: 8));
    container.read(fixtureRepository.notifier).state = first;
    await container.pump();
    await Future<void>.value();
    final oldReply = Completer<DriverFlowResult>();
    first.nextCommand = oldReply.future;
    final oldPending = getController().setOnline(true);
    final session = DriverFlowSession('driver-b', 2);
    final other = _ReplyOnlyAvailabilityRepository(
        availabilitySnapshot(session: session));
    container.read(fixtureScope.notifier).state =
        DriverAvailabilityScope(session, 'vehicle-b');
    container.read(fixtureRepository.notifier).state = other;
    await container.pump();
    await Future<void>.value();
    await getController().refresh();
    expect(getView().canChange, isTrue);
    final newReply = Completer<DriverFlowResult>();
    other.nextCommand = newReply.future;
    final newPending = getController().setOnline(true);
    oldReply.complete(DriverFlowResult(
        DriverFlowOutcome.simulated,
        availabilitySnapshot(
            revision: 3,
            version: 99,
            value: DriverAvailabilityState.available)));
    await oldPending;
    try {
      expect(getView().changing, isTrue);
      expect(getView().availability!.version, 1);
      await getController().setOnline(true);
      expect(other.commands, hasLength(1));
    } finally {
      newReply.complete(const DriverFlowResult(DriverFlowOutcome.unknown));
      await newPending;
    }
    await getController().refresh();
    expect(getView().phase, DriverFlowPhase.unknown);
    await getController().setOnline(true);
    expect(other.commands, hasLength(1));
    expect(first.commands, hasLength(1));
  });

  for (final outcome in ['pending', 'unknown']) {
    test('$outcome survives listener removal and remount', () async {
      await flushAvailability();
      final response = Completer<DriverFlowResult>();
      fake.nextCommand = response.future;
      final pending = getController().setOnline(true);
      if (outcome == 'unknown') {
        response.complete(const DriverFlowResult(DriverFlowOutcome.unknown));
        await pending;
      }
      listener.close();
      await flushAvailability();
      listener =
          container.listen(driverAvailabilityControllerProvider, (_, __) {});
      await flushAvailability();
      try {
        expect(getView().canChange, isFalse);
        await getController().refresh();
        await getController().setOnline(true);
        expect(fake.commands, hasLength(1));
      } finally {
        if (!response.isCompleted) {
          response.complete(const DriverFlowResult(DriverFlowOutcome.unknown));
        }
        await pending;
      }
    });
  }

  for (final phase in [DriverFlowPhase.loading, DriverFlowPhase.unavailable]) {
    test('version high-water survives $phase without availability', () async {
      await flushAvailability();
      fake.emit(availabilitySnapshot(
          revision: 2, version: 8, value: DriverAvailabilityState.reserved));
      fake.emit(driverFlowSnapshot(revision: 3, phase: phase));
      fake.emit(availabilitySnapshot(revision: 4, version: 7));
      expect(getView().phase, DriverFlowPhase.stale);
      await getController().setOnline(true);
      expect(fake.commands, isEmpty);
    });
  }

  test('authorization loss wins over regressed availability and stays latched',
      () async {
    await flushAvailability();
    fake.emit(availabilitySnapshot(
        revision: 2, version: 8, value: DriverAvailabilityState.reserved));
    fake.emit(availabilitySnapshot(
        revision: 3, version: 7, phase: DriverFlowPhase.unauthorized));
    expect(getView().phase, DriverFlowPhase.unauthorized);
    expect(getView().availability, isNull);
    fake.emit(availabilitySnapshot(revision: 4, version: 9));
    fake.nextRead =
        Future.value(availabilitySnapshot(revision: 5, version: 10));
    await getController().refresh();
    await getController().setOnline(true);
    expect(fake.nextRead, isNotNull);
    expect(getView().phase, DriverFlowPhase.unauthorized);
    expect(getView().canRefresh, isFalse);
    expect(fake.commands, isEmpty);
  });

  test('loading reads without dispatch', () async {
    await flushAvailability();
    container.invalidate(driverAvailabilityControllerProvider);
    final response = Completer<DriverFlowSnapshot>();
    fake.nextRead = response.future;
    expect(getView().phase, DriverFlowPhase.loading);
    await flushAvailability();
    expect(getView().reading, isTrue);
    response.complete(availabilitySnapshot());
    await flushAvailability();
    expect(getView().availability!.state, DriverAvailabilityState.offline);
    expect(getView().canChange, isTrue);
    expect(fake.commands, isEmpty);
  });

  for (final version in [8, 9]) {
    test('missing data preserves legitimate version $version observation',
        () async {
      await flushAvailability();
      fake.emit(availabilitySnapshot(
          revision: 2, version: 8, value: DriverAvailabilityState.onTrip));
      fake.emit(driverFlowSnapshot(revision: 3));
      expect(getView().canChange, isFalse);
      fake.emit(availabilitySnapshot(
          revision: 4,
          version: version,
          value: DriverAvailabilityState.onTrip));
      expect(getView().phase, DriverFlowPhase.ready);
      expect(getView().availability!.version, version);
      expect(getView().canChange, isFalse);
      expect(fake.commands, isEmpty);
    });
  }

  for (final initial in ['unknown', 'unauthorized', 'high-version']) {
    test('new session independently retires $initial protection', () async {
      await flushAvailability();
      if (initial == 'unknown') {
        await getController().setOnline(true);
      } else {
        fake.emit(availabilitySnapshot(
            revision: 2,
            version: 8,
            phase: initial == 'unauthorized'
                ? DriverFlowPhase.unauthorized
                : DriverFlowPhase.ready));
      }
      final replacement = DriverFlowSession('other-driver', 2);
      fake.replaceSession(replacement);
      fake.emit(availabilitySnapshot(session: replacement));
      container.read(fixtureScope.notifier).state =
          DriverAvailabilityScope(replacement, 'fake-vehicle');
      await flushAvailability();
      expect(getView().phase, DriverFlowPhase.ready);
      expect(getView().availability!.version, 1);
      expect(getView().canChange, isTrue);
      expect(getView().canRefresh, isTrue);
    });
  }

  test('repository replacement retires pending reply and version baseline',
      () async {
    await flushAvailability();
    fake.emit(availabilitySnapshot(revision: 2, version: 8));
    final response = Completer<DriverFlowResult>();
    fake.nextCommand = response.future;
    final pending = getController().setOnline(true);
    listener.close();
    final replacement = FakeDriverFlowRepository(availabilitySnapshot(),
        now: () => driverFlowTestTime);
    addTearDown(replacement.dispose);
    container.read(fixtureRepository.notifier).state = replacement;
    await flushAvailability();
    listener =
        container.listen(driverAvailabilityControllerProvider, (_, __) {});
    await flushAvailability();
    response.complete(DriverFlowResult(
        DriverFlowOutcome.simulated,
        availabilitySnapshot(
            revision: 3,
            version: 9,
            value: DriverAvailabilityState.available)));
    await pending;
    expect(getView().availability!.version, 1);
    expect(getView().availability!.state, DriverAvailabilityState.offline);
    expect(getView().canChange, isTrue);
    await getController().setOnline(true);
    expect(replacement.commands, hasLength(1));
    expect(fake.commands, hasLength(1));
  });

  test('independent containers isolate controller attempts and authorization',
      () async {
    await flushAvailability();
    final otherFake = FakeDriverFlowRepository(availabilitySnapshot(),
        now: () => driverFlowTestTime);
    final other = ProviderContainer(overrides: [
      driverFlowRepositoryProvider.overrideWithValue(otherFake),
      driverAvailabilityScopeProvider.overrideWithValue(
          DriverAvailabilityScope(otherFake.current.session, 'fake-vehicle')),
    ]);
    addTearDown(() async {
      other.dispose();
      await otherFake.dispose();
    });
    other.read(driverAvailabilityControllerProvider);
    await flushAvailability();
    await getController().setOnline(true);
    expect(getView().phase, DriverFlowPhase.unknown);
    expect(other.read(driverAvailabilityControllerProvider).canChange, isTrue);
    fake.emit(
        availabilitySnapshot(revision: 2, phase: DriverFlowPhase.unauthorized));
    await other
        .read(driverAvailabilityControllerProvider.notifier)
        .setOnline(true);
    expect(otherFake.commands, hasLength(1));
    expect(getView().phase, DriverFlowPhase.unauthorized);
    expect(other.read(driverAvailabilityControllerProvider).phase,
        DriverFlowPhase.unknown);
  });

  for (final initial in ['unknown', 'unauthorized']) {
    test('repository replacement clears only retired $initial state', () async {
      await flushAvailability();
      if (initial == 'unknown') {
        await getController().setOnline(true);
      } else {
        fake.emit(availabilitySnapshot(
            revision: 2, phase: DriverFlowPhase.unauthorized));
      }
      final replacement = FakeDriverFlowRepository(availabilitySnapshot(),
          now: () => driverFlowTestTime);
      addTearDown(replacement.dispose);
      container.read(fixtureRepository.notifier).state = replacement;
      await flushAvailability();
      expect(getView().phase, DriverFlowPhase.ready);
      expect(getView().canChange, isTrue);
      fake.emit(availabilitySnapshot(
          revision: 3, version: 99, phase: DriverFlowPhase.unauthorized));
      expect(getView().phase, DriverFlowPhase.ready);
      expect(getView().availability!.version, 1);
      expect(replacement.commands, isEmpty);
    });
  }

  test('read failure does not erase version high-water', () async {
    await flushAvailability();
    fake.emit(availabilitySnapshot(
        revision: 2, version: 8, value: DriverAvailabilityState.onTrip));
    fake.nextRead = Future.error(StateError('private'));
    await getController().refresh();
    fake.emit(
        driverFlowSnapshot(revision: 3, phase: DriverFlowPhase.unavailable));
    fake.emit(availabilitySnapshot(revision: 4, version: 7));
    expect(getView().phase, DriverFlowPhase.stale);
    await getController().setOnline(true);
    expect(fake.commands, isEmpty);
  });

  test(
      'regressed unauthorized event during write ignores late success across remount',
      () async {
    await flushAvailability();
    fake.emit(availabilitySnapshot(revision: 2, version: 8));
    final response = Completer<DriverFlowResult>();
    fake.nextCommand = response.future;
    final pending = getController().setOnline(true);
    fake.emit(availabilitySnapshot(
        revision: 3, version: 7, phase: DriverFlowPhase.unauthorized));
    listener.close();
    await flushAvailability();
    response.complete(DriverFlowResult(
        DriverFlowOutcome.simulated,
        availabilitySnapshot(
            revision: 4,
            version: 9,
            value: DriverAvailabilityState.available)));
    await pending;
    listener =
        container.listen(driverAvailabilityControllerProvider, (_, __) {});
    await flushAvailability();
    expect(getView().phase, DriverFlowPhase.unauthorized);
    expect(getView().availability, isNull);
    await getController().refresh();
    await getController().setOnline(true);
    expect(getView().canRefresh, isFalse);
    expect(fake.commands, hasLength(1));
  });
  for (final value in DriverAvailabilityState.values) {
    test('$value observed and protected correctly', () async {
      await flushAvailability();
      fake.emit(availabilitySnapshot(revision: 2, version: 8, value: value));
      expect(getView().availability!.state, value);
      expect(getView().availability!.version, 8);
      expect(
          getView().canChange,
          value == DriverAvailabilityState.offline ||
              value == DriverAvailabilityState.available);
      if (!getView().canChange) {
        await getController().setOnline(false);
        expect(fake.commands, isEmpty);
      }
    });
  }
  for (final phase in [
    DriverFlowPhase.unavailable,
    DriverFlowPhase.stale,
    DriverFlowPhase.unknown,
    DriverFlowPhase.unauthorized,
    DriverFlowPhase.completionBlocked
  ]) {
    test('$phase disables changes', () async {
      await flushAvailability();
      fake.emit(availabilitySnapshot(revision: 2, phase: phase));
      expect(getView().phase, phase);
      await getController().setOnline(true);
      expect(fake.commands, isEmpty);
    });
  }
  test('double command is single flight and no optimistic Online', () async {
    await flushAvailability();
    final response = Completer<DriverFlowResult>();
    fake.nextCommand = response.future;
    final first = getController().setOnline(true);
    await getController().setOnline(true);
    expect(getView().phase, DriverFlowPhase.pending);
    expect(getView().changing, isTrue);
    expect(getView().availability!.state, DriverAvailabilityState.offline);
    expect(fake.commands, hasLength(1));
    final command = fake.commands.single as DriverFlowSetAvailability;
    expect(command.expectedVersion, 1);
    expect(command.targetId, 'fake-driver');
    expect(command.vehicleId, 'fake-vehicle');
    response.complete(DriverFlowResult(
        DriverFlowOutcome.simulated,
        availabilitySnapshot(
            revision: 2,
            version: 2,
            value: DriverAvailabilityState.available)));
    await first;
    expect(getView().phase, DriverFlowPhase.ready);
    expect(getView().availability!.state, DriverAvailabilityState.available);
    expect(getView().changing, isFalse);
  });
  test('unknown write cannot be retried by reading the same version', () async {
    await flushAvailability();
    await getController().setOnline(true);
    expect(getView().phase, DriverFlowPhase.unknown);
    await getController().refresh();
    expect(getView().phase, DriverFlowPhase.unknown);
    await getController().setOnline(true);
    expect(fake.commands, hasLength(1));
    fake.emit(availabilitySnapshot(revision: 2, version: 2));
    expect(getView().phase, DriverFlowPhase.unknown);
    expect(fake.commands, hasLength(1));
  });
  test('authorization loss is terminal within the scope', () async {
    await flushAvailability();
    final response = Completer<DriverFlowResult>();
    fake.nextCommand = response.future;
    final pending = getController().setOnline(true);
    fake.emit(
        availabilitySnapshot(revision: 2, phase: DriverFlowPhase.unauthorized));
    response.complete(DriverFlowResult(
        DriverFlowOutcome.simulated,
        availabilitySnapshot(
            revision: 3,
            version: 2,
            value: DriverAvailabilityState.available)));
    await pending;
    expect(getView().phase, DriverFlowPhase.unauthorized);
    expect(getView().availability, isNull);
    await getController().refresh();
    fake.emit(availabilitySnapshot(revision: 4, version: 3));
    expect(getView().phase, DriverFlowPhase.unauthorized);
    expect(fake.commands, hasLength(1));
  });
  test('new reserved observation retires late command', () async {
    await flushAvailability();
    final response = Completer<DriverFlowResult>();
    fake.nextCommand = response.future;
    final pending = getController().setOnline(true);
    fake.emit(availabilitySnapshot(
        revision: 4, version: 3, value: DriverAvailabilityState.reserved));
    response.complete(DriverFlowResult(
        DriverFlowOutcome.simulated,
        availabilitySnapshot(
            revision: 2,
            version: 2,
            value: DriverAvailabilityState.available)));
    await pending;
    expect(getView().availability!.state, DriverAvailabilityState.reserved);
    expect(getView().canChange, isFalse);
  });
  test('entity version regression fails closed despite higher event revision',
      () async {
    await flushAvailability();
    fake.emit(availabilitySnapshot(revision: 2, version: 5));
    fake.emit(availabilitySnapshot(
        revision: 3, version: 4, value: DriverAvailabilityState.available));
    expect(getView().phase, DriverFlowPhase.stale);
    expect(getView().availability!.version, 5);
  });
  test('late read cannot overwrite a newer event', () async {
    await flushAvailability();
    final response = Completer<DriverFlowSnapshot>();
    fake.nextRead = response.future;
    final pending = getController().refresh();
    fake.emit(availabilitySnapshot(revision: 4, version: 3));
    response.complete(availabilitySnapshot(
        revision: 2, version: 2, value: DriverAvailabilityState.available));
    await pending;
    expect(getView().revision, 4);
    expect(getView().availability!.version, 3);
  });
  for (final operation in ['read', 'command']) {
    test('session replacement retires pending $operation', () async {
      await flushAvailability();
      final read = Completer<DriverFlowSnapshot>();
      final command = Completer<DriverFlowResult>();
      fake.nextRead = read.future;
      fake.nextCommand = command.future;
      final pending = operation == 'read'
          ? getController().refresh()
          : getController().setOnline(true);
      final replacement = DriverFlowSession('fake-driver', 3);
      fake.replaceSession(replacement);
      fake.emit(availabilitySnapshot(session: replacement, version: 8));
      container.read(fixtureScope.notifier).state =
          DriverAvailabilityScope(replacement, 'fake-vehicle');
      await flushAvailability();
      read.complete(availabilitySnapshot(revision: 99, version: 99));
      command.complete(DriverFlowResult(DriverFlowOutcome.simulated,
          availabilitySnapshot(revision: 99, version: 99)));
      await pending;
      expect(getView().availability!.version, 8);
      expect(getView().revision, 1);
    });
  }
  test('read error can safely retry without writing', () async {
    await flushAvailability();
    fake.nextRead = Future.error(StateError('private'));
    await getController().refresh();
    expect(getView().phase, DriverFlowPhase.unavailable);
    await getController().refresh();
    expect(getView().phase, DriverFlowPhase.ready);
    expect(fake.commands, isEmpty);
  });
  test('transport exception stays unknown with no replay', () async {
    await flushAvailability();
    fake.nextCommand = Future.error(TimeoutException('private'));
    await getController().setOnline(true);
    expect(getView().phase, DriverFlowPhase.unknown);
    await getController().refresh();
    expect(getView().canChange, isFalse);
    expect(fake.commands, hasLength(1));
  });
  test('retired scope ignores late command outcome', () async {
    await flushAvailability();
    final response = Completer<DriverFlowResult>();
    fake.nextCommand = response.future;
    final controller = getController();
    final pending = controller.setOnline(true);
    container.read(fixtureScope.notifier).state = null;
    listener.close();
    await flushAvailability();
    response.complete(DriverFlowResult(
        DriverFlowOutcome.simulated,
        availabilitySnapshot(
            revision: 2,
            version: 2,
            value: DriverAvailabilityState.available)));
    await pending;
    expect(getView().availability, isNull);
    expect(fake.commands, hasLength(1));
  });
  test('revoking the local scope clears data and retires pending write',
      () async {
    await flushAvailability();
    final response = Completer<DriverFlowResult>();
    fake.nextCommand = response.future;
    final pending = getController().setOnline(true);
    container.read(fixtureScope.notifier).state = null;
    await flushAvailability();
    expect(getView().availability, isNull);
    expect(getView().canChange, isFalse);
    response.complete(DriverFlowResult(
        DriverFlowOutcome.simulated,
        availabilitySnapshot(
            revision: 8,
            version: 8,
            value: DriverAvailabilityState.available)));
    await pending;
    expect(getView().availability, isNull);
    expect(fake.commands, hasLength(1));
  });
  test('equal-version observations do not resolve a pending write', () async {
    await flushAvailability();
    final response = Completer<DriverFlowResult>();
    fake.nextCommand = response.future;
    final pending = getController().setOnline(true);
    fake.emit(availabilitySnapshot(revision: 3));
    expect(getView().phase, DriverFlowPhase.unknown);
    expect(getView().changing, isTrue);
    response.complete(DriverFlowResult(
        DriverFlowOutcome.simulated,
        availabilitySnapshot(
            revision: 2,
            version: 2,
            value: DriverAvailabilityState.available)));
    await pending;
    expect(getView().phase, DriverFlowPhase.unknown);
    expect(getView().canChange, isFalse);
    await getController().refresh();
    expect(getView().phase, DriverFlowPhase.unknown);
  });
  test('delayed read after scope retirement cannot recreate state', () async {
    await flushAvailability();
    final response = Completer<DriverFlowSnapshot>();
    fake.nextRead = response.future;
    final pending = getController().refresh();
    container.read(fixtureScope.notifier).state = null;
    listener.close();
    await flushAvailability();
    response.complete(availabilitySnapshot(revision: 9, version: 9));
    await pending;
    expect(getView().availability, isNull);
    expect(getView().canChange, isFalse);
    expect(fake.commands, isEmpty);
  });
  test('stale command result cannot be reconciled by unrelated version advance',
      () async {
    await flushAvailability();
    fake.nextCommand =
        Future.value(const DriverFlowResult(DriverFlowOutcome.stale));
    await getController().setOnline(true);
    expect(getView().phase, DriverFlowPhase.stale);
    await getController().setOnline(true);
    expect(fake.commands, hasLength(1));
    fake.emit(availabilitySnapshot(revision: 2, version: 2));
    expect(getView().canChange, isFalse);
    expect(fake.commands, hasLength(1));
  });
}

// Exercises async continuations without a watch event pre-flushing dependencies.
// This B02-only seam leaves the committed B01 fake unchanged.
class _ReplyOnlyAvailabilityRepository implements DriverFlowRepository {
  _ReplyOnlyAvailabilityRepository(this.snapshot) {
    addTearDown(events.close);
  }
  DriverFlowSnapshot snapshot;
  final events = StreamController<DriverFlowSnapshot>.broadcast(sync: true);
  final commands = <DriverFlowCommand>[];
  Future<DriverFlowResult>? nextRead;
  Future<DriverFlowResult>? nextCommand;
  @override
  Stream<DriverFlowSnapshot> watch(DriverFlowSession session) => events.stream;
  @override
  Future<DriverFlowResult> read(DriverFlowSession session) {
    final reply = nextRead;
    nextRead = null;
    return reply ??
        Future.value(DriverFlowResult(DriverFlowOutcome.observed, snapshot));
  }

  @override
  Future<DriverFlowResult> execute(DriverFlowCommand command) {
    commands.add(command);
    final reply = nextCommand;
    nextCommand = null;
    return reply ??
        Future.value(const DriverFlowResult(DriverFlowOutcome.unknown));
  }
}
