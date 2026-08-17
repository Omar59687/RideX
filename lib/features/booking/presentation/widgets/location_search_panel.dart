import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/place_selection_state.dart';
import 'package:ridex/core/widgets/google_maps_attribution.dart';

class LocationSearchPanel extends StatelessWidget {
  const LocationSearchPanel({
    super.key,
    required this.endpoint,
    required this.state,
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onPredictionSelected,
    required this.onRetry,
    required this.onRetryAddress,
  });

  final LocationEndpoint endpoint;
  final PlaceSelectionState state;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final ValueChanged<int> onPredictionSelected;
  final VoidCallback onRetry;
  final VoidCallback onRetryAddress;

  @override
  Widget build(BuildContext context) {
    final label = endpoint == LocationEndpoint.pickup
        ? 'Search pickup'
        : 'Search destination';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: ValueKey('${endpoint.name}-search-field'),
          controller: controller,
          onChanged: onChanged,
          onSubmitted: (_) => onSubmitted(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: label,
            hintText: 'Place or street address',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: state.status == PlaceSearchStatus.loading ||
                    state.status == PlaceSearchStatus.resolving
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Search address',
                    onPressed: onSubmitted,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
          ),
        ),
        if (state.predictions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < state.predictions.length; index++)
                  ListTile(
                    key: ValueKey('${endpoint.name}-prediction-$index'),
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(state.predictions[index].primaryText),
                    subtitle: state.predictions[index].secondaryText.isEmpty
                        ? null
                        : Text(state.predictions[index].secondaryText),
                    onTap: () => onPredictionSelected(index),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: const GoogleMapsAttribution(),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (state.message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  state.message!,
                  key: ValueKey('${endpoint.name}-search-message'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (state.status == PlaceSearchStatus.failure)
                TextButton(onPressed: onRetry, child: const Text('Retry'))
              else if (state.status == PlaceSearchStatus.selected &&
                  state.selected?.address == 'Address unavailable')
                TextButton(
                  onPressed: onRetryAddress,
                  child: const Text('Retry address'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
