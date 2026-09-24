import 'package:flutter/foundation.dart';

abstract interface class AppErrorReporter {
  void report({
    required String operation,
    required Object error,
    StackTrace? stackTrace,
  });
}

class DebugAppErrorReporter implements AppErrorReporter {
  const DebugAppErrorReporter();

  @override
  void report({
    required String operation,
    required Object error,
    StackTrace? stackTrace,
  }) {
    if (!kDebugMode) return;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'RideX',
        context: ErrorDescription('while $operation'),
        silent: true,
      ),
    );
  }
}

class NoopAppErrorReporter implements AppErrorReporter {
  const NoopAppErrorReporter();

  @override
  void report({
    required String operation,
    required Object error,
    StackTrace? stackTrace,
  }) {}
}
