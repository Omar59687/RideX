import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/place_selection_state.dart';

class GoogleLocationSelectionMap extends StatefulWidget {
  const GoogleLocationSelectionMap({
    super.key,
    required this.activeEndpoint,
    required this.pickup,
    required this.destination,
    required this.currentLocation,
    required this.onPointSelected,
  });

  final LocationEndpoint activeEndpoint;
  final RideLocation? pickup;
  final RideLocation? destination;
  final LocationPoint? currentLocation;
  final ValueChanged<LocationPoint> onPointSelected;

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
    if (_activePoint != null && oldPoint != _activePoint) {
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
        if (_activePoint != null) _moveTo(_activePoint!);
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
    await _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: _latLng(point), zoom: 16),
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
