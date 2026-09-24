import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/place_selection_state.dart';
import 'package:ridex/core/providers/location_providers.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/widgets/google_location_selection_map.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';

typedef LocationSelectionMapBuilder = Widget Function(
  BuildContext context, {
  required LocationEndpoint activeEndpoint,
  required RideLocation? pickup,
  required RideLocation? destination,
  required LocationPoint? currentLocation,
  required List<LocationPoint> routeGeometry,
  required ValueChanged<LocationPoint> onPointSelected,
});

final locationSelectionMapBuilderProvider =
    Provider<LocationSelectionMapBuilder>((ref) {
  final errorReporter = ref.watch(appErrorReporterProvider);
  return (
    context, {
    required activeEndpoint,
    required pickup,
    required destination,
    required currentLocation,
    required routeGeometry,
    required onPointSelected,
  }) {
    return GoogleLocationSelectionMap(
      activeEndpoint: activeEndpoint,
      pickup: pickup,
      destination: destination,
      currentLocation: currentLocation,
      routeGeometry: routeGeometry,
      onPointSelected: onPointSelected,
      errorReporter: errorReporter,
    );
  };
});

class RideLocationSelectionMap extends ConsumerWidget {
  const RideLocationSelectionMap({
    super.key,
    required this.activeEndpoint,
    required this.pickup,
    required this.destination,
    required this.currentLocation,
    required this.onPointSelected,
    this.routeGeometry = const [],
    this.height = 280,
  });

  final LocationEndpoint activeEndpoint;
  final RideLocation? pickup;
  final RideLocation? destination;
  final LocationPoint? currentLocation;
  final List<LocationPoint> routeGeometry;
  final ValueChanged<LocationPoint> onPointSelected;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(mapConfigurationProvider);
    final supported = ref.watch(mapPlatformSupportedProvider);
    final mapAvailable = supported && configured.valueOrNull == true;
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: mapAvailable
            ? ref.watch(locationSelectionMapBuilderProvider)(
                context,
                activeEndpoint: activeEndpoint,
                pickup: pickup,
                destination: destination,
                currentLocation: currentLocation,
                routeGeometry: routeGeometry,
                onPointSelected: onPointSelected,
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  const MapPlaceholder(
                    semanticLabel: 'Map unavailable for manual pin selection',
                  ),
                  ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: .9),
                    child: const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Map selection is unavailable. Search still works.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
