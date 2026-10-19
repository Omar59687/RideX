import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/core/services/supabase/supabase_initialization_provenance.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (!EnvConfig.hasBackendConfig) {
    return null;
  }
  return Supabase.instance.client;
});

/// Read-only provenance access, not a live Driver completion/recovery provider.
/// Normal application repositories retain their existing singleton behavior.
/// Driver composition must use driverAccess with an approved registry and
/// recheck the resulting capability; this provider never grants approval.
final supabaseInitializationProvenanceProvider =
    Provider<SupabaseInitializationProvenance>(
        (ref) => SupabaseInitializationProvenance.application);
