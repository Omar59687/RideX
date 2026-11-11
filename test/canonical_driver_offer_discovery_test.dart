import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/driver_flow/data/canonical_driver_offer_discovery_port.dart';
import 'package:ridex/features/driver_flow/data/canonical_driver_repository.dart';
import 'package:ridex/features/driver_flow/data/polling_canonical_driver_offer_delivery.dart';
import 'package:ridex/features/driver_flow/domain/canonical_driver_delivery.dart';
import 'package:ridex/features/driver_flow/presentation/providers/canonical_driver_presentation_controller.dart';

import 'helpers/canonical_driver_presentation_harness.dart' show driverSession;
import 'helpers/fake_canonical_driver_port.dart' as f;

class _Port extends f.FakeCanonicalDriverPort
    implements CanonicalDriverOfferDiscoveryPort {
  List<Map<String, Object?>> rows = [_row()];
  int polls = 0;
  Future<List<Map<String, Object?>>> Function()? query;
  @override
  Future<List<Map<String, Object?>>> readOfferedRows(DateTime after) async {
    polls++;
    return query == null
        ? rows.map(Map<String, Object?>.of).toList()
        : await query!();
  }
}

Map<String, Object?> _row() => {
      ...f.offerRow(),
      'offered_at': f.now.toIso8601String(),
    };

final _harnesses = <_Harness>[];

void _testWidgets(String name, WidgetTesterCallback body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      for (final h in _harnesses) {
        h.dispose();
      }
      _harnesses.clear();
      await tester.pump();
    }
  });
}

class _Harness {
  _Harness(
      {bool enabled = true,
      bool compose = false,
      void Function(CanonicalDriverDeliverySignal)? onSignal}) {
    _harnesses.add(this);
    delivery = PollingCanonicalDriverOfferDelivery(
      port: port,
      session: session,
      authorityInvalidations: authority,
      enabled: enabled,
      clock: () => now,
    );
    if (compose) {
      repository = CanonicalDriverRepository(
        port,
        offerCommandsEnabled: true,
        clock: () => now,
      );
      controller = CanonicalDriverPresentationController(
        repository: repository!,
        session: session,
        authorityInvalidations: authority,
        delivery: delivery,
        enabled: true,
        offerActionsEnabled: true,
        clock: () => now,
        createIdempotencyKey: () => 'b09-original-key',
      );
    } else {
      subscription = delivery.signals.listen((event) {
        events.add(event);
        onSignal?.call(event);
      });
    }
  }
  final port = _Port();
  final session = ValueNotifier<SessionState>(driverSession());
  final authority = ValueNotifier<int>(0);
  final events = <CanonicalDriverDeliverySignal>[];
  DateTime now = f.now;
  late final PollingCanonicalDriverOfferDelivery delivery;
  StreamSubscription<CanonicalDriverDeliverySignal>? subscription;
  CanonicalDriverRepository? repository;
  CanonicalDriverPresentationController? controller;
  Iterable<CanonicalDriverOfferHint> get offers =>
      events.whereType<CanonicalDriverOfferHint>();
  bool get connected =>
      events.whereType<CanonicalDriverConnectionHint>().last.connected;
  Future<void> advance(WidgetTester tester, Duration delta) async {
    var remaining = delta;
    while (remaining > Duration.zero) {
      final step = remaining > const Duration(seconds: 1)
          ? const Duration(seconds: 1)
          : remaining;
      now = now.add(step);
      await tester.pump(step);
      remaining -= step;
    }
  }

  void dispose() {
    controller?.dispose();
    delivery.dispose();
    subscription?.cancel();
    repository?.dispose();
    session.dispose();
    authority.dispose();
  }
}

