import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_availability_controller.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_flow_repository_provider.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_incoming_offer_controller.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_trip_presentation_controller.dart';
import 'helpers/fake_driver_flow_repository.dart';

final tripScope = StateProvider<DriverAvailabilityScope?>((ref) =>
    DriverAvailabilityScope(
        DriverFlowSession('fake-driver', 1), 'fake-vehicle'));
final tripRepository = StateProvider<DriverFlowRepository?>((ref) => null);
final tripGate = StateProvider<bool>((ref) => true);

class TripTestSession extends SessionController {
  @override
  SessionState build() => tripSession();
  void replace(SessionState value) => state = value;
}

SessionState tripSession(
        {String id = 'fake-driver',
        RideRole role = RideRole.driver,
        bool blocked = false,
        DriverApprovalStatus approval = DriverApprovalStatus.approved}) =>
    SessionState.fromUser(AppUser(
        id: id,
        name: 'Demo Driver',
        email: 'demo@example.invalid',
        role: role,
        isBlocked: blocked,
        driverApprovalStatus: approval));

DriverFlowTrip previewTrip(
        {String id = 'demo-trip',
        int version = 1,
        DriverTripLifecycleStatus status = DriverTripLifecycleStatus.accepted,
        DriverFlowJourney? journey}) =>
    DriverFlowTrip(
        id: id,
        version: version,
        status: status,
        journey: journey ?? driverFlowJourney());

// No filtering, version policy, authorization or command deduplication here.
class TripTestRepository implements DriverFlowRepository {
  DriverFlowSnapshot current = driverFlowSnapshot(trip: previewTrip());
  final events = StreamController<DriverFlowSnapshot>.broadcast(sync: true);
  final commands = <DriverFlowCommand>[];
  final replies = <Completer<DriverFlowResult>>[];
  Future<DriverFlowResult>? nextRead;
  int reads = 0;
  void emit(DriverFlowSnapshot snapshot) {
    current = snapshot;
    events.add(snapshot);
  }

  @override
  Stream<DriverFlowSnapshot> watch(DriverFlowSession session) => events.stream;
  @override
  Future<DriverFlowResult> read(DriverFlowSession session) {
    reads++;
    final scripted = nextRead;
    nextRead = null;
    return scripted ??
        Future.value(DriverFlowResult(DriverFlowOutcome.observed, current));
  }

  @override
  Future<DriverFlowResult> execute(DriverFlowCommand command) {
    commands.add(command);
    final reply = Completer<DriverFlowResult>();
    replies.add(reply);
    return reply.future;
  }
}

class TripHarness {
  TripHarness({bool? enabled = true, bool offerEnabled = false}) {
    container = ProviderContainer(overrides: [
      sessionControllerProvider.overrideWith(TripTestSession.new),
      driverOfferSimulationEnabledProvider.overrideWithValue(offerEnabled),
      driverAvailabilityScopeProvider
          .overrideWith((ref) => ref.watch(tripScope)),
      driverFlowRepositoryProvider
          .overrideWith((ref) => ref.watch(tripRepository) ?? repository),
      if (enabled != null)
        driverTripSimulationEnabledProvider
            .overrideWith((ref) => enabled && ref.watch(tripGate)),
      driverTripResponseSchedulerProvider
          .overrideWithValue((duration, callback) {
        durations.add(duration);
        timers.add(callback);
        return () {};
      }),
      driverOfferClockProvider.overrideWithValue(() => driverFlowTestTime),
      driverOfferDecisionSchedulerProvider
          .overrideWithValue((duration, callback) => () {}),
    ]);
    container.read(driverTripPresentationProvider);
  }
  final repository = TripTestRepository();
  late final ProviderContainer container;
  final timers = <void Function()>[];
  final durations = <Duration>[];
  DriverTripPresentationController get controller =>
      container.read(driverTripPresentationProvider.notifier);
  DriverTripPresentationView get view =>
      container.read(driverTripPresentationProvider);
  TripTestSession get session =>
      container.read(sessionControllerProvider.notifier) as TripTestSession;
  Future<void> settle() async {
    container.read(driverTripPresentationProvider);
    await container.pump();
    await Future<void>.value();
  }

  Future<void> act() => controller.progress(view.trip!, view.nextStatus!,
      lifetime: view.lifetime);
  DriverFlowSnapshot result(
          {int revision = 2,
          int version = 2,
          DriverTripLifecycleStatus status =
              DriverTripLifecycleStatus.driverArriving}) =>
      driverFlowSnapshot(
          revision: revision,
          trip: previewTrip(version: version, status: status));
  Future<void> dispose() async {
    container.dispose();
    await repository.events.close();
  }
}

