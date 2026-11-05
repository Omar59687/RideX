import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/rider_live_map_marker.dart';
import 'package:ridex/core/models/rider_live_map_state.dart';
import 'package:ridex/core/widgets/google_maps_attribution.dart';

/// Camera command boundary. Test fakes can observe requests without creating a
/// platform GoogleMap.
abstract interface class RiderLiveMapCameraPort {
  Future<void> moveTo(LocationPoint point);
}

/// Surface seam used to inject a platform-free test map.
///
/// Implementations should initialize their camera to [marker]'s point and call
/// [onMapCreated] when camera commands can be accepted.
typedef GoogleRiderLiveMapSurfaceBuilder = Widget Function(
  BuildContext context, {
  required RiderLiveMapMarkerData marker,
  required ValueChanged<RiderLiveMapCameraPort> onMapCreated,
});

/// Google Maps implementation for the injected Rider live-map renderer seam.
///
/// [configured] must reflect both map-key configuration and platform support
/// from the existing host configuration boundary. The adapter performs no
/// configuration lookup, network request, or authorization decision of its own.
class GoogleRiderLiveMapRenderer extends StatelessWidget {
  const GoogleRiderLiveMapRenderer({
    super.key,
    required this.state,
    required this.configured,
    this.surfaceBuilder,
  });

  final RiderLiveMapState state;
  final bool configured;
  final GoogleRiderLiveMapSurfaceBuilder? surfaceBuilder;

  @override
  Widget build(BuildContext context) {
    final marker = RiderLiveMapMarkerData.project(state);
    if (!configured || marker == null) {
      return _GoogleMapUnavailableFallback(
        configured: configured,
        state: state,
        projectedMarker: marker,
      );
    }

    return _AuthorizedGoogleMapSurface(
      state: state,
      marker: marker,
      surfaceBuilder: surfaceBuilder ?? _googleMapSurface,
    );
  }
}

/// Pure Google marker-value mapping. It does not create or initialize a map.
Set<Marker> googleRiderDriverMarkers(RiderLiveMapState state) {
  final marker = RiderLiveMapMarkerData.project(state);
  return marker == null ? const {} : _googleMarkers(marker);
}

Set<Marker> _googleMarkers(RiderLiveMapMarkerData marker) {
  return {
    Marker(
      markerId: const MarkerId('ridex-authorized-driver'),
      position: LatLng(marker.point.latitude, marker.point.longitude),
      icon: BitmapDescriptor.defaultMarkerWithHue(
        marker.isLive ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueOrange,
      ),
      infoWindow: InfoWindow(title: marker.accessibleLabel),
      draggable: false,
      flat: false,
    ),
  };
}

Widget _googleMapSurface(
  BuildContext context, {
  required RiderLiveMapMarkerData marker,
  required ValueChanged<RiderLiveMapCameraPort> onMapCreated,
}) {
  final target = LatLng(marker.point.latitude, marker.point.longitude);
  return Stack(
    fit: StackFit.expand,
    children: [
      GoogleMap(
        key: const ValueKey('google-rider-live-map'),
        initialCameraPosition: CameraPosition(target: target, zoom: 15),
        markers: _googleMarkers(marker),
        polylines: const {},
        onMapCreated: (controller) =>
            onMapCreated(_GoogleMapsCameraPort(controller)),
        myLocationButtonEnabled: false,
        myLocationEnabled: false,
        compassEnabled: false,
        mapToolbarEnabled: false,
        zoomControlsEnabled: false,
      ),
      const Positioned(
        right: AppSpacing.xs,
        bottom: AppSpacing.xs,
        child: Material(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            child: GoogleMapsAttribution(),
          ),
        ),
      ),
    ],
  );
}

class _AuthorizedGoogleMapSurface extends StatefulWidget {
  const _AuthorizedGoogleMapSurface({
    required this.state,
    required this.marker,
    required this.surfaceBuilder,
  });

  final RiderLiveMapState state;
  final RiderLiveMapMarkerData marker;
  final GoogleRiderLiveMapSurfaceBuilder surfaceBuilder;

  @override
  State<_AuthorizedGoogleMapSurface> createState() =>
      _AuthorizedGoogleMapSurfaceState();
}

