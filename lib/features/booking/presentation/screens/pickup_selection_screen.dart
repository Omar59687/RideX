import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_bottom_sheet.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/coming_soon_dialog.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';

class PickupSelectionScreen extends ConsumerWidget {
  const PickupSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingControllerProvider);
    final pickup = draft.pickup ?? MockData.locations.first;
    final destination = draft.destination;
    return AppScaffold(
      title: 'Confirm pickup',
      padding: EdgeInsets.zero,
      maxContentWidth: 720,
      useSafeArea: false,
      body: Stack(
        children: [
          const Positioned.fill(
            child: MapPlaceholder(
              borderRadius: 0,
              semanticLabel: 'Demo map for pickup confirmation',
            ),
          ),
          Positioned(
            top: AppSpacing.md,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            child: Row(
              children: [
                _MapChip(
                  label:
                      '${draft.etaMinutes} min · ${draft.distanceKm.toStringAsFixed(1)} km',
                ),
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: 'Explain demo recentering',
                  onPressed: () => showComingSoonDialog(
                    context,
                    feature: 'Live map recentering',
                  ),
                  icon: const Icon(Icons.my_location_rounded),
                ),
              ],
            ),
          ),
          Positioned(
            top: 110,
            left: AppSpacing.lg,
            child: _MapChip(label: 'Demo map · pickup is not GPS-tracked'),
          ),
          AppBottomSheet(
            showHandle: true,
            useSafeArea: true,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PICKUP CONFIRMED',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    pickup.address,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pickup.label,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                'Demo pickup point · no precise entrance data',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => showComingSoonDialog(
                            context,
                            feature: 'Precise pickup editing',
                          ),
                          child: const Text('Edit'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Route to ${destination?.label ?? 'destination'}',
                        ),
                      ),
                      Text(
                        '${draft.etaMinutes} min',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Confirm pickup point',
                    onPressed: destination == null
                        ? null
                        : () {
                            ref
                                .read(bookingControllerProvider.notifier)
                                .setPickup(pickup);
                            context.push('/rider/vehicle');
                          },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapChip extends StatelessWidget {
  const _MapChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}
