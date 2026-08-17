import 'package:flutter/services.dart';

abstract class RideMapService {
  Future<bool> isConfigured();
}

class GoogleRideMapService implements RideMapService {
  const GoogleRideMapService({
    required this.enabled,
    this.channel = const MethodChannel('ridex/maps_configuration'),
  });

  final bool enabled;
  final MethodChannel channel;

  @override
  Future<bool> isConfigured() async {
    if (!enabled) return false;
    try {
      return await channel.invokeMethod<bool>('isConfigured') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

class MockRideMapService implements RideMapService {
  const MockRideMapService({this.configured = false});

  final bool configured;

  @override
  Future<bool> isConfigured() async => configured;
}
