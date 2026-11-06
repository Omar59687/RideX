import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/canonical_trip_reconciliation.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/providers/driver_cash_completion_providers.dart';
import 'package:ridex/core/repositories/driver_trip_completion_repository.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_incoming_offer_controller.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_trip_presentation_controller.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';
import 'driver_trip_presentation_controller_test.dart'
    show TripHarness, previewTrip;
import 'helpers/fake_driver_flow_repository.dart';

// Read-only characterization of EXISTING Phase 6 interfaces. Never mounted in UI.
class _NoCanonicalSource implements CanonicalDriverCompletionSource {
  int calls = 0;
  @override
  Future<CanonicalDriverCompletionContext?> load() async {
    calls++;
    return null;
  }
}

class _FixtureCanonicalSource implements CanonicalDriverCompletionSource {
  @override
  Future<CanonicalDriverCompletionContext?> load() async =>
      CanonicalDriverCompletionContext(
          driverId: '11111111-1111-4111-8111-111111111111',
          command: DriverCompleteTripCommand(
              tripId: '22222222-2222-4222-8222-222222222222',
              expectedTripVersion: 4,
              idempotencyKey: 'original-command'));
}

class _ExistingStaging implements DriverCompletionStagingGateway {
  @override
  Future<CoordinatorStagingDecision> stage(
          CanonicalDriverCompletionContext context) async =>
      StagingExistingEvidence(context.command);
}

class _NoStaging implements DriverCompletionStagingGateway {
  int calls = 0;
  @override
  Future<CoordinatorStagingDecision> stage(
      CanonicalDriverCompletionContext context) async {
    calls++;
    return const StagingBlocked(StagingBlockReason.invalidIdentity);
  }
}

