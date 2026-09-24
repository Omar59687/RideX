import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/place_selection_state.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';
import 'package:ridex/core/services/maps/ride_map_service.dart';

class GoogleLocationSelectionMap extends StatefulWidget {
  const GoogleLocationSelectionMap({
    super.key,
    required this.activeEndpoint,
    required this.pickup,
    required this.destination,
    required this.currentLocation,
    required this.routeGeometry,
    required this.onPointSelected,
    required this.errorReporter,
  });

  final LocationEndpoint activeEndpoint;
  final RideLocation? pickup;
  final RideLocation? destination;
  final LocationPoint? currentLocation;
  final List<LocationPoint> routeGeometry;
  final ValueChanged<LocationPoint> onPointSelected;
  final AppErrorReporter errorReporter;

  @override
  State<GoogleLocationSelectionMap> createState() =>
      _GoogleLocationSelectionMapState();
}

class _GoogleLocationSelectionMapState
    extends State<GoogleLocationSelectionMap> {
  GoogleMapController? _controller;

  LocationPoint? get _activePoint =>
      widget.activeEndpoint == LocationEndpoint.pickup
          ? widget.pickup?.point
          : widget.destination?.point;

  @override
  void didUpdateWidget(GoogleLocationSelectionMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPoint = oldWidget.activeEndpoint == LocationEndpoint.pickup
        ? oldWidget.pickup?.point
        : oldWidget.destination?.point;
    if (!listEquals(oldWidget.routeGeometry, widget.routeGeometry) &&
        widget.routeGeometry.length >= 2) {
      _scheduleRouteFit();
    } else if (_activePoint != null && oldPoint != _activePoint) {
      _moveTo(_activePoint!);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialPoint = _activePoint ?? widget.currentLocation;
    final initialTarget = initialPoint == null
        ? const LatLng(31.9539, 35.9106)
        : _latLng(initialPoint);
    return GoogleMap(
      key: const ValueKey('ridex-location-selection-google-map'),
      initialCameraPosition: CameraPosition(
        target: initialTarget,
        zoom: initialPoint == null ? 8 : 16,
      ),
      markers: _markers,
      polylines: buildRoutePolylines(
        geometry: widget.routeGeometry,
        routeColor: context.rideXTheme.routeLive,
        haloColor: context.rideXTheme.mapRouteHalo,
      ),
      onTap: (position) => widget.onPointSelected(
        LocationPoint(
          latitude: position.latitude,
          longitude: position.longitude,
        ),
      ),
      onMapCreated: (controller) {
        if (_controller != null) {
          controller.dispose();
          return;
        }
        _controller = controller;
        if (widget.routeGeometry.length >= 2) {
          _scheduleRouteFit();
        } else if (_activePoint != null) {
          _moveTo(_activePoint!);
        }
      },
      myLocationButtonEnabled: false,
      myLocationEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
    );
  }

  Set<Marker> get _markers {
    final markers = <Marker>{};
    final pickup = widget.pickup;
    final destination = widget.destination;
    final current = widget.currentLocation;
    if (current != null && !_sameCoordinates(current, pickup?.point)) {
      markers.add(
        Marker(
          markerId: const MarkerId('current-location'),
          position: _latLng(current),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Current location'),
        ),
      );
    }
    if (pickup != null) {
      markers.add(_endpointMarker(
        id: 'pickup',
        location: pickup,
        active: widget.activeEndpoint == LocationEndpoint.pickup,
        hue: BitmapDescriptor.hueOrange,
      ));
    }
    if (destination != null) {
      markers.add(_endpointMarker(
        id: 'destination',
        location: destination,
        active: widget.activeEndpoint == LocationEndpoint.destination,
        hue: BitmapDescriptor.hueBlue,
      ));
    }
    return markers;
  }

  Marker _endpointMarker({
    required String id,
    required RideLocation location,
    required bool active,
    required double hue,
  }) {
    return Marker(
      markerId: MarkerId(id),
      position: _latLng(location.point),
      draggable: active,
      icon: BitmapDescriptor.defaultMarkerWithHue(hue),
      infoWindow: InfoWindow(title: location.label),
      onDragEnd: active
          ? (position) => widget.onPointSelected(
                LocationPoint(
                  latitude: position.latitude,
                  longitude: position.longitude,
                ),
              )
          : null,
    );
  }

  Future<void> _moveTo(LocationPoint point) async {
    final controller = _controller;
    if (controller == null) return;
    await runMapCameraOperation(
      operation: 'moving the location-selection map camera',
      errorReporter: widget.errorReporter,
      action: () => controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _latLng(point), zoom: 16),
        ),
      ),
    );
  }

  void _scheduleRouteFit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitRoute();
    });
  }

  Future<void> _fitRoute() async {
    final bounds = routeBounds(widget.routeGeometry);
    final controller = _controller;
    if (bounds == null || controller == null) return;
    await runMapCameraOperation(
      operation: 'fitting the route on the map',
      errorReporter: widget.errorReporter,
      action: () => controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 44),
      ),
    );
  }

  static LatLng _latLng(LocationPoint point) =>
      LatLng(point.latitude, point.longitude);

  static bool _sameCoordinates(LocationPoint point, LocationPoint? other) =>
      other != null &&
      point.latitude == other.latitude &&
      point.longitude == other.longitude;
}

Set<Polyline> buildRoutePolylines({
  required List<LocationPoint> geometry,
  required Color routeColor,
  required Color haloColor,
}) {
  if (geometry.length < 2) return const {};
  final points = [
    for (final point in geometry) LatLng(point.latitude, point.longitude),
  ];
  return {
    Polyline(
      polylineId: const PolylineId('route-halo'),
      points: points,
      color: haloColor,
      width: 10,
      zIndex: 1,
    ),
    Polyline(
      polylineId: const PolylineId('route-live'),
      points: points,
      color: routeColor,
      width: 6,
      zIndex: 2,
    ),
  };
}

LatLngBounds? routeBounds(List<LocationPoint> geometry) {
  if (geometry.length < 2) return null;
  var minLatitude = geometry.first.latitude;
  var maxLatitude = geometry.first.latitude;
  var minLongitude = geometry.first.longitude;
  var maxLongitude = geometry.first.longitude;
  for (final point in geometry.skip(1)) {
    minLatitude = point.latitude < minLatitude ? point.latitude : minLatitude;
    maxLatitude = point.latitude > maxLatitude ? point.latitude : maxLatitude;
    minLongitude =
        point.longitude < minLongitude ? point.longitude : minLongitude;
    maxLongitude =
        point.longitude > maxLongitude ? point.longitude : maxLongitude;
  }
  return LatLngBounds(
    southwest: LatLng(minLatitude, minLongitude),
    northeast: LatLng(maxLatitude, maxLongitude),
  );
}
