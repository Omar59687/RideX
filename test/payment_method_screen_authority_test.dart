import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/app.dart';
import 'package:ridex/app/router/app_router.dart';
import 'package:ridex/app/router/route_names.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/app/theme/appearance_theme_mode_provider.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/fare_repository.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';
import 'package:ridex/core/services/fare/pending_fare_lock_store.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/features/booking/presentation/providers/rider_payment_selection_provider.dart';
import 'package:ridex/features/booking/presentation/screens/booking_confirmation_screen.dart';
import 'package:ridex/features/booking/presentation/screens/payment_method_screen.dart';

import 'helpers/in_memory_appearance_preferences.dart';

const _riderA = AppUser(
  id: 'rider-a',
  name: 'Rider A',
  email: 'rider-a@example.test',
  role: RideRole.rider,
);
const _riderB = AppUser(
  id: 'rider-b',
  name: 'Rider B',
  email: 'rider-b@example.test',
  role: RideRole.rider,
);

final _command = PendingFareLock(
  bookingRequestId: 'booking-r08',
  expectedBookingVersion: 1,
  fareQuoteId: 'quote-r08',
  expectedQuoteVersion: 1,
  riderId: _riderA.id,
  status: PendingLockRecoveryStatus.uncertain,
  createdAt: DateTime.utc(2026, 10, 10, 12),
);

final _createdAt = DateTime.utc(2026, 10, 10, 12);
final _lockedAt = DateTime.utc(2026, 10, 10, 12, 1);
final _expiresAt = DateTime.utc(2030, 10, 10, 12);

FareQuote _quote() => FareQuote(
      id: 'quote-r08',
      bookingRequestId: 'booking-r08',
      quoteVersion: 1,
      pricingVersion: 1,
      fixedFareFils: 2150,
      breakdown: const FareBreakdown(
        baseFareFils: 500,
        distanceFils: 1200,
        durationFils: 300,
        stopsFils: 150,
        subtotalFils: 2150,
        minimumFareFils: 1000,
        roundingIncrementFils: 50,
        fixedFareFils: 2150,
      ),
      status: FareQuoteStatus.locked,
      expiresAt: _expiresAt,
      createdAt: _createdAt,
      routeDistanceMeters: 5400,
      routeDurationSeconds: 720,
    );

Map<String, dynamic> _bookingRow({
  String method = 'cash',
  int version = 2,
  String status = 'draft',
  String? linkedQuote = 'quote-r08',
  String quoteStatus = 'locked',
}) =>
    {
      'id': 'booking-r08',
      'rider_id': _riderA.id,
      'version': version,
      'status': status,
      'fare_quote_id': linkedQuote,
      'payment_method': method,
      'fare_quotes': [
        {
          'id': 'quote-r08',
          'booking_request_id': 'booking-r08',
          'rider_id': _riderA.id,
          'quote_version': 1,
          'pricing_version': 1,
          'fixed_fare_fils': 2150,
          'breakdown': _quote().breakdown.toJson(),
          'status': quoteStatus,
          'expires_at': _expiresAt.toIso8601String(),
          'created_at': _createdAt.toIso8601String(),
          'route_distance_meters': 5400,
          'route_duration_seconds': 720,
          'locked_at':
              quoteStatus == 'locked' ? _lockedAt.toIso8601String() : null,
          'currency': 'JOD',
        }
      ],
    };

class _AuthRepository extends MockAuthRepository {
  _AuthRepository(this.user);

  AppUser? user;

  @override
  Future<AppUser?> restoreSession() async => user;
}

class _MemoryLockStore implements PendingFareLockStore {
  final Map<String, PendingFareLock> pending = {_riderA.id: _command};

  @override
  Future<void> clearForRider(String riderId) async {
    pending.remove(riderId);
  }

  @override
  Future<PendingFareLock?> loadForRider(String riderId) async =>
      pending[riderId];

