import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/auth_repository.dart';
import 'package:ridex/core/repositories/canonical_payment_repository.dart';
import 'package:ridex/core/repositories/card_payment_repository.dart';
import 'package:ridex/core/repositories/payment_repository.dart';
import 'package:ridex/features/history/presentation/providers/rider_payment_providers.dart';
import 'package:ridex/features/history/presentation/widgets/rider_payment_status_card.dart';

const _riderA = AppUser(
  id: 'rider-a',
  name: 'Rider A',
  email: 'rider-a@ridex.app',
  role: RideRole.rider,
);

const _riderB = AppUser(
  id: 'rider-b',
  name: 'Rider B',
  email: 'rider-b@ridex.app',
  role: RideRole.rider,
);

CashPayment _cash({
  CashPaymentStatus status = CashPaymentStatus.cashSelected,
  String? paymentId = 'payment-1',
  String? tripId = 'trip-1',
  String? bookingRequestId = 'booking-1',
  int amountFils = 7350,
}) => CashPayment(
  paymentId: paymentId,
  tripId: tripId,
  bookingRequestId: bookingRequestId,
  amountFils: amountFils,
  status: status,
  version: 3,
);

CardPayment _card({
  CardPaymentStatus status = CardPaymentStatus.cardPaymentSucceeded,
  String? paymentId = 'payment-1',
  String? tripId = 'trip-1',
  String? bookingRequestId = 'booking-1',
  int amountFils = 7350,
  String? cardBrand,
  String? cardLastFour,
}) => CardPayment(
  paymentId: paymentId,
  tripId: tripId,
  bookingRequestId: bookingRequestId,
  amountFils: amountFils,
  status: status,
  version: 3,
  cardBrand: cardBrand,
  cardLastFour: cardLastFour,
);

/// Recording reader wrapper around the canonical fixture fake.
///
/// [PaymentRepository] exposes only reads, so the wrapper can record every
/// attempted read ID, fail a bounded number of times, and hold one read
/// pending on a completer. Delegated reads return the seeded canonical
/// [CashPayment] fixture unchanged.
class _RecordingCashRepository implements PaymentRepository {
  _RecordingCashRepository([FakePaymentRepository? inner])
    : inner = inner ?? FakePaymentRepository();

  final FakePaymentRepository inner;
  final List<String> readIds = [];
  Object? nextError;

  /// When set, the next read waits on this completer instead of the fixture.
  Completer<CashPayment>? gate;

  @override
  Future<CashPayment> readCashPayment({required String paymentId}) async {
    readIds.add(paymentId);
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    final pending = gate;
    if (pending != null) {
      gate = null;
      return pending.future;
    }
    return inner.readCashPayment(paymentId: paymentId);
  }
}

/// Card-side counterpart of [_RecordingCashRepository].
class _RecordingCardRepository implements CardPaymentRepository {
  _RecordingCardRepository([FakeCardPaymentRepository? inner])
    : inner = inner ?? FakeCardPaymentRepository();

  final FakeCardPaymentRepository inner;
  final List<String> readIds = [];
  Object? nextError;
  Completer<CardPayment>? gate;

  @override
  Future<CardPayment> readCardPayment({required String paymentId}) async {
    readIds.add(paymentId);
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    final pending = gate;
    if (pending != null) {
      gate = null;
      return pending.future;
    }
    return inner.readCardPayment(paymentId: paymentId);
  }
}

/// Minimal controllable [AuthRepository] driving the real [SessionController]
/// so session-isolation tests exercise the production listener path.
class _SwitchableAuthRepository implements AuthRepository {
  _SwitchableAuthRepository(this.user);

  AppUser? user;

  @override
  Stream<void> authStateChanges() => const Stream<void>.empty();

  @override
  Future<AppUser?> restoreSession() async => user;

  @override
  Future<AppUser> continueAsDemo() async => user ?? _riderA;

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    return user ?? _riderA;
  }

  @override
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    return user ?? _riderA;
  }

  @override
  Future<void> signOut() async {
    user = null;
  }
}

