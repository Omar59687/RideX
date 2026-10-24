import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/auth/presentation/providers/admin_payment_providers.dart';
import 'package:ridex/features/auth/presentation/screens/admin_placeholder_screen.dart';
import 'package:ridex/features/auth/presentation/widgets/admin_payment_visibility_panel.dart';
import 'package:ridex/features/auth/presentation/widgets/admin_sanitized_payment_mapper.dart';

SessionState _session({
  String id = 'admin-a',
  RideRole role = RideRole.admin,
  bool blocked = false,
}) =>
    SessionState.fromUser(
      AppUser(
        id: id,
        name: 'User',
        email: 'user@example.invalid',
        role: role,
        isBlocked: blocked,
      ),
    );

final _payment = AdminSanitizedPayment.fromCash(
  CashPayment(
    paymentId: 'private-payment',
    bookingRequestId: 'private-booking',
    tripId: 'private-trip',
    amountFils: 4200,
    status: CashPaymentStatus.cashSelected,
    version: 2,
  ),
);

class _Session extends SessionController {
  _Session(this.initial);
  final SessionState initial;
  @override
  SessionState build() => initial;
  void set(SessionState next) => state = next;
}

class _Reader implements AdminPaymentReader {
  _Reader(this.read);
  final Future<List<AdminSanitizedPayment>> Function() read;
  int calls = 0;
  @override
  Future<List<AdminSanitizedPayment>> readPayments() {
    calls++;
    return read();
  }
}

ProviderContainer _container({
  AdminPaymentReader? reader,
  SessionState? session,
}) {
  final container = ProviderContainer(
    overrides: [
      sessionControllerProvider.overrideWith(
        () => _Session(session ?? _session()),
      ),
      if (reader != null) adminPaymentReaderProvider.overrideWithValue(reader),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  bool screen = false,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: screen
            ? const AdminPlaceholderScreen()
            : const Scaffold(
                body: SingleChildScrollView(
                  child: AdminPaymentVisibilityPanel(),
                ),
              ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('loading then empty is distinct from unavailable', (
    tester,
  ) async {
    final gate = Completer<List<AdminSanitizedPayment>>();
    final reader = _Reader(() => gate.future);
    final container = _container(reader: reader);
    await _pump(tester, container);
    expect(find.text('Loading payment summaries'), findsOneWidget);
    gate.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No payment records are available.'), findsOneWidget);
    expect(reader.calls, 1);
  });

  testWidgets('production default never substitutes fixture payments', (
    tester,
  ) async {
    await _pump(tester, _container());
    await tester.pumpAndSettle();
    expect(
      find.text('Payment visibility is unavailable in this configuration.'),
      findsOneWidget,
    );
    expect(find.text('No payment records are available.'), findsNothing);
    expect(find.text('JOD 4.20'), findsNothing);
  });

  testWidgets('Admin route screen renders only existing sanitized fields', (
    tester,
  ) async {
    await _pump(
      tester,
      _container(reader: _Reader(() async => [_payment])),
      screen: true,
    );
    await tester.pumpAndSettle();
    expect(find.text('Admin payments'), findsOneWidget);
    expect(find.text('JOD 4.20'), findsOneWidget);
    expect(find.text('Selected (unpaid)'), findsOneWidget);
    for (final secret in [
      'private-payment',
      'private-booking',
      'private-trip',
    ]) {
      expect(find.textContaining(secret), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('raw errors stay private and retry can recover', (tester) async {
    var fail = true;
    final reader = _Reader(() async {
      if (fail) throw StateError('private-provider-payload');
      return [_payment];
    });
    await _pump(tester, _container(reader: reader));
    await tester.pumpAndSettle();
    expect(find.text('Payment summaries could not be loaded.'), findsOneWidget);
    expect(find.textContaining('private-provider'), findsNothing);
    fail = false;
    await tester.tap(find.text('Retry payment summaries'));
    await tester.pumpAndSettle();
    expect(find.text('JOD 4.20'), findsOneWidget);
    expect(reader.calls, 2);
  });

  for (final session in [
    const SessionState.unauthenticated(),
    const SessionState.loading(),
    _session(role: RideRole.rider),
    _session(role: RideRole.driver),
    _session(blocked: true),
    _session(id: ''),
  ]) {
    testWidgets(
      'unauthorized ${session.status}-${session.role}-${session.user?.id} never reads',
      (tester) async {
        final reader = _Reader(() async => [_payment]);
        await _pump(tester, _container(reader: reader, session: session));
        await tester.pumpAndSettle();
        expect(
          find.text('Administrator access is required to view payments.'),
          findsOneWidget,
        );
        expect(find.text('JOD 4.20'), findsNothing);
        expect(reader.calls, 0);
      },
    );
  }

  for (final change in ['logout', 'role', 'blocked', 'other admin']) {
    testWidgets('$change immediately hides loaded payment summaries', (
      tester,
    ) async {
      Future<List<AdminSanitizedPayment>> response = Future.value([_payment]);
      final reader = _Reader(() => response);
      final container = _container(reader: reader);
      await _pump(tester, container);
      await tester.pumpAndSettle();
      expect(find.text('JOD 4.20'), findsOneWidget);
      final gate = Completer<List<AdminSanitizedPayment>>();
      // Other Admin gets a fresh read, never the previous Admin's cached data.
      response = gate.future;
      (container.read(sessionControllerProvider.notifier) as _Session).set(
        switch (change) {
          'logout' => const SessionState.unauthenticated(),
          'role' => _session(role: RideRole.rider),
          'blocked' => _session(blocked: true),
          _ => _session(id: 'admin-b'),
        },
      );
      await tester.pump();
      expect(find.text('JOD 4.20'), findsNothing);
      gate.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('JOD 4.20'), findsNothing);
    });
  }

  testWidgets('A-B-A role changes discard late data from the first read', (
    tester,
  ) async {
    final gate = Completer<List<AdminSanitizedPayment>>();
    var reads = 0;
    final reader = _Reader(() async => ++reads == 1 ? await gate.future : []);
    final container = _container(reader: reader);
    await _pump(tester, container);
    final session =
        container.read(sessionControllerProvider.notifier) as _Session;
    session.set(_session(role: RideRole.rider));
    await tester.pump();
    session.set(_session());
    await tester.pumpAndSettle();
    gate.complete([_payment]);
    await tester.pumpAndSettle();
    expect(find.text('JOD 4.20'), findsNothing);
    expect(find.text('No payment records are available.'), findsOneWidget);
  });

  testWidgets('late failure after disposal is contained', (tester) async {
    final gate = Completer<List<AdminSanitizedPayment>>();
    await _pump(tester, _container(reader: _Reader(() => gate.future)));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    gate.completeError(StateError('private-error'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
