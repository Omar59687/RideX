import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ridex/core/models/booking_handoff.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';
import 'package:ridex/core/services/fare/pending_fare_lock_store.dart';
import 'package:ridex/core/repositories/fare_repository.dart';
import 'package:ridex/features/booking/presentation/screens/booking_confirmation_screen.dart';

final _command = PendingFareLock(
  bookingRequestId: 'booking-1',
  expectedBookingVersion: 1,
  fareQuoteId: 'quote-1',
  expectedQuoteVersion: 1,
  riderId: 'rider-1',
  status: PendingLockRecoveryStatus.uncertain,
  createdAt: DateTime.utc(2026, 10, 10, 12),
);

// Matches the migration 007 projection; a lock preserves the original expiry
// and quote version, links the booking, and advances its version by one.
Map<String, dynamic> _quoteRow(
        {String status = 'locked',
        String id = 'quote-1',
        int version = 1,
        String rider = 'rider-1'}) =>
    {
      'id': id,
      'booking_request_id': 'booking-1',
      'rider_id': rider,
      'status': status,
      'quote_version': version,
      'pricing_version': 1,
      'currency': 'JOD',
      'fixed_fare_fils': 2000,
      'breakdown': {
        'base_fare_fils': 500,
        'distance_fils': 1200,
        'duration_fils': 300,
        'stops_fils': 0,
        'subtotal_fils': 2000,
        'minimum_fare_fils': 1000,
        'rounding_increment_fils': 50,
        'fixed_fare_fils': 2000
      },
      'created_at': '2026-10-10T12:00:00Z',
      'expires_at': '2026-10-10T12:10:00Z',
      'locked_at': status == 'locked' ? '2026-10-10T12:01:00Z' : null,
      'route_distance_meters': 5400,
      'route_duration_seconds': 720,
    };
Map<String, dynamic> _bookingRow(
        {int version = 2,
        String? link = 'quote-1',
        String status = 'draft',
        List<Map<String, dynamic>>? quotes}) =>
    {
      'id': 'booking-1',
      'rider_id': 'rider-1',
      'version': version,
      'status': status,
      'fare_quote_id': link,
      'fare_quotes': quotes ?? [_quoteRow()],
    };

class _Auth extends MockAuthRepository {
  AppUser? user = MockData.demoRider;
  @override
  Future<AppUser?> restoreSession() async => user;
}

// Fake only the platform IO, so all envelope logic is production code.
// Mutable IO fault injection deliberately implements the immutable SDK facade.
// ignore: must_be_immutable
class _Preferences implements SharedPreferencesAsync {
  final values = <String, String>{};
  bool failBeforeWrite = false;
  bool failAfterWrite = false;
  bool failRead = false;
  Future<void> Function()? beforeRead;
  Completer<void>? writeGate;
  int writes = 0;
  @override
  Future<String?> getString(String key) async {
    if (beforeRead != null) await beforeRead!();
    if (failRead) throw StateError('read interrupted');
    return values[key];
  }

  @override
  Future<void> setString(String key, String value) async {
    writes++;
    if (writeGate != null) await writeGate!.future;
    if (failBeforeWrite) throw StateError('write interrupted');
    values[key] = value;
    if (failAfterWrite) throw StateError('acknowledgement lost');
  }

