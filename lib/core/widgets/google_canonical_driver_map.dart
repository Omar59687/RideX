import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ridex/core/models/rider_trip_location.dart';

/// Displays only a canonical Trip/Driver-verified location supplied by D04.
/// Authorization is owned by the parent lifecycle and location adapters;
/// this map never reads a raw Realtime payload or retains a stale marker.
class GoogleCanonicalDriverMap extends StatefulWidget {
  const GoogleCanonicalDriverMap({
    super.key,
    required this.location,
    this.maximumAge = const Duration(seconds: 45),
    this.clock = DateTime.now,
  });

  final RiderTripLocation location;
  final Duration maximumAge;
  final DateTime Function() clock;

  @override
  State<GoogleCanonicalDriverMap> createState() =>
      _GoogleCanonicalDriverMapState();
}

class _GoogleCanonicalDriverMapState extends State<GoogleCanonicalDriverMap> {
  GoogleMapController? _controller;
  Timer? _expiryTimer;
  int _cameraGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scheduleExpiry();
  }

  @override
  void didUpdateWidget(covariant GoogleCanonicalDriverMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location.tripId != widget.location.tripId ||
        oldWidget.location.driverId != widget.location.driverId) {
      // The new Trip/Driver must never reuse a camera from an old identity.
      _cameraGeneration++;
      final previous = _controller;
      _controller = null;
      previous?.dispose();
    } else if (oldWidget.location.sequence != widget.location.sequence) {
      unawaited(_moveCamera());
    }
    _scheduleExpiry();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _cameraGeneration++;
    _controller?.dispose();
    super.dispose();
  }

  bool get _fresh {
    final age = widget.clock().toUtc().difference(widget.location.recordedAt);
    return !age.isNegative && age <= widget.maximumAge;
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final delay = widget.location.recordedAt
        .add(widget.maximumAge)
        .add(const Duration(milliseconds: 1))
        .difference(widget.clock().toUtc());
    _expiryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        if (!mounted) return;
        if (!_fresh) {
          _cameraGeneration++;
          final previous = _controller;
          _controller = null;
          previous?.dispose();
        }
        setState(() {});
      },
    );
  }

  Future<void> _moveCamera() async {
    final camera = _controller;
    if (camera == null || !_fresh) return;
    final generation = ++_cameraGeneration;
    final point = widget.location.point;
    try {
      if (!mounted || generation != _cameraGeneration || !_fresh) return;
      await camera.animateCamera(CameraUpdate.newLatLng(
        LatLng(point.latitude, point.longitude),
      ));
    } on Object {
      // A removed map or unavailable platform cannot leak location details.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_fresh) {
      return const Text(
        'Waiting for a fresh verified Driver location.',
        key: ValueKey('canonical-driver-location-unavailable'),
      );
    }

    final point = widget.location.point;
    final target = LatLng(point.latitude, point.longitude);
    return SizedBox(
      height: 240,
      child: GoogleMap(
        key: ValueKey('canonical-driver-map-${widget.location.tripId}-${widget.location.driverId}'),
        initialCameraPosition: CameraPosition(target: target, zoom: 15),
        markers: {
          Marker(
            markerId: const MarkerId('canonical-verified-driver'),
            position: target,
            infoWindow: const InfoWindow(title: 'Verified Driver location'),
          ),
        },
        onMapCreated: (controller) {
          if (!mounted || !_fresh || _controller != null) {
            controller.dispose();
            return;
          }
          _controller = controller;
        },
        myLocationEnabled: false,
        myLocationButtonEnabled: false,
        compassEnabled: false,
        mapToolbarEnabled: false,
        zoomControlsEnabled: false,
      ),
    );
  }
}
