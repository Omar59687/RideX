import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_availability_controller.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_flow_repository_provider.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_incoming_offer_controller.dart';
import 'helpers/fake_driver_flow_repository.dart';

final actionScope = StateProvider<DriverAvailabilityScope?>((ref) =>
    DriverAvailabilityScope(
        DriverFlowSession('fake-driver', 1), 'fake-vehicle'));
final actionRepository = StateProvider<DriverFlowRepository?>((ref) => null);
final actionGate = StateProvider<bool>((ref) => true);

// Deliberately unfiltered: the controller must own every admission/order check.
class ActionRepository implements DriverFlowRepository {
  DriverFlowSnapshot current = driverFlowSnapshot(offer: driverFlowOffer());
  final events = StreamController<DriverFlowSnapshot>.broadcast(sync: true);
  final commands = <DriverFlowDecideOffer>[];
  final replies = <Completer<DriverFlowResult>>[];
  void emit(DriverFlowSnapshot value) {
    current = value;
    events.add(value);
  }

  @override
  Stream<DriverFlowSnapshot> watch(DriverFlowSession session) => events.stream;
  @override
  Future<DriverFlowResult> read(DriverFlowSession session) async =>
      DriverFlowResult(DriverFlowOutcome.observed, current);
  @override
  Future<DriverFlowResult> execute(DriverFlowCommand command) {
    commands.add(command as DriverFlowDecideOffer);
    final reply = Completer<DriverFlowResult>();
    replies.add(reply);
    return reply.future;
  }
}

class ActionHarness {
  ActionHarness({bool? enabled = true}) {
    container = ProviderContainer(overrides: [
      driverAvailabilityScopeProvider
          .overrideWith((ref) => ref.watch(actionScope)),
      driverFlowRepositoryProvider
          .overrideWith((ref) => ref.watch(actionRepository) ?? repository),
      driverOfferClockProvider.overrideWithValue(() => now),
      if (enabled != null)
        driverOfferSimulationEnabledProvider
            .overrideWith((ref) => enabled && ref.watch(actionGate)),
      driverOfferDecisionSchedulerProvider
          .overrideWithValue((duration, callback) {
        scheduledDuration = duration;
        timeout = callback;
        scheduledCallbacks.add(callback);
        return () {
          if (identical(timeout, callback)) timeout = null;
        };
      }),
    ]);
    container.read(driverIncomingOfferProvider);
  }
  final repository = ActionRepository();
  late final ProviderContainer container;
  DateTime now = driverFlowTestTime;
  void Function()? timeout;
  final scheduledCallbacks = <void Function()>[];
  Duration? scheduledDuration;
  DriverIncomingOfferController get controller =>
      container.read(driverIncomingOfferProvider.notifier);
  DriverIncomingOfferView get view =>
      container.read(driverIncomingOfferProvider);
  Future<void> settle() async {
    container.read(driverIncomingOfferProvider);
    await container.pump();
    await Future<void>.value();
  }

  Future<void> act(
          [DriverFlowOfferDecision decision =
              DriverFlowOfferDecision.accept]) =>
      controller.decide(view.offer!, decision);
  DriverFlowSnapshot outcome({bool decline = false, int revision = 2}) =>
      driverFlowSnapshot(
          revision: revision,
          trip: decline
              ? null
              : DriverFlowTrip(
                  id: 'simulated-trip',
                  version: 1,
                  status: DriverTripLifecycleStatus.accepted,
                  journey: driverFlowJourney()));
  Future<void> dispose() async {
    container.dispose();
    await repository.events.close();
  }
}