  @override
  Future<void> remove(String key) async => values.remove(key);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness({FareCanonicalReader? reader, _Preferences? persisted})
      : preferences = persisted ?? _Preferences() {
    store = SharedPreferencesPendingFareLockStore(preferences);
    if (persisted == null) {
      preferences.values[_key] = jsonEncode(_command.toJson());
    }
    repository = SupabaseFareRepository(
        bookingMutationGate: (dispatch) => pending.runBookingMutation(dispatch),
        rpc: ({required name, required params}) async {
          calls.add(name);
          if (lockGate != null && name == 'rider_lock_fare_quote') {
            await lockGate!.future;
            return _quoteRow();
          }
          return {'id': 'booking-2', 'version': 1};
        },
        quoteEdge: (_) async =>
            throw StateError('no new quote during resolution'),
        canonicalReader: reader ??
            ({required bookingRequestId, required riderId}) async => [
                  _bookingRow(
                      version: confirmed ? 3 : 2,
                      status: confirmed ? 'confirmed' : 'draft')
                ],
        bookingConfirmer: (
            {required bookingRequestId,
            required expectedVersion,
            required idempotencyKey,
            required riderId}) async {
          confirmations++;
          expect(expectedVersion, 2);
          if (confirmGate != null) await confirmGate!.future;
          if (conflict) throw const FareTransportFailure(code: '40001');
          confirmed = true;
          if (malformed) return {'status': 'confirmed'};
          return {
            'booking_request_id': bookingRequestId,
            'status': 'confirmed'
          };
        });
    container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      fareRepositoryProvider.overrideWithValue(repository),
      pendingFareLockStoreProvider.overrideWithValue(store),
      appErrorReporterProvider.overrideWithValue(const NoopAppErrorReporter()),
    ]);
  }
  final _Preferences preferences;
  late final SharedPreferencesPendingFareLockStore store;
  final auth = _Auth();
  late final ProviderContainer container;
  late final SupabaseFareRepository repository;
  final calls = <String>[];
  bool confirmed = false;
  bool malformed = false;
  bool conflict = false;
  int confirmations = 0;
  Completer<void>? confirmGate;
  Completer<void>? lockGate;
  PendingFareLockController get pending =>
      container.read(pendingFareLockControllerProvider.notifier);
  Future<void> authenticate() async {
    await container.read(sessionControllerProvider.notifier).refreshSession();
    await pending.restorePendingLock();
  }

  Future<FareBookingRef> create() => repository.createBookingDraft(
      pickup: const FareRouteLocation(latitude: 31.95, longitude: 35.92),
      destination: const FareRouteLocation(latitude: 32, longitude: 36),
      vehicleTypeCode: 'economy',
      paymentMethod: 'cash');
  Future<BookingHandoff> resolve() =>
      pending.resolveConfirmedEvidence(_command);
}

