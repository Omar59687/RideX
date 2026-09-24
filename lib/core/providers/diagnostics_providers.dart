import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';

final appErrorReporterProvider = Provider<AppErrorReporter>(
  (_) => const DebugAppErrorReporter(),
);