void main() {
  late ActionHarness h;
  setUp(() async {
    h = ActionHarness();
    await h.settle();
  });
  tearDown(() => h.dispose());

  for (final first in DriverFlowOfferDecision.values) {
    for (final second in DriverFlowOfferDecision.values) {
      test('single flight $first then $second preserves original command',
          () async {
        final original = h.view.offer!;
        final pending = h.act(first);
        await h.controller.decide(original, second);
        expect(h.repository.commands, hasLength(1));
        final command = h.repository.commands.single;
        expect(command.targetId, original.id);
        expect(command.expectedVersion, original.version);
        expect(command.decision, first);
        expect(
            command.session.sameSession(h.repository.current.session), isTrue);
        expect(command.idempotencyToken, isNotEmpty);
        h.controller.updateTime();
        await h.controller.refresh();
        expect(h.view.command, same(command));
        h.repository.replies.single
            .complete(const DriverFlowResult(DriverFlowOutcome.rejected));
        await pending;
        expect(h.view.decisionStatus, DriverOfferDecisionStatus.rejected);
        await h.controller.decide(original, second);
        expect(h.repository.commands, hasLength(1));
      });
    }
  }
  test('default gate blocks even direct calls', () async {
    final defaults = ActionHarness(enabled: false);
    addTearDown(defaults.dispose);
    await defaults.settle();
    await defaults.act();
    expect(defaults.repository.commands, isEmpty);
    expect(defaults.view.canDecide, isFalse);
  });
  test('exact deadline prevents dispatch independent of timer', () async {
    h.now = h.view.offer!.expiresAt;
    await h.act();
    expect(h.repository.commands, isEmpty);
  });
  for (final decision in DriverFlowOfferDecision.values) {
    test('expiry while $decision pending latches unknown', () async {
      final pending = h.act(decision);
      h.now = h.view.offer!.expiresAt;
      h.controller.updateTime();
      expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
      h.repository.replies.single.complete(DriverFlowResult(
          DriverFlowOutcome.simulated,
          h.outcome(decline: decision == DriverFlowOfferDecision.decline)));
      await pending;
      expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
    });
    test('valid simulated $decision result published before reply', () async {
      final pending = h.act(decision);
      final outcome =
          h.outcome(decline: decision == DriverFlowOfferDecision.decline);
      h.repository.emit(outcome);
      h.repository.replies.single
          .complete(DriverFlowResult(DriverFlowOutcome.simulated, outcome));
      await pending;
      expect(
          h.view.decisionStatus,
          decision == DriverFlowOfferDecision.accept
              ? DriverOfferDecisionStatus.simulatedAccepted
              : DriverOfferDecisionStatus.simulatedDeclined);
      expect(h.view.canDecide, isFalse);
    });
    test('existing fake supports simulated $decision', () async {
      final fake = FakeDriverFlowRepository(
          driverFlowSnapshot(offer: driverFlowOffer()),
          now: () => h.now);
      addTearDown(fake.dispose);
      h.container.read(actionRepository.notifier).state = fake;
      await h.settle();
      fake.nextCommand = Future.value(DriverFlowResult(
          DriverFlowOutcome.simulated,
          h.outcome(decline: decision == DriverFlowOfferDecision.decline)));
      await h.act(decision);
      expect(
          h.view.decisionStatus,
          decision == DriverFlowOfferDecision.accept
              ? DriverOfferDecisionStatus.simulatedAccepted
              : DriverOfferDecisionStatus.simulatedDeclined);
    });
  }
  test('equivalent reconstruction preserves pending token and deadline',
      () async {
    final pending = h.act();
    final command = h.view.command;
    h.repository
        .emit(driverFlowSnapshot(revision: 2, offer: driverFlowOffer()));
    expect(h.view.command, same(command));
    h.repository.replies.single.complete(
        DriverFlowResult(DriverFlowOutcome.simulated, h.outcome(revision: 3)));
    await pending;
    expect(h.view.decisionStatus, DriverOfferDecisionStatus.simulatedAccepted);
  });
  for (final version in [2, 4]) {
    test('offer version $version cannot unlock pending version 3', () async {
      final pending = h.act();
      h.repository.emit(driverFlowSnapshot(
          revision: 2, offer: driverFlowOffer(version: version)));
      expect(h.view.canDecide, isFalse);
      h.repository.replies.single.complete(DriverFlowResult(
          DriverFlowOutcome.simulated, h.outcome(revision: 3)));
      await pending;
      expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
      expect(h.view.offer!.version, version == 2 ? 3 : 4);
    });
  }
  test('conflicting same-version payload blocks late success', () async {
    final pending = h.act();
    h.repository.emit(driverFlowSnapshot(
        revision: 2,
        offer:
            driverFlowOffer(expiresAt: h.now.add(const Duration(minutes: 2)))));
    h.repository.replies.single.complete(
        DriverFlowResult(DriverFlowOutcome.simulated, h.outcome(revision: 3)));
    await pending;
    expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
  });
  for (final result in [
    DriverFlowOutcome.unknown,
    DriverFlowOutcome.unavailable,
    DriverFlowOutcome.unsupported
  ]) {
    test('$result cannot be reconciled by ordinary new offers or reads',
        () async {
      final pending = h.act();
      h.repository.replies.single.complete(DriverFlowResult(result));
      await pending;
      h.repository.emit(driverFlowSnapshot(
          revision: 9, offer: driverFlowOffer(id: 'new', version: 10)));
      await h.controller.refresh();
      await h.act(DriverFlowOfferDecision.decline);
      expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
      expect(h.repository.commands, hasLength(1));
    });
  }
  test('timeout uses injectable scheduler and late success stays unknown',
      () async {
    final pending = h.act();
    expect(h.scheduledDuration, const Duration(seconds: 15));
    h.timeout!();
    await pending;
    expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
    h.repository.replies.single
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, h.outcome()));
    await h.settle();
    expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
  });
  test('transport exception is unknown', () async {
    final pending = h.act();
    h.repository.replies.single.completeError(StateError('lost'));
    await pending;
    expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
  });
  test('malformed simulated result is unknown', () async {
    final pending = h.act();
    h.repository.replies.single
        .complete(const DriverFlowResult(DriverFlowOutcome.simulated));
    await pending;
    expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
  });
  for (final result in [DriverFlowOutcome.stale, DriverFlowOutcome.expired]) {
    test('definitive $result retires original target', () async {
      final pending = h.act();
      h.repository.replies.single.complete(DriverFlowResult(result));
      await pending;
      expect(h.view.canDecide, isFalse);
      await h.act();
      expect(h.repository.commands, hasLength(1));
    });
  }
  test('authorization loss hides details and rejects late response', () async {
    final pending = h.act();
    h.repository.emit(
        driverFlowSnapshot(revision: 2, phase: DriverFlowPhase.unauthorized));
    h.repository.replies.single.complete(
        DriverFlowResult(DriverFlowOutcome.simulated, h.outcome(revision: 3)));
    await pending;
    expect(h.view.offer, isNull);
    expect(h.view.decisionStatus, DriverOfferDecisionStatus.unauthorized);
  });
  for (final replacement in ['session', 'repository', 'aba']) {
    test(
        'no-flush $replacement retires old completion without unlocking newer attempt',
        () async {
      final old = h.act();
      final oldReply = h.repository.replies.single;
      if (replacement == 'repository') {
        final next = ActionRepository();
        addTearDown(next.events.close);
        h.container.read(actionRepository.notifier).state = next;
      } else {
        h.container.read(actionScope.notifier).state = DriverAvailabilityScope(
            DriverFlowSession(
                replacement == 'aba' ? 'fake-driver' : 'other', 3),
            'fake-vehicle');
        h.repository.current = driverFlowSnapshot(
            session: h.container.read(actionScope)!.session,
            offer: driverFlowOffer());
      }
      oldReply
          .complete(DriverFlowResult(DriverFlowOutcome.simulated, h.outcome()));
      await old;
      await h.settle();
      expect(h.view.decisionStatus, DriverOfferDecisionStatus.idle);
      final pending = h.act();
      final command = h.view.command;
      expect(command, isNotNull);
      expect(h.view.canDecide, isFalse);
      final active = h.container.read(actionRepository) as ActionRepository? ??
          h.repository;
      active.replies.last
          .complete(const DriverFlowResult(DriverFlowOutcome.rejected));
      await pending;
    });
  }
  test('old timeout completion cannot clear replacement pending command',
      () async {
    final old = h.act();
    h.timeout!();
    await old;
    final next = ActionRepository();
    addTearDown(next.events.close);
    h.container.read(actionRepository.notifier).state = next;
    await h.settle();
    final pending = h.act();
    final command = h.view.command;
    h.repository.replies.single
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, h.outcome()));
    await h.settle();
    expect(h.view.command, same(command));
    expect(h.view.canDecide, isFalse);
    next.replies.single
        .complete(const DriverFlowResult(DriverFlowOutcome.rejected));
    await pending;
  });
  test('captured stale callback cannot decide a replacement', () async {
    final old = h.view.offer!;
    h.repository.emit(
        driverFlowSnapshot(revision: 2, offer: driverFlowOffer(id: 'new')));
    await h.controller.decide(old, DriverFlowOfferDecision.accept);
    expect(h.repository.commands, isEmpty);
  });
  test('status refresh restores idle controls without waiting for a timer',
      () async {
    await h.controller.refresh();
    expect(h.view.canDecide, isTrue);
  });
  test('response authorization loss wins over an uncertain pending decision',
      () async {
    final pending = h.act();
    h.repository
        .emit(driverFlowSnapshot(revision: 2, phase: DriverFlowPhase.unknown));
    h.repository.replies.single
        .complete(const DriverFlowResult(DriverFlowOutcome.unauthorized));
    await pending;
    expect(h.view.status, IncomingOfferStatus.unauthorized);
    expect(h.view.offer, isNull);
  });
  test(
      'empty observation cannot erase original route while decision is unresolved',
      () async {
    final original = h.view.offer!;
    final pending = h.act();
    h.repository.emit(driverFlowSnapshot(revision: 2));
    expect(h.view.offer, same(original));
    h.repository.replies.single
        .complete(const DriverFlowResult(DriverFlowOutcome.unknown));
    await pending;
    await h.controller.refresh();
    expect(h.view.offer, same(original));
    expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
  });
  test('different Trip publication cannot be promoted by a newer command reply',
      () async {
    final pending = h.act();
    h.repository.emit(h.outcome());
    final different = driverFlowSnapshot(
        revision: 3,
        trip: DriverFlowTrip(
            id: 'different-trip',
            version: 1,
            status: DriverTripLifecycleStatus.accepted,
            journey: driverFlowJourney()));
    h.repository.replies.single
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, different));
    await pending;
    expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
  });
  for (final phase in [
    DriverFlowPhase.pending,
    DriverFlowPhase.unknown,
    DriverFlowPhase.unavailable,
    DriverFlowPhase.stale,
    DriverFlowPhase.loading
  ]) {
    test('cannot dispatch from $phase', () async {
      h.repository.emit(driverFlowSnapshot(
          revision: 2, phase: phase, offer: driverFlowOffer()));
      await h.act();
      expect(h.repository.commands, isEmpty);
    });
  }
  test('fake acceptance with changed journey is not success', () async {
    final pending = h.act();
    final j = driverFlowJourney();
    final changed = DriverFlowJourney(
        pickup: j.pickup,
        destination: j.destination,
        vehicleId: j.vehicleId,
        vehicleLabel: j.vehicleLabel,
        lockedFareFils: j.lockedFareFils + 1,
        distanceMeters: j.distanceMeters,
        durationSeconds: j.durationSeconds);
    h.repository.replies.single.complete(DriverFlowResult(
        DriverFlowOutcome.simulated,
        driverFlowSnapshot(
            revision: 2,
            trip: DriverFlowTrip(
                id: 'fake',
                version: 1,
                status: DriverTripLifecycleStatus.accepted,
                journey: changed))));
    await pending;
    expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
  });
  test('rejection followed by fresh offer may start a distinct token',
      () async {
    final pending = h.act();
    final first = h.view.command!;
    h.repository.replies.single
        .complete(const DriverFlowResult(DriverFlowOutcome.rejected));
    await pending;
    h.repository.emit(
        driverFlowSnapshot(revision: 2, offer: driverFlowOffer(id: 'next')));
    final next = h.act(DriverFlowOfferDecision.decline);
    expect(h.repository.commands, hasLength(2));
    expect(h.view.command!.idempotencyToken, isNot(first.idempotencyToken));
    h.repository.replies.last
        .complete(const DriverFlowResult(DriverFlowOutcome.rejected));
    await next;
  });
  test('duplicate and out-of-order events cannot replace pending command',
      () async {
    final pending = h.act();
    final command = h.view.command;
    h.repository.emit(
        driverFlowSnapshot(revision: 1, offer: driverFlowOffer(id: 'wrong')));
    h.repository.emit(
        driverFlowSnapshot(revision: 0, offer: driverFlowOffer(version: 4)));
    expect(h.view.command, same(command));
    expect(h.view.offer!.id, 'fake-offer');
    h.repository.replies.single
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, h.outcome()));
    await pending;
    expect(h.view.decisionStatus, DriverOfferDecisionStatus.simulatedAccepted);
  });
  test('disposal during command contains completion', () async {
    final pending = h.act();
    h.container.dispose();
    h.repository.replies.single
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, h.outcome()));
    await pending;
  });
  test('disposal retires a command even when repository never replies',
      () async {
    var completed = false;
    final pending = h.act().then((_) {
      completed = true;
    });
    h.container.dispose();
    for (var i = 0; i < 10; i++) {
      await Future<void>.value();
    }
    expect(completed, isTrue);
    await pending;
  });
  test('actual A-B-A replacement never restores the first A attempt', () async {
    final old = h.act();
    for (final session in [
      DriverFlowSession('driver-b', 2),
      DriverFlowSession('fake-driver', 3)
    ]) {
      h.container.read(actionScope.notifier).state =
          DriverAvailabilityScope(session, 'fake-vehicle');
      h.repository.current =
          driverFlowSnapshot(session: session, offer: driverFlowOffer());
      await h.settle();
    }
    final pending = h.act(DriverFlowOfferDecision.decline);
    final current = h.view.command;
    h.repository.replies.first
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, h.outcome()));
    await old;
    await h.settle();
    expect(h.view.command, same(current));
    expect(h.view.command!.session.generation, 3);
    expect(h.view.canDecide, isFalse);
    h.repository.replies.last
        .complete(const DriverFlowResult(DriverFlowOutcome.rejected));
    await pending;
  });
  test('scope revoked by pending-state listener prevents dispatch', () async {
    final subscription =
        h.container.listen(driverIncomingOfferProvider, (previous, next) {
      if (next.decisionStatus == DriverOfferDecisionStatus.pendingAccept) {
        h.container.read(actionScope.notifier).state = null;
      }
    });
    addTearDown(subscription.close);
    final pending = h.act();
    await h.settle();
    for (final reply in h.repository.replies) {
      reply.complete(const DriverFlowResult(DriverFlowOutcome.unknown));
    }
    await pending;
    expect(h.repository.commands, isEmpty);
  });
  test('expiry caused by pending-state listener prevents dispatch', () async {
    final subscription =
        h.container.listen(driverIncomingOfferProvider, (previous, next) {
      if (next.decisionStatus == DriverOfferDecisionStatus.pendingAccept) {
        h.now = next.offer!.expiresAt;
      }
    });
    addTearDown(subscription.close);
    final pending = h.act();
    for (final reply in h.repository.replies) {
      reply.complete(const DriverFlowResult(DriverFlowOutcome.unknown));
    }
    await pending;
    expect(h.repository.commands, isEmpty);
    expect(h.view.decisionStatus, DriverOfferDecisionStatus.expired);
  });
  for (final decision in DriverFlowOfferDecision.values) {
    for (final change in [
      'loading',
      'pending',
      'stream error',
      'trip',
      'unauthorized',
      'payload',
      'version',
      'lower version',
      'gate',
      'scope',
      'repository'
    ]) {
      test(
          'P2 reentrant $change before $decision has zero dispatch and no unknown',
          () async {
        final states = <DriverOfferDecisionStatus>[];
        var injected = false;
        final subscription =
            h.container.listen(driverIncomingOfferProvider, (previous, next) {
          states.add(next.decisionStatus);
          if (injected ||
              (next.decisionStatus != DriverOfferDecisionStatus.pendingAccept &&
                  next.decisionStatus !=
                      DriverOfferDecisionStatus.pendingDecline)) {
            return;
          }
          injected = true;
          switch (change) {
            case 'loading':
            case 'pending':
              h.repository.emit(driverFlowSnapshot(
                  revision: 2,
                  offer: driverFlowOffer(),
                  phase: change == 'loading'
                      ? DriverFlowPhase.loading
                      : DriverFlowPhase.pending));
            case 'stream error':
              h.repository.events
                  .addError(StateError('observation unavailable'));
            case 'trip':
              h.repository.emit(h.outcome());
            case 'unauthorized':
              h.repository.emit(driverFlowSnapshot(
                  revision: 2, phase: DriverFlowPhase.unauthorized));
            case 'payload':
              h.repository.emit(driverFlowSnapshot(
                  revision: 2,
                  offer: driverFlowOffer(
                      expiresAt: h.now.add(const Duration(minutes: 2)))));
            case 'version':
            case 'lower version':
              h.repository.emit(driverFlowSnapshot(
                  revision: 2,
                  offer:
                      driverFlowOffer(version: change == 'version' ? 4 : 2)));
            case 'gate':
              h.container.read(actionGate.notifier).state = false;
            case 'scope':
              h.container.read(actionScope.notifier).state = null;
            case 'repository':
              final nextRepository = ActionRepository();
              addTearDown(nextRepository.events.close);
              h.container.read(actionRepository.notifier).state =
                  nextRepository;
          }
        });
        addTearDown(subscription.close);
        final pending = h.act(decision);
        for (final reply in h.repository.replies) {
          reply.complete(const DriverFlowResult(DriverFlowOutcome.rejected));
        }
        await pending;
        await h.settle();
        expect(injected, isTrue);
        expect(h.repository.commands, isEmpty);
        expect(states, isNot(contains(DriverOfferDecisionStatus.unknown)));
        expect(h.timeout, isNull);
      });
    }
    test(
        'P2 equivalent ready observation before $decision still dispatches once',
        () async {
      var injected = false;
      final subscription =
          h.container.listen(driverIncomingOfferProvider, (previous, next) {
        if (injected ||
            (next.decisionStatus != DriverOfferDecisionStatus.pendingAccept &&
                next.decisionStatus !=
                    DriverOfferDecisionStatus.pendingDecline)) {
          return;
        }
        injected = true;
        h.repository
            .emit(driverFlowSnapshot(revision: 2, offer: driverFlowOffer()));
      });
      addTearDown(subscription.close);
      final pending = h.act(decision);
      expect(h.repository.commands, hasLength(1));
      final command = h.repository.commands.single;
      expect(command.targetId, 'fake-offer');
      expect(command.expectedVersion, 3);
      expect(h.view.command, same(command));
      h.repository.replies.single.complete(DriverFlowResult(
          DriverFlowOutcome.simulated,
          h.outcome(
              decline: decision == DriverFlowOfferDecision.decline,
              revision: 3)));
      await pending;
      expect(
          h.view.decisionStatus,
          decision == DriverFlowOfferDecision.accept
              ? DriverOfferDecisionStatus.simulatedAccepted
              : DriverOfferDecisionStatus.simulatedDeclined);
    });
    for (final invalid in ['source', 'session']) {
      test('P2 mismatched result $invalid for $decision remains unknown',
          () async {
        final pending = h.act(decision);
        final outcome = invalid == 'source'
            ? DriverFlowSnapshot(
                session: h.repository.current.session,
                revision: 2,
                phase: DriverFlowPhase.ready,
                source: DriverFlowSource.unconfigured)
            : driverFlowSnapshot(
                session: DriverFlowSession('foreign', 9),
                revision: 2,
                trip: decision == DriverFlowOfferDecision.decline
                    ? null
                    : h.outcome().trip);
        h.repository.replies.single
            .complete(DriverFlowResult(DriverFlowOutcome.simulated, outcome));
        await pending;
        expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
        expect(h.view.canDecide, isFalse);
      });
    }
  }
  test('P2 actual default gate is false without a gate override', () async {
    final defaults = ActionHarness(enabled: null);
    addTearDown(defaults.dispose);
    await defaults.settle();
    expect(
        defaults.container.read(driverOfferSimulationEnabledProvider), isFalse);
    await defaults.act();
    expect(defaults.repository.commands, isEmpty);
  });
  test('P2 unsent attempt callback cannot unlock a later legitimate attempt',
      () async {
    var injected = false;
    final subscription =
        h.container.listen(driverIncomingOfferProvider, (previous, next) {
      if (!injected &&
          next.decisionStatus == DriverOfferDecisionStatus.pendingAccept) {
        injected = true;
        h.repository.emit(driverFlowSnapshot(
            revision: 2,
            phase: DriverFlowPhase.loading,
            offer: driverFlowOffer()));
      }
    });
    await h.act();
    subscription.close();
    expect(h.repository.commands, isEmpty);
    final oldTimeout = h.scheduledCallbacks.single;
    h.repository
        .emit(driverFlowSnapshot(revision: 3, offer: driverFlowOffer()));
    final pending = h.act(DriverFlowOfferDecision.decline);
    final current = h.view.command;
    oldTimeout();
    await h.settle();
    expect(h.repository.commands, hasLength(1));
    expect(h.view.command, same(current));
    expect(h.view.decisionStatus, DriverOfferDecisionStatus.pendingDecline);
    h.repository.replies.single
        .complete(const DriverFlowResult(DriverFlowOutcome.rejected));
    await pending;
  });
  for (final decision in DriverFlowOfferDecision.values) {
    test('P2 stream failure after $decision dispatch stays unknown', () async {
      final pending = h.act(decision);
      expect(h.repository.commands, hasLength(1));
      h.repository.events.addError(StateError('lost observation'));
      expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
      h.repository.replies.single.complete(DriverFlowResult(
          DriverFlowOutcome.simulated,
          h.outcome(decline: decision == DriverFlowOfferDecision.decline)));
      await pending;
      expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
    });
    test('P2 mismatched result payload for $decision is unknown', () async {
      final pending = h.act(decision);
      final j = driverFlowJourney();
      final changed = DriverFlowJourney(
          pickup: j.pickup,
          destination: j.destination,
          vehicleId: j.vehicleId,
          vehicleLabel: j.vehicleLabel,
          lockedFareFils: j.lockedFareFils + 1,
          distanceMeters: j.distanceMeters,
          durationSeconds: j.durationSeconds);
      h.repository.replies.single.complete(DriverFlowResult(
          DriverFlowOutcome.simulated,
          driverFlowSnapshot(
              revision: 2,
              trip: DriverFlowTrip(
                  id: 'wrong',
                  version: 1,
                  status: DriverTripLifecycleStatus.accepted,
                  journey: changed))));
      await pending;
      expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
      expect(h.view.canDecide, isFalse);
    });
  }
}
