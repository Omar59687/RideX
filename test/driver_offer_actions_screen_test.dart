import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_incoming_offer_controller.dart';
import 'package:ridex/features/driver_flow/presentation/screens/driver_incoming_offer_screen.dart';
import 'driver_offer_actions_controller_test.dart' show ActionHarness;

void main() {
  Future<void> mount(WidgetTester tester, ActionHarness h) async {
    await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(home: DriverIncomingOfferScreen())));
    await tester.pump();
  }

  for (final action in ['accept', 'decline']) {
    testWidgets('rapid simulated $action disables both and announces pending',
        (tester) async {
      final h = ActionHarness();
      addTearDown(h.dispose);
      await h.settle();
      await mount(tester, h);
      final target = find.text('Simulate $action');
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.tap(target);
      await tester.pump();
      expect(h.repository.commands, hasLength(1));
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      expect(
          tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
          isNull);
      expect(find.text('Simulated $action pending. No assignment confirmed.'),
          findsOneWidget);
      expect(
          tester
              .widgetList<Semantics>(find.ancestor(
                  of: find.text(
                      'Simulated $action pending. No assignment confirmed.'),
                  matching: find.byType(Semantics)))
              .any((widget) => widget.properties.liveRegion == true),
          isTrue);
      h.repository.replies.single
          .complete(const DriverFlowResult(DriverFlowOutcome.rejected));
      await tester.pump();
      await tester.pump();
      expect(find.text('Simulated decision rejected. Check status.'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('default configuration keeps original disabled controls',
      (tester) async {
    final h = ActionHarness(enabled: null);
    addTearDown(h.dispose);
    await h.settle();
    await mount(tester, h);
    expect(find.text('Accept unavailable'), findsOneWidget);
    expect(find.text('Decline unavailable'), findsOneWidget);
    expect(h.repository.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('pending survives remount and background/resume crossing expiry',
      (tester) async {
    final h = ActionHarness();
    addTearDown(h.dispose);
    await h.settle();
    await mount(tester, h);
    await tester.ensureVisible(find.text('Simulate accept'));
    await tester.tap(find.text('Simulate accept'));
    await tester.pump();
    final command = h.view.command;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpWidget(const SizedBox());
    h.now = h.view.offer!.expiresAt;
    await mount(tester, h);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
    expect(h.view.command, same(command));
    expect(h.repository.commands, hasLength(1));
    expect(
        find.text('Outcome unknown. Check status; do not repeat the action.'),
        findsOneWidget);
    expect(
        tester
            .widgetList<Semantics>(find.ancestor(
                of: find.text(
                    'Outcome unknown. Check status; do not repeat the action.'),
                matching: find.byType(Semantics)))
            .any((widget) => widget.properties.liveRegion == true),
        isTrue);
    h.repository.replies.single
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, h.outcome()));
    await tester.pump();
    await tester.pump();
    expect(h.view.decisionStatus, DriverOfferDecisionStatus.unknown);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'fake success stays on preview without canonical navigation or finance',
      (tester) async {
    final h = ActionHarness();
    addTearDown(h.dispose);
    await h.settle();
    await mount(tester, h);
    await tester.ensureVisible(find.text('Simulate accept'));
    await tester.tap(find.text('Simulate accept'));
    h.repository.replies.single
        .complete(DriverFlowResult(DriverFlowOutcome.simulated, h.outcome()));
    await tester.pump();
    await tester.pump();
    expect(find.byType(DriverIncomingOfferScreen), findsOneWidget);
    expect(
        find.text(
            'Simulated acceptance only. No real assignment or payment confirmed.'),
        findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Local demonstration only'), -300);
    expect(find.text('Local demonstration only'), findsOneWidget);
    expect(find.byIcon(Icons.phone), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('large text at narrow width renders actionable preview safely',
      (tester) async {
    final h = ActionHarness();
    addTearDown(h.dispose);
    await h.settle();
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
            home: const DriverIncomingOfferScreen())));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Simulate decline'), 250);
    expect(tester.getSize(find.byType(OutlinedButton)).height,
        greaterThanOrEqualTo(48));
    await tester.pumpWidget(const SizedBox());
  });
}
