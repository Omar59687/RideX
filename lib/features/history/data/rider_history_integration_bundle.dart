import 'package:ridex/features/history/data/rider_active_trip_restoration.dart';
import 'package:ridex/features/history/data/rider_active_trip_restore_controller.dart';
import 'package:ridex/features/history/data/rider_exact_trip_detail.dart';
import 'package:ridex/features/history/data/rider_trip_history_contract.dart';

/// One feature-local injection point for the final integration owner.
/// Never chooses a fake, global provider, backend client or route.
final class RiderHistoryIntegrationBundle {
  RiderHistoryIntegrationBundle({
    required this.history,
    required this.activeTrips,
    required this.currentRiderId,
    required this.isAuthorizedRider,
    required this.sessionEpoch,
    this.financial,
  }) : activeController = RiderActiveTripRestoreController(
          RiderActiveTripRestorer(
            reader: activeTrips,
            currentRiderId: currentRiderId,
            isAuthorized: isAuthorizedRider,
            sessionEpoch: sessionEpoch,
          ),
        );

  final RiderTripHistoryRepository history;
  final RiderActiveTripReadPort activeTrips;
  final RiderTripFinancialReadPort? financial;
  final String? Function() currentRiderId;
  final bool Function() isAuthorizedRider;

  /// Must return a different object on SDK session replacement, including
  /// A -> B -> A. A constant token is not safe for production.
  final Object? Function() sessionEpoch;
  final RiderActiveTripRestoreController activeController;

  RiderExactTripDetailReader get details => RiderExactTripDetailReader(
        history: history,
        financial: financial,
        activeRiderId: currentRiderId,
        isAuthorized: isAuthorizedRider,
        sessionEpoch: sessionEpoch,
      );

  /// Call *before* exposing an auth/session change to UI navigation.
  void onAuthIdentityChanged() => activeController.invalidate();

  void dispose() => activeController.dispose();
}
