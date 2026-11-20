import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/rider_payments/application/rider_checkout_controller.dart';
import 'package:ridex/features/rider_payments/application/rider_checkout_launcher.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';
import 'package:ridex/features/rider_payments/models/rider_receipt_state.dart';

/// Feature-local injection seam. No Supabase or payment provider is wired in
/// this checkpoint; the default reader fails closed until B05 is approved.
final riderCheckoutReaderProvider = Provider<RiderCheckoutReader>(
  (ref) => const UnavailableRiderCheckoutReader(),
);

final riderCheckoutLauncherProvider = Provider<RiderCheckoutLauncher>(
  (ref) => const DisabledRiderCheckoutLauncher(),
);

final riderReceiptReaderProvider = Provider<RiderReceiptReader>(
  (ref) => const UnavailableRiderReceiptReader(),
);

final riderCheckoutControllerProvider =
    ChangeNotifierProvider.autoDispose<RiderCheckoutController>((ref) {
  final controller = RiderCheckoutController(
    reader: ref.watch(riderCheckoutReaderProvider),
    receiptReader: ref.watch(riderReceiptReaderProvider),
    launcher: ref.watch(riderCheckoutLauncherProvider),
    readSession: () => ref.read(sessionControllerProvider),
  );
  ref.listen(sessionControllerProvider, (previous, next) {
    if (!identical(previous, next)) controller.sessionChanged();
  });
  return controller;
});
