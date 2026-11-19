import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/providers/driver_cash_completion_providers.dart';
import 'package:ridex/features/trips/application/driver_cash_completion_controller.dart';
import '../../application/driver_completion_interaction.dart';

/// Integration owner must supply a session/route-owned gate using the SAME
/// verified normal-user client/source as driverCashCompletionProvider. No
/// endpoint, Driver, vehicle, connected state or approval is invented here.
final driverCompletionInteractionGateProvider =
    Provider.autoDispose<DriverCompletionInteraction?>((ref) => null);

/// Borrow the existing one-attempt coordinator/controller; never duplicate state.
final driverCompletionInteractionControllerProvider =
    Provider.autoDispose<DriverCashCompletionController?>((ref) {
  final interaction = ref.watch(driverCompletionInteractionGateProvider);
  if (interaction == null) return null;
  final controller = ref.watch(driverCashCompletionProvider.notifier);
  if (controller == null) return null;
  controller.bindInteraction(interaction);
  ref.onDispose(
      () => controller.invalidateInteraction(deferNotification: true));
  return controller;
});
