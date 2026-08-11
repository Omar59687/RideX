import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/services/maps/ride_map_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ridex/test_maps_configuration');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('does not query native configuration when Maps is disabled', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      return true;
    });
    const service = GoogleRideMapService(enabled: false, channel: channel);

    expect(await service.isConfigured(), isFalse);
    expect(calls, 0);
  });

  test('requires both Dart enablement and a native API key', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isConfigured');
      return false;
    });
    const service = GoogleRideMapService(enabled: true, channel: channel);

    expect(await service.isConfigured(), isFalse);
  });

  test('fails closed when native configuration cannot be inspected', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'unavailable');
    });
    const service = GoogleRideMapService(enabled: true, channel: channel);

    expect(await service.isConfigured(), isFalse);
  });
}
