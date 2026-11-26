import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/features/driver_flow/application/driver_completion_interaction.dart';
import 'package:ridex/features/trips/application/driver_completion_coordinator.dart';
import 'helpers/fake_canonical_driver_port.dart' as f;

void main() {
  late f.FakeCanonicalDriverPort port;
  late ValueNotifier<bool> connection;
  late CanonicalDriverCompletionInteraction gate;
  late bool current;
  late Map<String, Object?>? vehicle;
  late DriverCompleteTripCommand command;
  late CanonicalDriverCompletionContext? context;
  CanonicalDriverCompletionInteraction make(
          {bool enabled = true,
          bool reviewed = true,
          String driver = f.driverId,
          String vehicleId = f.vehicleId}) =>
      CanonicalDriverCompletionInteraction(
          configuration: DriverCompletionInteractionConfiguration(
              backend: f.backend,
              driverId: driver,
              vehicleId: vehicleId,
              enabled: enabled,
              reviewedNonproduction: reviewed),
          port: port,
          connected: connection,
          sessionCurrent: () => current,
          loadContext: () async => context,
          readVehicle: () async => vehicle);
  setUp(() {
    port = f.FakeCanonicalDriverPort()..accept();
    port.trip = {...port.trip!, 'status': 'inProgress', 'version': 4};
    connection = ValueNotifier(true);
    current = true;
    command = DriverCompleteTripCommand(
        tripId: f.tripId,
        expectedTripVersion: 4,
        idempotencyKey: 'original-key');
    context = CanonicalDriverCompletionContext(
        driverId: f.driverId, command: command);
    vehicle = {'id': f.vehicleId, 'driver_id': f.driverId, 'is_active': true};
    gate = make();
  });
  tearDown(() {
    gate.dispose();
    connection.dispose();
  });
  test('eligible exact canonical Cash context verifies without any command',
      () async {
    expect(await gate.verify(expected: command), isTrue);
    expect(port.calls, isEmpty);
    expect(await gate.confirmCompleted(command), isFalse);
    port.trip = {...port.trip!, 'status': 'completed', 'version': 5};
    port.availability = {
      ...f.availabilityRow(),
      'state': 'offline',
      'vehicle_id': null,
      'reserved_booking_request_id': null,
      'active_trip_id': null
    };
    expect(await gate.confirmCompleted(command), isTrue);
    expect(port.calls, isEmpty);
  });
  for (final scenario in [
    'disabled',
    'unreviewed',
    'wrong-driver',
    'wrong-vehicle',
    'disconnected',
    'session',
    'epoch',
    'role',
    'blocked',
    'approval',
    'trip-id',
    'version',
    'accepted',
    'arriving',
    'arrived',
    'completed',
    'card',
    'vehicle-inactive',
    'vehicle-foreign',
    'no-context',
    'wrong-key',
    'source-session',
    'read-failure'
  ]) {
    test('C02 blocks $scenario without any command', () async {
      switch (scenario) {
        case 'disabled':
          gate.dispose();
          gate = make(enabled: false);
        case 'unreviewed':
          gate.dispose();
          gate = make(reviewed: false);
        case 'wrong-driver':
          gate.dispose();
          gate = make(driver: f.otherId);
        case 'wrong-vehicle':
          gate.dispose();
          gate = make(vehicleId: f.otherId);
        case 'disconnected':
          connection.value = false;
        case 'session':
          port.sessionIdentity = Object();
        case 'epoch':
          port.epoch++;
        case 'role':
          port.user!['role'] = 'rider';
        case 'blocked':
          port.user!['is_blocked'] = true;
        case 'approval':
          port.profile!['approval_status'] = 'pending';
        case 'trip-id':
          port.trip!['id'] = f.otherId;
        case 'version':
          port.trip!['version'] = 5;
        case 'accepted':
          port.trip!['status'] = 'accepted';
        case 'arriving':
          port.trip!['status'] = 'driverArriving';
        case 'arrived':
          port.trip!['status'] = 'driverArrived';
        case 'completed':
          port.trip!['status'] = 'completed';
        case 'card':
          port.trip!['payment_method'] = 'card';
        case 'vehicle-inactive':
          vehicle!['is_active'] = false;
        case 'vehicle-foreign':
          vehicle!['driver_id'] = f.otherId;
        case 'no-context':
          context = null;
        case 'wrong-key':
          context = CanonicalDriverCompletionContext(
              driverId: f.driverId,
              command: DriverCompleteTripCommand(
                  tripId: f.tripId,
                  expectedTripVersion: 4,
                  idempotencyKey: 'rotated-key'));
        case 'source-session':
          current = false;
        case 'read-failure':
          port.beforeRead = (_) async => throw StateError('offline');
      }
      expect(await gate.verify(expected: command), isFalse);
      expect(port.calls, isEmpty);
    });
  }
  test('session replacement during canonical read suppresses eligibility',
      () async {
    port.beforeRead = (name) async {
      if (name == 'trip') port.sessionIdentity = Object();
    };
    expect(await gate.verify(), isFalse);
  });
  test('RPC-style completed with unchanged version is not completion evidence',
      () async {
    port.trip!['status'] = 'completed';
    expect(await gate.confirmCompleted(command), isFalse);
  });
  test('confirmed completion requires current Driver and connection', () async {
    port.trip = {...port.trip!, 'status': 'completed', 'version': 5};
    port.user!['is_blocked'] = true;
    expect(await gate.confirmCompleted(command), isFalse);
    connection.value = false;
    expect(await gate.confirmCompleted(command), isFalse);
  });
}
