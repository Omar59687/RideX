import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/providers/session_providers.dart';

/// Rider cash payment selection (P6-05 Slice A).
///
/// Feature-local UI choice state: which payment method the rider selected
/// on the booking flow. Defaults to [PaymentMethod.cash]; Card stays a
/// Coming Soon placeholder in this slice.
///
/// The provider lives under `lib/features/booking/` (not core) so no shared
/// core/session provider changes. It is a [NotifierProvider] (matching
/// `SessionController`/`BookingController` conventions) whose only public
/// operation is [RiderPaymentSelectionController.selectCash]: there is
/// intentionally no `selectCard()` yet, so no feature code path can produce
/// `PaymentMethod.card` and backend draft calls derived from this state can
/// only send `'cash'` in Slice A.
///
/// Session isolation: a provider-level listener on
/// [sessionControllerProvider] resets the selection to Cash whenever the
/// authenticated identity, role, or status changes (mirroring
/// `PendingFareLockController`'s session-isolation pattern). Same-rider
/// refreshes with identical id/status/role early-return, so ordinary
/// navigation preserves the selection. The listener lives on the provider
/// (not a screen), so sign-out while screens are disposed still resets, and
/// the idempotent guard avoids notifying when already cash (preserving the
/// fare screen's pending-lock gates).
///
/// Fare identity (review Findings 3/5): the fare screen includes
/// `state.backendValue` in its quote key and draft RPCs. The Cash-only
/// invariant means the captured key value and the dispatched value are both
/// always `'cash'`, so no mismatch is possible in Slice A. A future slice
/// enabling Card toggling must capture the payment value at key time and
/// pass it into the refresh dispatch (deferred requirement); do not rely on
/// two independent live reads once switching exists.
///
/// Safety: selecting Cash never creates, settles, or declares a payment.
/// Backend draft calls send [PaymentMethod.backendValue] (`'cash'`) via the
/// existing `FareRepository` contract; fare lock, recovery, confirmation,
/// and demo-mode behavior are untouched.
class RiderPaymentSelectionController extends Notifier<PaymentMethod> {
  @override
  PaymentMethod build() {
    ref.listen(sessionControllerProvider, (previous, next) {
      if (previous?.user?.id == next.user?.id &&
          previous?.status == next.status &&
          previous?.role == next.role) {
        return;
      }
      if (state != PaymentMethod.cash) {
        state = PaymentMethod.cash;
      }
    });
    return PaymentMethod.cash;
  }

  /// Select Cash. Idempotent; the only allowed selection in Slice A.
  void selectCash() {
    if (state != PaymentMethod.cash) {
      state = PaymentMethod.cash;
    }
  }
}

final riderPaymentSelectionProvider =
    NotifierProvider<RiderPaymentSelectionController, PaymentMethod>(
  RiderPaymentSelectionController.new,
);
