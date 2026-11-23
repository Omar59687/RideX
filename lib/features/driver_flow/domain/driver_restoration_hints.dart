import 'package:flutter/foundation.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/features/trips/application/driver_cash_recovery_controller.dart';

/// Advisory ID only. A journal/cache never establishes active assignment.
class DriverRestorationRecoveryHint {
  const DriverRestorationRecoveryHint(
      {this.tripId, this.requiresRecovery = false});
  final String? tripId;
  final bool requiresRecovery;
}

/// Health-only hint; no coordinates are displayed or treated as Trip authority.
class DriverRestorationLocationHint {
  const DriverRestorationLocationHint(
      {required this.owner,
      required this.sdkSession,
      required this.tripId,
      required this.recordedAt});
  final DriverAuthorityOwner owner;
  final Object sdkSession;
  final String tripId;
  final DateTime recordedAt;
}

/// Borrows C03's existing journal/recovery owner. No discovery, staging, cleanup,
/// replay or command creation. Multiple historical records never pick a Trip.
class DriverCompletionRestorationHints extends ChangeNotifier
    implements ValueListenable<DriverRestorationRecoveryHint> {
  DriverCompletionRestorationHints(this.recovery) {
    recovery.addListener(_changed);
  }
  final DriverCashRecoveryController recovery;
  @override
  DriverRestorationRecoveryHint get value {
    if (recovery.state == DriverCashRecoveryState.authorizationRevoked) {
      return const DriverRestorationRecoveryHint(requiresRecovery: true);
    }
    final evidence = recovery.canonicalEvidence;
    return DriverRestorationRecoveryHint(
        tripId: evidence.length == 1 ? evidence.keys.single : null,
        requiresRecovery: switch (recovery.state) {
          DriverCashRecoveryState.noPendingRecovery ||
          DriverCashRecoveryState.completionVerifiedReceiptVerified ||
          DriverCashRecoveryState.completionVerifiedReceiptUnverified =>
            false,
          _ => true,
        });
  }

  void _changed() => notifyListeners();
  @override
  void dispose() {
    recovery.removeListener(_changed);
    super.dispose();
  }
}