Future<ProviderContainer> _container({
  PaymentRepository? cashRepository,
  CardPaymentRepository? cardRepository,
  AuthRepository? authRepository,
}) async {
  final container = ProviderContainer(
    overrides: [
      if (cashRepository != null)
        riderCashPaymentRepositoryProvider.overrideWithValue(cashRepository),
      if (cardRepository != null)
        riderCardPaymentRepositoryProvider.overrideWithValue(cardRepository),
      authRepositoryProvider.overrideWithValue(
        authRepository ?? _SwitchableAuthRepository(_riderA),
      ),
    ],
  );
  addTearDown(container.dispose);
  // Settle the session before any read: reads require an authenticated
  // Rider session at request time, and a session transition while a read
  // is pending resets the state. The session controller's build-time
  // refresh microtask must not race the reads.
  await container.read(sessionControllerProvider.notifier).refreshSession();
  return container;
}

RiderPaymentReadState _stateOf(ProviderContainer container) =>
    container.read(riderPaymentReadControllerProvider);

void main() {
  group('Read-state management', () {
    test('missing or blank payment ID resolves to unavailable', () async {
      final repository = _RecordingCashRepository();
      final container = await _container(cashRepository: repository);
      final notifier = container.read(
        riderPaymentReadControllerProvider.notifier,
      );

      await notifier.readPayment(paymentId: null, method: PaymentMethod.cash);
      expect(_stateOf(container), isA<RiderPaymentUnavailable>());

      await notifier.readPayment(paymentId: '   ', method: PaymentMethod.cash);
      expect(_stateOf(container), isA<RiderPaymentUnavailable>());

      expect(repository.readIds, isEmpty);
    });

    test(
      'default configuration has no approved reader and fails closed',
      () async {
        final container = await _container();
        final notifier = container.read(
          riderPaymentReadControllerProvider.notifier,
        );

        await notifier.readPayment(
          paymentId: 'payment-1',
          method: PaymentMethod.cash,
        );
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());

        await notifier.readPayment(
          paymentId: 'payment-1',
          method: PaymentMethod.card,
        );
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());
      },
    );

    test('reads a canonical Cash record through the injected reader', () async {
      final inner = FakePaymentRepository()..seedCashPayment(_cash());
      final repository = _RecordingCashRepository(inner);
      final container = await _container(cashRepository: repository);

      await container
          .read(riderPaymentReadControllerProvider.notifier)
          .readPayment(paymentId: 'payment-1', method: PaymentMethod.cash);

      final state = _stateOf(container);
      expect(state, isA<RiderPaymentReady>());
      final presentation = (state as RiderPaymentReady).presentation;
      expect(presentation.methodLabel, 'Cash');
      expect(presentation.statusLabel, 'Cash selected (unpaid)');
      expect(presentation.amountFils, 7350);
      expect(presentation.formattedAmount, 'JOD 7.35');
      expect(repository.readIds, ['payment-1']);
    });

    test('reads a canonical Card record through the injected reader', () async {
      final inner = FakeCardPaymentRepository()
        ..seedCardPayment(
          _card(
            status: CardPaymentStatus.cardPaymentAuthorized,
            cardBrand: 'Visa',
            cardLastFour: '4242',
          ),
        );
      final repository = _RecordingCardRepository(inner);
      final container = await _container(cardRepository: repository);

      await container
          .read(riderPaymentReadControllerProvider.notifier)
          .readPayment(paymentId: 'payment-1', method: PaymentMethod.card);

      final state = _stateOf(container);
      expect(state, isA<RiderPaymentReady>());
      final presentation = (state as RiderPaymentReady).presentation;
      expect(presentation.methodLabel, 'Card');
      expect(presentation.statusLabel, 'Authorized (not captured)');
      expect(presentation.formattedAmount, 'JOD 7.35');
      expect(repository.readIds, ['payment-1']);
    });

    test('shows loading while an accepted read is pending', () async {
      final repository = _RecordingCashRepository();
      final gate = Completer<CashPayment>();
      repository.gate = gate;
      final container = await _container(cashRepository: repository);
      final notifier = container.read(
        riderPaymentReadControllerProvider.notifier,
      );

      final read = notifier.readPayment(
        paymentId: 'payment-1',
        method: PaymentMethod.cash,
      );
      expect(_stateOf(container), isA<RiderPaymentLoading>());

      gate.complete(_cash());
      await read;
      expect(_stateOf(container), isA<RiderPaymentReady>());
    });

    test(
      'successful read never produces unauthorized success claims',
      () async {
        final inner = FakeCardPaymentRepository()
          ..seedCardPayment(
            _card(status: CardPaymentStatus.cardPaymentSucceeded),
          );
        final repository = _RecordingCardRepository(inner);
        final container = await _container(cardRepository: repository);

        await container
            .read(riderPaymentReadControllerProvider.notifier)
            .readPayment(paymentId: 'payment-1', method: PaymentMethod.card);

        final state = _stateOf(container);
        expect(state, isA<RiderPaymentReady>());
        final presentation = (state as RiderPaymentReady).presentation;
        expect(presentation.canDescribeAsPaid, isFalse);
        expect(presentation.statusLabel, 'Success status reported');

        final display = RiderPaymentStatusDisplay.failClosed(presentation);
        expect(display.title, 'Success status reported');
        expect(
          display.title,
          isNot(anyOf('Payment captured', 'Payment completed')),
        );
        expect(display.unverifiedSuccess, isFalse);
        expect(display.markerLabel, isNull);
      },
    );

    test('a missing canonical record resolves to unavailable', () async {
      final repository = _RecordingCashRepository();
      final container = await _container(cashRepository: repository);

      await container
          .read(riderPaymentReadControllerProvider.notifier)
          .readPayment(paymentId: 'missing-1', method: PaymentMethod.cash);

      expect(_stateOf(container), isA<RiderPaymentUnavailable>());
      expect(repository.readIds, ['missing-1']);
    });

    test(
      'invalidRequest resolves to unavailable, not a read failure',
      () async {
        final repository = _RecordingCashRepository()
          ..nextError = const PaymentException(PaymentFailure.invalidRequest);
        final container = await _container(cashRepository: repository);

        await container
            .read(riderPaymentReadControllerProvider.notifier)
            .readPayment(paymentId: 'payment-1', method: PaymentMethod.cash);

        expect(_stateOf(container), isA<RiderPaymentUnavailable>());
        expect(repository.readIds, ['payment-1']);
      },
    );

    test(
      'canonical authorization rejection has a distinct safe state',
      () async {
        final repository = _RecordingCashRepository()
          ..nextError = const CanonicalPaymentReadException(
            CanonicalPaymentReadFailure.unauthorized,
          );
        final container = await _container(cashRepository: repository);

        await container
            .read(riderPaymentReadControllerProvider.notifier)
            .readPayment(paymentId: 'payment-1', method: PaymentMethod.cash);

        expect(_stateOf(container), isA<RiderPaymentAuthorizationFailure>());
      },
    );

    testWidgets(
      'unexpected repository errors render a sanitized read failure',
      (tester) async {
        final repository = _RecordingCashRepository()
          ..nextError = StateError('internal detail db-42');
        final container = await _container(cashRepository: repository);
        final notifier = container.read(
          riderPaymentReadControllerProvider.notifier,
        );

        await notifier.readPayment(
          paymentId: 'payment-1',
          method: PaymentMethod.cash,
        );
        final state = _stateOf(container);
        expect(state, isA<RiderPaymentReadFailure>());

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: RiderPaymentStatusCard(
                readState: state,
                onRetry: notifier.retry,
              ),
            ),
          ),
        );
        expect(find.text('Payment status could not be loaded'), findsOneWidget);
        expect(find.text('Payment failed'), findsNothing);
        expect(find.textContaining('db-42'), findsNothing);
        expect(find.textContaining('internal detail'), findsNothing);
      },
    );

    test('retry re-reads after a failed read and no-ops otherwise', () async {
      final inner = FakePaymentRepository()
        ..seedCashPayment(_cash(status: CashPaymentStatus.paid));
      final repository = _RecordingCashRepository(inner)
        ..nextError = StateError('transient');
      final container = await _container(cashRepository: repository);
      final notifier = container.read(
        riderPaymentReadControllerProvider.notifier,
      );

      await notifier.readPayment(
        paymentId: 'payment-1',
        method: PaymentMethod.cash,
      );
      expect(_stateOf(container), isA<RiderPaymentReadFailure>());

      await notifier.retry();
      expect(_stateOf(container), isA<RiderPaymentReady>());
      expect(repository.readIds, ['payment-1', 'payment-1']);

      await notifier.retry();
      expect(repository.readIds, ['payment-1', 'payment-1']);
    });

    test('retry never creates or mutates the payment record', () async {
      final seeded = _card(
        status: CardPaymentStatus.cardPaymentAuthorized,
        cardBrand: 'Visa',
        cardLastFour: '4242',
      );
      final inner = FakeCardPaymentRepository()..seedCardPayment(seeded);
      final repository = _RecordingCardRepository(inner)
        ..nextError = StateError('transient');
      final container = await _container(cardRepository: repository);
      final notifier = container.read(
        riderPaymentReadControllerProvider.notifier,
      );

      await notifier.readPayment(
        paymentId: 'payment-1',
        method: PaymentMethod.card,
      );
      expect(_stateOf(container), isA<RiderPaymentReadFailure>());

      await notifier.retry();
      expect(_stateOf(container), isA<RiderPaymentReady>());

      final after = await inner.readCardPayment(paymentId: 'payment-1');
      expect(after, equals(seeded));
      expect(after.status, CardPaymentStatus.cardPaymentAuthorized);
      expect(after.amountFils, 7350);
      expect(after.version, 3);
      expect(repository.readIds, ['payment-1', 'payment-1']);
    });

    test('rapid payment ID changes discard out-of-order completions', () async {
      final inner = FakePaymentRepository()
        ..seedCashPayment(
          _cash(
            paymentId: 'pay-a',
            tripId: 'trip-a',
            bookingRequestId: 'book-a',
          ),
        )
        ..seedCashPayment(
          _cash(
            paymentId: 'pay-b',
            tripId: 'trip-b',
            bookingRequestId: 'book-b',
            status: CashPaymentStatus.paid,
          ),
        );
      final repository = _RecordingCashRepository(inner);
      final container = await _container(cashRepository: repository);
      final notifier = container.read(
        riderPaymentReadControllerProvider.notifier,
      );

      final firstGate = Completer<CashPayment>();
      repository.gate = firstGate;
      final first = notifier.readPayment(
        paymentId: 'pay-a',
        method: PaymentMethod.cash,
      );

      final secondGate = Completer<CashPayment>();
      repository.gate = secondGate;
      final second = notifier.readPayment(
        paymentId: 'pay-b',
        method: PaymentMethod.cash,
      );

      secondGate.complete(
        _cash(
          paymentId: 'pay-b',
          tripId: 'trip-b',
          bookingRequestId: 'book-b',
          status: CashPaymentStatus.paid,
        ),
      );
      await second;
      expect(
        (_stateOf(container) as RiderPaymentReady).presentation.statusLabel,
        'Paid status reported',
      );

      firstGate.complete(
        _cash(paymentId: 'pay-a', tripId: 'trip-a', bookingRequestId: 'book-a'),
      );
      await first;
      final afterLate = _stateOf(container);
      expect(afterLate, isA<RiderPaymentReady>());
      expect(
        (afterLate as RiderPaymentReady).presentation.statusLabel,
        'Paid status reported',
      );
      expect(repository.readIds, ['pay-a', 'pay-b']);
    });

    test(
      'logout while a read is pending cannot publish the response',
      () async {
        final inner = FakePaymentRepository()..seedCashPayment(_cash());
        final repository = _RecordingCashRepository(inner);
        final auth = _SwitchableAuthRepository(_riderA);
        final container = await _container(
          cashRepository: repository,
          authRepository: auth,
        );
        expect(
          container.read(sessionControllerProvider).status,
          SessionStatus.authenticated,
        );

        final notifier = container.read(
          riderPaymentReadControllerProvider.notifier,
        );
        final gate = Completer<CashPayment>();
        repository.gate = gate;
        final read = notifier.readPayment(
          paymentId: 'payment-1',
          method: PaymentMethod.cash,
        );
        expect(_stateOf(container), isA<RiderPaymentLoading>());

        auth.user = null;
        await container
            .read(sessionControllerProvider.notifier)
            .refreshSession();
        expect(
          container.read(sessionControllerProvider).status,
          SessionStatus.unauthenticated,
        );
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());

        gate.complete(_cash());
        await read;
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());
        expect(repository.readIds, ['payment-1']);

        await notifier.retry();
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());
        expect(repository.readIds, ['payment-1']);
      },
    );

    test('rider identity change cannot expose the previous response', () async {
      final inner = FakePaymentRepository()..seedCashPayment(_cash());
      final repository = _RecordingCashRepository(inner);
      final auth = _SwitchableAuthRepository(_riderA);
      final container = await _container(
        cashRepository: repository,
        authRepository: auth,
      );
      expect(container.read(sessionControllerProvider).user?.id, 'rider-a');

      final gate = Completer<CashPayment>();
      repository.gate = gate;
      final read = container
          .read(riderPaymentReadControllerProvider.notifier)
          .readPayment(paymentId: 'payment-1', method: PaymentMethod.cash);

      auth.user = _riderB;
      await container.read(sessionControllerProvider.notifier).refreshSession();
      expect(container.read(sessionControllerProvider).user?.id, 'rider-b');
      expect(_stateOf(container), isA<RiderPaymentUnavailable>());

      gate.complete(_cash());
      await read;
      expect(_stateOf(container), isA<RiderPaymentUnavailable>());
    });

    test(
      'retry racing a newer payment request discards the older completion',
      () async {
        final inner = FakePaymentRepository()
          ..seedCashPayment(
            _cash(
              paymentId: 'pay-a',
              tripId: 'trip-a',
              bookingRequestId: 'book-a',
            ),
          )
          ..seedCashPayment(
            _cash(
              paymentId: 'pay-b',
              tripId: 'trip-b',
              bookingRequestId: 'book-b',
              status: CashPaymentStatus.paid,
            ),
          );
        final repository = _RecordingCashRepository(inner)
          ..nextError = StateError('transient');
        final container = await _container(cashRepository: repository);
        final notifier = container.read(
          riderPaymentReadControllerProvider.notifier,
        );

        await notifier.readPayment(
          paymentId: 'pay-a',
          method: PaymentMethod.cash,
        );
        expect(_stateOf(container), isA<RiderPaymentReadFailure>());
        expect(repository.readIds, ['pay-a']);

        final retryGate = Completer<CashPayment>();
        repository.gate = retryGate;
        final retryRead = notifier.retry();
        expect(_stateOf(container), isA<RiderPaymentLoading>());
        expect(repository.readIds, ['pay-a', 'pay-a']);

        final newerGate = Completer<CashPayment>();
        repository.gate = newerGate;
        final newerRead = notifier.readPayment(
          paymentId: 'pay-b',
          method: PaymentMethod.cash,
        );
        expect(repository.readIds, ['pay-a', 'pay-a', 'pay-b']);

        newerGate.complete(
          _cash(
            paymentId: 'pay-b',
            tripId: 'trip-b',
            bookingRequestId: 'book-b',
            status: CashPaymentStatus.paid,
          ),
        );
        await newerRead;
        expect(
          (_stateOf(container) as RiderPaymentReady).presentation.statusLabel,
          'Paid status reported',
        );

        retryGate.complete(
          _cash(
            paymentId: 'pay-a',
            tripId: 'trip-a',
            bookingRequestId: 'book-a',
          ),
        );
        await retryRead;
        expect(
          (_stateOf(container) as RiderPaymentReady).presentation.statusLabel,
          'Paid status reported',
        );
        expect(repository.readIds, ['pay-a', 'pay-a', 'pay-b']);
      },
    );

    test(
      'a stale read error after identity change cannot publish a failure',
      () async {
        final inner = FakePaymentRepository()..seedCashPayment(_cash());
        final repository = _RecordingCashRepository(inner);
        final auth = _SwitchableAuthRepository(_riderA);
        final container = await _container(
          cashRepository: repository,
          authRepository: auth,
        );

        final gate = Completer<CashPayment>();
        repository.gate = gate;
        final read = container
            .read(riderPaymentReadControllerProvider.notifier)
            .readPayment(paymentId: 'payment-1', method: PaymentMethod.cash);
        expect(_stateOf(container), isA<RiderPaymentLoading>());

        auth.user = _riderB;
        await container
            .read(sessionControllerProvider.notifier)
            .refreshSession();
        expect(container.read(sessionControllerProvider).user?.id, 'rider-b');
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());

        gate.completeError(StateError('stale transport error'));
        await read;
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());
        expect(repository.readIds, ['payment-1']);
      },
    );

    test(
      'provider invalidation during an in-flight read discards it',
      () async {
        final inner = FakePaymentRepository()..seedCashPayment(_cash());
        final repository = _RecordingCashRepository(inner);
        final container = await _container(cashRepository: repository);
        final notifier = container.read(
          riderPaymentReadControllerProvider.notifier,
        );

        final gate = Completer<CashPayment>();
        repository.gate = gate;
        final read = notifier.readPayment(
          paymentId: 'payment-1',
          method: PaymentMethod.cash,
        );
        expect(_stateOf(container), isA<RiderPaymentLoading>());

        container.invalidate(riderPaymentReadControllerProvider);
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());

        gate.complete(_cash());
        await read;
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());
        expect(repository.readIds, ['payment-1']);
      },
    );

    test(
      'read initiated while logged out fails closed without repository calls',
      () async {
        final cash = _RecordingCashRepository();
        final card = _RecordingCardRepository();
        final container = await _container(
          cashRepository: cash,
          cardRepository: card,
          authRepository: _SwitchableAuthRepository(null),
        );
        expect(
          container.read(sessionControllerProvider).status,
          SessionStatus.unauthenticated,
        );
        final notifier = container.read(
          riderPaymentReadControllerProvider.notifier,
        );

        await notifier.readPayment(
          paymentId: 'payment-1',
          method: PaymentMethod.cash,
        );
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());

        await notifier.readPayment(
          paymentId: 'payment-1',
          method: PaymentMethod.card,
        );
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());

        expect(cash.readIds, isEmpty);
        expect(card.readIds, isEmpty);
      },
    );

    test(
      'read during session loading fails closed without repository calls',
      () async {
        final repository = _RecordingCashRepository();
        final container = ProviderContainer(
          overrides: [
            riderCashPaymentRepositoryProvider.overrideWithValue(repository),
            authRepositoryProvider.overrideWithValue(
              _SwitchableAuthRepository(_riderA),
            ),
          ],
        );
        addTearDown(container.dispose);
        expect(
          container.read(sessionControllerProvider).status,
          SessionStatus.loading,
        );
        final notifier = container.read(
          riderPaymentReadControllerProvider.notifier,
        );

        await notifier.readPayment(
          paymentId: 'payment-1',
          method: PaymentMethod.cash,
        );
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());
        expect(repository.readIds, isEmpty);

        await container
            .read(sessionControllerProvider.notifier)
            .refreshSession();
        expect(
          container.read(sessionControllerProvider).status,
          SessionStatus.authenticated,
        );
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());
      },
    );

    test('read with an authenticated non-Rider role fails closed', () async {
      const driver = AppUser(
        id: 'driver-1',
        name: 'Driver',
        email: 'driver@ridex.app',
        role: RideRole.driver,
        driverApprovalStatus: DriverApprovalStatus.approved,
      );
      final repository = _RecordingCashRepository();
      final container = await _container(
        cashRepository: repository,
        authRepository: _SwitchableAuthRepository(driver),
      );
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
      expect(container.read(sessionControllerProvider).role, RideRole.driver);

      await container
          .read(riderPaymentReadControllerProvider.notifier)
          .readPayment(paymentId: 'payment-1', method: PaymentMethod.cash);

      expect(_stateOf(container), isA<RiderPaymentUnavailable>());
      expect(repository.readIds, isEmpty);
    });

    test('read with a blank Rider identity fails closed', () async {
      const blankRider = AppUser(
        id: '  ',
        name: 'Blank',
        email: 'blank@ridex.app',
        role: RideRole.rider,
      );
      final repository = _RecordingCashRepository();
      final container = await _container(
        cashRepository: repository,
        authRepository: _SwitchableAuthRepository(blankRider),
      );
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );

      await container
          .read(riderPaymentReadControllerProvider.notifier)
          .readPayment(paymentId: 'payment-1', method: PaymentMethod.cash);

      expect(_stateOf(container), isA<RiderPaymentUnavailable>());
      expect(repository.readIds, isEmpty);
    });

    test('invalid-session read clears retry eligibility', () async {
      final inner = FakePaymentRepository()
        ..seedCashPayment(_cash(status: CashPaymentStatus.paid));
      final repository = _RecordingCashRepository(inner)
        ..nextError = StateError('transient');
      final auth = _SwitchableAuthRepository(_riderA);
      final container = await _container(
        cashRepository: repository,
        authRepository: auth,
      );
      final notifier = container.read(
        riderPaymentReadControllerProvider.notifier,
      );

      await notifier.readPayment(
        paymentId: 'payment-1',
        method: PaymentMethod.cash,
      );
      expect(_stateOf(container), isA<RiderPaymentReadFailure>());
      expect(repository.readIds, ['payment-1']);

      auth.user = null;
      await container.read(sessionControllerProvider.notifier).refreshSession();
      expect(_stateOf(container), isA<RiderPaymentUnavailable>());

      await notifier.readPayment(
        paymentId: 'payment-1',
        method: PaymentMethod.cash,
      );
      expect(_stateOf(container), isA<RiderPaymentUnavailable>());
      expect(repository.readIds, ['payment-1']);

      await notifier.retry();
      expect(_stateOf(container), isA<RiderPaymentUnavailable>());
      expect(repository.readIds, ['payment-1']);
    });

    test(
      'logout then another Rider login cannot resurrect the prior state',
      () async {
        final inner = FakePaymentRepository()
          ..seedCashPayment(_cash(status: CashPaymentStatus.paid));
        final repository = _RecordingCashRepository(inner);
        final auth = _SwitchableAuthRepository(_riderA);
        final container = await _container(
          cashRepository: repository,
          authRepository: auth,
        );
        final notifier = container.read(
          riderPaymentReadControllerProvider.notifier,
        );

        await notifier.readPayment(
          paymentId: 'payment-1',
          method: PaymentMethod.cash,
        );
        expect(_stateOf(container), isA<RiderPaymentReady>());

        auth.user = null;
        await container
            .read(sessionControllerProvider.notifier)
            .refreshSession();
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());

        await notifier.readPayment(
          paymentId: 'payment-1',
          method: PaymentMethod.cash,
        );
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());
        expect(repository.readIds, ['payment-1']);

        auth.user = _riderB;
        await container
            .read(sessionControllerProvider.notifier)
            .refreshSession();
        expect(container.read(sessionControllerProvider).user?.id, 'rider-b');
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());

        await notifier.retry();
        expect(_stateOf(container), isA<RiderPaymentUnavailable>());
        expect(repository.readIds, ['payment-1']);

        await notifier.readPayment(
          paymentId: 'payment-1',
          method: PaymentMethod.cash,
        );
        expect(_stateOf(container), isA<RiderPaymentReady>());
        expect(repository.readIds, ['payment-1', 'payment-1']);
      },
    );

    test(
      'disposal discards a pending completion without touching state',
      () async {
        final inner = FakePaymentRepository()..seedCashPayment(_cash());
        final repository = _RecordingCashRepository(inner);
        final container = ProviderContainer(
          overrides: [
            riderCashPaymentRepositoryProvider.overrideWithValue(repository),
            authRepositoryProvider.overrideWithValue(
              _SwitchableAuthRepository(_riderA),
            ),
          ],
        );
        await container
            .read(sessionControllerProvider.notifier)
            .refreshSession();
        expect(
          container.read(sessionControllerProvider).status,
          SessionStatus.authenticated,
        );
        final gate = Completer<CashPayment>();
        repository.gate = gate;
        final read = container
            .read(riderPaymentReadControllerProvider.notifier)
            .readPayment(paymentId: 'payment-1', method: PaymentMethod.cash);

        container.dispose();
        gate.complete(_cash());
        await read;
      },
    );

    test('disposal swallows a late read error without throwing', () async {
      final repository = _RecordingCashRepository();
      final gate = Completer<CashPayment>();
      repository.gate = gate;
      final container = ProviderContainer(
        overrides: [
          riderCashPaymentRepositoryProvider.overrideWithValue(repository),
          authRepositoryProvider.overrideWithValue(
            _SwitchableAuthRepository(_riderA),
          ),
        ],
      );
      await container.read(sessionControllerProvider.notifier).refreshSession();
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
      final read = container
          .read(riderPaymentReadControllerProvider.notifier)
          .readPayment(paymentId: 'payment-1', method: PaymentMethod.cash);

      container.dispose();
      gate.completeError(StateError('late transport error'));
      await read;
    });

    testWidgets(
      'read failure is never rendered as a canonical payment failure',
      (tester) async {
        final failing = _RecordingCashRepository()
          ..nextError = StateError('transport');
        final failingContainer = await _container(cashRepository: failing);
        await failingContainer
            .read(riderPaymentReadControllerProvider.notifier)
            .readPayment(paymentId: 'payment-1', method: PaymentMethod.cash);
        final failureState = _stateOf(failingContainer);
        expect(failureState, isA<RiderPaymentReadFailure>());

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: RiderPaymentStatusCard(readState: failureState),
            ),
          ),
        );
        expect(find.text('Payment status could not be loaded'), findsOneWidget);
        expect(find.text('Payment failed'), findsNothing);
        expect(find.text('Refunded'), findsNothing);

        final canonical = _RecordingCardRepository(
          FakeCardPaymentRepository()..seedCardPayment(
            _card(status: CardPaymentStatus.cardPaymentFailed),
          ),
        );
        final canonicalContainer = await _container(cardRepository: canonical);
        await canonicalContainer
            .read(riderPaymentReadControllerProvider.notifier)
            .readPayment(paymentId: 'payment-1', method: PaymentMethod.card);
        final canonicalState = _stateOf(canonicalContainer);
        expect(canonicalState, isA<RiderPaymentReady>());
        expect(
          (canonicalState as RiderPaymentReady).presentation.statusLabel,
          'Payment failed',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: RiderPaymentStatusCard(readState: canonicalState),
            ),
          ),
        );
        expect(find.text('Payment failed'), findsOneWidget);
        expect(find.text('Payment status could not be loaded'), findsNothing);
      },
    );

    test('canonical success never infers receipt issuance', () async {
      final cashRepository = _RecordingCashRepository(
        FakePaymentRepository()
          ..seedCashPayment(_cash(status: CashPaymentStatus.paid)),
      );
      final cashContainer = await _container(cashRepository: cashRepository);
      await cashContainer
          .read(riderPaymentReadControllerProvider.notifier)
          .readPayment(paymentId: 'payment-1', method: PaymentMethod.cash);
      final cashReady = _stateOf(cashContainer) as RiderPaymentReady;
      expect(cashReady.presentation.statusLabel, 'Paid status reported');
      expect(cashReady.presentation.canDescribeAsPaid, isFalse);
      expect(cashReady.presentation.issuedReceiptExists, isNull);

      final cardRepository = _RecordingCardRepository(
        FakeCardPaymentRepository()..seedCardPayment(
          _card(status: CardPaymentStatus.cardPaymentSucceeded),
        ),
      );
      final cardContainer = await _container(cardRepository: cardRepository);
      await cardContainer
          .read(riderPaymentReadControllerProvider.notifier)
          .readPayment(paymentId: 'payment-1', method: PaymentMethod.card);
      final cardReady = _stateOf(cardContainer) as RiderPaymentReady;
      expect(cardReady.presentation.statusLabel, 'Success status reported');
      expect(cardReady.presentation.canDescribeAsPaid, isFalse);
      expect(cardReady.presentation.issuedReceiptExists, isNull);
    });

    test('production provider source never references forbidden APIs', () {
      final source = File(
        'lib/features/history/presentation/providers/rider_payment_providers.dart',
      ).readAsStringSync();

      for (final forbidden in const [
        '.simulated(',
        'RiderPaymentTripEvidence',
        'tripEvidence',
        'MockTrip',
        'MockData',
        'tripsRepository',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }
      expect(source, isNot(contains(".from('payments')")));
    });
  });
}
