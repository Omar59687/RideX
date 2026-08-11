import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/current_location_state.dart';
import 'package:ridex/core/providers/location_providers.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';

class RideCurrentLocationMap extends ConsumerStatefulWidget {
  const RideCurrentLocationMap({
    super.key,
    this.height,
    this.borderRadius = AppRadii.card,
    required this.semanticLabel,
  });

  final double? height;
  final double borderRadius;
  final String semanticLabel;

  @override
  ConsumerState<RideCurrentLocationMap> createState() =>
      _RideCurrentLocationMapState();
}

class _RideCurrentLocationMapState
    extends ConsumerState<RideCurrentLocationMap> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _refreshAfterSettings);
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapConfiguration = ref.watch(mapConfigurationProvider);
    final supportedPlatform = ref.watch(mapPlatformSupportedProvider);
    final showGoogleMap =
        mapConfiguration.valueOrNull == true && supportedPlatform;
    final checkingConfiguration =
        mapConfiguration.isLoading && supportedPlatform;
    final location = showGoogleMap
        ? ref.watch(currentLocationControllerProvider)
        : const CurrentLocationState.initial();

    return Semantics(
      image: true,
      label: widget.semanticLabel,
      child: SizedBox(
        height: widget.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showGoogleMap)
                ref.watch(currentLocationMapBuilderProvider)(
                  context,
                  location.point,
                )
              else
                MapPlaceholder(
                  borderRadius: 0,
                  semanticLabel: widget.semanticLabel,
                ),
              if (checkingConfiguration)
                const _MapNotice(
                  key: ValueKey('map-configuration-loading'),
                  message: 'Preparing Google Maps...',
                  loading: true,
                )
              else if (!showGoogleMap)
                const _MapNotice(
                  key: ValueKey('map-configuration-fallback'),
                  message:
                      'Google Maps is unavailable. You can continue using RideX.',
                )
              else if (location.status != CurrentLocationStatus.available)
                _LocationNotice(location: location),
            ],
          ),
        ),
      ),
    );
  }

  void _refreshAfterSettings() {
    final mapConfigured =
        ref.read(mapConfigurationProvider).valueOrNull == true;
    final supportedPlatform = ref.read(mapPlatformSupportedProvider);
    if (!mapConfigured || !supportedPlatform) return;

    final location = ref.read(currentLocationControllerProvider);
    final loading = location.status == CurrentLocationStatus.checking ||
        location.status == CurrentLocationStatus.requestingPermission ||
        location.status == CurrentLocationStatus.loading;
    if (!loading) {
      ref.read(currentLocationControllerProvider.notifier).refresh();
    }
  }
}

class _LocationNotice extends ConsumerWidget {
  const _LocationNotice({required this.location});

  final CurrentLocationState location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(currentLocationControllerProvider.notifier);
    final loading = location.status == CurrentLocationStatus.checking ||
        location.status == CurrentLocationStatus.requestingPermission ||
        location.status == CurrentLocationStatus.loading;

    if (loading) {
      return const _MapNotice(
        key: ValueKey('current-location-loading'),
        message: 'Finding your current location...',
        loading: true,
      );
    }

    if (location.status == CurrentLocationStatus.serviceDisabled) {
      return _MapNotice(
        key: const ValueKey('location-service-disabled'),
        message:
            'Device location is turned off. RideX remains available without GPS.',
        actionLabel: 'Location settings',
        onAction: controller.openLocationSettings,
      );
    }

    if (location.permission == LocationPermissionStatus.permanentlyDenied) {
      return _MapNotice(
        key: const ValueKey('location-permanently-denied'),
        message:
            'Location permission is blocked. RideX remains available without GPS.',
        actionLabel: 'App settings',
        onAction: controller.openAppSettings,
      );
    }

    if (location.permission == LocationPermissionStatus.notRequested ||
        location.permission == LocationPermissionStatus.denied) {
      return _MapNotice(
        key: ValueKey(
          location.permission == LocationPermissionStatus.notRequested
              ? 'location-permission-initial'
              : 'location-permission-denied',
        ),
        message:
            'Allow location to show your current position. You can continue without it.',
        actionLabel: 'Allow location',
        onAction: controller.requestPermission,
      );
    }

    return _MapNotice(
      key: const ValueKey('current-location-unavailable'),
      message:
          'Your current location could not be found. You can continue without GPS.',
      actionLabel: 'Try again',
      onAction: controller.refresh,
    );
  }
}

class _MapNotice extends StatelessWidget {
  const _MapNotice({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.loading = false,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Card(
        margin: const EdgeInsets.all(AppSpacing.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              if (loading) ...[
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child:
                    Text(message, style: Theme.of(context).textTheme.bodySmall),
              ),
              if (actionLabel != null)
                TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ),
        ),
      ),
    );
  }
}
