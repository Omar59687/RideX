import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ridex/core/models/location_point.dart';

class GoogleCurrentLocationMap extends StatefulWidget {
  const GoogleCurrentLocationMap({super.key, required this.point});

  final LocationPoint? point;

  @override
  State<GoogleCurrentLocationMap> createState() =>
      _GoogleCurrentLocationMapState();
}

class _GoogleCurrentLocationMapState extends State<GoogleCurrentLocationMap> {
  GoogleMapController? _controller;

  @override
  void didUpdateWidget(GoogleCurrentLocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.point != widget.point && widget.point != null) {
      _moveTo(widget.point!);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final point = widget.point;
    final target = point == null
        ? const LatLng(0, 0)
        : LatLng(point.latitude, point.longitude);

    return GoogleMap(
      key: const ValueKey('ridex-google-map'),
      initialCameraPosition: CameraPosition(
        target: target,
        zoom: point == null ? 1 : 16,
      ),
      mapType: MapType.normal,
      markers: point == null
          ? const {}
          : {
              Marker(
                markerId: const MarkerId('current-location'),
                position: target,
                infoWindow: const InfoWindow(title: 'Current location'),
              ),
            },
      myLocationButtonEnabled: false,
      myLocationEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
      onMapCreated: (controller) {
        if (_controller != null) {
          controller.dispose();
          return;
        }
        _controller = controller;
        if (point != null) _moveTo(point);
      },
    );
  }

  Future<void> _moveTo(LocationPoint point) async {
    await _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(point.latitude, point.longitude),
          zoom: 16,
        ),
      ),
    );
  }
}
