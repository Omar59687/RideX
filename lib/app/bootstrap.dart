import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/app.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/core/services/supabase/supabase_initialization_provenance.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final environment = EnvConfig.supabaseEnvironment;
    await SupabaseInitializationProvenance.application.initialize(environment);
  } on EnvConfigException {
    _reportStartupFailure('Backend configuration was rejected.');
    runApp(const RideXInitializationFailureApp());
    return;
  } on Object {
    _reportStartupFailure('Backend initialization did not complete.');
    runApp(const RideXInitializationFailureApp());
    return;
  }

  runApp(const ProviderScope(child: RideXApp()));
}

void _reportStartupFailure(String category) {
  if (kDebugMode) {
    debugPrint('RideX startup failed: $category');
  }
}
