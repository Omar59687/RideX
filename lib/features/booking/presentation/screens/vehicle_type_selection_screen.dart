import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/vehicle_type_card.dart';

class VehicleTypeSelectionScreen extends ConsumerWidget {
  const VehicleTypeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingControllerProvider);
    return AppScaffold(
      title: 'Choose your ride',
      body: Column(
        children: [
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: ListView.separated(
              itemCount: MockData.vehicleTypes.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                final vehicle = MockData.vehicleTypes[index];
                return VehicleTypeCard(
                  vehicle: vehicle,
                  selected: draft.vehicleType?.id == vehicle.id,
                  onTap: () => ref
                      .read(bookingControllerProvider.notifier)
                      .setVehicleType(vehicle),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
              label: 'Continue',
              onPressed: draft.vehicleType == null
                  ? null
                  : () => context.push('/rider/fare')),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}