void main() {
  late TripHarness h;
  setUp(() async {
    h = TripHarness();
    await h.settle();
  });
  tearDown(() => h.dispose());

  for (final status in DriverTripLifecycleStatus.values) {
    test('B06 $status cannot complete through UI boundary or progression',
        () async {
      h.repository.emit(driverFlowSnapshot(
          revision: 2, trip: previewTrip(version: 2, status: status)));
      expect(h.view.completionGate.canComplete, isFalse);
      expect(h.controller.requestCompletion(), DriverFlowOutcome.unsupported);
      await h.controller.progress(
          h.view.trip!, DriverTripLifecycleStatus.completed,
          lifetime: h.view.lifetime);
      expect(h.repository.commands, isEmpty);
      expect(h.view.trip!.status, status);
    });
  }
  test('B06 actual production defaults cannot dispatch completion', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(driverTripSimulationEnabledProvider), isFalse);
    expect(c.read(driverTripPresentationProvider).completionGate.canComplete,
        isFalse);
    expect(c.read(driverTripPresentationProvider.notifier).requestCompletion(),
        DriverFlowOutcome.unsupported);
    expect(c.exists(driverCashCompletionProvider), isFalse);
  });
  test(
      'B06 required evidence is an immutable checklist, never an activation flag',
      () {
    final gate = h.view.completionGate;
    expect(gate.requiredPhase6Gates, ['P6-R01', 'P6-R02', 'P6-R03', 'P6-R07']);
    expect(gate.requiredEvidence,
        containsAll(DriverTripCompletionRequirement.values));
    expect(
        () => gate.requiredPhase6Gates.add('approved'), throwsUnsupportedError);
    expect(() => gate.requiredEvidence.clear(), throwsUnsupportedError);
    expect(gate.canComplete, isFalse);
    expect(h.controller.requestCompletion(), DriverFlowOutcome.unsupported);
    expect(h.repository.commands, isEmpty);
  });
  test(
      'B06 rapid direct completion attempts are pure and dispatch zero commands',
      () {
    final before = h.view;
    for (var i = 0; i < 20; i++) {
      expect(h.controller.requestCompletion(), DriverFlowOutcome.unsupported);
    }
    expect(h.view, same(before));
    expect(h.repository.commands, isEmpty);
  });
  test(
      'B06 UNKNOWN and token survive completion attempts, read and late success',
      () async {
    final pending = h.act();
    final command = h.view.command;
    h.timers.single();
    await pending;
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
    expect(h.controller.requestCompletion(), DriverFlowOutcome.unsupported);
    h.repository.emit(h.result());
    await h.controller.refresh();
    h.repository.replies.single
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, h.result()));
    await h.settle();
    expect(h.view.progressStatus, DriverTripProgressStatus.unknown);
    expect(h.view.command, same(command));
    expect(h.view.completionGate.canComplete, isFalse);
    expect(h.repository.commands, hasLength(1));
    expect(h.repository.commands.single, isA<DriverFlowProgressTrip>());
  });
  test('B06 completion stop cannot unlock a pending legal progression',
      () async {
    final pending = h.act();
    final command = h.view.command;
    h.controller.requestCompletion();
    await h.controller.refresh();
    expect(h.view.command, same(command));
    expect(h.view.progressStatus, DriverTripProgressStatus.pending);
    expect(h.repository.commands, hasLength(1));
    h.repository.replies.single
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, h.result()));
    await pending;
    expect(h.view.progressStatus, DriverTripProgressStatus.simulated);
    expect(h.view.completionGate.canComplete, isFalse);
  });
  for (final decision in DriverFlowOfferDecision.values) {
    test('B06 B04 $decision pending and UNKNOWN cannot bypass completion stop',
        () async {
      final d = TripHarness(offerEnabled: true);
      addTearDown(d.dispose);
      await d.settle();
      d.repository
          .emit(driverFlowSnapshot(revision: 2, offer: driverFlowOffer()));
      final pending = d.container
          .read(driverIncomingOfferProvider.notifier)
          .decide(
              d.container.read(driverIncomingOfferProvider).offer!, decision);
      expect(d.controller.requestCompletion(), DriverFlowOutcome.unsupported);
      expect(d.view.offerBlocked, isTrue);
      d.repository.replies.single
          .complete(const DriverFlowResult(DriverFlowOutcome.unknown));
      await pending;
      d.repository.emit(driverFlowSnapshot(revision: 3, trip: previewTrip()));
      expect(d.controller.requestCompletion(), DriverFlowOutcome.unsupported);
      expect(d.view.offerBlocked, isTrue);
      expect(d.repository.commands, hasLength(1));
      expect(d.repository.commands.single, isA<DriverFlowDecideOffer>());
    });
  }
  test(
      'B06 refreshed simulated completed UUID does not instantiate canonical authority',
      () async {
    final d = TripHarness();
    addTearDown(d.dispose);
    d.repository.current = driverFlowSnapshot(
        trip: previewTrip(
            id: '11111111-1111-4111-8111-111111111111',
            status: DriverTripLifecycleStatus.completed));
    await d.settle();
    await d.controller.refresh();
    expect(d.view.trip!.status, DriverTripLifecycleStatus.completed);
    expect(d.view.canProgress, isFalse);
    expect(d.controller.requestCompletion(), DriverFlowOutcome.unsupported);
    expect(d.container.exists(driverCashCompletionProvider), isFalse);
    expect(d.repository.commands, isEmpty);
  });
  test(
      'B06 B01 public progression rejects completion without widening the contract',
      () {
    expect(
        () => DriverFlowProgressTrip(
            session: DriverFlowSession('fake-driver', 1),
            targetId: 'demo-trip',
            expectedVersion: 1,
            idempotencyToken: 'original',
            status: DriverTripLifecycleStatus.completed),
        throwsArgumentError);
    expect(h.repository.commands, isEmpty);
  });
  test(
      'B06 handoff existing canonical coordinator requires source evidence before staging',
      () async {
    final staging = _NoStaging();
    final financial = FakeDriverTripCompletionRepository();
    final coordinator = DriverCompletionCoordinator(
        canonicalSource: _NoCanonicalSource(),
        stagingGateway: staging,
        repository: financial,
        sessionReader: () async => const DriverCompletionSessionSnapshot(
            driverId: '11111111-1111-4111-8111-111111111111',
            epoch: 1,
            isApprovedDriver: true));
    addTearDown(coordinator.dispose);
    expect(await coordinator.complete(), isA<CoordinatorNoContext>());
    expect(staging.calls, 0);
    expect(financial.callCount, 0);
  });
  test(
      'B06 handoff canonical command rejects absent ID, version or original token',
      () {
    for (final id in ['demo-trip', '']) {
      expect(
          () => DriverCompleteTripCommand(
              tripId: id, expectedTripVersion: 1, idempotencyKey: 'original'),
          throwsArgumentError);
    }
    expect(
        () => DriverCompleteTripCommand(
            tripId: '11111111-1111-4111-8111-111111111111',
            expectedTripVersion: 0,
            idempotencyKey: 'original'),
        throwsArgumentError);
    expect(
        () => DriverCompleteTripCommand(
            tripId: '11111111-1111-4111-8111-111111111111',
            expectedTripVersion: 1,
            idempotencyKey: ''),
        throwsArgumentError);
    expect(h.repository.commands, isEmpty);
  });
  test(
      'B06 handoff canonical completed truth is not a verified receipt or payment',
      () {
    final trip = CanonicalTripEvidence(
        tripId: '11111111-1111-4111-8111-111111111111',
        driverId: '22222222-2222-4222-8222-222222222222',
        status: DriverTripLifecycleStatus.completed,
        backendVersion: 4,
        paymentMethod: 'cash');
    final result = DriverCompleteTripResult(
        tripId: trip.tripId,
        status: trip.status,
        backendVersion: trip.backendVersion);
    expect(result.isCompleted, isTrue);
    expect(result.receiptVerified, isFalse);
    expect(result.receiptNumber, isNull);
    expect(h.view.completionGate.canComplete, isFalse);
    expect(h.repository.commands, isEmpty);
  });
  test('B06 unverified session cannot load canonical context or stage',
      () async {
    final source = _NoCanonicalSource();
    final staging = _NoStaging();
    final financial = FakeDriverTripCompletionRepository();
    final coordinator = DriverCompletionCoordinator(
        canonicalSource: source,
        stagingGateway: staging,
        repository: financial,
        sessionReader: () async => const DriverCompletionSessionSnapshot(
            driverId: null, epoch: 1, isApprovedDriver: false));
    addTearDown(coordinator.dispose);
    expect(await coordinator.complete(), isA<CoordinatorSessionInvalid>());
    expect(source.calls, 0);
    expect(staging.calls, 0);
    expect(financial.callCount, 0);
  });
  test('B06 missing durable acknowledgement blocks existing canonical handoff',
      () async {
    final financial = FakeDriverTripCompletionRepository();
    final staging = _NoStaging();
    final coordinator = DriverCompletionCoordinator(
        canonicalSource: _FixtureCanonicalSource(),
        stagingGateway: staging,
        repository: financial,
        sessionReader: () async => const DriverCompletionSessionSnapshot(
            driverId: '11111111-1111-4111-8111-111111111111',
            epoch: 1,
            isApprovedDriver: true));
    addTearDown(coordinator.dispose);
    expect(await coordinator.complete(), isA<CoordinatorBlocked>());
    expect(staging.calls, 1);
    expect(financial.callCount, 0);
  });
  test('B06 existing durable evidence is reconciliation-only, never replayed',
      () async {
    final financial = FakeDriverTripCompletionRepository();
    final coordinator = DriverCompletionCoordinator(
        canonicalSource: _FixtureCanonicalSource(),
        stagingGateway: _ExistingStaging(),
        repository: financial,
        sessionReader: () async => const DriverCompletionSessionSnapshot(
            driverId: '11111111-1111-4111-8111-111111111111',
            epoch: 1,
            isApprovedDriver: true));
    addTearDown(coordinator.dispose);
    await coordinator.complete();
    await coordinator.complete();
    expect(financial.callCount, 0);
  });
  test('B06 fake verified receipt object cannot activate preview or dispatch',
      () {
    final fakeResult = DriverCompleteTripResult(
        tripId: '11111111-1111-4111-8111-111111111111',
        status: DriverTripLifecycleStatus.completed,
        receiptVerified: true,
        receiptNumber: 'DEMO-NOT-EVIDENCE');
    final fakeFinancial =
        FakeDriverTripCompletionRepository(successResult: fakeResult);
    expect(h.controller.requestCompletion(), DriverFlowOutcome.unsupported);
    expect(h.view.completionGate.canComplete, isFalse);
    expect(fakeFinancial.callCount, 0);
    expect(h.repository.commands, isEmpty);
  });
  test('B06 revoked session stays hidden after direct blocked completion calls',
      () {
    final view = h.view;
    h.repository.emit(
        driverFlowSnapshot(revision: 2, phase: DriverFlowPhase.unauthorized));
    expect(h.controller.requestCompletion(), DriverFlowOutcome.unsupported);
    expect(h.view.phase, DriverFlowPhase.unauthorized);
    expect(h.view.trip, isNull);
    expect(h.controller.canPreview(view.trip!, view.session!, view.lifetime),
        isFalse);
    expect(h.repository.commands, isEmpty);
  });
}
