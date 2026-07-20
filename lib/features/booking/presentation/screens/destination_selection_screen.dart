import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/ride_location_card.dart';
import 'package:ridex/core/widgets/section_header.dart';

class DestinationSelectionScreen extends ConsumerWidget {
  const DestinationSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      title: 'Destination',
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.sm),
          const SectionHeader(
              title: 'Select destination',
              subtitle: 'Use quick picks inspired by the prototype screens.'),
          const SizedBox(height: AppSpacing.lg),
          for (final location in MockData.locations.skip(1))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: RideLocationCard(
                location: location,
                icon: Icons.location_on_outlined,
                onTap: () {
                  ref
                      .read(bookingControllerProvider.notifier)
                      .setDestination(location);
                  context.push('/rider/vehicle');
                },
              ),
            ),
        ],
      ),
    );
  }
}
