import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/current_location_state.dart';
import 'package:ridex/core/models/place_selection_state.dart';
import 'package:ridex/core/providers/location_providers.dart';
import 'package:ridex/core/providers/place_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/ride_location_selection_map.dart';
import 'package:ridex/core/widgets/google_maps_attribution.dart';
import 'package:ridex/features/booking/presentation/widgets/location_search_panel.dart';

class PickupSelectionScreen extends ConsumerStatefulWidget {
  const PickupSelectionScreen({super.key});

  @override
  ConsumerState<PickupSelectionScreen> createState() =>
      _PickupSelectionScreenState();
}

class _PickupSelectionScreenState extends ConsumerState<PickupSelectionScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const endpoint = LocationEndpoint.pickup;
    final selection = ref.watch(placeSelectionControllerProvider(endpoint));
    final selectionController =
        ref.read(placeSelectionControllerProvider(endpoint).notifier);
    final draft = ref.watch(bookingControllerProvider);
    final current = ref.watch(currentLocationControllerProvider);
    final validationMessage = switch (draft.locationValidation) {
      BookingLocationValidation.sameLocation =>
        'Pickup and destination must be different locations.',
      BookingLocationValidation.missingDestination =>
        'Choose a destination before continuing.',
      _ => null,
    };
    return AppScaffold(
      title: 'Choose pickup',
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          LocationSearchPanel(
            endpoint: endpoint,
            state: selection,
            controller: _search,
            onChanged: selectionController.search,
            onSubmitted: selectionController.submitAddress,
            onPredictionSelected: (index) => selectionController
                .selectPrediction(selection.predictions[index]),
            onRetry: selectionController.retrySearch,
            onRetryAddress: selectionController.retryAddress,
          ),
          const SizedBox(height: AppSpacing.sm),
          _CurrentLocationAction(
            state: current,
            onUse: current.point == null
                ? null
                : () => selectionController.selectPoint(
                      current.point!,
                      source: LocationSelectionSource.gps,
                    ),
            onRequest: () => ref
                .read(currentLocationControllerProvider.notifier)
                .requestPermission(),
            onOpenAppSettings: () => ref
                .read(currentLocationControllerProvider.notifier)
                .openAppSettings(),
            onOpenLocationSettings: () => ref
                .read(currentLocationControllerProvider.notifier)
                .openLocationSettings(),
            onRetry: () =>
                ref.read(currentLocationControllerProvider.notifier).refresh(),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Or place the pickup pin',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          RideLocationSelectionMap(
            activeEndpoint: endpoint,
            pickup: draft.pickup,
            destination: draft.destination,
            currentLocation: current.point,
            onPointSelected: (point) => selectionController.selectPoint(
              point,
              source: LocationSelectionSource.map,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: ListTile(
              leading: const Icon(Icons.trip_origin_rounded),
              title: Text(draft.pickup?.label ?? 'No pickup selected'),
              subtitle: Text(
                draft.pickup?.address ??
                    'Use GPS, search, or tap the map to choose pickup.',
              ),
            ),
          ),
          if (draft.pickup?.providerName == 'google') ...[
            const SizedBox(height: AppSpacing.xs),
            const Align(
              alignment: Alignment.centerRight,
              child: GoogleMapsAttribution(),
            ),
          ],
          if (validationMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              validationMessage,
              key: const ValueKey('booking-location-validation'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: selection.isResolving
                ? 'Resolving pickup...'
                : 'Confirm pickup point',
            onPressed: !draft.isRoutingReady ||
                    selection.isResolving ||
                    selection.hasUncommittedQuery
                ? null
                : () => context.push('/rider/vehicle'),
          ),
        ],
      ),
    );
  }
}

class _CurrentLocationAction extends StatelessWidget {
  const _CurrentLocationAction({
    required this.state,
    required this.onUse,
    required this.onRequest,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
    required this.onRetry,
  });

  final CurrentLocationState state;
  final VoidCallback? onUse;
  final VoidCallback onRequest;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.point != null) {
      return OutlinedButton.icon(
        key: const ValueKey('use-current-location'),
        onPressed: onUse,
        icon: const Icon(Icons.my_location_rounded),
        label: const Text('Use current GPS location'),
      );
    }
    final isBusy = state.status == CurrentLocationStatus.checking ||
        state.status == CurrentLocationStatus.requestingPermission ||
        state.status == CurrentLocationStatus.loading;
    if (isBusy) {
      return const Row(
        children: [
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('Checking current location...')),
        ],
      );
    }
    final (message, action, actionLabel) = switch (state.status) {
      CurrentLocationStatus.serviceDisabled => (
          'Location services are disabled. Search still works.',
          onOpenLocationSettings,
          'Location settings',
        ),
      _ when state.permission == LocationPermissionStatus.permanentlyDenied => (
          'Location permission is blocked. Search still works.',
          onOpenAppSettings,
          'App settings',
        ),
      CurrentLocationStatus.unavailable => (
          'GPS is unavailable. Search or select manually.',
          onRetry,
          'Try again',
        ),
      _ => (
          'GPS unavailable? Search or select manually.',
          onRequest,
          'Allow location',
        ),
    };
    return Row(
      children: [
        Expanded(child: Text(message)),
        TextButton(onPressed: action, child: Text(actionLabel)),
      ],
    );
  }
}