  @override
  Future<PendingFareLockSlot> inspectForRider(String riderId) async {
    final command = pending[riderId];
    return command == null
        ? const PendingFareLockSlot.absent()
        : PendingFareLockSlot.valid(command);
  }

  @override
  Future<void> save(PendingFareLock command) async {
    pending[command.riderId] = command;
  }
}

class _FareHarness {
  _FareHarness(this.reader) {
    repository = SupabaseFareRepository(
      bookingMutationGate: (dispatch) => dispatch(),
      rpc: ({required name, required params}) async {
        rpcCalls++;
        throw StateError('The Payment Method screen must not call an RPC.');
      },
      quoteEdge: (_) async {
        quoteCalls++;
        throw StateError('The Payment Method screen must not request a fare.');
      },
      canonicalReader: ({required bookingRequestId, required riderId}) {
        reads++;
        readIdentities.add((bookingRequestId, riderId));
        return reader(bookingRequestId: bookingRequestId, riderId: riderId);
      },
      bookingConfirmer: ({
        required bookingRequestId,
        required expectedVersion,
        required idempotencyKey,
        required riderId,
      }) async {
        confirmationCalls++;
        return {
          'booking_request_id': bookingRequestId,
          'status': 'confirmed',
        };
      },
    );
  }

  final Future<List<Map<String, dynamic>>> Function({
    required String bookingRequestId,
    required String riderId,
  }) reader;
  final store = _MemoryLockStore();
  final auth = _AuthRepository(_riderA);
  late final SupabaseFareRepository repository;
  late final ProviderContainer container = ProviderContainer(overrides: [
    appRouterProvider.overrideWithValue(router),
    appearancePreferencesProvider.overrideWithValue(
      InMemoryAppearancePreferences(),
    ),
    authRepositoryProvider.overrideWithValue(auth),
    fareRepositoryProvider.overrideWithValue(repository),
    pendingFareLockStoreProvider.overrideWithValue(store),
    appErrorReporterProvider.overrideWithValue(const NoopAppErrorReporter()),
  ]);
  final List<(String, String)> readIdentities = [];
  int reads = 0;
  int rpcCalls = 0;
  int quoteCalls = 0;
  int confirmationCalls = 0;

  late final GoRouter router = GoRouter(
    initialLocation: '/payment-method',
    routes: [
      GoRoute(
        path: '/payment-method',
        name: 'testPaymentMethod',
        builder: (_, __) => PaymentMethodScreen(
          data: PaymentMethodRouteData(quote: _quote(), riderId: _riderA.id),
        ),
      ),
      GoRoute(
        path: '/rider/confirmation',
        name: RouteNames.confirmation,
        builder: (_, state) => BookingConfirmationScreen(
          bookingRequestId: state.uri.queryParameters['booking'],
        ),
      ),
    ],
  );

  Future<void> mount(WidgetTester tester) async {
    await container.read(sessionControllerProvider.notifier).refreshSession();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    ));
  }

  Future<void> mountWithRideXApp(WidgetTester tester) async {
    await container.read(sessionControllerProvider.notifier).refreshSession();
    await pumpRideXApp(tester);
  }

  Future<void> pumpRideXApp(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const RideXApp(),
    ));
  }

  void dispose() {
    router.dispose();
    container.dispose();
  }
}