void main() {
  late TripHarness h;
  setUp(() async {
    h = TripHarness();
    await h.settle();
  });
  tearDown(() => h.dispose());

  test(
      'P2-1 unauthorized reply after UNKNOWN hides data without settling outcome',
      () async {
    final pending = h.act();
    final command = h.view.command;
    h.repository.events.addError(StateError('watch lost'));
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
    h.repository.replies.single
        .complete(const DriverFlowResult(DriverFlowOutcome.unauthorized));
    await pending;
    expect(h.view.phase, DriverFlowPhase.unauthorized);
    expect(h.view.trip, isNull);
    expect(h.view.canProgress, isFalse);
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
    expect(h.view.command, same(command));
    h.repository.emit(h.result(revision: 9));
    await h.controller.refresh();
    expect(h.view.phase, DriverFlowPhase.unauthorized);
    expect(h.view.trip, isNull);
    expect(h.repository.commands, hasLength(1));
  });
  test('P2-1 old unauthorized reply cannot revoke a replacement lifetime',
      () async {
    final pending = h.act();
    h.container.read(tripScope.notifier).state = DriverAvailabilityScope(
        DriverFlowSession('fake-driver', 2), 'fake-vehicle');
    h.repository.current = driverFlowSnapshot(
        session: DriverFlowSession('fake-driver', 2), trip: previewTrip());
    await h.settle();
    await pending;
    h.repository.replies.single
        .complete(const DriverFlowResult(DriverFlowOutcome.unauthorized));
    await h.settle();
    expect(h.view.phase, DriverFlowPhase.ready);
    expect(h.view.trip, isNotNull);
    expect(h.repository.commands, hasLength(1));
  });
  test(
      'P2-1 unauthorized reply after response timeout still revokes current access',
      () async {
    final pending = h.act();
    final command = h.view.command;
    h.timers.single();
    await pending;
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
    h.repository.replies.single
        .complete(const DriverFlowResult(DriverFlowOutcome.unauthorized));
    await h.settle();
    expect(h.view.phase, DriverFlowPhase.unauthorized);
    expect(h.view.trip, isNull);
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
    expect(h.view.command, same(command));
    expect(h.repository.commands, hasLength(1));
  });
  test('P2-2 matching unconfigured unauthorized snapshot latches access loss',
      () async {
    h.repository.emit(DriverFlowSnapshot(
        session: h.repository.current.session,
        revision: 2,
        phase: DriverFlowPhase.unauthorized,
        source: DriverFlowSource.unconfigured));
    expect(h.view.phase, DriverFlowPhase.unauthorized);
    expect(h.view.trip, isNull);
    h.repository.emit(h.result(revision: 3));
    await h.controller.refresh();
    expect(h.view.phase, DriverFlowPhase.unauthorized);
    expect(h.view.canProgress, isFalse);
    expect(h.repository.commands, isEmpty);
  });
  test('P2-2 foreign unauthorized snapshot cannot revoke replacement session',
      () async {
    h.container.read(tripScope.notifier).state = DriverAvailabilityScope(
        DriverFlowSession('fake-driver', 2), 'fake-vehicle');
    h.repository.current = driverFlowSnapshot(
        session: DriverFlowSession('fake-driver', 2), trip: previewTrip());
    await h.settle();
    h.repository.emit(DriverFlowSnapshot(
        session: DriverFlowSession('fake-driver', 1),
        revision: 90,
        phase: DriverFlowPhase.unauthorized,
        source: DriverFlowSource.unconfigured));
    expect(h.view.phase, isNot(DriverFlowPhase.unauthorized));
    h.repository.emit(driverFlowSnapshot(
        session: DriverFlowSession('fake-driver', 2),
        revision: 2,
        trip: previewTrip()));
    expect(h.view.phase, DriverFlowPhase.ready);
    expect(h.repository.commands, isEmpty);
  });
  for (final failure in ['watch', 'read']) {
    test(
        'P2-3 equivalent equal revision explicit read recovers $failure failure',
        () async {
      final original = h.repository.current;
      if (failure == 'watch') {
        h.repository.events.addError(StateError('watch lost'));
      } else {
        h.repository.nextRead = Future.error(StateError('read lost'));
        await h.controller.refresh();
      }
      expect(h.view.phase, DriverFlowPhase.unavailable);
      h.repository
          .emit(original); // Duplicate watch is not an explicit recovery read.
      expect(h.view.phase, DriverFlowPhase.unavailable);
      await h.controller.refresh();
      expect(h.view.phase, DriverFlowPhase.ready);
      expect(h.view.trip!.version, 1);
      expect(h.view.canProgress, isTrue);
      expect(h.repository.commands, isEmpty);
    });
  }
  for (final conflict in [
    'journey',
    'status',
    'version',
    'revision',
    'identity'
  ]) {
    test('P2-3 equal read recovery rejects $conflict mismatch', () async {
      h.repository.emit(h.result(revision: 4, version: 3));
      h.repository.events.addError(StateError('watch lost'));
      final base = driverFlowJourney();
      h.repository.current = driverFlowSnapshot(
          revision: conflict == 'revision' ? 3 : 4,
          trip: previewTrip(
              id: conflict == 'identity' ? 'foreign-trip' : 'demo-trip',
              version: conflict == 'version' ? 2 : 3,
              status: conflict == 'status'
                  ? DriverTripLifecycleStatus.inProgress
                  : DriverTripLifecycleStatus.driverArriving,
              journey: conflict == 'journey'
                  ? DriverFlowJourney(
                      pickup: base.pickup,
                      destination: base.destination,
                      vehicleId: base.vehicleId,
                      vehicleLabel: 'Changed',
                      lockedFareFils: base.lockedFareFils,
                      distanceMeters: base.distanceMeters,
                      durationSeconds: base.durationSeconds)
                  : base));
      await h.controller.refresh();
      expect(h.view.phase, isNot(DriverFlowPhase.ready));
      expect(h.view.canProgress, isFalse);
      expect(h.repository.commands, isEmpty);
    });
  }
  for (final barrier in [
    'conflict',
    'replacement',
    'high-water',
    'unauthorized',
    'unknown'
  ]) {
    test('P2-3 equivalent read never clears $barrier barrier', () async {
      Future<void>? pending;
      if (barrier == 'unknown') {
        pending = h.act();
        h.repository.events.addError(StateError('watch lost'));
      } else if (barrier == 'unauthorized') {
        h.session.replace(const SessionState.unauthenticated());
      } else if (barrier == 'conflict') {
        h.repository.emit(driverFlowSnapshot(
            revision: 2,
            trip: previewTrip(status: DriverTripLifecycleStatus.inProgress)));
      } else if (barrier == 'replacement') {
        h.repository.emit(driverFlowSnapshot(
            revision: 2, trip: previewTrip(id: 'replacement')));
      } else {
        h.repository.emit(h.result());
        h.repository.emit(driverFlowSnapshot(revision: 3, trip: previewTrip()));
      }
      h.repository.events.addError(StateError('transport lost'));
      await h.controller.refresh();
      expect(h.view.canProgress, isFalse);
      if (barrier == 'unknown') {
        expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
        h.repository.replies.single
            .complete(const DriverFlowResult(DriverFlowOutcome.unknown));
        await pending;
      } else {
        expect(h.repository.commands, isEmpty);
      }
    });
  }
  for (final unknown in [false, true]) {
    test(
        'P2-3 equal recovery preserves B04 ${unknown ? 'UNKNOWN' : 'pending'} barrier',
        () async {
      final d = TripHarness(offerEnabled: true);
      addTearDown(d.dispose);
      await d.settle();
      d.repository
          .emit(driverFlowSnapshot(revision: 2, offer: driverFlowOffer()));
      final decision = d.container
          .read(driverIncomingOfferProvider.notifier)
          .decide(d.container.read(driverIncomingOfferProvider).offer!,
              DriverFlowOfferDecision.accept);
      d.repository.emit(driverFlowSnapshot(revision: 3, trip: previewTrip()));
      if (unknown) {
        d.repository.replies.single
            .complete(const DriverFlowResult(DriverFlowOutcome.unknown));
        await decision;
      }
      // Fail only B05's read so the shared B04 command truly stays pending.
      d.repository.nextRead = Future.error(StateError('transport lost'));
      await d.controller.refresh();
      expect(
          d.container.read(driverIncomingOfferProvider).decisionStatus,
          unknown
              ? DriverOfferDecisionStatus.unknown
              : DriverOfferDecisionStatus.pendingAccept);
      await d.controller.refresh();
      expect(d.view.phase, DriverFlowPhase.ready);
      expect(d.view.offerBlocked, isTrue);
      expect(d.view.canProgress, isFalse);
      expect(d.repository.commands, hasLength(1));
      expect(d.repository.commands.single, isA<DriverFlowDecideOffer>());
      if (!unknown) {
        d.repository.replies.single
            .complete(const DriverFlowResult(DriverFlowOutcome.unknown));
        await decision;
      }
    });
  }
  test('P2-3 late equivalent read cannot recover a replaced repository',
      () async {
    final read = Completer<DriverFlowResult>();
    final original = h.repository.current;
    h.repository.events.addError(StateError('transport lost'));
    h.repository.nextRead = read.future;
    final refresh = h.controller.refresh();
    final replacement = TripTestRepository();
    addTearDown(replacement.events.close);
    h.container.read(tripRepository.notifier).state = replacement;
    await h.settle();
    read.complete(DriverFlowResult(DriverFlowOutcome.observed, original));
    await refresh;
    expect(h.view.trip, isNull);
    expect(h.view.canProgress, isFalse);
    expect(replacement.commands, isEmpty);
  });

  test('valid simulated Trip is observed, never created from button state', () {
    expect(h.view.trip!.id, 'demo-trip');
    expect(h.view.phase, DriverFlowPhase.ready);
    expect(h.view.canProgress, isTrue);
    expect(h.repository.commands, isEmpty);
  });
  test('actual default simulation gate prevents direct dispatch', () async {
    final d = TripHarness(enabled: null);
    addTearDown(d.dispose);
    await d.settle();
    expect(d.container.read(driverTripSimulationEnabledProvider), isFalse);
    await d.controller.progress(
        d.view.trip!, DriverTripLifecycleStatus.driverArriving,
        lifetime: d.view.lifetime);
    expect(d.view.canProgress, isFalse);
    expect(d.repository.commands, isEmpty);
  });
  test('unconfigured production defaults remain unavailable', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(driverTripSimulationEnabledProvider), isFalse);
    expect(c.read(driverTripPresentationProvider).phase,
        DriverFlowPhase.unavailable);
    await c.read(driverTripPresentationProvider.notifier).progress(
        previewTrip(), DriverTripLifecycleStatus.driverArriving,
        lifetime: c.read(driverTripPresentationProvider).lifetime);
    expect(c.read(driverTripPresentationProvider).trip, isNull);
    expect(
        (await c
                .read(driverFlowRepositoryProvider)
                .read(DriverFlowSession('fake-driver', 1)))
            .outcome,
        DriverFlowOutcome.unavailable);
  });
  for (final status in DriverTripLifecycleStatus.values) {
    test('lifecycle $status permits only its adjacent nonfinancial edge',
        () async {
      h.repository.emit(driverFlowSnapshot(
          revision: 2, trip: previewTrip(version: 2, status: status)));
      final next = switch (status) {
        DriverTripLifecycleStatus.accepted =>
          DriverTripLifecycleStatus.driverArriving,
        DriverTripLifecycleStatus.driverArriving =>
          DriverTripLifecycleStatus.driverArrived,
        DriverTripLifecycleStatus.driverArrived =>
          DriverTripLifecycleStatus.inProgress,
        _ => null,
      };
      expect(h.view.nextStatus, next);
      if (next != null) {
        final pending = h.act();
        expect(h.repository.commands, hasLength(1));
        final cmd = h.repository.commands.single as DriverFlowProgressTrip;
        expect(cmd.status, next);
        expect(cmd.targetId, 'demo-trip');
        expect(cmd.expectedVersion, 2);
        h.repository.replies.single.complete(DriverFlowResult(
            DriverFlowOutcome.simulated,
            driverFlowSnapshot(
                revision: 3, trip: previewTrip(version: 3, status: next))));
        await pending;
        expect(h.view.progressStatus, DriverTripProgressStatus.simulated);
      } else {
        await h.controller.progress(
            h.view.trip!, DriverTripLifecycleStatus.completed,
            lifetime: h.view.lifetime);
        expect(h.repository.commands, isEmpty);
        expect(h.view.canProgress, isFalse);
      }
    });
  }
  test(
      'single flight preserves original token, target and session across reads',
      () async {
    final original = h.view.trip!;
    final pending = h.act();
    await h.controller.progress(
        original, DriverTripLifecycleStatus.driverArriving,
        lifetime: h.view.lifetime);
    await h.controller.progress(
        original, DriverTripLifecycleStatus.driverArrived,
        lifetime: h.view.lifetime);
    expect(h.repository.commands, hasLength(1));
    final command = h.view.command!;
    final token = command.idempotencyToken;
    expect(token, isNotEmpty);
    expect(command.session.sameSession(h.repository.current.session), isTrue);
    await h.controller.refresh();
    expect(h.view.command, same(command));
    expect(h.view.command!.idempotencyToken, token);
    expect(h.view.progressStatus, DriverTripProgressStatus.pending);
    h.repository.replies.single
        .complete(const DriverFlowResult(DriverFlowOutcome.rejected));
    await pending;
    expect(h.view.progressStatus, DriverTripProgressStatus.rejected);
    await h.controller.progress(
        original, DriverTripLifecycleStatus.driverArriving,
        lifetime: h.view.lifetime);
    expect(h.repository.commands, hasLength(1));
  });
  for (final phase
      in DriverFlowPhase.values.where((p) => p != DriverFlowPhase.ready)) {
    test('reentrant $phase blocks unsent command without transient UNKNOWN',
        () async {
      final states = <DriverTripProgressStatus>[];
      var once = false;
      final sub = h.container.listen(driverTripPresentationProvider, (_, next) {
        states.add(next.progressStatus);
        if (!once && next.progressStatus == DriverTripProgressStatus.pending) {
          once = true;
          h.repository.emit(driverFlowSnapshot(
              revision: 2, phase: phase, trip: previewTrip()));
        }
      });
      await h.act();
      sub.close();
      expect(once, isTrue);
      expect(h.repository.commands, isEmpty);
      expect(states, isNot(contains(DriverTripProgressStatus.unknown)));
      expect(h.view.canProgress, isFalse);
    });
  }
  for (final change in [
    'stream error',
    'Trip ID',
    'version',
    'payload',
    'logout',
    'session',
    'repository',
    'gate',
    'equivalent'
  ]) {
    test('final dispatch revalidates reentrant $change', () async {
      var once = false;
      final states = <DriverTripProgressStatus>[];
      final replacement = TripTestRepository();
      addTearDown(replacement.events.close);
      final sub = h.container.listen(driverTripPresentationProvider, (_, next) {
        states.add(next.progressStatus);
        if (once || next.progressStatus != DriverTripProgressStatus.pending) {
          return;
        }
        once = true;
        switch (change) {
          case 'stream error':
            h.repository.events.addError(StateError('lost watch'));
          case 'Trip ID':
            h.repository.emit(driverFlowSnapshot(
                revision: 2, trip: previewTrip(id: 'other')));
          case 'version':
            h.repository.emit(h.result());
          case 'payload':
            h.repository.emit(driverFlowSnapshot(
                revision: 2,
                trip: previewTrip(
                    status: DriverTripLifecycleStatus.driverArrived)));
          case 'logout':
            h.session.replace(const SessionState.unauthenticated());
          case 'session':
            h.container.read(tripScope.notifier).state =
                DriverAvailabilityScope(
                    DriverFlowSession('fake-driver', 2), 'fake-vehicle');
          case 'repository':
            h.container.read(tripRepository.notifier).state = replacement;
          case 'gate':
            h.container.read(tripGate.notifier).state = false;
          case 'equivalent':
            h.repository
                .emit(driverFlowSnapshot(revision: 2, trip: previewTrip()));
        }
      });
      final pending = h.act();
      if (change == 'equivalent') {
        expect(h.repository.commands, hasLength(1));
        h.repository.replies.single.complete(DriverFlowResult(
            DriverFlowOutcome.simulated, h.result(revision: 3)));
      }
      await pending;
      sub.close();
      expect(once, isTrue);
      expect(h.repository.commands.length, change == 'equivalent' ? 1 : 0);
      expect(replacement.commands, isEmpty);
      expect(states, isNot(contains(DriverTripProgressStatus.unknown)));
    });
  }
  test('unsent cleanup and old timeout cannot unlock a newer attempt',
      () async {
    var once = false;
    final sub = h.container.listen(driverTripPresentationProvider, (_, next) {
      if (!once && next.progressStatus == DriverTripProgressStatus.pending) {
        once = true;
        h.repository.emit(driverFlowSnapshot(
            revision: 2, phase: DriverFlowPhase.loading, trip: previewTrip()));
      }
    });
    await h.act();
    sub.close();
    final oldTimer = h.timers.single;
    h.repository.emit(driverFlowSnapshot(revision: 3, trip: previewTrip()));
    final pending = h.act();
    final command = h.view.command;
    oldTimer();
    expect(h.view.progressStatus, DriverTripProgressStatus.pending);
    expect(h.view.command, same(command));
    h.timers.last();
    await pending;
    oldTimer();
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
    expect(h.repository.commands, hasLength(1));
  });
  for (final phase in [
    DriverFlowPhase.loading,
    DriverFlowPhase.pending,
    DriverFlowPhase.unavailable,
    DriverFlowPhase.stale,
    DriverFlowPhase.unknown
  ]) {
    test('$phase observations disable progression', () {
      h.repository.emit(
          driverFlowSnapshot(revision: 2, phase: phase, trip: previewTrip()));
      expect(h.view.canProgress, isFalse);
    });
  }
  test('missing Trip has no accepted fallback', () {
    h.repository.emit(driverFlowSnapshot(revision: 2));
    expect(h.view.trip, isNull);
    expect(h.view.canProgress, isFalse);
  });
  test('Trip identity replacement is pinned stale', () {
    h.repository.emit(
        driverFlowSnapshot(revision: 2, trip: previewTrip(id: 'replacement')));
    expect(h.view.trip!.id, 'demo-trip');
    expect(h.view.phase, DriverFlowPhase.stale);
    h.repository.emit(driverFlowSnapshot(revision: 3, trip: previewTrip()));
    expect(h.view.canProgress, isFalse);
  });
  test('higher revision cannot regress entity version, including after missing',
      () {
    h.repository.emit(h.result());
    h.repository.emit(driverFlowSnapshot(revision: 3));
    h.repository.emit(driverFlowSnapshot(revision: 4, trip: previewTrip()));
    expect(h.view.phase, DriverFlowPhase.stale);
    expect(h.view.canProgress, isFalse);
    expect(h.view.trip!.version, 2);
  });
  test('older observation cannot overwrite newer watch', () {
    h.repository.emit(h.result(revision: 4));
    h.repository.emit(driverFlowSnapshot(revision: 2, trip: previewTrip()));
    expect(h.view.trip!.version, 2);
    expect(h.view.phase, DriverFlowPhase.ready);
  });
  test('same-version incompatible payload latches conflict', () {
    h.repository.emit(driverFlowSnapshot(
        revision: 2,
        trip: previewTrip(status: DriverTripLifecycleStatus.inProgress)));
    expect(h.view.phase, DriverFlowPhase.stale);
    h.repository.emit(driverFlowSnapshot(revision: 3, trip: previewTrip()));
    expect(h.view.canProgress, isFalse);
  });
  test(
      'higher-version lifecycle regression and terminal resurrection are blocked',
      () {
    h.repository.emit(h.result(status: DriverTripLifecycleStatus.inProgress));
    h.repository
        .emit(driverFlowSnapshot(revision: 3, trip: previewTrip(version: 3)));
    expect(h.view.phase, DriverFlowPhase.stale);
  });
  test('terminal cannot become active even at a higher version', () {
    h.repository.emit(h.result(status: DriverTripLifecycleStatus.completed));
    h.repository.emit(driverFlowSnapshot(
        revision: 3,
        trip: previewTrip(
            version: 3, status: DriverTripLifecycleStatus.inProgress)));
    expect(h.view.phase, DriverFlowPhase.stale);
    expect(h.view.canProgress, isFalse);
  });
  test('late read cannot overwrite newer stream, reconnect only reads',
      () async {
    final read = Completer<DriverFlowResult>();
    h.repository.nextRead = read.future;
    final refresh = h.controller.refresh();
    h.repository.emit(
        h.result(revision: 5, status: DriverTripLifecycleStatus.inProgress));
    read.complete(DriverFlowResult(
        DriverFlowOutcome.observed, driverFlowSnapshot(trip: previewTrip())));
    await refresh;
    expect(h.view.trip!.status, DriverTripLifecycleStatus.inProgress);
    expect(h.repository.commands, isEmpty);
  });
  test('timeout remains UNKNOWN through late success, read and newer Trip',
      () async {
    final pending = h.act();
    final command = h.view.command;
    expect(h.durations.single, const Duration(seconds: 15));
    h.timers.single();
    await pending;
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
    h.repository.replies.single
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, h.result()));
    h.repository.emit(h.result());
    await h.controller.refresh();
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
    expect(h.view.command, same(command));
    expect(h.view.canProgress, isFalse);
    await h.controller.progress(
        h.view.trip!, DriverTripLifecycleStatus.driverArrived,
        lifetime: h.view.lifetime);
    expect(h.repository.commands, hasLength(1));
  });
  for (final outcome in [
    DriverFlowOutcome.unknown,
    DriverFlowOutcome.unavailable,
    DriverFlowOutcome.observed
  ]) {
    test('ambiguous $outcome reply latches unknown', () async {
      final pending = h.act();
      h.repository.replies.single.complete(DriverFlowResult(outcome));
      await pending;
      expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
    });
  }
  test('network exception is unknown and not retried', () async {
    final pending = h.act();
    h.repository.replies.single.completeError(StateError('lost reply'));
    await pending;
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
    expect(h.repository.commands, hasLength(1));
  });
  for (final mismatch in [
    'source',
    'session',
    'payload',
    'id',
    'version',
    'status'
  ]) {
    test('simulated success requires matching $mismatch', () async {
      final pending = h.act();
      final good = h.result();
      final reply = DriverFlowSnapshot(
          session: mismatch == 'session'
              ? DriverFlowSession('other', 9)
              : good.session,
          revision: 2,
          phase: DriverFlowPhase.ready,
          source: mismatch == 'source'
              ? DriverFlowSource.unconfigured
              : DriverFlowSource.simulated,
          trip: mismatch == 'source'
              ? null
              : previewTrip(
                  id: mismatch == 'id' ? 'other' : 'demo-trip',
                  version: mismatch == 'version' ? 1 : 2,
                  status: mismatch == 'status'
                      ? DriverTripLifecycleStatus.inProgress
                      : DriverTripLifecycleStatus.driverArriving,
                  journey: mismatch == 'payload'
                      ? DriverFlowJourney(
                          pickup: good.trip!.journey.pickup,
                          destination: good.trip!.journey.destination,
                          vehicleId: 'fake-vehicle',
                          vehicleLabel: 'Changed',
                          lockedFareFils: 1990,
                          distanceMeters: 5000,
                          durationSeconds: 600)
                      : null));
      h.repository.replies.single
          .complete(DriverFlowResult(DriverFlowOutcome.simulated, reply));
      await pending;
      expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
      expect(h.view.trip!.status, DriverTripLifecycleStatus.accepted);
    });
  }
  test('matching simulated publication before Future is correlated', () async {
    final pending = h.act();
    final result = h.result();
    h.repository.emit(result);
    expect(h.view.progressStatus, DriverTripProgressStatus.pending);
    expect(h.view.canProgress, isFalse);
    h.repository.replies.single
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, result));
    await pending;
    expect(h.view.progressStatus, DriverTripProgressStatus.simulated);
    expect(h.view.trip!.status, DriverTripLifecycleStatus.driverArriving);
  });
  for (final loss in ['logout', 'role', 'blocked', 'approval', 'account']) {
    test('$loss retires pending access and late success cannot resurrect',
        () async {
      final pending = h.act();
      h.session.replace(switch (loss) {
        'logout' => const SessionState.unauthenticated(),
        'role' => tripSession(role: RideRole.rider),
        'blocked' => tripSession(blocked: true),
        'approval' => tripSession(approval: DriverApprovalStatus.pending),
        _ => tripSession(id: 'other'),
      });
      await pending;
      expect(h.view.phase, DriverFlowPhase.unauthorized);
      expect(h.view.trip, isNull);
      h.repository.replies.single
          .complete(DriverFlowResult(DriverFlowOutcome.simulated, h.result()));
      h.session.replace(tripSession());
      await h.settle();
      expect(h.view.phase, DriverFlowPhase.unauthorized);
      expect(h.view.trip, isNull);
    });
  }
  test('A-B-A scope cannot revive original generation', () async {
    final scope = h.container.read(tripScope);
    h.session.replace(tripSession(id: 'B'));
    h.container.read(tripScope.notifier).state =
        DriverAvailabilityScope(DriverFlowSession('B', 2), 'fake-vehicle');
    await h.settle();
    h.session.replace(tripSession());
    h.container.read(tripScope.notifier).state = scope;
    await h.settle();
    expect(h.view.phase, DriverFlowPhase.unauthorized);
  });
  test('old completion cannot unlock newer pending or UNKNOWN lifetime',
      () async {
    final old = h.act();
    final oldTimer = h.timers.single;
    h.container.read(tripScope.notifier).state = DriverAvailabilityScope(
        DriverFlowSession('fake-driver', 2), 'fake-vehicle');
    h.repository.current = driverFlowSnapshot(
        session: DriverFlowSession('fake-driver', 2), trip: previewTrip());
    await h.settle();
    await old;
    final pending = h.act();
    final command = h.view.command;
    h.repository.replies.first
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, h.result()));
    oldTimer();
    await h.settle();
    expect(h.view.progressStatus, DriverTripProgressStatus.pending);
    expect(h.view.command, same(command));
    h.timers.last();
    await pending;
    oldTimer();
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
  });
  test('repository replacement hides old Trip and retires pending', () async {
    final pending = h.act();
    final other = TripTestRepository();
    addTearDown(other.events.close);
    h.container.read(tripRepository.notifier).state = other;
    await h.settle();
    await pending;
    h.repository.replies.single
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, h.result()));
    await h.settle();
    expect(h.view.trip, isNull);
    expect(other.commands, isEmpty);
  });
  test(
      'captured UI callback cannot target an equivalent Trip in a new lifetime',
      () async {
    final displayed = h.view.trip!;
    final lifetime = h.view.lifetime;
    Future<void> callback() => h.controller.progress(
        displayed, DriverTripLifecycleStatus.driverArriving,
        lifetime: lifetime);
    h.container.read(tripScope.notifier).state = DriverAvailabilityScope(
        DriverFlowSession('fake-driver', 2), 'fake-vehicle');
    h.repository.current = driverFlowSnapshot(
        session: DriverFlowSession('fake-driver', 2), trip: previewTrip());
    await h.settle();
    final completion = callback();
    expect(h.repository.commands, isEmpty);
    await completion;
  });
  test('disposing container retires never-completing operation', () async {
    final d = TripHarness();
    await d.settle();
    final pending = d.act();
    await d.dispose();
    await pending;
    d.repository.replies.single
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, d.result()));
  });
  test(
      'existing scripted fake supports progression without authority promotion',
      () async {
    final fake = FakeDriverFlowRepository(
        driverFlowSnapshot(trip: previewTrip()),
        now: () => driverFlowTestTime);
    addTearDown(fake.dispose);
    h.container.read(tripScope.notifier).state = DriverAvailabilityScope(
        DriverFlowSession('fake-driver', 2), 'fake-vehicle');
    fake.replaceSession(DriverFlowSession('fake-driver', 2));
    fake.emit(driverFlowSnapshot(
        session: DriverFlowSession('fake-driver', 2),
        revision: 2,
        trip: previewTrip()));
    h.container.read(tripRepository.notifier).state = fake;
    await h.settle();
    fake.nextCommand = Future.value(DriverFlowResult(
        DriverFlowOutcome.simulated,
        driverFlowSnapshot(
            session: DriverFlowSession('fake-driver', 2),
            revision: 3,
            trip: previewTrip(
                version: 2,
                status: DriverTripLifecycleStatus.driverArriving))));
    await h.act();
    expect(fake.commands.single, isA<DriverFlowProgressTrip>());
    expect(h.view.progressStatus, DriverTripProgressStatus.simulated);
  });
  test(
      'B04 pending and UNKNOWN barrier cannot be bypassed by Trip observations',
      () async {
    final d = TripHarness(offerEnabled: true);
    addTearDown(d.dispose);
    await d.settle();
    d.repository
        .emit(driverFlowSnapshot(revision: 2, offer: driverFlowOffer()));
    final offers = d.container.read(driverIncomingOfferProvider.notifier);
    final decision = offers.decide(
        d.container.read(driverIncomingOfferProvider).offer!,
        DriverFlowOfferDecision.accept);
    expect(d.repository.commands, hasLength(1));
    d.repository.emit(driverFlowSnapshot(revision: 3, trip: previewTrip()));
    expect(d.view.offerBlocked, isTrue);
    expect(d.view.canProgress, isFalse);
    await d.controller.progress(
        d.view.trip!, DriverTripLifecycleStatus.driverArriving,
        lifetime: d.view.lifetime);
    expect(d.repository.commands, hasLength(1));
    d.repository.replies.single
        .complete(const DriverFlowResult(DriverFlowOutcome.unknown));
    await decision;
    expect(d.container.read(driverIncomingOfferProvider).decisionStatus,
        DriverOfferDecisionStatus.unknown);
    await d.controller.refresh();
    expect(d.view.offerBlocked, isTrue);
    expect(d.view.canProgress, isFalse);
    expect(d.repository.commands, hasLength(1));
  });
  for (final before in [
    DriverTripLifecycleStatus.accepted,
    DriverTripLifecycleStatus.driverArriving,
    DriverTripLifecycleStatus.driverArrived
  ]) {
    test('rapid repeated $before progression dispatches once', () async {
      h.repository.emit(driverFlowSnapshot(
          revision: 2, trip: previewTrip(version: 2, status: before)));
      final displayed = h.view;
      final pending = h.act();
      await h.controller.progress(displayed.trip!, displayed.nextStatus!,
          lifetime: displayed.lifetime);
      expect(h.repository.commands, hasLength(1));
      h.repository.replies.single
          .complete(const DriverFlowResult(DriverFlowOutcome.unknown));
      await pending;
      expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
    });
  }
  test('watch error after dispatch latches UNKNOWN before the reply', () async {
    final pending = h.act();
    h.repository.events.addError(StateError('watch lost'));
    expect(h.view.phase, DriverFlowPhase.unavailable);
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
    h.repository.replies.single
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, h.result()));
    await pending;
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
  });
  test(
      'lower version after a valid pending publication makes negative reply ambiguous',
      () async {
    final pending = h.act();
    h.repository.emit(h.result());
    h.repository.emit(driverFlowSnapshot(revision: 3, trip: previewTrip()));
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
    h.repository.replies.single
        .complete(const DriverFlowResult(DriverFlowOutcome.rejected));
    await pending;
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
  });
  test('external UNKNOWN cannot silently become ready through ordinary reads',
      () async {
    h.repository.emit(driverFlowSnapshot(
        revision: 2, phase: DriverFlowPhase.unknown, trip: previewTrip()));
    h.repository.emit(driverFlowSnapshot(revision: 3, trip: previewTrip()));
    await h.controller.refresh();
    expect(h.view.phase, DriverFlowPhase.unknown);
    expect(h.view.canProgress, isFalse);
  });
  test(
      'conflicting equal revision is rejected, equivalent publication is harmless',
      () {
    h.repository.emit(driverFlowSnapshot(trip: previewTrip()));
    expect(h.view.phase, DriverFlowPhase.ready);
    h.repository.emit(driverFlowSnapshot(
        trip: previewTrip(status: DriverTripLifecycleStatus.inProgress)));
    expect(h.view.phase, DriverFlowPhase.stale);
    expect(h.view.canProgress, isFalse);
  });
  test(
      'equivalent reconstructs during pending preserve exact command and token',
      () async {
    final pending = h.act();
    final command = h.view.command;
    h.repository.emit(driverFlowSnapshot(revision: 2, trip: previewTrip()));
    expect(h.view.command, same(command));
    expect(h.view.command!.idempotencyToken, command!.idempotencyToken);
    h.repository.replies.single.complete(
        DriverFlowResult(DriverFlowOutcome.simulated, h.result(revision: 3)));
    await pending;
    expect(h.view.progressStatus, DriverTripProgressStatus.simulated);
  });
  for (final outcome in [
    DriverFlowOutcome.rejected,
    DriverFlowOutcome.stale,
    DriverFlowOutcome.expired,
    DriverFlowOutcome.unsupported
  ]) {
    test('definitive $outcome does not replay original target version',
        () async {
      final pending = h.act();
      h.repository.replies.single.complete(DriverFlowResult(outcome));
      await pending;
      expect(h.view.progressStatus, isNot(DriverTripProgressStatus.unknown));
      h.repository.emit(driverFlowSnapshot(revision: 2, trip: previewTrip()));
      await h.controller.progress(
          h.view.trip!, DriverTripLifecycleStatus.driverArriving,
          lifetime: h.view.lifetime);
      expect(h.repository.commands, hasLength(1));
    });
  }
  test('read failure is unavailable and a newer read-only observation recovers',
      () async {
    h.repository.nextRead = Future.error(StateError('read lost'));
    await h.controller.refresh();
    expect(h.view.phase, DriverFlowPhase.unavailable);
    h.repository.current =
        h.result(revision: 4, status: DriverTripLifecycleStatus.inProgress);
    await h.controller.refresh();
    expect(h.view.phase, DriverFlowPhase.ready);
    expect(h.view.trip!.status, DriverTripLifecycleStatus.inProgress);
    expect(h.repository.commands, isEmpty);
  });
  test(
      'authorization observation hides Trip and cannot be cleared by later ready',
      () {
    h.repository.emit(driverFlowSnapshot(
        revision: 2, phase: DriverFlowPhase.unauthorized, trip: previewTrip()));
    h.repository.emit(h.result(revision: 3));
    expect(h.view.phase, DriverFlowPhase.unauthorized);
    expect(h.view.trip, isNull);
  });
  test('late read after fresh scope cannot populate replacement owner',
      () async {
    final read = Completer<DriverFlowResult>();
    h.repository.nextRead = read.future;
    final refresh = h.controller.refresh();
    h.container.read(tripScope.notifier).state = DriverAvailabilityScope(
        DriverFlowSession('fake-driver', 2), 'fake-vehicle');
    h.repository.current =
        driverFlowSnapshot(session: DriverFlowSession('fake-driver', 2));
    await h.settle();
    read.complete(DriverFlowResult(DriverFlowOutcome.observed, h.result()));
    await refresh;
    expect(h.view.trip, isNull);
    expect(h.repository.commands, isEmpty);
  });
  test('B04 observation does not reset a pending B05 command or UNKNOWN',
      () async {
    final pending = h.act();
    final command = h.view.command;
    final lifetime = h.view.lifetime;
    h.repository.emit(driverFlowSnapshot(revision: 2, trip: previewTrip()));
    expect(h.view.command, same(command));
    expect(h.view.lifetime, lifetime);
    expect(h.view.progressStatus, DriverTripProgressStatus.pending);
    h.timers.single();
    await pending;
    h.repository.emit(h.result(revision: 3));
    expect(h.view.command, same(command));
    expect(h.view.lifetime, lifetime);
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
  });
  test(
      'B04 uncertain decline blocks Trip progression without a second decision owner',
      () async {
    final d = TripHarness(offerEnabled: true);
    addTearDown(d.dispose);
    await d.settle();
    d.repository
        .emit(driverFlowSnapshot(revision: 2, offer: driverFlowOffer()));
    final decision = d.container
        .read(driverIncomingOfferProvider.notifier)
        .decide(d.container.read(driverIncomingOfferProvider).offer!,
            DriverFlowOfferDecision.decline);
    expect(d.container.read(driverIncomingOfferProvider).decisionStatus,
        DriverOfferDecisionStatus.pendingDecline);
    d.repository.emit(driverFlowSnapshot(revision: 3, trip: previewTrip()));
    d.repository.replies.single
        .complete(const DriverFlowResult(DriverFlowOutcome.unknown));
    await decision;
    await d.controller.progress(
        d.view.trip!, DriverTripLifecycleStatus.driverArriving,
        lifetime: d.view.lifetime);
    expect(d.view.offerBlocked, isTrue);
    expect(d.view.canProgress, isFalse);
    expect(d.repository.commands, hasLength(1));
    expect(d.repository.commands.single, isA<DriverFlowDecideOffer>());
  });
}
