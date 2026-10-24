import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/providers/driver_tracking_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends MockAuthRepository {
  final events = StreamController<void>.broadcast(sync: true);
  Future<AppUser?> Function()? restore;
  Future<AppUser> Function()? login;
  int logouts = 0;
  @override
  Stream<void> authStateChanges() => events.stream;
  @override
  Future<AppUser?> restoreSession() => restore?.call() ?? Future.value(null);
  @override
  Future<AppUser> signIn({required String email, required String password}) =>
      login?.call() ?? super.signIn(email: email, password: password);
  @override
  Future<void> signOut() async {
    logouts++;
  }
}

class _Tracking extends DriverTrackingController {
  final gate = Completer<void>();
  int stops = 0;
  @override
  DriverTrackingState build() => const DriverTrackingState.initial();
  @override
  Future<void> stopForSignOut() {
    stops++;
    return gate.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Auth auth;
  late _Tracking tracking;
  late SessionController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    auth = _Auth();
    tracking = _Tracking();
    container = ProviderContainer(overrides: [
      authServiceProvider.overrideWithValue(null),
      authRepositoryProvider.overrideWithValue(auth),
      driverTrackingControllerProvider.overrideWith(() => tracking),
    ]);
    controller = container.read(sessionControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    if (!tracking.gate.isCompleted) tracking.gate.complete();
    container.dispose();
    await auth.events.close();
  });

  for (final fails in [false, true]) {
    test(
        'logout rejects late restoration fails=$fails before tracking finishes',
        () async {
      final gate = Completer<AppUser?>();
      auth.restore = () => gate.future;
      final restoration = controller.refreshSession();
      final logout = controller.signOut();
      expect(container.read(sessionControllerProvider).user, isNull);
      expect(auth.logouts, 0);
      expect(controller.signOut(), same(logout));
      expect(tracking.stops, 1);
      if (fails) {
        gate.completeError(StateError('private-canary'));
      } else {
        gate.complete(MockData.demoDriver);
      }
      await restoration;
      expect(container.read(sessionControllerProvider).user, isNull);
      auth.events.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionControllerProvider).user, isNull);
      tracking.gate.complete();
      await logout;
      expect(auth.logouts, 1);
    });

    test('logout rejects late sign-in fails=$fails', () async {
      final gate = Completer<AppUser>();
      auth.login = () => gate.future;
      final login =
          controller.signIn(email: 'driver@ridex.app', password: '123456');
      final logout = controller.signOut();
      if (fails) {
        gate.completeError(StateError('private-canary'));
      } else {
        gate.complete(MockData.demoDriver);
      }
      await login;
      expect(container.read(sessionControllerProvider).user, isNull);
      tracking.gate.complete();
      await logout;
      expect(container.read(sessionControllerProvider).user, isNull);
    });
  }

  for (final users in [
    (MockData.demoRider, MockData.demoDriver),
    (MockData.demoDriver, MockData.demoRider),
  ]) {
    test(
        'account switch ${users.$1.role} to ${users.$2.role} rejects old response',
        () async {
      final old = Completer<AppUser>();
      auth.login = () => old.future;
      final previous = controller.signIn(email: 'old', password: 'fixture');
      auth.login = () async => users.$2;
      await controller.signIn(email: 'new', password: 'fixture');
      old.complete(users.$1);
      await previous;
      expect(container.read(sessionControllerProvider).user, users.$2);
    });
  }

  test('stream errors revoke pending restoration and expose no raw detail',
      () async {
    final gate = Completer<AppUser?>();
    auth.restore = () => gate.future;
    final restoration = controller.refreshSession();
    auth.events.addError(StateError('private-canary'));
    gate.complete(MockData.demoDriver);
    await restoration;
    expect(container.read(sessionControllerProvider).user, isNull);
    expect(container.read(sessionControllerProvider).errorMessage, isNull);
    auth.events.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(sessionControllerProvider).user, isNull);
  });

  test('provider disposal rejects late success and failure', () async {
    final gate = Completer<AppUser?>();
    auth.restore = () => gate.future;
    final restoration = controller.refreshSession();
    container.dispose();
    gate.complete(MockData.demoDriver);
    await restoration;
    await controller.signOut();
  });

  test('explicit Rider/demo entry works after logout', () async {
    final logout = controller.signOut();
    tracking.gate.complete();
    await logout;
    await controller.continueAsDemo();
    expect(container.read(sessionControllerProvider).user, MockData.demoRider);
  });

  test('explicit first refresh publishes before its returned future completes',
      () async {
    container.dispose();
    auth.restore = () async => MockData.demoRider;
    container = ProviderContainer(overrides: [
      authServiceProvider.overrideWithValue(null),
      authRepositoryProvider.overrideWithValue(auth),
    ]);
    await container.read(sessionControllerProvider.notifier).refreshSession();
    expect(container.read(sessionControllerProvider).user, MockData.demoRider);
  });
}
