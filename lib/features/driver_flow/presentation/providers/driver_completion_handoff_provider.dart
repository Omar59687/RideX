import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/driver_completion_handoff_controller.dart';

/// Driver-owned read-only integration seam. No authorized Driver finance
/// endpoint/adapter is supplied by C05; keep null until backend-owner review.
final driverCompletionHandoffProvider =
    ChangeNotifierProvider.autoDispose<DriverCompletionHandoffController?>(
        (ref) => null);
