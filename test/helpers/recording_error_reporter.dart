import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';

const rawErrorCanary =
    'PlatformException GoogleMaps https://provider.example/route?key=secret_key '
    '{"access_token":"secret_token"} HTTP 500 SDK failure\n#0 stackFrame';

class RecordedAppError {
  const RecordedAppError({
    required this.operation,
    required this.error,
    required this.stackTrace,
  });

  final String operation;
  final Object error;
  final StackTrace? stackTrace;
}

class RecordingAppErrorReporter implements AppErrorReporter {
  final reports = <RecordedAppError>[];

  @override
  void report({
    required String operation,
    required Object error,
    StackTrace? stackTrace,
  }) {
    reports.add(
      RecordedAppError(
        operation: operation,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }
}
