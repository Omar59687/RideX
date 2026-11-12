import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/bootstrap.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/features/driver_flow/presentation/providers/controlled_driver_runtime.dart';

/// Owner-reviewed build inputs, never route/JWT/user metadata. Configuring these
/// is an operator action AFTER approval; source contains no approved deployment.
Future<void> main() async {
  const approved = bool.fromEnvironment('RIDEX_APPROVED_NONPRODUCTION');
  const approval = String.fromEnvironment('RIDEX_ACCEPTANCE_APPROVAL_REF');
  const driver = String.fromEnvironment('RIDEX_ACCEPTANCE_DRIVER_ID');
  const vehicle = String.fromEnvironment('RIDEX_ACCEPTANCE_VEHICLE_ID');
  const endpoint = String.fromEnvironment('RIDEX_ACCEPTANCE_SUPABASE_URL');
  const commands = bool.fromEnvironment('RIDEX_APPROVED_OFFER_COMMANDS');
  final overrides = <Override>[];
  if (!kReleaseMode &&
      approved &&
      approval.trim().isNotEmpty &&
      endpoint == EnvConfig.supabaseUrl &&
      endpoint.isNotEmpty) {
    final target = CanonicalDriverTestTarget(
      backend: DriverBackendIdentity(
          endpoint: Uri.parse(endpoint), namespace: 'cash-acceptance'),
      driverId: driver,
      vehicleId: vehicle,
    );
    overrides
        .add(approvedCanonicalDriverTargetProvider.overrideWithValue(target));
    overrides.add(
        controlledDriverCommandsEnabledProvider.overrideWithValue(commands));
  }
  await bootstrap(overrides: overrides);
}
