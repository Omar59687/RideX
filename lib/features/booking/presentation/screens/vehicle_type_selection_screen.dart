import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/utils/money_utils.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/coming_soon_dialog.dart';
import 'package:ridex/core/widgets/route_timeline.dart';
import 'package:ridex/core/widgets/vehicle_type_card.dart';

class VehicleTypeSelectionScreen extends ConsumerWidget {
  const VehicleTypeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingControllerProvider);
    final vehicle = draft.vehicleType;
    return AppScaffold(
      title: 'Choose your ride',
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: RouteTimeline(
                      compact: true,
                      pickup: RouteTimelineStop(
                        title: draft.pickup?.address ?? 'Pickup not selected',
                      ),
                      destination: RouteTimelineStop(
                        title: draft.destination?.address ??
                            'Destination not selected',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${draft.distanceKm.toStringAsFixed(1)} km',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '${draft.etaMinutes} min',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final option in MockData.vehicleTypes) ...[
            VehicleTypeCard(
              key: ValueKey('vehicle-${option.id}'),
              vehicle: option,
              selected: vehicle?.id == option.id,
              onTap: () => ref
                  .read(bookingControllerProvider.notifier)
                  .setVehicleType(option),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            children: [
              Expanded(
                child: _OptionButton(
                  icon: Icons.payments_outlined,
                  label: 'Cash',
                  supporting: 'Current',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _OptionButton(
                  icon: Icons.credit_card_rounded,
                  label: 'Card',
                  onTap: () => showComingSoonDialog(
                    context,
                    feature: 'Card payments',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _OptionButton(
                  icon: Icons.local_offer_outlined,
                  label: 'Promo',
                  onTap: () => showComingSoonDialog(
                    context,
                    feature: 'Promo codes',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const Expanded(child: Text('No surge. Demo prices stay fixed.')),
              if (vehicle != null)
                Text(
                  formatMoney(vehicle.baseFare),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: vehicle == null ? 'Choose a ride' : 'Choose ${vehicle.name}',
            onPressed: vehicle == null
                ? null
                : () async {
                    await ref
                        .read(bookingControllerProvider.notifier)
                        .estimateFare();
                    if (context.mounted) context.push('/rider/fare');
                  },
          ),
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.supporting,
  });

  final IconData icon;
  final String label;
  final String? supporting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: AppSpacing.xxs),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (supporting != null)
            Text(
              supporting!,
              style: Theme.of(context).textTheme.labelSmall,
            ),
        ],
      ),
    );
  }
}
