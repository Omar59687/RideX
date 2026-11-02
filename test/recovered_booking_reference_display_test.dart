import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/booking_handoff.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/fare_repository.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';
import 'package:ridex/core/services/fare/pending_fare_lock_store.dart';
import 'package:ridex/features/booking/presentation/screens/fare_estimate_screen.dart';

const _riderAId = 'rider-a';

const _riderA = AppUser(
  id: 'rider-a',
  name: 'Rider A',
  email: 'rider-a@example.test',
  role: RideRole.rider,
);

/// Deliberately long UUID-shaped identifier that must never be rendered as a
/// locator label.
const _rawBookingId = 'a8f3c2d1-7b4e-4f6a-9c0d-1e2f3a4b5c6d';

final _createdAt = DateTime.utc(2026, 10, 10, 12);
final _expiresAt = DateTime.utc(2030, 10, 10, 12);

FareQuote _lockedQuote({required String bookingRequestId}) => FareQuote(
      id: 'quote-$bookingRequestId',
      bookingRequestId: bookingRequestId,
      quoteVersion: 1,
      pricingVersion: 1,
      fixedFareFils: 2000,
      breakdown: const FareBreakdown(
        baseFareFils: 500,
        distanceFils: 1200,
        durationFils: 300,
        stopsFils: 0,
        subtotalFils: 2000,
        minimumFareFils: 1000,
        roundingIncrementFils: 50,
        fixedFareFils: 2000,
      ),
      status: FareQuoteStatus.locked,
      expiresAt: _expiresAt,
      createdAt: _createdAt,
      routeDistanceMeters: 5400,
      routeDurationSeconds: 720,
    );

PendingFareLock _command(
        {required String bookingRequestId, String riderId = _riderAId}) =>
    PendingFareLock(
      bookingRequestId: bookingRequestId,
      expectedBookingVersion: 3,
      fareQuoteId: 'quote-$bookingRequestId',
      expectedQuoteVersion: 1,
      riderId: riderId,
      status: PendingLockRecoveryStatus.uncertain,
      createdAt: _createdAt,
    );

ConfirmedBookingReference _reference(
        {required String bookingRequestId, String riderId = _riderAId}) =>
    ConfirmedBookingReference(
      command: _command(bookingRequestId: bookingRequestId, riderId: riderId),
      quote: _lockedQuote(bookingRequestId: bookingRequestId),
    );

class _Auth extends MockAuthRepository {
  _Auth(this.user);

  AppUser? user;

  @override
  Future<AppUser?> restoreSession() async => user;
}

class _MemoryStore implements PendingFareLockStore {
  _MemoryStore(this.confirmed);

  final List<ConfirmedBookingReference> confirmed;

  @override
  Future<void> clearForRider(String riderId) async {}

  @override
  Future<PendingFareLock?> loadForRider(String riderId) async => null;

  @override
  Future<PendingFareLockSlot> inspectForRider(String riderId) async =>
      PendingFareLockSlot.absent(List.unmodifiable(confirmed));

  @override
  Future<void> save(PendingFareLock command) async {}
}

const _referenceMonthLabels = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

void main() {
  testWidgets(
      'recovered booking buttons show locked amount and date, never the raw id',
      (tester) async {
      final auth = _Auth(_riderA);
      final repository = SupabaseFareRepository(
        bookingMutationGate: (dispatch) =>
            Future.error(StateError('display test must not mutate')),
        rpc: ({required name, required params}) =>
            Future.error(StateError('display test must not call an RPC')),
        quoteEdge: (_) =>
            Future.error(StateError('display test must not request a quote')),
        canonicalReader: ({required bookingRequestId, required riderId}) =>
            Future.error(StateError('display test must not read canonical')),
      );
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          fareRepositoryProvider.overrideWithValue(repository),
          pendingFareLockStoreProvider.overrideWithValue(
            _MemoryStore([_reference(bookingRequestId: _rawBookingId)]),
          ),
          appErrorReporterProvider.overrideWithValue(
            const NoopAppErrorReporter(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionControllerProvider.notifier).refreshSession();

      final expectedLocal = _createdAt.toLocal();
      final expectedDate =
          '${_referenceMonthLabels[expectedLocal.month - 1]} ${expectedLocal.day}';
      final expectedLabel = 'View recovered booking · JOD 2.00 · $expectedDate';

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const FareEstimateScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The reference locator sits at the bottom of the lazy ListView.
      final locator = find.text(expectedLabel, skipOffstage: false);
      expect(locator, findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(expectedLabel),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text(expectedLabel), findsOneWidget);
      expect(find.textContaining('other-booking'), findsNothing);
      expect(find.textContaining(_rawBookingId), findsNothing);
    });
}
