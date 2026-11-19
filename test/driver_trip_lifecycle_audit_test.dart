import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/features/driver_flow/data/canonical_driver_repository.dart';
import 'package:ridex/features/driver_flow/domain/driver_trip_transition_policy.dart';
import 'helpers/fake_canonical_driver_port.dart' as f;
import 'helpers/fake_driver_trip_transition_port.dart';

void main() {
  late FakeDriverTripTransitionPort port;
  late CanonicalDriverRepository repository;
  setUp(() {
    port = FakeDriverTripTransitionPort();
    repository = CanonicalDriverRepository(port);
  });
  tearDown(() => repository.dispose());
  Future<CanonicalDriverResult> inspect({
    String id = f.tripId,
    int version = 1,
    DriverTripLifecycleStatus target = DriverTripLifecycleStatus.driverArriving,
  }) => repository.inspectTransition(
    tripId: id,
    expectedVersion: version,
    requestedStatus: target,
  );

  test('all enum pairs match only the RPC/trigger Driver edges', () {
    const edges = {
      'accepted>driverArriving',
      'accepted>cancelledByDriver',
      'driverArriving>driverArrived',
      'driverArriving>cancelledByDriver',
      'driverArrived>inProgress',
      'driverArrived>cancelledByDriver',
      'inProgress>completed',
    };
    for (final from in DriverTripLifecycleStatus.values) {
      for (final to in DriverTripLifecycleStatus.values) {
        expect(
          DriverTripTransitionPolicy.allows(from, to),
          edges.contains('${from.name}>${to.name}'),
          reason: '$from > $to',
        );
      }
    }
  });

  test(
    'canonical path retains exact Trip and versions; preflight never writes',
    () async {
      var version = 1;
      for (final target in [
        DriverTripLifecycleStatus.driverArriving,
        DriverTripLifecycleStatus.driverArrived,
        DriverTripLifecycleStatus.inProgress,
        DriverTripLifecycleStatus.completed,
      ]) {
        final result = await inspect(version: version, target: target);
        expect(result.outcome, CanonicalDriverOutcome.observed);
        expect(result.trip!.id, f.tripId);
        expect(result.trip!.version, version);
        expect(port.transitions, hasLength(version - 1));
        port.transition(f.tripId, target, version, 'original-$version');
        version++;
      }
      expect(port.trip!['status'], 'completed');
      expect(port.trip!.containsKey('receipt'), isFalse);
      expect(port.trip!.containsKey('paid'), isFalse);
      expect(
        (await inspect(
          version: 5,
          target: DriverTripLifecycleStatus.completed,
        )).outcome,
        CanonicalDriverOutcome.stale,
      );
      expect(port.calls, isEmpty);
    },
  );

  for (final change in [
    'role',
    'blocked',
    'approval',
    'logout',
    'session',
    'epoch',
    'driver',
    'trip',
    'vehicle',
    'active-trip',
    'offline',
    'version',
    'card',
    'mock',
  ]) {
    test('blocks $change without any transition', () async {
      switch (change) {
        case 'role':
          port.user!['role'] = 'rider';
        case 'blocked':
          port.user!['is_blocked'] = true;
        case 'approval':
          port.profile!['approval_status'] = 'pending';
        case 'logout':
          port.valid = false;
        case 'session':
          port.sessionIdentity = Object();
        case 'epoch':
          port.epoch++;
        case 'driver':
          port.trip!['driver_id'] = f.otherId;
        case 'trip':
          port.trip!['id'] = f.otherId;
        case 'vehicle':
          port.availability!['vehicle_id'] = f.otherId;
        case 'active-trip':
          port.availability!['active_trip_id'] = f.otherId;
        case 'offline':
          port.availability = {
            ...f.availabilityRow(),
            'state': 'offline',
            'vehicle_id': null,
            'reserved_booking_request_id': null,
          };
        case 'version':
          port.trip!['version'] = 2;
        case 'card':
          port.trip!['payment_method'] = 'card';
        case 'mock':
          port.trip!['id'] = 'trip-1';
      }
      final result = await inspect();
      expect(result.outcome, isNot(CanonicalDriverOutcome.observed));
      expect(result.trip, isNull);
      expect(port.transitions, isEmpty);
      expect(port.calls, isEmpty);
    });
  }
  for (final boundary in ['user', 'profile', 'availability', 'trip']) {
    test('SDK session replacement at $boundary revokes publication', () async {
      port.beforeRead = (name) async {
        if (name == boundary) port.sessionIdentity = Object();
      };
      expect((await inspect()).outcome, CanonicalDriverOutcome.unauthorized);
      expect(port.transitions, isEmpty);
    });
  }
  test('availability replacement during Trip read fails closed', () async {
    port.beforeRead = (name) async {
      if (name == 'trip') port.availability!['active_trip_id'] = f.otherId;
    };
    expect((await inspect()).outcome, CanonicalDriverOutcome.stale);
  });
  test(
    'remote approval loss after Trip read revokes earlier evidence',
    () async {
      final prior = await inspect();
      var reads = 0;
      port.beforeRead = (name) async {
        if (name == 'availability' && ++reads == 2) {
          port.profile!['approval_status'] = 'rejected';
        }
      };
      expect((await inspect()).outcome, CanonicalDriverOutcome.unauthorized);
      expect(prior.trip, isNull);
    },
  );
  test('disconnect is unavailable without inventing progress', () async {
    port.beforeRead = (_) async => throw StateError('disconnected');
    expect((await inspect()).outcome, CanonicalDriverOutcome.unavailable);
    expect(port.transitions, isEmpty);
  });
  test(
    'invalid transition, expected version and mock locator cannot grant authority',
    () async {
      expect(
        (await inspect(target: DriverTripLifecycleStatus.completed)).outcome,
        CanonicalDriverOutcome.unsupported,
      );
      expect((await inspect(version: 0)).outcome, CanonicalDriverOutcome.stale);
      port.reads.clear();
      expect(
        (await inspect(id: 'trip-1')).outcome,
        CanonicalDriverOutcome.unavailable,
      );
      expect(port.reads, isEmpty);
      expect(port.transitions, isEmpty);
    },
  );
  test(
    'fake transition rejects skips, stale versions and conflicting original key',
    () {
      expect(
        () => port.transition(
          f.tripId,
          DriverTripLifecycleStatus.completed,
          1,
          'key',
        ),
        throwsStateError,
      );
      expect(
        () => port.transition(
          f.tripId,
          DriverTripLifecycleStatus.driverArriving,
          2,
          'key',
        ),
        throwsStateError,
      );
      port.transition(
        f.tripId,
        DriverTripLifecycleStatus.driverArriving,
        1,
        'key',
      );
      port.transition(
        f.tripId,
        DriverTripLifecycleStatus.driverArriving,
        1,
        'key',
      );
      expect(port.transitions, hasLength(1));
      expect(
        () => port.transition(
          f.tripId,
          DriverTripLifecycleStatus.driverArrived,
          2,
          'key',
        ),
        throwsStateError,
      );
    },
  );
}
