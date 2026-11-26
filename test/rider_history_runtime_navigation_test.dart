import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/history/data/supabase_rider_history_summary_repository.dart';
import 'package:ridex/features/history/presentation/providers/rider_history_summary_provider.dart';
import 'package:ridex/features/history/presentation/screens/rider_history_runtime_screens.dart';

const _rider = 'a7000000-0000-0000-0000-000000000001';
const _trip = 'a7100000-0000-0000-0000-000000000001';

class _TestSession extends SessionController {
  @override
  SessionState build() => SessionState.fromUser(const AppUser(
        id: _rider,
        name: 'Synthetic Rider',
        email: 'rider@example.invalid',
        role: RideRole.rider,
      ));
}

class _FakeHistory implements RiderHistorySummaryReader {
  String? exactRead;
  final row = RiderHistorySummary(
    tripId: _trip,
    version: 2,
    status: DriverTripLifecycleStatus.completed,
    createdAt: DateTime.utc(2026, 11, 26),
    paymentId: null,
    paymentVersion: null,
    paymentMethod: PaymentMethod.cash,
  );

  @override
  Future<RiderHistorySummaryPage> readPage({
    int limit = 20,
    RiderHistorySummaryCursor? cursor,
  }) async =>
      RiderHistorySummaryPage(rows: [row]);

  @override
  Future<RiderHistorySummary?> readExactTrip(String tripId) async {
    exactRead = tripId;
    return tripId == _trip ? row : null;
  }
}

void main() {
  testWidgets(
    'Rider history opens exact authorized Trip details',
    (tester) async {
      final history = _FakeHistory();
      final router = GoRouter(
        initialLocation: '/history',
        routes: [
          GoRoute(
            path: '/history',
            builder: (_, __) => const RoleAwareHistoryRoute(),
          ),
          GoRoute(
            path: '/history/:tripId',
            builder: (_, state) => RoleAwareTripDetailsRoute(
              tripId: state.pathParameters['tripId']!,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionControllerProvider.overrideWith(_TestSession.new),
            riderHistorySummaryRepositoryProvider.overrideWithValue(history),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('canonical-history-$_trip')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('canonical-history-$_trip')));
      await tester.pumpAndSettle();
      expect(history.exactRead, _trip);
      expect(find.text('Trip status: Completed'), findsOneWidget);
      expect(
        find.text(
          'This history contract does not provide Cash payment or receipt details.',
        ),
        findsOneWidget,
      );
    },
  );
}
