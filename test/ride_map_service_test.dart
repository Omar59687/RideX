import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/services/maps/ride_map_service.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';

import 'helpers/recording_error_reporter.dart';

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
    const service = GoogleRideMapService(
      enabled: false,
      errorReporter: NoopAppErrorReporter(),
      channel: channel,
    );

    expect(await service.isConfigured(), isFalse);
    expect(calls, 0);
  });

  test('requires both Dart enablement and a native API key', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isConfigured');
      return false;
    });
    const service = GoogleRideMapService(
      enabled: true,
      errorReporter: NoopAppErrorReporter(),
      channel: channel,
    );

    expect(await service.isConfigured(), isFalse);
  });

  test('fails closed when native configuration cannot be inspected', () async {
    final error =
        PlatformException(code: 'unavailable', message: rawErrorCanary);
    final reporter = RecordingAppErrorReporter();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw error;
    });
    final service = GoogleRideMapService(
      enabled: true,
      errorReporter: reporter,
      channel: channel,
    );

    expect(await service.isConfigured(), isFalse);
    expect(reporter.reports.single.error, isA<PlatformException>());
    expect(reporter.reports.single.error.toString(), contains(rawErrorCanary));
  });

  test('camera failures are contained and reported', () async {
    final error = StateError(rawErrorCanary);
    final reporter = RecordingAppErrorReporter();

    await runMapCameraOperation(
      operation: 'testing a map camera operation',
      errorReporter: reporter,
      action: () => Future<void>.error(error),
    );

    expect(reporter.reports.single.error, same(error));
  });
}
