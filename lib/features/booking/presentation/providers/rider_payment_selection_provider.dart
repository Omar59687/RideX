import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/providers/session_providers.dart';

/// Rider payment method selection (P6-05).
///
/// Feature-local UI choice state: which payment method the rider selected
/// on the booking flow. Defaults to [PaymentMethod.cash]; Card is selectable
/// as a booking payment **method only**.
///
/// The provider lives under `lib/features/booking/` (not core) so no shared
/// core/session provider changes. It is a [NotifierProvider] (matching
/// `SessionController`/`BookingController` conventions) exposing
/// [RiderPaymentSelectionController.selectCash] and
/// [RiderPaymentSelectionController.selectCard] (plus the generic
/// [RiderPaymentSelectionController.select]). Selecting a method only records
/// the rider's intent: it never creates, authorizes, captures, settles, or
/// refunds a payment, and no code path may treat the selection as a completed
/// charge. Backend draft calls send [PaymentMethod.backendValue] (`'cash'` or
/// `'card'`) through the existing `FareRepository` contract; every real card
/// authorization/capture remains a trusted backend operation, deferred to the
/// authorized P6-04/P6-09 scope.
///
/// Session isolation: a provider-level listener on
/// [sessionControllerProvider] resets the selection to Cash whenever the
/// authenticated identity, role, or status changes (mirroring
/// `PendingFareLockController`'s session-isolation pattern). Same-rider
/// refreshes with identical id/status/role early-return, so ordinary
/// navigation preserves the selection. The listener lives on the provider
/// (not a screen), so sign-out while screens are disposed still resets, and
/// the idempotent guard avoids notifying when the value is unchanged
/// (preserving the fare screen's pending-lock gates).
///
/// Fare identity (review Findings 3/5): the fare screen includes the selected
/// method's `backendValue` in its quote key and dispatches the *same captured*
/// value it keyed with, so a selection change during an in-flight request
/// re-quotes with the new method instead of mixing a key method with a live
/// dispatch method.
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

  /// Select Cash. Idempotent.
  void selectCash() => _select(PaymentMethod.cash);

  /// Select Card as the booking payment method. Idempotent; never an
  /// authorization, capture, or settlement.
  void selectCard() => _select(PaymentMethod.card);

  /// Select [method]. Idempotent.
  void select(PaymentMethod method) => _select(method);

  void _select(PaymentMethod method) {
    if (state != method) {
      state = method;
    }
  }
}

final riderPaymentSelectionProvider =
    NotifierProvider<RiderPaymentSelectionController, PaymentMethod>(
  RiderPaymentSelectionController.new,
);
