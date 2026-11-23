import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'canonical_driver_presentation_controller.dart';

/// Driver-owned default-off insertion point. Reviewed host composition creates
/// a fresh repository/delivery/session owner on login/resume and disposes those
/// borrowed inputs with ref.onDispose. Require restorationEnabled true and
/// offerActionsEnabled false. No global routing, SDK or journal is invented here.
final driverActiveTripRestorationProvider =
    ChangeNotifierProvider.autoDispose<CanonicalDriverPresentationController?>(
        (ref) => null);