void main() {
  test(
    'committed schema grants SELECT under participant RLS and 15s expiry',
    () {
      final sql = File(
        'supabase/migrations/007_phase3_booking_fare_matching_foundation.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      expect(
        sql,
        contains(
          'alter table public.driver_match_offers enable row level security',
        ),
      );
      expect(
        sql,
        contains('on public.driver_match_offers for select to authenticated'),
      );
      expect(
        sql,
        contains(
          'using (private.can_read_match_offer(booking_request_id, driver_id))',
        ),
      );
      expect(
        sql,
        contains("users.role = 'driver' and users.id = target_driver_id"),
      );
      expect(sql, contains('and not users.is_blocked'));
      expect(sql, contains("expires_at = offered_at + interval '15 seconds'"));
      expect(
        sql,
        contains(
          'constraint driver_match_offers_version_positive check (version > 0)',
        ),
      );
      expect(sql, contains('public.driver_match_offers\nto authenticated;'));
    },
  );

  _testWidgets('valid owned offer emits ordered advisory hint with no command',
      (
    tester,
  ) async {
    final h = _Harness();

    await tester.pump();
    expect(h.connected, isTrue);
    expect(h.offers.single.offerId, f.offerId);
    expect(h.events.map((e) => e.revision), orderedEquals([0, 1]));
    expect(h.port.polls, 1);
    expect(h.port.calls, isEmpty);
  });

  _testWidgets('default-off construction never polls', (tester) async {
    final port = _Port();
    final session = ValueNotifier(driverSession());
    final authority = ValueNotifier(0);
    final delivery = PollingCanonicalDriverOfferDelivery(
      port: port,
      session: session,
      authorityInvalidations: authority,
    );
    final subscription = delivery.signals.listen((_) {});
    await tester.pump(const Duration(seconds: 30));
    expect(port.polls, 0);
    delivery.dispose();
    unawaited(subscription.cancel());
    session.dispose();
    authority.dispose();
  });

  final invalidRows = <String, void Function(Map<String, Object?>)>{
    'foreign Driver': (r) => r['driver_id'] = f.otherId,
    'malformed ID': (r) => r['id'] = 'not-a-uuid',
    'missing booking': (r) => r.remove('booking_request_id'),
    'missing quote': (r) => r.remove('fare_quote_id'),
    'missing vehicle': (r) => r.remove('vehicle_id'),
    'missing version': (r) => r.remove('version'),
    'zero version': (r) => r['version'] = 0,
    'fractional version': (r) => r['version'] = 1.5,
    'overflow version': (r) => r['version'] = 2147483648,
    'unknown status': (r) => r['status'] = 'pending',
    'missing expiry': (r) => r.remove('expires_at'),
    'missing offered time': (r) => r.remove('offered_at'),
    'malformed timestamp': (r) => r['offered_at'] = 'yesterday',
    'timezone ambiguous': (r) => r['offered_at'] = '2026-11-10T12:00:00',
    'longer than 15 seconds': (r) => r['expires_at'] =
        f.now.add(const Duration(seconds: 16)).toIso8601String(),
    'future offer': (r) {
      r['offered_at'] = f.now.add(const Duration(seconds: 1)).toIso8601String();
      r['expires_at'] =
          f.now.add(const Duration(seconds: 16)).toIso8601String();
    },
    'expired': (r) {
      r['offered_at'] =
          f.now.subtract(const Duration(seconds: 15)).toIso8601String();
      r['expires_at'] = f.now.toIso8601String();
    },
    for (final status in ['accepted', 'declined', 'cancelled', 'expired'])
      status: (r) => r['status'] = status,
  };
  for (final entry in invalidRows.entries) {
    _testWidgets('rejects ${entry.key} without publishing an offer', (
      tester,
    ) async {
      final h = _Harness();

      entry.value(h.port.rows.single);
      await tester.pump();
      expect(h.offers, isEmpty);
      expect(h.connected, isFalse);
      expect(h.port.calls, isEmpty);
    });
  }

  for (final count in [2, 3]) {
    _testWidgets('$count rows yields no arbitrary eligible offer', (
      tester,
    ) async {
      final h = _Harness();

      h.port.rows = List.generate(
        count,
        (i) => {..._row(), 'id': 'b7000000-0000-0000-0000-00000000000${i + 1}'},
      );
      await tester.pump();
      expect(h.offers, isEmpty);
      expect(h.connected, isFalse);
    });
  }

  _testWidgets('healthy empty SELECT emits connectivity without an offer',
      (tester) async {
    final h = _Harness();
    h.port.rows = [];
    await tester.pump();
    expect(h.connected, isTrue);
    expect(h.offers, isEmpty);
    expect(h.port.calls, isEmpty);
  });

  _testWidgets(
    'duplicate rows fail closed; duplicate polls suppress repeated hints',
    (tester) async {
      final h = _Harness();

      h.port.rows = [_row(), _row()];
      await tester.pump();
      expect(h.offers, isEmpty);
      h.port.rows = [_row()];
      await h.advance(tester, const Duration(seconds: 2));
      expect(h.offers, hasLength(1));
      await h.advance(tester, const Duration(seconds: 2));
      expect(h.offers, hasLength(1));
      expect(h.port.polls, 3);
    },
  );

  _testWidgets('version rollback and immutable identity changes are rejected', (
    tester,
  ) async {
    final h = _Harness();

    h.port.rows.single['version'] = 3;
    await tester.pump();
    h.port.rows.single['version'] = 2;
    await h.advance(tester, const Duration(seconds: 2));
    expect(h.connected, isFalse);
    expect(h.offers, hasLength(1));
    h.port.rows.single['version'] = 3;
    h.port.rows.single['vehicle_id'] = f.otherId;
    await h.advance(tester, const Duration(seconds: 2));
    expect(h.connected, isFalse);
    expect(h.offers, hasLength(1));
    h.port.rows.single['vehicle_id'] = f.vehicleId;
    await h.advance(tester, const Duration(seconds: 2));
    expect(h.connected, isTrue);
    expect(h.offers, hasLength(2));
  });

  _testWidgets('terminal offer cannot resurrect even with a higher version', (
    tester,
  ) async {
    final h = _Harness();

    await tester.pump();
    h.port.rows.single['status'] = 'cancelled';
    h.port.rows.single['version'] = 2;
    await h.advance(tester, const Duration(seconds: 2));
    h.port.rows.single['status'] = 'offered';
    h.port.rows.single['version'] = 3;
    await h.advance(tester, const Duration(seconds: 2));
    expect(h.connected, isFalse);
    expect(h.offers, hasLength(1));
  });

  _testWidgets(
    'network failure hides offer; recovery rereads and emits a fresh hint',
    (tester) async {
      final h = _Harness();

      await tester.pump();
      h.port.query = () async => throw StateError('private-error-canary');
      await h.advance(tester, const Duration(seconds: 2));
      expect(h.connected, isFalse);
      expect(h.events.join(), isNot(contains('private-error-canary')));
      h.port.query = null;
      await h.advance(tester, const Duration(seconds: 2));
      expect(h.connected, isTrue);
      expect(h.offers, hasLength(2));
    },
  );

  _testWidgets('15-second inclusive deadline hides offer between polls', (
    tester,
  ) async {
    final h = _Harness();

    await tester.pump();
    await h.advance(tester, const Duration(milliseconds: 14999));
    expect(h.connected, isTrue);
    await h.advance(tester, const Duration(milliseconds: 1));
    expect(h.connected, isFalse);
    expect(h.port.calls, isEmpty);
  });

  _testWidgets(
    'read timeout disconnects without overlapping or publishing late results',
    (tester) async {
      final h = _Harness();

      final gate = Completer<List<Map<String, Object?>>>();
      h.port.query = () => gate.future;
      await tester.pump();
      await h.advance(tester, const Duration(seconds: 8));
      expect(h.connected, isFalse);
      expect(h.port.polls, 1);
      gate.complete([_row()]);
      await tester.pump();
      expect(h.offers, isEmpty);
      h.port.query = null;
      await h.advance(tester, const Duration(seconds: 2));
      expect(h.offers, hasLength(1));
    },
  );

  for (final loss in [
    'logout',
    'SDK replacement',
    'epoch change',
    'UI replacement',
    'invalidation',
    'disposal',
    'cancel subscription',
  ]) {
    _testWidgets('$loss suppresses delayed result and cancels future polling', (
      tester,
    ) async {
      final h = _Harness();

      final gate = Completer<List<Map<String, Object?>>>();
      h.port.query = () => gate.future;
      await tester.pump();
      switch (loss) {
        case 'logout':
          h.port.valid = false;
        case 'SDK replacement':
          h.port.sessionIdentity = Object();
        case 'epoch change':
          h.port.epoch++;
        case 'UI replacement':
          h.session.value = driverSession();
        case 'invalidation':
          h.authority.value++;
        case 'disposal':
          h.delivery.dispose();
        case 'cancel subscription':
          unawaited(h.subscription!.cancel());
      }
      gate.complete([_row()]);
      await tester.pump();
      await h.advance(tester, const Duration(seconds: 20));
      expect(h.offers, isEmpty);
      expect(h.port.polls, 1);
      expect(h.port.calls, isEmpty);
    });
  }

  _testWidgets('remote blocked Driver stops polling after eligibility reread', (
    tester,
  ) async {
    final h = _Harness();

    await tester.pump();
    h.port.user!['is_blocked'] = true;
    await h.advance(tester, const Duration(seconds: 2));
    await h.advance(tester, const Duration(seconds: 2));
    expect(h.connected, isFalse);
    expect(h.port.polls, 1);
  });

  _testWidgets(
    'B08 presents only B07 canonical reread, never discovery row evidence',
    (tester) async {
      final h = _Harness(compose: true);

      await tester.pump();
      expect(h.controller!.view.phase, CanonicalDriverPresentationPhase.offer);
      expect(h.port.reads, contains('offer'));
      expect(h.controller!.view.offer!.id, f.offerId);
      expect(h.port.calls, isEmpty);
    },
  );

  _testWidgets(
    'B07 rejects changed canonical owner despite valid advisory discovery',
    (tester) async {
      final h = _Harness(compose: true);

      h.port.offer!['driver_id'] = f.otherId;
      await tester.pump();
      expect(h.controller!.view.offer, isNull);
      expect(h.port.calls, isEmpty);
    },
  );

  _testWidgets('disposal after publication cancels every future poll',
      (tester) async {
    final h = _Harness();
    await tester.pump();
    h.delivery.dispose();
    final count = h.port.polls;
    await h.advance(tester, const Duration(seconds: 30));
    expect(h.port.polls, count);
    expect(h.connected, isFalse);
  });

  _testWidgets(
      'bounded rollback history retires rather than evicting identities',
      (tester) async {
    final h = _Harness();
    for (var i = 0;
        i <= PollingCanonicalDriverOfferDelivery.maxRememberedOffers;
        i++) {
      h.port.rows = [
        {
          ..._row(),
          'id':
              'b7000000-0000-0000-0000-${(i + 1).toRadixString(16).padLeft(12, '0')}',
          'offered_at': h.now.toIso8601String(),
          'expires_at': h.now.add(const Duration(seconds: 15)).toIso8601String()
        }
      ];
      if (i == 0) {
        await tester.pump();
      } else {
        await h.advance(tester, const Duration(seconds: 2));
      }
    }
    expect(h.connected, isFalse);
    expect(h.offers,
        hasLength(PollingCanonicalDriverOfferDelivery.maxRememberedOffers));
    final polls = h.port.polls;
    await h.advance(tester, const Duration(seconds: 4));
    expect(h.port.polls, polls);
  });

  _testWidgets('empty malformed row is rejected without a hint',
      (tester) async {
    final h = _Harness();
    h.port.rows = [{}];
    await tester.pump();
    expect(h.offers, isEmpty);
    expect(h.connected, isFalse);
  });

  _testWidgets(
      'successful RPC acknowledgement alone never becomes Trip assignment',
      (tester) async {
    final h = _Harness(compose: true);
    await tester.pump();
    h.port.onCommand = (_) async => {'trip_id': f.tripId, 'status': 'accepted'};
    await h.controller!
        .decide(h.controller!.view, CanonicalOfferDecision.accept);
    await tester.pump();
    expect(h.controller!.view.phase, CanonicalDriverPresentationPhase.unknown);
    expect(h.controller!.view.trip, isNull);
    expect(h.port.calls, hasLength(1));
    expect(h.controller!.requestCompletion().name, 'unsupported');
    expect(h.controller!.view.completionGate.canComplete, isFalse);
    await h.advance(tester, const Duration(seconds: 4));
    expect(h.port.calls, hasLength(1));
    expect(h.port.calls.single.$1, 'accept');
  });

  _testWidgets(
      'healthy empty discovery enables explicit UNKNOWN reconciliation',
      (tester) async {
    final h = _Harness(compose: true);
    await tester.pump();
    h.port.onCommand = (_) async {
      h.port.accept();
      h.port.beforeRead = (name) async {
        if (name == 'booking-trip') throw StateError('readback lost');
      };
      throw StateError('ack lost');
    };
    await h.controller!
        .decide(h.controller!.view, CanonicalOfferDecision.accept);
    await tester.pump();
    expect(h.controller!.view.phase, CanonicalDriverPresentationPhase.unknown);
    h.port.beforeRead = null;
    h.port.rows = [];
    await h.advance(tester, const Duration(seconds: 2));
    expect(h.controller!.view.canReconcile, isTrue);
    expect(h.controller!.view.trip, isNull);
    expect(h.port.calls, hasLength(1));
    await h.controller!.reconcile();
    await tester.pump();
    expect(h.controller!.view.phase, CanonicalDriverPresentationPhase.trip);
    expect(h.controller!.view.trip!.id, f.tripId);
    await h.advance(tester, const Duration(seconds: 20));
    expect(h.controller!.view.trip!.id, f.tripId);
    expect(h.port.calls, hasLength(1));
  });

  _testWidgets(
      'healthy empty discovery retains a canonically verified accepted Trip',
      (tester) async {
    final h = _Harness(compose: true);
    await tester.pump();
    h.port.onCommand = (_) async {
      h.port.accept();
      return {'trip_id': f.otherId};
    };
    await h.controller!
        .decide(h.controller!.view, CanonicalOfferDecision.accept);
    await tester.pump();
    expect(h.controller!.view.trip!.id, f.tripId);
    h.port.rows = [];
    await h.advance(tester, const Duration(seconds: 16));
    expect(h.controller!.view.trip!.id, f.tripId);
    expect(h.port.calls, hasLength(1));
  });

  _testWidgets(
      'repeated empty polls cannot starve a delayed canonical Trip refresh',
      (tester) async {
    final h = _Harness(compose: true);
    await tester.pump();
    h.port.onCommand = (_) async {
      h.port.accept();
      return {};
    };
    await h.controller!
        .decide(h.controller!.view, CanonicalOfferDecision.accept);
    await tester.pump();
    expect(h.controller!.view.trip!.id, f.tripId);
    h.port.rows = [];
    h.port.beforeRead = (name) async {
      if (name == 'trip') {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    };
    await h.advance(tester, const Duration(seconds: 10));
    expect(h.controller!.view.phase, CanonicalDriverPresentationPhase.trip);
    expect(h.controller!.view.trip!.id, f.tripId);
    expect(h.port.polls, greaterThan(3));
    expect(h.port.calls, hasLength(1));
  });

  _testWidgets(
      'reentrant authority invalidation during connection cancels expiry and queued hint',
      (tester) async {
    late _Harness h;
    h = _Harness(onSignal: (event) {
      if (event is CanonicalDriverConnectionHint && event.connected) {
        h.authority.value++;
      }
    });
    await tester.pump();
    expect(h.offers, isEmpty);
    expect(h.port.polls, 1);
    // Wrapper disposes before timer invariants: revocation must have cancelled
    // the already-created expiry timer even when triggered inside a listener.
  });

  _testWidgets(
    'UNKNOWN never replays after network recovery and controller replacement',
    (tester) async {
      final h = _Harness(compose: true);

      await tester.pump();
      final offer = h.controller!.view.offer!;
      h.port.onCommand = (_) async => throw StateError('uncertain');
      await h.controller!
          .decide(h.controller!.view, CanonicalOfferDecision.accept);
      await tester.pump();
      expect(
        h.controller!.view.phase,
        CanonicalDriverPresentationPhase.unknown,
      );
      expect(h.port.calls, hasLength(1));
      h.port.query = () async => throw StateError('network');
      await h.advance(tester, const Duration(seconds: 2));
      h.port.query = null;
      await h.advance(tester, const Duration(seconds: 2));
      expect(
          h.controller!.view.phase, CanonicalDriverPresentationPhase.unknown);
      h.controller!.dispose();
      h.controller = CanonicalDriverPresentationController(
        repository: h.repository!,
        session: h.session,
        authorityInvalidations: h.authority,
        delivery: null,
        enabled: true,
        offerActionsEnabled: true,
        clock: () => h.now,
      );
      expect(h.port.calls, hasLength(1));
      expect(
        (await h.repository!.decideOffer(
                offer, CanonicalOfferDecision.accept, 'new-unsafe-key'))
            .outcome,
        CanonicalDriverOutcome.unknown,
      );
      expect(h.port.calls.every((c) => c.$1 == 'accept'), isTrue);
    },
  );
}
