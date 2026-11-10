import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/driver_flow/data/canonical_driver_repository.dart';
import 'package:ridex/features/driver_flow/domain/canonical_driver_delivery.dart';
import 'package:ridex/features/driver_flow/presentation/providers/canonical_driver_presentation_controller.dart';
import 'fake_canonical_driver_port.dart' as f;

SessionState driverSession(
        {String id = f.driverId,
        RideRole role = RideRole.driver,
        bool blocked = false,
        DriverApprovalStatus approval = DriverApprovalStatus.approved}) =>
    SessionState.fromUser(AppUser(
        id: id,
        name: 'Local fixture',
        email: 'fixture@example.test',
        role: role,
        isBlocked: blocked,
        driverApprovalStatus: approval));

class FakeCanonicalDelivery implements CanonicalDriverDelivery {
  FakeCanonicalDelivery() {
    events = StreamController<CanonicalDriverDeliverySignal>.broadcast(
        sync: true, onListen: () => listeners++, onCancel: () => listeners--);
  }
  late final StreamController<CanonicalDriverDeliverySignal> events;
  int listeners = 0, revision = 0;
  @override
  Stream<CanonicalDriverDeliverySignal> get signals => events.stream;
  void connect() =>
      events.add(CanonicalDriverConnectionHint(++revision, connected: true));
  void disconnect() =>
      events.add(CanonicalDriverConnectionHint(++revision, connected: false));
  void offer([String id = f.offerId]) =>
      events.add(CanonicalDriverOfferHint(++revision, id));
  void trip([String id = f.tripId]) =>
      events.add(CanonicalDriverTripHint(++revision, id));
}

class B08Harness {
  B08Harness(
      {bool enabled = true,
      bool actions = true,
      bool deliveryPresent = true,
      f.FakeCanonicalDriverPort? fakePort}) {
    port = fakePort ?? f.FakeCanonicalDriverPort();
    repository = CanonicalDriverRepository(port,
        offerCommandsEnabled: true, clock: () => now);
    controller = CanonicalDriverPresentationController(
        repository: repository,
        session: session,
        authorityInvalidations: authority,
        delivery: deliveryPresent ? delivery : null,
        enabled: enabled,
        offerActionsEnabled: actions,
        clock: () => now,
        createIdempotencyKey: () => 'b08-original-${++keys}');
  }
  DateTime now = f.now;
  final session = ValueNotifier<SessionState>(driverSession());
  final authority = ValueNotifier<int>(0);
  final delivery = FakeCanonicalDelivery();
  late final f.FakeCanonicalDriverPort port;
  late final CanonicalDriverRepository repository;
  late final CanonicalDriverPresentationController controller;
  int keys = 0;
  CanonicalDriverPresentationView get view => controller.view;
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  Future<void> offer() async {
    delivery.connect();
    delivery.offer();
    await flush();
  }

  Future<void> dispose() async {
    controller.dispose();
    repository.dispose();
    session.dispose();
    authority.dispose();
    await delivery.events.close();
  }
}