class _AuthorizedGoogleMapSurfaceState
    extends State<_AuthorizedGoogleMapSurface> {
  RiderLiveMapCameraPort? _camera;
  LocationPoint? _pendingTarget;
  LocationPoint? _lastRequestedTarget;
  int _surfaceGeneration = 0;
  int _cameraGeneration = 0;
  Future<void> _cameraQueue = Future<void>.value();

  @override
  void didUpdateWidget(_AuthorizedGoogleMapSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.surfaceBuilder != widget.surfaceBuilder) {
      _invalidateSurfaceGeneration();
    } else if (oldWidget.marker.point != widget.marker.point) {
      _pendingTarget = widget.marker.point;
      _queueCurrentTarget();
    }
  }

  @override
  void dispose() {
    // Invalidates queued commands and late onMapCreated callbacks. GoogleMap
    // owns its concrete controller and disposes it with the platform widget.
    _surfaceGeneration++;
    _cameraGeneration++;
    _camera = null;
    _pendingTarget = null;
    _lastRequestedTarget = null;
    _cameraQueue = Future<void>.value();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surfaceGeneration = _surfaceGeneration;
    return Semantics(
      container: true,
      image: true,
      label: widget.marker.accessibleLabel,
      child: KeyedSubtree(
        key: ValueKey('authorized-map-surface-$surfaceGeneration'),
        child: widget.surfaceBuilder(
          context,
          marker: widget.marker,
          onMapCreated: (camera) => _onMapCreated(camera, surfaceGeneration),
        ),
      ),
    );
  }

  void _onMapCreated(
    RiderLiveMapCameraPort camera,
    int surfaceGeneration,
  ) {
    if (!mounted || surfaceGeneration != _surfaceGeneration) return;
    final activeCamera = _camera;
    if (activeCamera != null) {
      // The first ready controller owns a surface generation. Repeated or
      // late callbacks cannot replace it with a different map instance.
      if (identical(activeCamera, camera) && _pendingTarget != null) {
        _queueCurrentTarget();
      }
      return;
    }
    _camera = camera;
    if (_pendingTarget == null) {
      // The initial camera position is already the authorized point supplied
      // to the map surface. Do not issue the same camera command again.
      _lastRequestedTarget = widget.marker.point;
      return;
    }
    _queueCurrentTarget();
  }

  void _invalidateSurfaceGeneration() {
    _surfaceGeneration++;
    _cameraGeneration++;
    _camera = null;
    _pendingTarget = null;
    _lastRequestedTarget = null;
    // Do not let a delayed command for the previous controller block the new
    // surface. Its queued closure checks the generation before dispatch.
    _cameraQueue = Future<void>.value();
    // The replacement surface receives the current widget.marker and uses it
    // as its own authorized initial camera target.
  }

  void _queueCurrentTarget() {
    final camera = _camera;
    final target = _pendingTarget ?? widget.marker.point;
    if (camera == null) {
      _pendingTarget = target;
      return;
    }
    if (_lastRequestedTarget == target && _pendingTarget == null) return;

    _pendingTarget = null;
    _lastRequestedTarget = target;
    final generation = ++_cameraGeneration;
    _cameraQueue = _cameraQueue.catchError((Object _) {}).then((_) async {
      if (!_isCurrentTarget(generation, camera, target)) return;
      try {
        await camera.moveTo(target);
      } on Object {
        // Provider/platform details and coordinates are intentionally not
        // surfaced or logged. A later authorized point can retry the move.
        if (_isCurrentTarget(generation, camera, target)) {
          _lastRequestedTarget = null;
        }
      }
    });
  }

  bool _isCurrentTarget(
    int generation,
    RiderLiveMapCameraPort camera,
    LocationPoint target,
  ) {
    if (!mounted ||
        generation != _cameraGeneration ||
        !identical(_camera, camera)) {
      return false;
    }
    final current = RiderLiveMapMarkerData.project(widget.state);
    return current != null && current.point == target;
  }
}

class _GoogleMapsCameraPort implements RiderLiveMapCameraPort {
  const _GoogleMapsCameraPort(this._controller);

  final GoogleMapController _controller;

  @override
  Future<void> moveTo(LocationPoint point) {
    return _controller.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(point.latitude, point.longitude),
          zoom: 15,
        ),
      ),
    );
  }
}

class _GoogleMapUnavailableFallback extends StatelessWidget {
  const _GoogleMapUnavailableFallback({
    required this.configured,
    required this.state,
    required this.projectedMarker,
  });

  final bool configured;
  final RiderLiveMapState state;
  final RiderLiveMapMarkerData? projectedMarker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authorized =
        state.authorizationStatus == RiderLiveMapAuthorizationStatus.authorized;
    final message = !configured
        ? projectedMarker == null
            ? 'Google Maps is unavailable. No Driver marker is plotted.'
            : 'Google Maps is unavailable. ${projectedMarker!.accessibleLabel} is available but not geographically plotted.'
        : !authorized
            ? 'Trip authorization is unavailable. Driver marker hidden.'
            : state.gpsStatus == RiderLiveMapGpsStatus.unavailable
                ? 'Driver GPS is unavailable. No current marker is available.'
                : 'Waiting for a valid authorized Driver location.';

    return ColoredBox(
      key: const ValueKey('google-rider-map-unavailable'),
      color: theme.colorScheme.surfaceContainerLow,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Semantics(
            container: true,
            image: true,
            label: message,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  projectedMarker == null || configured
                      ? Icons.map_outlined
                      : Icons.location_on_rounded,
                  size: 34,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  projectedMarker == null || configured
                      ? 'Map unavailable'
                      : 'Marker not plotted',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
