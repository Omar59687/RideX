import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/features/driver_flow/data/canonical_driver_repository.dart';
import 'helpers/fake_canonical_driver_port.dart' as f;

void main() {
  late f.FakeCanonicalDriverPort port;
  late CanonicalDriverRepository repository;
  late DateTime clock;
  setUp(() {
    port = f.FakeCanonicalDriverPort();
    clock = f.now;
    repository = CanonicalDriverRepository(port,
        offerCommandsEnabled: true, clock: () => clock);
  });
  tearDown(() => repository.dispose());
  Future<CanonicalDriverOffer> observed() async {
    final result = await repository.observe(offerId: f.offerId);
    expect(result.outcome, CanonicalDriverOutcome.observed);
    return result.offer!;
  }

  Future<CanonicalDriverResult> accept(CanonicalDriverOffer offer,
          [String key = 'original-key']) =>
      repository.decideOffer(offer, CanonicalOfferDecision.accept, key);

  test(
      'authorized availability and exact canonical offer without delivery source',
      () async {
    final result = await repository.observe(offerId: f.offerId);
    expect(result.outcome, CanonicalDriverOutcome.observed);
    expect(result.availability!.state, DriverAvailabilityState.reserved);
    expect(result.availability!.bookingId, f.bookingId);
    expect(result.offer!.quoteId, f.quoteId);
    expect(port.calls, isEmpty);
  });
  for (final kind in [
    'rider',
    'admin',
    'blocked',
    'pending',
    'rejected',
    'missing-user',
    'foreign-profile',
    'malformed-role'
  ]) {
    test('unauthorized eligibility: $kind', () async {
      switch (kind) {
        case 'rider':
          port.user!['role'] = 'rider';
        case 'admin':
          port.user!['role'] = 'admin';
        case 'blocked':
          port.user!['is_blocked'] = true;
        case 'pending':
          port.profile!['approval_status'] = 'pending';
        case 'rejected':
          port.profile!['approval_status'] = 'rejected';
        case 'missing-user':
          port.user = null;
        case 'foreign-profile':
          port.profile!['user_id'] = f.otherId;
        case 'malformed-role':
          port.user!['role'] = null;
      }
      final result = await repository.observe(offerId: f.offerId);
      expect(result.outcome, CanonicalDriverOutcome.unauthorized);
      expect(result.offer, isNull);
      expect(port.reads, isNot(contains('availability')));
      expect(port.calls, isEmpty);
    });
  }
  test('unauthenticated session performs no reads', () async {
    repository.dispose();
    port.valid = false;
    repository = CanonicalDriverRepository(port);
    expect((await repository.observe()).outcome,
        CanonicalDriverOutcome.unauthorized);
    expect(port.reads, isEmpty);
  });
  for (final field in ['driver_id', 'id']) {
    test('foreign offer $field is rejected', () async {
      port.offer![field] = f.otherId;
      expect((await repository.observe(offerId: f.offerId)).outcome,
          CanonicalDriverOutcome.unauthorized);
      expect(port.calls, isEmpty);
    });
    test('foreign Trip $field is rejected', () async {
      port.trip = {...f.tripRow(), field: f.otherId};
      final result = await repository.readTrip(f.tripId);
      expect(result.outcome, CanonicalDriverOutcome.unauthorized);
      expect(result.trip, isNull);
    });
  }
  test('foreign availability owner rejected', () async {
    port.availability!['driver_id'] = f.otherId;
    expect((await repository.observe()).outcome,
        CanonicalDriverOutcome.unauthorized);
  });
  test('owned Cash Trip read and expected-version conflict', () async {
    port.trip = f.tripRow();
    expect((await repository.readTrip(f.tripId, expectedVersion: 1)).trip!.id,
        f.tripId);
    expect((await repository.readTrip(f.tripId, expectedVersion: 2)).outcome,
        CanonicalDriverOutcome.stale);
    expect(port.calls, isEmpty);
  });
  test('Trip version regression latches stale', () async {
    port.trip = {...f.tripRow(), 'version': 3, 'status': 'driverArrived'};
    expect((await repository.readTrip(f.tripId)).outcome,
        CanonicalDriverOutcome.observed);
    port.trip = {...f.tripRow(), 'version': 2};
    expect((await repository.readTrip(f.tripId)).outcome,
        CanonicalDriverOutcome.stale);
    port.trip = {...f.tripRow(), 'version': 4};
    expect((await repository.readTrip(f.tripId)).outcome,
        CanonicalDriverOutcome.stale);
  });
  test('Card Trip unavailable and no dispatch', () async {
    port.trip = {...f.tripRow(), 'payment_method': 'card'};
    expect((await repository.readTrip(f.tripId)).outcome,
        CanonicalDriverOutcome.unavailable);
    expect(port.calls, isEmpty);
  });
  for (final method in ['card', 'unknown', null]) {
    test('unsupported canonical booking payment method blocks RPC: $method',
        () async {
      final offer = await observed();
      port.booking!['payment_method'] = method;
      expect((await accept(offer)).outcome, CanonicalDriverOutcome.unsupported);
      expect(port.calls, isEmpty);
    });
  }
  test('missing booking authority prevents offer write', () async {
    final offer = await observed();
    port.booking = null;
    expect((await accept(offer)).outcome, CanonicalDriverOutcome.unavailable);
    expect(port.calls, isEmpty);
  });
  test('default command gate blocks authorized offer', () async {
    repository.dispose();
    repository = CanonicalDriverRepository(port, clock: () => clock);
    final offer = await observed();
    expect((await accept(offer)).outcome, CanonicalDriverOutcome.unavailable);
    expect(port.calls, isEmpty);
  });
  test(
      'accept retains key/version and reads canonical result, not RPC identity',
      () async {
    final offer = await observed();
    port.onCommand = (_) async {
      port.accept();
      return {'trip_id': f.otherId};
    };
    final result = await accept(offer);
    expect(result.outcome, CanonicalDriverOutcome.accepted);
    expect(result.trip!.id, f.tripId);
    expect(port.calls, [('accept', f.offerId, 1, 'original-key')]);
  });
  test('decline uses canonical read rather than RPC row', () async {
    final offer = await observed();
    port.onCommand = (_) async {
      port.decline();
      return {'status': 'accepted'};
    };
    final result = await repository.decideOffer(
        offer, CanonicalOfferDecision.decline, 'decline-key');
    expect(result.outcome, CanonicalDriverOutcome.declined);
    expect(result.trip, isNull);
    expect(port.calls, [('decline', f.offerId, 1, 'decline-key')]);
  });
  test('inclusive expiry boundary blocks dispatch', () async {
    final offer = await observed();
    clock = offer.expiresAt;
    expect((await accept(offer)).outcome, CanonicalDriverOutcome.expired);
    expect(port.calls, isEmpty);
  });
  test('changed pre-dispatch offer version blocks command', () async {
    final offer = await observed();
    port.offer!['version'] = 2;
    expect((await accept(offer)).outcome, CanonicalDriverOutcome.stale);
    expect(port.calls, isEmpty);
  });
  for (final field in [
    'booking_request_id',
    'fare_quote_id',
    'vehicle_id',
    'expires_at'
  ]) {
    test('incompatible $field latches stale after equivalent reobservation',
        () async {
      final offer = await observed();
      final original = Map<String, Object?>.of(port.offer!);
      port.offer![field] = field == 'expires_at'
          ? clock.add(const Duration(seconds: 25)).toIso8601String()
          : f.otherId;
      expect((await repository.observe(offerId: f.offerId)).outcome,
          CanonicalDriverOutcome.stale);
      port.offer = original;
      expect((await accept(offer)).outcome, CanonicalDriverOutcome.stale);
      expect(port.calls, isEmpty);
    });
  }
  test('changed reservation blocks dispatch', () async {
    final offer = await observed();
    port.availability!['reserved_booking_request_id'] = f.otherId;
    expect((await accept(offer)).outcome, CanonicalDriverOutcome.stale);
    expect(port.calls, isEmpty);
  });
  test('duplicate acceptance single-flight and new-key block', () async {
    final offer = await observed();
    final entered = Completer<void>();
    final gate = Completer<void>();
    port.onCommand = (_) async {
      entered.complete();
      await gate.future;
      port.accept();
      return null;
    };
    final first = accept(offer);
    final second = accept(offer);
    expect(identical(first, second), isTrue);
    await entered.future;
    expect((await accept(offer, 'different-key')).outcome,
        CanonicalDriverOutcome.unknown);
    gate.complete();
    expect((await first).outcome, CanonicalDriverOutcome.accepted);
    expect((await second).trip!.id, f.tripId);
    expect((await accept(offer)).outcome, CanonicalDriverOutcome.accepted);
    expect(port.calls, hasLength(1));
  });
  test('network interruption stays UNKNOWN without blind retry', () async {
    final offer = await observed();
    port.onCommand = (_) async => throw StateError('private-network-detail');
    expect((await accept(offer)).outcome, CanonicalDriverOutcome.unknown);
    expect(
        (await repository.reconcile()).outcome, CanonicalDriverOutcome.unknown);
    expect((await accept(offer)).outcome, CanonicalDriverOutcome.unknown);
    expect((await accept(offer, 'new-key')).outcome,
        CanonicalDriverOutcome.unknown);
    expect(port.calls, hasLength(1));
  });
  test('lost reply after committed accept resolves canonically', () async {
    final offer = await observed();
    port.onCommand = (_) async {
      port.accept();
      throw StateError('lost-response');
    };
    expect((await accept(offer)).outcome, CanonicalDriverOutcome.accepted);
    expect(port.calls, hasLength(1));
  });
  for (final field in [
    'booking_request_id',
    'fare_quote_id',
    'vehicle_id',
    'driver_id'
  ]) {
    test('UNKNOWN recovery rejects wrong Trip $field correlation', () async {
      final offer = await observed();
      expect((await accept(offer)).outcome, CanonicalDriverOutcome.unknown);
      port.accept();
      port.trip![field] = f.otherId;
      expect((await repository.reconcile()).outcome,
          CanonicalDriverOutcome.unknown);
      expect(port.calls, hasLength(1));
    });
  }
  test('later canonical acceptance recovers UNKNOWN using reads only',
      () async {
    final offer = await observed();
    expect((await accept(offer)).outcome, CanonicalDriverOutcome.unknown);
    port.accept();
    final result = await repository.reconcile();
    expect(result.outcome, CanonicalDriverOutcome.accepted);
    expect(result.trip!.id, f.tripId);
    expect(port.calls, hasLength(1));
  });
  test('RPC accepted payload alone never proves assignment', () async {
    final offer = await observed();
    port.onCommand = (_) async => {'trip_id': f.tripId, 'status': 'accepted'};
    expect((await accept(offer)).outcome, CanonicalDriverOutcome.unknown);
  });
  test('post-dispatch expiry does not prove rejection', () async {
    final offer = await observed();
    port.onCommand = (_) async {
      clock = offer.expiresAt;
      return null;
    };
    expect((await accept(offer)).outcome, CanonicalDriverOutcome.unknown);
    port.offer = {...port.offer!, 'status': 'expired', 'version': 2};
    expect(
        (await repository.reconcile()).outcome, CanonicalDriverOutcome.unknown);
    expect(port.calls, hasLength(1));
  });
  test('filtered/missing row cannot prove rejection', () async {
    final offer = await observed();
    port.onCommand = (_) async {
      port.offer = null;
      return null;
    };
    expect((await accept(offer)).outcome, CanonicalDriverOutcome.unknown);
    expect(port.calls, hasLength(1));
  });
  for (final change in [
    'logout',
    'same-user-session',
    'epoch',
    'account',
    'dispose'
  ]) {
    test('$change invalidates pending read and earlier visible result',
        () async {
      final prior = await repository.observe(offerId: f.offerId);
      final entered = Completer<void>();
      final gate = Completer<void>();
      port.beforeRead = (name) async {
        if (name == 'availability') {
          entered.complete();
          await gate.future;
        }
      };
      final pending = repository.observe();
      await entered.future;
      switch (change) {
        case 'logout':
          port.valid = false;
        case 'same-user-session':
          port.sessionIdentity = Object();
        case 'epoch':
          port.epoch++;
        case 'account':
          port.driver = f.otherId;
        case 'dispose':
          repository.dispose();
      }
      gate.complete();
      expect((await pending).outcome, CanonicalDriverOutcome.unauthorized);
      expect(prior.offer, isNull);
      expect(prior.availability, isNull);
      expect(port.calls, isEmpty);
    });
  }
  test('logout during write cannot publish delayed assignment', () async {
    final offer = await observed();
    final entered = Completer<void>();
    final gate = Completer<void>();
    port.onCommand = (_) async {
      entered.complete();
      await gate.future;
      port.accept();
      return null;
    };
    final pending = accept(offer);
    await entered.future;
    port.valid = false;
    gate.complete();
    expect((await pending).outcome, CanonicalDriverOutcome.unauthorized);
    expect((await repository.reconcile()).trip, isNull);
    expect(port.calls, hasLength(1));
  });
  test('observed remote block revokes prior snapshots', () async {
    final prior = await repository.observe(offerId: f.offerId);
    port.user!['is_blocked'] = true;
    expect((await repository.observe()).outcome,
        CanonicalDriverOutcome.unauthorized);
    expect(prior.offer, isNull);
  });
  test('eligibility network failure unavailable without dispatch', () async {
    port.beforeRead = (_) async => throw StateError('private-canary');
    expect((await repository.observe()).outcome,
        CanonicalDriverOutcome.unavailable);
    expect(port.calls, isEmpty);
  });
  test('bounded command timeout and read-only recovery after delayed commit',
      () async {
    repository.dispose();
    repository = CanonicalDriverRepository(port,
        offerCommandsEnabled: true,
        clock: () => clock,
        commandTimeout: Duration.zero);
    final offer = await observed();
    final gate = Completer<void>();
    port.onCommand = (_) async {
      await gate.future;
      port.accept();
      return null;
    };
    expect((await accept(offer)).outcome, CanonicalDriverOutcome.unknown);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect((await repository.reconcile()).outcome,
        CanonicalDriverOutcome.accepted);
    expect(port.calls, hasLength(1));
  });
  test('missing Realtime unavailable without polling or writes', () async {
    expect((await repository.watch().single).outcome,
        CanonicalDriverOutcome.unavailable);
    expect(port.reads, isEmpty);
    expect(port.calls, isEmpty);
  });
  test('financial commands and progression unsupported with no dispatch', () {
    expect(repository.unsupportedCommand().outcome,
        CanonicalDriverOutcome.unsupported);
    expect(port.calls, isEmpty);
  });
  for (final value in ['demo-offer', '', ' ${f.offerId}']) {
    test('noncanonical locator rejected before port read', () async {
      expect((await repository.observe(offerId: value)).outcome,
          CanonicalDriverOutcome.unavailable);
      expect(port.reads, isEmpty);
    });
  }
}
