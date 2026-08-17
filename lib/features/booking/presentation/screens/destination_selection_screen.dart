import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/place_selection_state.dart';
import 'package:ridex/core/providers/location_providers.dart';
import 'package:ridex/core/providers/place_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/ride_location_selection_map.dart';
import 'package:ridex/core/widgets/google_maps_attribution.dart';
import 'package:ridex/features/booking/presentation/widgets/location_search_panel.dart';

class DestinationSelectionScreen extends ConsumerStatefulWidget {
  const DestinationSelectionScreen({super.key});

  @override
  ConsumerState<DestinationSelectionScreen> createState() =>
      _DestinationSelectionScreenState();
}

class _DestinationSelectionScreenState
    extends ConsumerState<DestinationSelectionScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const endpoint = LocationEndpoint.destination;
    final selection = ref.watch(placeSelectionControllerProvider(endpoint));
    final selectionController =
        ref.read(placeSelectionControllerProvider(endpoint).notifier);
    final draft = ref.watch(bookingControllerProvider);
    final current = ref.watch(currentLocationControllerProvider).point;
    return AppScaffold(
      title: 'Choose destination',
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
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Or place the destination pin',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          RideLocationSelectionMap(
            activeEndpoint: endpoint,
            pickup: draft.pickup,
            destination: draft.destination,
            currentLocation: current,
            onPointSelected: (point) => selectionController.selectPoint(
              point,
              source: LocationSelectionSource.map,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _SelectedLocation(location: draft.destination),
          if (draft.destination?.providerName == 'google') ...[
            const SizedBox(height: AppSpacing.xs),
            const Align(
              alignment: Alignment.centerRight,
              child: GoogleMapsAttribution(),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: selection.isResolving
                ? 'Resolving destination...'
                : 'Choose pickup',
            onPressed: draft.destination == null ||
                    selection.isResolving ||
                    selection.hasUncommittedQuery
                ? null
                : () => context.push('/rider/pickup'),
          ),
        ],
      ),
    );
  }
}

class _SelectedLocation extends StatelessWidget {
  const _SelectedLocation({required this.location});

  final RideLocation? location;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.flag_outlined),
        title: Text(location?.label ?? 'No destination selected'),
        subtitle: Text(
          location?.address ?? 'Search or tap the map to choose a destination.',
        ),
      ),
    );
  }
}
