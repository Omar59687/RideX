import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';
import 'package:ridex/core/widgets/ride_location_card.dart';
import 'package:ridex/core/widgets/section_header.dart';

class PickupSelectionScreen extends ConsumerWidget {
  const PickupSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      title: 'Pickup',
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.sm),
          const SectionHeader(
              title: 'Choose pickup',
              subtitle:
                  'Maps are mocked in this phase, but the flow stays realistic.'),
          const SizedBox(height: AppSpacing.lg),
          const MapPlaceholder(showRoute: false),
          const SizedBox(height: AppSpacing.lg),
          for (final location in MockData.locations)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: RideLocationCard(
                location: location,
                icon: Icons.my_location_rounded,
                onTap: () {
                  ref
                      .read(bookingControllerProvider.notifier)
                      .setPickup(location);
                  context.push('/rider/destination');
                },
              ),
            ),
        ],
      ),
    );
  }
}
