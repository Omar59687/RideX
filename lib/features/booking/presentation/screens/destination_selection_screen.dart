import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/coming_soon_dialog.dart';

class DestinationSelectionScreen extends ConsumerWidget {
  const DestinationSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingControllerProvider);
    return AppScaffold(
      title: 'Plan your route',
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          const SizedBox(height: AppSpacing.xs),
          _RouteFields(draft: draft),
          const SizedBox(height: AppSpacing.md),
          const _QuickActions(),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Suggested in Jordan',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final location in MockData.locations.skip(1))
                  _DestinationTile(
                    location: location,
                    onTap: () => _select(context, ref, location),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Recent destinations',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          _RecentDestination(
            location: MockData.locations[1],
            detail: 'Demo recent ride · Standard',
            onTap: () => _select(context, ref, MockData.locations[1]),
          ),
          _RecentDestination(
            location: MockData.locations[3],
            detail: 'Demo recent ride · Economy',
            onTap: () => _select(context, ref, MockData.locations[3]),
          ),
        ],
      ),
    );
  }

  void _select(BuildContext context, WidgetRef ref, RideLocation location) {
    ref.read(bookingControllerProvider.notifier).setDestination(location);
    context.push('/rider/pickup');
  }
}

class _RouteFields extends StatelessWidget {
  const _RouteFields({required this.draft});

  final BookingDraft draft;

  @override
  Widget build(BuildContext context) {
    final pickup = draft.pickup?.address ?? 'Choose pickup next';
    final destination = draft.destination?.address ?? 'Search destination';
    return SizedBox(
      height: 148,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Column(
              children: [
                _RouteDot(color: context.rideXTheme.pickup),
                Expanded(
                  child: Container(
                    width: 2,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                _RouteDot(color: context.rideXTheme.destination),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              children: [
                _LocationField(
                  label: 'Pickup',
                  value: pickup,
                  trailing: 'Next',
                ),
                const SizedBox(height: AppSpacing.sm),
                _LocationField(
                  label: 'Destination',
                  value: destination,
                  active: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteDot extends StatelessWidget {
  const _RouteDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: color, width: 3),
      ),
    );
  }
}

class _LocationField extends StatelessWidget {
  const _LocationField({
    required this.label,
    required this.value,
    this.trailing,
    this.active = false,
  });

  final String label;
  final String value;
  final String? trailing;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? context.rideXTheme.focus
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: theme.textTheme.labelSmall),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
          ),
          if (trailing != null)
            Text(trailing!, style: theme.textTheme.labelMedium)
          else
            const Icon(Icons.search_rounded),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    const actions = [
      (Icons.add_rounded, 'Add stop'),
      (Icons.person_outline_rounded, 'For someone'),
      (Icons.swap_horiz_rounded, 'Round trip'),
    ];
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final action in actions)
          ActionChip(
            avatar: Icon(action.$1, size: 18),
            label: Text(action.$2),
            onPressed: () => showComingSoonDialog(
              context,
              feature: action.$2,
            ),
          ),
      ],
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({required this.location, required this.onTap});

  final RideLocation location;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minVerticalPadding: AppSpacing.sm,
      leading: CircleAvatar(
        child: Text(location.label.characters.first.toUpperCase()),
      ),
      title: Text(location.label),
      subtitle: Text(location.address),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _RecentDestination extends StatelessWidget {
  const _RecentDestination({
    required this.location,
    required this.detail,
    required this.onTap,
  });

  final RideLocation location;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history_rounded),
      title: Text(location.label),
      subtitle: Text(detail),
      onTap: onTap,
    );
  }
}
