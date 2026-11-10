import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/features/driver_flow/presentation/providers/canonical_driver_presentation_controller.dart';
import 'package:ridex/features/driver_flow/presentation/widgets/canonical_driver_reference_panel.dart';
import 'helpers/canonical_driver_presentation_harness.dart';
import 'helpers/fake_canonical_driver_port.dart' as f;

void main() {
  late B08Harness h;
  late ProviderContainer container;
  void testPanel(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      // Create stream subscriptions inside the widget test's fake async zone.
      h = B08Harness();
      container = ProviderContainer(overrides: [
        driverCanonicalPresentationProvider.overrideWith((ref) => h.controller),
      ]);
      await body(tester);
    });
  }

  tearDown(() async {
    container.dispose();
    await h.dispose();
  });
  Widget page({bool mounted = true}) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: mounted
                      ? const CanonicalDriverReferencePanel()
                      : const SizedBox()))));
  Future<void> showOffer(WidgetTester tester) async {
    await tester.pumpWidget(page());
    h.delivery.connect();
    h.delivery.offer();
    await tester.pumpAndSettle();
  }

  FilledButton acceptButton(WidgetTester tester) => tester
      .widget(find.widgetWithText(FilledButton, 'Accept canonical offer'));

  testPanel('default provider displays disabled panel without activation',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: CanonicalDriverReferencePanel())))));
    expect(find.text('Canonical presentation is disabled.'), findsOneWidget);
    expect(acceptButton(tester).onPressed, isNull);
    expect(h.port.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testPanel(
      'shows only verified identifiers and explicit missing journey evidence',
      (tester) async {
    await showOffer(tester);
    expect(find.text('Offer ID: ${f.offerId}'), findsOneWidget);
    expect(find.text('Offer version: 1'), findsOneWidget);
    expect(find.text('Quote ID: ${f.quoteId}'), findsOneWidget);
    expect(find.text('Fare unavailable. Route unavailable.'), findsOneWidget);
    expect(find.text('Rider details unavailable. Vehicle details unavailable.'),
        findsOneWidget);
    expect(find.textContaining('JOD'), findsNothing);
    expect(find.textContaining('Toyota'), findsNothing);
    expect(find.textContaining('Hashemite'), findsNothing);
    expect(find.textContaining('Simulat'), findsNothing);
    expect(find.textContaining('Paid'), findsNothing);
    expect(h.port.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testPanel('default action gate remains off with canonical evidence',
      (tester) async {
    container.dispose();
    await h.dispose();
    h = B08Harness(actions: false);
    container = ProviderContainer(overrides: [
      driverCanonicalPresentationProvider.overrideWith((ref) => h.controller)
    ]);
    await showOffer(tester);
    expect(acceptButton(tester).onPressed, isNull);
    expect(h.port.calls, isEmpty);
  });

  testPanel('foreign offer never appears or enables controls', (tester) async {
    h.port.offer!['driver_id'] = f.otherId;
    await showOffer(tester);
    expect(find.text('Offer ID: ${f.offerId}'), findsNothing);
    expect(find.textContaining('Driver authorization unavailable.'),
        findsOneWidget);
    expect(acceptButton(tester).onPressed, isNull);
  });

  testPanel('duplicate tap dispatches once; UNKNOWN survives panel remount',
      (tester) async {
    await showOffer(tester);
    final entered = Completer<void>(), gate = Completer<void>();
    h.port.onCommand = (_) async {
      entered.complete();
      await gate.future;
      return null;
    };
    final callback = acceptButton(tester).onPressed!;
    callback();
    callback();
    await tester.pumpAndSettle();
    expect(entered.isCompleted, isTrue);
    expect(h.port.calls, hasLength(1));
    expect(h.keys, 1);
    await tester.pumpWidget(page(mounted: false));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('Outcome unknown. No automatic replay.'), findsOneWidget);
    expect(acceptButton(tester).onPressed, isNull);
    expect(h.port.calls, hasLength(1));
    expect(h.keys, 1);
    h.delivery.offer();
    h.delivery.connect();
    await tester.pumpAndSettle();
    expect(find.text('Outcome unknown. No automatic replay.'), findsOneWidget);
    expect(h.port.calls, hasLength(1));
  });

  testPanel(
      'session invalidation removes previously rendered references on next frame',
      (tester) async {
    await showOffer(tester);
    h.port.sessionIdentity = Object();
    h.authority.value++;
    await tester.pump();
    expect(find.text('Offer ID: ${f.offerId}'), findsNothing);
    expect(acceptButton(tester).onPressed, isNull);
    expect(find.textContaining('Driver authorization unavailable.'),
        findsOneWidget);
  });

  testPanel('expiry disables controls and remount does not refresh/replay',
      (tester) async {
    await showOffer(tester);
    h.now = h.view.offer!.expiresAt;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Offer expired. Actions unavailable.'), findsOneWidget);
    expect(acceptButton(tester).onPressed, isNull);
    final reads = h.port.reads.length;
    await tester.pumpWidget(page(mounted: false));
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(h.port.reads.length, reads);
    expect(h.port.calls, isEmpty);
  });

  testPanel('disconnection hides ID widgets immediately; reconnect uses reads',
      (tester) async {
    await showOffer(tester);
    h.delivery.disconnect();
    await tester.pump();
    expect(find.text('Offer ID: ${f.offerId}'), findsNothing);
    expect(acceptButton(tester).onPressed, isNull);
    h.delivery.connect();
    await tester.pumpAndSettle();
    expect(find.text('Offer ID: ${f.offerId}'), findsOneWidget);
    expect(h.port.calls, isEmpty);
  });

  testPanel(
      'verified Trip renders canonical status with unconditional completion block',
      (tester) async {
    h.port.accept();
    h.port.trip!['status'] = 'inProgress';
    h.port.trip!['version'] = 4;
    await tester.pumpWidget(page());
    h.delivery.connect();
    await tester.pumpAndSettle();
    expect(find.text('Trip ID: ${f.tripId}'), findsOneWidget);
    expect(find.text('Trip version: 4'), findsOneWidget);
    expect(find.text('Trip status: inProgress'), findsOneWidget);
    final complete = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Completion unavailable'));
    expect(complete.onPressed, isNull);
    expect(h.view.completionGate.canComplete, isFalse);
    expect(h.port.calls, isEmpty);
    expect(find.textContaining('Paid'), findsNothing);
  });

  testPanel('narrow panel wraps actions and identifier text without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showOffer(tester);
    expect(tester.takeException(), isNull);
  });
}