Finder get _continueButton => find.byType(AppButton).first;

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  group('canonical payment method screen authority', () {
    testWidgets(
        'canonical Cash verifies booking and fare, then opens review only',
        (tester) async {
      final gate = Completer<List<Map<String, dynamic>>>();
      final started = Completer<void>();
      final harness = _FareHarness(
        ({required bookingRequestId, required riderId}) {
          if (!started.isCompleted) started.complete();
          return gate.future;
        },
      );
      addTearDown(harness.dispose);

      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );

      await harness.mountWithRideXApp(tester);
      await tester.pump();
      await started.future;
      expect(find.text('Verifying payment method'), findsOneWidget);
      expect(tester.widget<AppButton>(_continueButton).onPressed, isNull);
      gate.complete([_bookingRow(method: 'cash')]);
      await _settle(tester);

      expect(harness.readIdentities, [("booking-r08", _riderA.id)]);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Payment method locked with this fare'), findsOneWidget);
      expect(find.text('JOD 2.15'), findsNWidgets(2));
      expect(find.text('Continue with Cash'), findsOneWidget);
      expect(tester.widget<AppButton>(_continueButton).onPressed, isNotNull);
      expect(
          harness.container.read(pendingFareLockControllerProvider), _command);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
      final cashCard = find.byWidgetPredicate((widget) =>
          widget is Semantics &&
          widget.properties.label == 'Cash, Pay your driver after the trip');
      final cardCard = find.byWidgetPredicate((widget) =>
          widget is Semantics &&
          widget.properties.label ==
              'Card, Pay securely with your card, Currently unavailable');
      expect(tester.widget<Semantics>(cashCard).properties.enabled, isFalse);
      expect(tester.widget<Semantics>(cardCard).properties.enabled, isFalse);

      final themeController =
          harness.container.read(appearanceThemeModeProvider.notifier);
      for (final mode in [ThemeMode.light, ThemeMode.dark, ThemeMode.system]) {
        await themeController.setThemeMode(mode);
        await _settle(tester);
        expect(find.text('Cash'), findsOneWidget);
        expect(find.text('Continue with Cash'), findsOneWidget);
        expect(tester.widget<AppButton>(_continueButton).onPressed, isNotNull);
      }
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await _settle(tester);
      expect(find.text('Cash'), findsOneWidget);
      expect(tester.widget<AppButton>(_continueButton).onPressed, isNotNull);

      await tester.tap(_continueButton);
      await _settle(tester);

      expect(find.byType(BookingConfirmationScreen), findsOneWidget);
      expect(
          find.text('Fare locked — booking not yet confirmed'), findsOneWidget);
      expect(harness.confirmationCalls, 0);
      expect(harness.rpcCalls, 0);
      expect(harness.quoteCalls, 0);
    });

    testWidgets('canonical Card overrides session-local Cash and stays blocked',
        (tester) async {
      final harness = _FareHarness(
        ({required bookingRequestId, required riderId}) async =>
            [_bookingRow(method: 'card')],
      );
      addTearDown(harness.dispose);
      await harness.container
          .read(sessionControllerProvider.notifier)
          .refreshSession();
      harness.container
          .read(riderPaymentSelectionProvider.notifier)
          .selectCash();

      await harness.pumpRideXApp(tester);
      await _settle(tester);

      expect(find.text('Card'), findsOneWidget);
      expect(find.text('Selected'), findsOneWidget);
      expect(find.text('Currently unavailable'), findsOneWidget);
      expect(find.text('Card currently unavailable'), findsOneWidget);
      expect(
          find.textContaining('Card payment is unavailable'), findsOneWidget);
      expect(tester.widget<AppButton>(_continueButton).onPressed, isNull);
      expect(harness.confirmationCalls, 0);
      expect(harness.rpcCalls, 0);
      expect(harness.quoteCalls, 0);
      expect(harness.readIdentities.single, ('booking-r08', _riderA.id));

      final themeController =
          harness.container.read(appearanceThemeModeProvider.notifier);
      for (final mode in [ThemeMode.light, ThemeMode.dark, ThemeMode.system]) {
        await themeController.setThemeMode(mode);
        await _settle(tester);
        expect(find.text('Card'), findsOneWidget);
        expect(find.text('Card currently unavailable'), findsOneWidget);
        expect(tester.widget<AppButton>(_continueButton).onPressed, isNull);
        expect(harness.confirmationCalls, 0);
        expect(harness.rpcCalls, 0);
        expect(harness.quoteCalls, 0);
      }
    });

    testWidgets('same Rider logout and login reloads canonical method',
        (tester) async {
      final harness = _FareHarness(
        ({required bookingRequestId, required riderId}) async =>
            [_bookingRow(method: 'cash')],
      );
      addTearDown(harness.dispose);
      await harness.mount(tester);
      await _settle(tester);
      expect(tester.widget<AppButton>(_continueButton).onPressed, isNotNull);

      harness.auth.user = null;
      await harness.container
          .read(sessionControllerProvider.notifier)
          .refreshSession();
      await _settle(tester);
      expect(tester.widget<AppButton>(_continueButton).onPressed, isNull);
      expect(
          find.textContaining('Rider session is unavailable'), findsOneWidget);

      harness.auth.user = _riderA;
      await harness.container
          .read(sessionControllerProvider.notifier)
          .refreshSession();
      await _settle(tester);
      expect(tester.widget<AppButton>(_continueButton).onPressed, isNotNull);
      expect(harness.reads, 2);
    });

    testWidgets('Rider A to B disables; returning to A re-reads its booking',
        (tester) async {
      final harness = _FareHarness(
        ({required bookingRequestId, required riderId}) async =>
            [_bookingRow(method: 'cash')],
      );
      addTearDown(harness.dispose);
      await harness.mount(tester);
      await _settle(tester);

      harness.auth.user = _riderB;
      await harness.container
          .read(sessionControllerProvider.notifier)
          .refreshSession();
      await _settle(tester);
      expect(tester.widget<AppButton>(_continueButton).onPressed, isNull);

      harness.auth.user = _riderA;
      await harness.container
          .read(sessionControllerProvider.notifier)
          .refreshSession();
      await _settle(tester);
      expect(tester.widget<AppButton>(_continueButton).onPressed, isNotNull);
      expect(harness.reads, 2);
      expect(harness.readIdentities, everyElement(('booking-r08', _riderA.id)));
    });

    testWidgets('logout while canonical read is pending discards late Cash',
        (tester) async {
      final gate = Completer<List<Map<String, dynamic>>>();
      final started = Completer<void>();
      final harness = _FareHarness(
        ({required bookingRequestId, required riderId}) {
          started.complete();
          return gate.future;
        },
      );
      addTearDown(harness.dispose);
      await harness.mount(tester);
      await tester.pump();
      await started.future;
      expect(tester.widget<AppButton>(_continueButton).onPressed, isNull);

      harness.auth.user = null;
      await harness.container
          .read(sessionControllerProvider.notifier)
          .refreshSession();
      await tester.pump();
      gate.complete([_bookingRow(method: 'cash')]);
      await _settle(tester);

      expect(tester.widget<AppButton>(_continueButton).onPressed, isNull);
      expect(find.byType(BookingConfirmationScreen), findsNothing);
      expect(harness.confirmationCalls, 0);
    });

    testWidgets('old Rider response after A to B to A cannot overwrite latest',
        (tester) async {
      final first = Completer<List<Map<String, dynamic>>>();
      final second = Completer<List<Map<String, dynamic>>>();
      final secondStarted = Completer<void>();
      var calls = 0;
      final harness = _FareHarness(
        ({required bookingRequestId, required riderId}) {
          calls++;
          if (calls == 1) return first.future;
          secondStarted.complete();
          return second.future;
        },
      );
      addTearDown(harness.dispose);
      await harness.mount(tester);
      await tester.pump();

      harness.auth.user = _riderB;
      await harness.container
          .read(sessionControllerProvider.notifier)
          .refreshSession();
      await tester.pump();
      harness.auth.user = _riderA;
      await harness.container
          .read(sessionControllerProvider.notifier)
          .refreshSession();
      await tester.pump();

      first.complete([_bookingRow(method: 'card')]);
      await tester.pump();
      await secondStarted.future;
      expect(tester.widget<AppButton>(_continueButton).onPressed, isNull);
      second.complete([_bookingRow(method: 'cash')]);
      await _settle(tester);

      expect(tester.widget<AppButton>(_continueButton).onPressed, isNotNull);
      expect(find.text('Continue with Cash'), findsOneWidget);
      expect(calls, 2);
      expect(harness.confirmationCalls, 0);
    });

    testWidgets('Continue revalidates and rejects a changed Card method',
        (tester) async {
      var reads = 0;
      final harness = _FareHarness(
        ({required bookingRequestId, required riderId}) async {
          reads++;
          return [_bookingRow(method: reads == 1 ? 'cash' : 'card')];
        },
      );
      addTearDown(harness.dispose);
      await harness.mount(tester);
      await _settle(tester);
      expect(tester.widget<AppButton>(_continueButton).onPressed, isNotNull);

      await tester.tap(_continueButton);
      await _settle(tester);

      expect(reads, 2);
      expect(find.byType(BookingConfirmationScreen), findsNothing);
      expect(tester.widget<AppButton>(_continueButton).onPressed, isNull);
      expect(find.text('Card currently unavailable'), findsOneWidget);
      expect(harness.confirmationCalls, 0);
    });

    testWidgets('Continue rejects a quote lock that became stale',
        (tester) async {
      var reads = 0;
      final harness = _FareHarness(
        ({required bookingRequestId, required riderId}) async {
          reads++;
          return [
            reads == 1
                ? _bookingRow(method: 'cash')
                : _bookingRow(
                    method: 'cash',
                    version: 3,
                    linkedQuote: null,
                    quoteStatus: 'superseded')
          ];
        },
      );
      addTearDown(harness.dispose);
      await harness.mount(tester);
      await _settle(tester);

      await tester.tap(_continueButton);
      await _settle(tester);

      expect(reads, 2);
      expect(find.byType(BookingConfirmationScreen), findsNothing);
      expect(tester.widget<AppButton>(_continueButton).onPressed, isNull);
      expect(harness.confirmationCalls, 0);
    });

    testWidgets('canonical verification failure during Continue stays blocked',
        (tester) async {
      var reads = 0;
      final harness = _FareHarness(
        ({required bookingRequestId, required riderId}) async {
          reads++;
          if (reads == 1) return [_bookingRow(method: 'cash')];
          throw const FareException(FareFailure.networkFailure);
        },
      );
      addTearDown(harness.dispose);
      await harness.mount(tester);
      await _settle(tester);

      await tester.tap(_continueButton);
      await _settle(tester);

      expect(reads, 2);
      expect(find.byType(BookingConfirmationScreen), findsNothing);
      expect(tester.widget<AppButton>(_continueButton).onPressed, isNull);
      expect(harness.confirmationCalls, 0);
      expect(harness.rpcCalls, 0);
      expect(harness.quoteCalls, 0);
    });

    testWidgets('rapid Continue taps cause one fresh read and one navigation',
        (tester) async {
      final gate = Completer<List<Map<String, dynamic>>>();
      var reads = 0;
      final harness = _FareHarness(
        ({required bookingRequestId, required riderId}) {
          reads++;
          return reads == 1
              ? Future.value([_bookingRow(method: 'cash')])
              : gate.future;
        },
      );
      addTearDown(harness.dispose);
      await harness.mount(tester);
      await _settle(tester);

      await tester.tap(_continueButton);
      await tester.pump();
      await tester.tap(_continueButton, warnIfMissed: false);
      await tester.pump();
      expect(reads, 2);
      expect(tester.widget<AppButton>(_continueButton).onPressed, isNull);

      gate.complete([_bookingRow(method: 'cash')]);
      await tester.pump();
      await _settle(tester);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(BookingConfirmationScreen), findsOneWidget,
          reason: 'reader calls: $reads');
      expect(harness.reads, 3);
      expect(harness.confirmationCalls, 0);
      expect(harness.rpcCalls, 0);
      expect(harness.quoteCalls, 0);
    });
  });
}
