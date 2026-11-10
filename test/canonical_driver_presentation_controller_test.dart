import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/driver_flow/data/canonical_driver_repository.dart';
import 'package:ridex/features/driver_flow/domain/canonical_driver_delivery.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import 'package:ridex/features/driver_flow/presentation/providers/canonical_driver_presentation_controller.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_flow_repository_provider.dart';
import 'helpers/canonical_driver_presentation_harness.dart';
import 'helpers/fake_canonical_driver_port.dart' as f;

void main() {
  late B08Harness h;
  setUp(() => h = B08Harness());
  tearDown(() => h.dispose());

  test(
      'production defaults stay null, unavailable, and separate from simulated source',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(driverCanonicalPresentationProvider), isNull);
    final simulated = container.read(driverFlowRepositoryProvider);
    expect((await simulated.read(DriverFlowSession(f.driverId, 1))).outcome,
        DriverFlowOutcome.unavailable);
    expect(DriverFlowSource.values,
        [DriverFlowSource.simulated, DriverFlowSource.unconfigured]);
  });
  test('positive hint causes authorized canonical offer projection only',
      () async {
    await h.offer();
    expect(h.view.phase, CanonicalDriverPresentationPhase.offer);
    expect(h.view.offer!.id, f.offerId);
    expect(h.view.offer!.version, 1);
    expect(h.view.trip, isNull);
    expect(h.view.canDecide, isTrue);
    expect(h.port.reads, contains('offer'));
    expect(h.port.calls, isEmpty);
  });
  test('controller itself defaults disabled without subscribing', () async {
    final controller = CanonicalDriverPresentationController(
        repository: h.repository,
        session: h.session,
        authorityInvalidations: h.authority,
        delivery: h.delivery);
    addTearDown(controller.dispose);
    expect(controller.view.phase, CanonicalDriverPresentationPhase.disabled);
    expect(controller.view.canDecide, isFalse);
    expect(h.delivery.listeners, 1); // Only h's explicitly enabled controller.
  });
  test('missing delivery fails closed even on explicit refresh', () async {
    await h.dispose();
    h = B08Harness(deliveryPresent: false);
    await h.controller.refresh();
    expect(h.view.phase, CanonicalDriverPresentationPhase.missingDelivery);
    expect(h.port.reads, isEmpty);
    expect(h.port.calls, isEmpty);
  });
  for (final target in ['driver_id', 'id']) {
    test('foreign offer $target is hidden and unauthorized', () async {
      h.port.offer![target] = f.otherId;
      await h.offer();
      expect(h.view.phase, CanonicalDriverPresentationPhase.unauthorized);
      expect(h.view.offer, isNull);
      expect(h.view.canDecide, isFalse);
      expect(h.port.calls, isEmpty);
    });
  }
  test('backend rejected role hides all references', () async {
    h.port.user!['role'] = 'rider';
    await h.offer();
    expect(h.view.phase, CanonicalDriverPresentationPhase.unauthorized);
    expect(h.view.offer, isNull);
  });
  test('reservation mismatch is stale and cannot become actionable', () async {
    h.port.availability!['reserved_booking_request_id'] = f.otherId;
    await h.offer();
    expect(h.view.phase, CanonicalDriverPresentationPhase.stale);
    expect(h.view.offer, isNull);
    expect(h.view.canDecide, isFalse);
  });
  test('advisory ID never overrides returned canonical identity', () async {
    h.delivery.connect();
    h.delivery.offer(f.otherId);
    await h.flush();
    expect(h.view.phase, CanonicalDriverPresentationPhase.unauthorized);
    expect(h.port.calls, isEmpty);
  });
  test('invalid locator fails closed without command', () async {
    h.delivery.connect();
    h.delivery.offer('demo-offer');
    await h.flush();
    expect(h.view.phase, CanonicalDriverPresentationPhase.stale);
    expect(h.port.calls, isEmpty);
  });
  test('duplicate observations never generate a key or dispatch automatically',
      () async {
    await h.offer();
    final previous = h.view;
    h.delivery.offer();
    await h.flush();
    expect(h.view.offer!.version, 1);
    expect(h.keys, 0);
    expect(h.port.calls, isEmpty);
    await h.controller.decide(previous, CanonicalOfferDecision.accept);
    expect(h.port.calls, isEmpty); // Old publication callback is retired.
  });
  test('inclusive deadline expires monotonically after clock tick', () async {
    await h.offer();
    final previous = h.view;
    h.now = h.view.offer!.expiresAt;
    h.controller.tick();
    expect(h.view.phase, CanonicalDriverPresentationPhase.expired);
    expect(h.view.canDecide, isFalse);
    h.now = f.now;
    expect(h.view.phase, CanonicalDriverPresentationPhase.expired);
    await h.controller.decide(previous, CanonicalOfferDecision.accept);
    expect(h.keys, 0);
    expect(h.port.calls, isEmpty);
  });
  test('older or duplicate delivery revision cannot replace latest identity',
      () async {
    await h.offer();
    h.delivery.events.add(const CanonicalDriverOfferHint(1, f.otherId));
    h.delivery.events
        .add(const CanonicalDriverConnectionHint(2, connected: false));
    await h.flush();
    expect(h.view.phase, CanonicalDriverPresentationPhase.offer);
    expect(h.view.offer!.id, f.offerId);
    expect(h.port.calls, isEmpty);
  });
  test('older pending read cannot publish after disconnection', () async {
    final entered = Completer<void>(), gate = Completer<void>();
    h.port.beforeRead = (name) async {
      if (name == 'offer') {
        entered.complete();
        await gate.future;
      }
    };
    h.delivery.connect();
    h.delivery.offer();
    await entered.future;
    h.delivery.disconnect();
    gate.complete();
    await h.flush();
    expect(h.view.phase, CanonicalDriverPresentationPhase.disconnected);
    expect(h.view.offer, isNull);
    expect(h.port.calls, isEmpty);
  });
  test('disconnect hides captured view and reconnect rereads canonically',
      () async {
    await h.offer();
    final prior = h.view;
    final count = h.port.reads.length;
    h.delivery.disconnect();
    expect(prior.offer, isNull);
    expect(h.view.offer, isNull);
    h.delivery.connect();
    await h.flush();
    expect(h.view.phase, CanonicalDriverPresentationPhase.offer);
    expect(h.port.reads.length, greaterThan(count));
    expect(h.port.calls, isEmpty);
  });
  test('late startup read cannot overwrite newer canonical offer read',
      () async {
    final entered = Completer<void>(), gate = Completer<void>();
    var first = true;
    h.port.beforeRead = (name) async {
      if (name == 'availability' && first) {
        first = false;
        entered.complete();
        await gate.future;
      }
    };
    h.delivery.connect();
    await entered.future;
    h.delivery.offer();
    await h.flush();
    expect(h.view.offer!.id, f.offerId);
    gate.complete();
    await h.flush();
    expect(h.view.phase, CanonicalDriverPresentationPhase.offer);
    expect(h.view.offer!.id, f.offerId);
    expect(h.port.calls, isEmpty);
  });
  test('reentrant pending-publication disconnect prevents command handoff',
      () async {
    await h.offer();
    h.controller.addListener(() {
      if (h.view.phase == CanonicalDriverPresentationPhase.pending) {
        h.delivery.disconnect();
      }
    });
    await h.controller.decide(h.view, CanonicalOfferDecision.accept);
    expect(h.port.calls, isEmpty);
    expect(h.keys, 0);
  });
  test('reentrant pending-publication replacement prevents old offer command',
      () async {
    await h.offer();
    var changed = false;
    h.controller.addListener(() {
      if (!changed &&
          h.view.phase == CanonicalDriverPresentationPhase.pending) {
        changed = true;
        h.delivery.offer(f.otherId);
      }
    });
    await h.controller.decide(h.view, CanonicalOfferDecision.accept);
    expect(h.port.calls, isEmpty);
    expect(h.keys, 0);
    expect(h.view.phase, CanonicalDriverPresentationPhase.stale);
  });
  test('offer version conflict hides canonical action projection', () async {
    await h.offer();
    h.port.offer!['version'] = 3;
    h.delivery.offer();
    await h.flush();
    h.port.offer!['version'] = 2;
    h.delivery.offer();
    await h.flush();
    expect(h.view.phase, CanonicalDriverPresentationPhase.stale);
    expect(h.view.offer, isNull);
    expect(h.port.calls, isEmpty);
  });
  test('stream error disconnects and hides data', () async {
    await h.offer();
    h.delivery.events.addError(StateError('private-error'), StackTrace.current);
    expect(h.view.phase, CanonicalDriverPresentationPhase.disconnected);
    expect(h.view.offer, isNull);
  });
  test('stream completion disconnects', () async {
    await h.offer();
    await h.delivery.events.close();
    expect(h.view.phase, CanonicalDriverPresentationPhase.disconnected);
    expect(h.view.offer, isNull);
  });
  test('accept publishes Trip only after extra authorized canonical reread',
      () async {
    await h.offer();
    h.port.onCommand = (_) async {
      h.port.accept();
      return null;
    };
    await h.controller.decide(h.view, CanonicalOfferDecision.accept);
    expect(h.view.phase, CanonicalDriverPresentationPhase.trip);
    expect(h.view.trip!.id, f.tripId);
    expect(h.port.reads, contains('trip'));
    expect(h.port.calls, [('accept', f.offerId, 1, 'b08-original-1')]);
    expect(h.keys, 1);
  });
  test('canonical availability discovers own Trip, not arbitrary Trip hint',
      () async {
    h.port.accept();
    h.delivery.connect();
    await h.flush();
    expect(h.view.phase, CanonicalDriverPresentationPhase.trip);
    expect(h.view.trip!.id, f.tripId);
    final count = h.port.reads.length;
    h.delivery.trip(f.otherId);
    await h.flush();
    expect(h.port.reads.length, count);
    expect(h.view.trip!.id, f.tripId);
  });
  test(
      'exact Trip hint rereads current status/version, never supplies status itself',
      () async {
    h.port.accept();
    h.delivery.connect();
    await h.flush();
    h.port.trip = {...f.tripRow(), 'version': 2, 'status': 'driverArriving'};
    h.delivery.trip();
    await h.flush();
    expect(h.view.trip!.version, 2);
    expect(h.view.trip!.status.backendValue, 'driverArriving');
    expect(h.port.calls, isEmpty);
  });
  test('terminal Trip cannot resurrect on newer canonical row', () async {
    h.port.accept();
    h.delivery.connect();
    await h.flush();
    h.port.trip = {...f.tripRow(), 'version': 2, 'status': 'completed'};
    h.delivery.trip();
    await h.flush();
    expect(h.view.trip!.status.backendValue, 'completed');
    h.port.trip = {...f.tripRow(), 'version': 3};
    h.delivery.trip();
    await h.flush();
    expect(h.view.phase, CanonicalDriverPresentationPhase.stale);
    expect(h.view.trip, isNull);
  });
  test('Trip version regression becomes stale', () async {
    h.port.accept();
    h.port.trip!['version'] = 3;
    h.delivery.connect();
    await h.flush();
    h.port.trip!['version'] = 2;
    h.delivery.trip();
    await h.flush();
    expect(h.view.phase, CanonicalDriverPresentationPhase.stale);
    expect(h.view.trip, isNull);
  });
  test(
      'lost response is UNKNOWN; ordinary reads/events cannot reconcile or replay',
      () async {
    await h.offer();
    h.port.onCommand = (_) async => throw StateError('lost');
    await h.controller.decide(h.view, CanonicalOfferDecision.accept);
    expect(h.view.phase, CanonicalDriverPresentationPhase.unknown);
    h.port.accept();
    h.delivery.offer();
    h.delivery.trip();
    h.delivery.disconnect();
    h.delivery.connect();
    await h.controller.refresh();
    await h.flush();
    expect(h.view.phase, CanonicalDriverPresentationPhase.unknown);
    expect(h.port.calls, hasLength(1));
    expect(h.keys, 1);
    await h.controller.reconcile();
    expect(h.view.phase, CanonicalDriverPresentationPhase.trip);
    expect(h.port.calls, hasLength(1));
    expect(h.keys, 1);
  });
  test('missing canonical evidence keeps explicit recovery UNKNOWN', () async {
    await h.offer();
    await h.controller.decide(h.view, CanonicalOfferDecision.accept);
    await h.controller.reconcile();
    expect(h.view.phase, CanonicalDriverPresentationPhase.unknown);
    expect(h.port.calls, hasLength(1));
  });
  test('duplicate action during pending only hands one key/command to B07',
      () async {
    await h.offer();
    final displayed = h.view;
    final entered = Completer<void>(), gate = Completer<void>();
    h.port.onCommand = (_) async {
      entered.complete();
      await gate.future;
      h.port.accept();
      return null;
    };
    final first = h.controller.decide(displayed, CanonicalOfferDecision.accept);
    await entered.future;
    await h.controller.decide(displayed, CanonicalOfferDecision.accept);
    gate.complete();
    await first;
    expect(h.port.calls, hasLength(1));
    expect(h.keys, 1);
  });
  test('expiry while command pending remains UNKNOWN despite late success',
      () async {
    await h.offer();
    final deadline = h.view.offer!.expiresAt;
    final entered = Completer<void>(), gate = Completer<void>();
    h.port.onCommand = (_) async {
      entered.complete();
      await gate.future;
      h.port.accept();
      return null;
    };
    final pending = h.controller.decide(h.view, CanonicalOfferDecision.accept);
    await entered.future;
    h.now = deadline;
    h.controller.tick();
    gate.complete();
    await pending;
    expect(h.view.phase, CanonicalDriverPresentationPhase.unknown);
    expect(h.port.calls, hasLength(1));
  });
  test(
      'disconnect while command pending retains UNKNOWN after late reply and reconnect',
      () async {
    await h.offer();
    final entered = Completer<void>(), gate = Completer<void>();
    h.port.onCommand = (_) async {
      entered.complete();
      await gate.future;
      h.port.accept();
      return null;
    };
    final pending = h.controller.decide(h.view, CanonicalOfferDecision.accept);
    await entered.future;
    h.delivery.disconnect();
    gate.complete();
    await pending;
    h.delivery.connect();
    await h.flush();
    expect(h.view.phase, CanonicalDriverPresentationPhase.unknown);
    expect(h.view.trip, isNull);
    expect(h.port.calls, hasLength(1));
  });
  for (final invalidation in [
    'expiry',
    'expiry-without-tick',
    'disconnect-reconnect'
  ]) {
    test(
        'final acceptance Trip read retains pending ownership across $invalidation',
        () async {
      await h.offer();
      final deadline = h.view.offer!.expiresAt;
      h.port.onCommand = (_) async {
        h.port.accept();
        return null;
      };
      final entered = Completer<void>(), gate = Completer<void>();
      h.port.beforeRead = (name) async {
        if (name == 'trip') {
          if (!entered.isCompleted) entered.complete();
          await gate.future;
        }
      };
      final publications = <CanonicalDriverPresentationPhase>[];
      h.controller.addListener(() => publications.add(h.view.phase));
      final pending =
          h.controller.decide(h.view, CanonicalOfferDecision.accept);
      await entered.future;
      if (invalidation.startsWith('expiry')) {
        h.now = deadline;
        if (invalidation == 'expiry') h.controller.tick();
      } else {
        h.delivery.disconnect();
        h.delivery.connect();
      }
      final ordinaryRefresh = h.controller.refresh();
      await h.flush();
      final intermediate = h.view.phase;
      gate.complete();
      await pending;
      await ordinaryRefresh;
      expect(
          intermediate,
          invalidation == 'expiry-without-tick'
              ? CanonicalDriverPresentationPhase.pending
              : CanonicalDriverPresentationPhase.unknown);
      expect(h.view.phase, CanonicalDriverPresentationPhase.unknown);
      expect(
          publications, isNot(contains(CanonicalDriverPresentationPhase.trip)));
      expect(h.port.calls, hasLength(1));
      expect(h.keys, 1);
    });
  }
  for (final decision in CanonicalOfferDecision.values) {
    test('retired connection cannot publish $decision recovery', () async {
      await h.offer();
      await h.controller.decide(h.view, decision);
      expect(h.view.phase, CanonicalDriverPresentationPhase.unknown);
      if (decision == CanonicalOfferDecision.accept) {
        h.port.accept();
      } else {
        h.port.decline();
      }
      final entered = Completer<void>(), gate = Completer<void>();
      h.port.beforeRead = (name) async {
        if (name == 'booking-trip') {
          entered.complete();
          await gate.future;
        }
      };
      final publications = <CanonicalDriverPresentationPhase>[];
      h.controller.addListener(() => publications.add(h.view.phase));
      final recovery = h.controller.reconcile();
      await entered.future;
      h.delivery.disconnect();
      h.delivery.connect();
      await h.flush();
      gate.complete();
      await recovery;
      expect(h.view.phase, CanonicalDriverPresentationPhase.unknown);
      expect(
          publications, isNot(contains(CanonicalDriverPresentationPhase.trip)));
      expect(publications,
          isNot(contains(CanonicalDriverPresentationPhase.declined)));
      h.port.beforeRead = null;
      await h.controller.reconcile();
      expect(
          h.view.phase,
          decision == CanonicalOfferDecision.accept
              ? CanonicalDriverPresentationPhase.trip
              : CanonicalDriverPresentationPhase.declined);
      expect(h.port.calls, hasLength(1));
      expect(h.keys, 1);
    });
  }
  for (final decision in CanonicalOfferDecision.values) {
    test(
        'reentrant connection retirement aborts $decision recovery before reads',
        () async {
      await h.offer();
      await h.controller.decide(h.view, decision);
      if (decision == CanonicalOfferDecision.accept) {
        h.port.accept();
      } else {
        h.port.decline();
      }
      var retired = false;
      h.controller.addListener(() {
        if (!retired &&
            h.view.phase == CanonicalDriverPresentationPhase.unknown &&
            !h.view.canReconcile) {
          retired = true;
          h.delivery.disconnect();
          h.delivery.connect();
        }
      });
      final reads = h.port.reads.length;
      await h.controller.reconcile();
      expect(retired, isTrue);
      expect(h.port.reads.length, reads);
      expect(h.view.phase, CanonicalDriverPresentationPhase.unknown);
      await h.controller.reconcile();
      expect(
          h.view.phase,
          decision == CanonicalOfferDecision.accept
              ? CanonicalDriverPresentationPhase.trip
              : CanonicalDriverPresentationPhase.declined);
      expect(h.port.calls, hasLength(1));
    });
  }
  test(
      'explicit accepted recovery retains UNKNOWN through final Trip read invalidation',
      () async {
    await h.offer();
    await h.controller.decide(h.view, CanonicalOfferDecision.accept);
    h.port.accept();
    final entered = Completer<void>(), gate = Completer<void>();
    h.port.beforeRead = (name) async {
      if (name == 'trip') {
        entered.complete();
        await gate.future;
      }
    };
    final publications = <CanonicalDriverPresentationPhase>[];
    h.controller.addListener(() => publications.add(h.view.phase));
    final recovery = h.controller.reconcile();
    await entered.future;
    h.delivery.disconnect();
    h.delivery.connect();
    final ordinary = h.controller.refresh();
    await h.flush();
    final intermediate = h.view.phase;
    gate.complete();
    await recovery;
    await ordinary;
    expect(intermediate, CanonicalDriverPresentationPhase.unknown);
    expect(h.view.phase, CanonicalDriverPresentationPhase.unknown);
    expect(
        publications, isNot(contains(CanonicalDriverPresentationPhase.trip)));
    h.port.beforeRead = null;
    await h.controller.reconcile();
    expect(h.view.phase, CanonicalDriverPresentationPhase.trip);
    expect(h.port.calls, hasLength(1));
    expect(h.keys, 1);
  });
  for (final kind in [
    'logout',
    'same-driver',
    'foreign-driver',
    'role',
    'blocked',
    'approval',
    'sdk-authority'
  ]) {
    test('$kind replacement hides captured references and prevents late read',
        () async {
      await h.offer();
      final prior = h.view;
      switch (kind) {
        case 'logout':
          h.session.value = const SessionState.unauthenticated();
        case 'same-driver':
          h.session.value = driverSession();
        case 'foreign-driver':
          h.session.value = driverSession(id: f.otherId);
        case 'role':
          h.session.value = driverSession(role: RideRole.rider);
        case 'blocked':
          h.session.value = driverSession(blocked: true);
        case 'approval':
          h.session.value =
              driverSession(approval: DriverApprovalStatus.pending);
        case 'sdk-authority':
          h.port.sessionIdentity = Object();
          h.authority.value++;
      }
      expect(prior.offer, isNull);
      expect(h.view.offer, isNull);
      expect(h.view.phase, CanonicalDriverPresentationPhase.unauthorized);
      await h.controller.decide(prior, CanonicalOfferDecision.accept);
      expect(h.port.calls, isEmpty);
    });
  }
  test(
      'disposal during command hides late result and borrowed repository remains uncertain',
      () async {
    await h.offer();
    final prior = h.view;
    final entered = Completer<void>(), gate = Completer<void>();
    h.port.onCommand = (_) async {
      entered.complete();
      await gate.future;
      return null;
    };
    final pending = h.controller.decide(prior, CanonicalOfferDecision.accept);
    await entered.future;
    h.controller.dispose();
    gate.complete();
    await pending;
    expect(prior.offer, isNull);
    expect(h.delivery.listeners, 0);
    expect((await h.repository.reconcile()).outcome,
        CanonicalDriverOutcome.unknown);
    expect(h.port.calls, hasLength(1));
  });
  test('B06 remains unconditional before/after UNKNOWN and disposal', () async {
    await h.offer();
    await h.controller.decide(h.view, CanonicalOfferDecision.accept);
    final phase = h.view.phase;
    for (var i = 0; i < 3; i++) {
      expect(h.view.completionGate.canComplete, isFalse);
      expect(h.controller.requestCompletion(), DriverFlowOutcome.unsupported);
    }
    expect(h.view.phase, phase);
    expect(h.port.calls, hasLength(1));
    h.controller.dispose();
    expect(h.controller.requestCompletion(), DriverFlowOutcome.unsupported);
    expect(h.port.calls, hasLength(1));
  });
}
