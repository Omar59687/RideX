import 'package:flutter/services.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';

abstract class RideMapService {
  Future<bool> isConfigured();
}

class GoogleRideMapService implements RideMapService {
  const GoogleRideMapService({
    required this.enabled,
    required this.errorReporter,
    this.channel = const MethodChannel('ridex/maps_configuration'),
  });

  final bool enabled;
  final AppErrorReporter errorReporter;
  final MethodChannel channel;

  @override
  Future<bool> isConfigured() async {
    if (!enabled) return false;
    try {
      return await channel.invokeMethod<bool>('isConfigured') ?? false;
    } on Object catch (error, stackTrace) {
      errorReporter.report(
        operation: 'checking map configuration',
        error: error,
        stackTrace: stackTrace,
      );
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

Future<void> runMapCameraOperation({
  required String operation,
  required AppErrorReporter errorReporter,
  required Future<void> Function() action,
}) async {
  try {
    await action();
  } on Object catch (error, stackTrace) {
    errorReporter.report(
      operation: operation,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