final _key = SharedPreferencesPendingFareLockStore.keyForRider('rider-1');
final _blocked = throwsA(isA<FareException>());
PendingFareLock _newCommand() => PendingFareLock(
    bookingRequestId: 'booking-2',
    expectedBookingVersion: 1,
    fareQuoteId: 'quote-2',
    expectedQuoteVersion: 1,
    riderId: 'rider-1',
    status: PendingLockRecoveryStatus.uncertain,
    createdAt: DateTime.utc(2026, 10, 11));
Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  test(
      'confirm, transfer, create second real draft and independently reread original',
      () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    await expectLater(h.create(), _blocked);
    final confirmed = await h.pending.bookingHandoff(confirm: true);
    final resolved = await h.resolve();
    expect(resolved.quote, confirmed.quote);
    expect(resolved.booking.id, 'booking-1');
    expect(resolved.booking.version, 3);
    expect(resolved.quote.id, 'quote-1');
    expect(resolved.quote.quoteVersion, 1);
    expect(resolved.quote.fixedFareFils, 2000);
    expect(h.container.read(pendingFareLockControllerProvider), isNull);
    final second = await h.create();
    expect(second.bookingRequestId, 'booking-2');
    expect(h.calls, ['rider_create_booking_draft']);
    await h.pending.stageForDispatch(_newCommand());
    final original =
        await h.pending.bookingHandoff(bookingRequestId: 'booking-1');
    expect(original.isConfirmed, true);
    expect(original.quote, confirmed.quote);
    expect(h.confirmations, 1);
    await expectLater(h.create(), _blocked);
  });

  test(
      'older restage, duplicate resolution and stale clear preserve newer pending',
      () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    h.confirmed = true;
    final before = h.preferences.writes;
    final results = await Future.wait([h.resolve(), h.resolve()]);
    expect(results.every((r) => r.isConfirmed), true);
    expect(h.preferences.writes, before + 1);
    await expectLater(h.pending.stageForDispatch(_command),
        throwsA(isA<PendingFareLockConflictException>()));
    final newer = _newCommand();
    await h.pending.stageForDispatch(newer);
    await h.resolve();
    await h.pending.clear(_command);
    expect(h.container.read(pendingFareLockControllerProvider), newer);
    expect((await h.store.inspectForRider('rider-1')).command, newer);
    expect((await h.store.inspectForRider('rider-1')).confirmed.length, 1);
  });

  test(
      'same-process retry reconciles applied write without clearing newer evidence',
      () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    h.confirmed = true;
    h.preferences.failAfterWrite = true;
    await expectLater(h.resolve(), throwsA(isA<StateError>()));
    h.preferences.failAfterWrite = false;
    await h.resolve();
    expect(h.container.read(pendingFareLockControllerProvider), isNull);
    expect((await h.create()).bookingRequestId, 'booking-2');
  });

  test('restoration keeps both confirmed owner and newer unresolved command',
      () async {
    final h = _Harness();
    await h.authenticate();
    h.confirmed = true;
    await h.resolve();
    await h.pending.stageForDispatch(_newCommand());
    h.container.dispose();
    final restart = _Harness(persisted: h.preferences);
    addTearDown(restart.container.dispose);
    restart.confirmed = true;
    await restart.authenticate();
    expect(restart.container.read(pendingFareLockControllerProvider),
        _newCommand());
    await expectLater(restart.create(), _blocked);
    expect(
        (await restart.pending.bookingHandoff(bookingRequestId: 'booking-1'))
            .isConfirmed,
        true);
  });

  test(
      'unresolved, missing, ambiguous, advanced and mismatched canonical state blocks retirement',
      () async {
    final cases = <List<Map<String, dynamic>>>[
      [],
      [
        _bookingRow(version: 3, status: 'confirmed'),
        _bookingRow(version: 3, status: 'confirmed')
      ],
      [_bookingRow()],
      [_bookingRow(version: 4, status: 'confirmed')],
      [_bookingRow(version: 4, status: 'searching')],
      [_bookingRow(version: 3, status: 'confirmed', link: 'different')],
      [
        _bookingRow(
            version: 3, status: 'confirmed', quotes: [_quoteRow(version: 2)])
      ],
      [
        _bookingRow(
            version: 3,
            status: 'confirmed',
            quotes: [_quoteRow(), _quoteRow(id: 'other', version: 2)])
      ],
      [
        _bookingRow(
            version: 3,
            status: 'confirmed',
            quotes: [_quoteRow(rider: 'other')])
      ],
      [
        _bookingRow(version: 3, status: 'confirmed', quotes: [
          {..._quoteRow(), 'fixed_fare_fils': 999}
        ])
      ],
      [
        _bookingRow(version: 3, status: 'confirmed', quotes: [
          {..._quoteRow(), 'breakdown': {}}
        ])
      ],
      [
        {..._bookingRow(version: 3, status: 'confirmed'), 'id': 'other'}
      ],
      [
        {..._bookingRow(version: 3, status: 'confirmed'), 'rider_id': 'other'}
      ],
      [
        _bookingRow(version: 3, status: 'confirmed', quotes: [
          {..._quoteRow(), 'locked_at': null}
        ])
      ],
    ];
    for (final rows in cases) {
      final h = _Harness(
          reader: ({required bookingRequestId, required riderId}) async =>
              rows);
      await h.authenticate();
      final raw = h.preferences.values[_key];
      await expectLater(h.resolve(), _blocked);
      expect(h.preferences.values[_key], raw);
      await expectLater(h.create(), _blocked);
      h.container.dispose();
    }
  });

  test('failed canonical SELECT and unreadable storage never retire', () async {
    final h = _Harness(
        reader: ({required bookingRequestId, required riderId}) async =>
            throw const FareTransportFailure(code: '401'));
    addTearDown(h.container.dispose);
    await h.authenticate();
    await expectLater(h.resolve(), _blocked);
    expect(h.preferences.writes, 0);
    await expectLater(h.create(), _blocked);
    final other = _Harness();
    addTearDown(other.container.dispose);
    await other.authenticate();
    other.confirmed = true;
    other.preferences.failRead = true;
    await expectLater(other.resolve(), _blocked);
    await expectLater(other.create(), _blocked);
    expect(other.preferences.writes, 0);
  });

  for (final applied in [false, true]) {
    test('interrupted write applied=$applied remains blocked until restoration',
        () async {
      final h = _Harness();
      await h.authenticate();
      h.confirmed = true;
      h.preferences.failBeforeWrite = !applied;
      h.preferences.failAfterWrite = applied;
      await expectLater(h.resolve(), throwsA(isA<StateError>()));
      expect(h.container.read(pendingFareLockControllerProvider), _command);
      await expectLater(h.create(), _blocked);
      h.preferences.failBeforeWrite = false;
      h.preferences.failAfterWrite = false;
      h.container.dispose();
      final restart = _Harness(persisted: h.preferences);
      addTearDown(restart.container.dispose);
      restart.confirmed = true;
      await restart.authenticate();
      if (!applied) {
        await expectLater(restart.create(), _blocked);
        await restart.resolve();
      }
      expect((await restart.pending.bookingHandoff()).isConfirmed, true);
      expect((await restart.create()).bookingRequestId, 'booking-2');
      await expectLater(restart.pending.stageForDispatch(_command),
          throwsA(isA<PendingFareLockConflictException>()));
    });
  }

  test(
      'same Rider reauthentication restores reference; different Rider cannot access it',
      () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    h.confirmed = true;
    await h.resolve();
    h.auth.user = null;
    await h.authenticate();
    expect(h.container.read(confirmedBookingReferencesProvider), isEmpty);
    await expectLater(
        h.pending.bookingHandoff(bookingRequestId: 'booking-1'), _blocked);
    h.auth.user = MockData.demoRider;
    await h.authenticate();
    expect((await h.pending.bookingHandoff()).isConfirmed, true);
    h.auth.user = const AppUser(
        id: 'rider-2',
        name: 'Other',
        email: 'other@test',
        role: RideRole.rider);
    await h.authenticate();
    expect(h.container.read(confirmedBookingReferencesProvider), isEmpty);
    await expectLater(h.resolve(), _blocked);
    await expectLater(
        h.pending.bookingHandoff(bookingRequestId: 'booking-1'), _blocked);
    expect((await h.store.inspectForRider('rider-1')).confirmed.length, 1);
  });

  test(
      'queued draft waits for evidence transfer and then dispatches exactly once',
      () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    h.confirmed = true;
    h.preferences.writeGate = Completer<void>();
    final resolution = h.resolve();
    await _tick();
    final draft = h.create();
    await _tick();
    expect(h.calls, isEmpty);
    h.preferences.writeGate!.complete();
    await resolution;
    expect((await draft).bookingRequestId, 'booking-2');
    expect(h.calls.length, 1);
  });

  test('draft queued before resolution blocks, later draft succeeds', () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    h.confirmed = true;
    final blocked = expectLater(h.create(), _blocked);
    final resolution = h.resolve();
    await blocked;
    await resolution;
    expect((await h.create()).bookingRequestId, 'booking-2');
  });

  test('session refresh during canonical resolution invalidates delayed result',
      () async {
    final read = Completer<List<Map<String, dynamic>>>();
    final h = _Harness(
        reader: ({required bookingRequestId, required riderId}) => read.future);
    addTearDown(h.container.dispose);
    await h.authenticate();
    final blocked = expectLater(h.resolve(), _blocked);
    await _tick();
    await h.container.read(sessionControllerProvider.notifier).refreshSession();
    read.complete([_bookingRow(version: 3, status: 'confirmed')]);
    await blocked;
    expect(h.preferences.writes, 0);
    await expectLater(h.create(), _blocked);
  });

  test(
      'session loss during transfer publishes nothing; original Rider restores complete envelope',
      () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    h.confirmed = true;
    h.preferences.writeGate = Completer<void>();
    final blocked = expectLater(h.resolve(), _blocked);
    await _tick();
    h.auth.user = null;
    await h.container.read(sessionControllerProvider.notifier).refreshSession();
    h.preferences.writeGate!.complete();
    await blocked;
    expect(h.container.read(confirmedBookingReferencesProvider), isEmpty);
    h.auth.user = MockData.demoRider;
    await h.authenticate();
    expect((await h.pending.bookingHandoff()).isConfirmed, true);
    expect((await h.create()).bookingRequestId, 'booking-2');
  });

  test('session change during transfer reinspection prevents write dispatch',
      () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    h.confirmed = true;
    var reads = 0;
    final inspected = Completer<void>();
    final release = Completer<void>();
    h.preferences.beforeRead = () async {
      if (++reads == 2) {
        inspected.complete();
        await release.future;
      }
    };
    final blocked = expectLater(
        h.resolve(), throwsA(isA<PendingFareLockOwnershipException>()));
    await inspected.future;
    await h.container.read(sessionControllerProvider.notifier).refreshSession();
    release.complete();
    await blocked;
    expect(h.preferences.writes, 0);
    expect(h.preferences.values[_key], jsonEncode(_command.toJson()));
  });

  test('delayed lock response cannot restage retired command', () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    h.lockGate = Completer<void>();
    final lock = h.repository.lockQuote(
        bookingRequestId: 'booking-1',
        fareQuoteId: 'quote-1',
        expectedBookingVersion: 1,
        expectedQuoteVersion: 1);
    h.confirmed = true;
    await h.resolve();
    h.lockGate!.complete();
    await lock;
    await expectLater(h.pending.stageForDispatch(_command),
        throwsA(isA<PendingFareLockConflictException>()));
    expect((await h.create()).bookingRequestId, 'booking-2');
  });

  test(
      'delayed confirmation serializes resolution without duplicate submission',
      () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    h.confirmGate = Completer<void>();
    final confirmation = h.pending.bookingHandoff(confirm: true);
    await _tick();
    final resolution = h.resolve();
    await _tick();
    expect(h.preferences.writes, 0);
    h.confirmGate!.complete();
    await confirmation;
    await resolution;
    expect(h.confirmations, 1);
    expect((await h.create()).bookingRequestId, 'booking-2');
  });

  test(
      'confirmation conflicts, malformed responses and failed rereads preserve pending',
      () async {
    for (final mode in ['conflict', 'malformed', 'reread']) {
      late _Harness h;
      h = _Harness(
          reader: mode == 'reread'
              ? ({required bookingRequestId, required riderId}) async {
                  if (h.confirmed) {
                    throw const FareTransportFailure(code: '401');
                  }
                  return [_bookingRow()];
                }
              : null);
      await h.authenticate();
      h.conflict = mode == 'conflict';
      h.malformed = mode == 'malformed';
      await expectLater(h.pending.bookingHandoff(confirm: true), _blocked);
      expect(h.container.read(pendingFareLockControllerProvider), _command);
      expect(h.preferences.writes, 0);
      await expectLater(h.create(), _blocked);
      h.container.dispose();
    }
  });

  test('corrupt envelope or conflicting pending cannot be overwritten',
      () async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    h.confirmed = true;
    for (final raw in [
      '{broken',
      jsonEncode({
        'schema': 2,
        'pending': null,
        'confirmed': [{}]
      }),
      jsonEncode({'schema': 2, 'pending': null}),
      jsonEncode(_newCommand().toJson())
    ]) {
      h.preferences.values[_key] = raw;
      await expectLater(h.resolve(), _blocked);
      await expectLater(h.create(), _blocked);
      expect(h.preferences.values[_key], raw);
    }
  });

  testWidgets('screen resolves and reloads retained original independently',
      (tester) async {
    final h = _Harness();
    addTearDown(h.container.dispose);
    await h.authenticate();
    Future<void> pump() async {
      await tester.pumpWidget(UncontrolledProviderScope(
          container: h.container,
          child: const MaterialApp(
              home: BookingConfirmationScreen(bookingRequestId: 'booking-1'))));
      await tester.pumpAndSettle();
    }

    await pump();
    await tester.tap(find.text('Confirm original booking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolve evidence for another booking'));
    await tester.pumpAndSettle();
    expect(find.text('Booking confirmed'), findsOneWidget);
    expect(find.text('Start another booking'), findsOneWidget);
    expect(find.text('Locked fare: JOD 2.00'), findsOneWidget);
    await h.pending.stageForDispatch(_newCommand());
    await tester.pumpWidget(const SizedBox());
    await pump();
    expect(find.text('Booking confirmed'), findsOneWidget);
    expect(find.text('Locked fare: JOD 2.00'), findsOneWidget);
    expect(h.confirmations, 1);
  });
}
