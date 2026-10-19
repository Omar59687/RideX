import 'dart:js_interop';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@JS('supabaseFlutterClientToDispose')
external JSFunction? get capturedCleanup;

/// Invokes the actual JS callback installed by the SDK on web initialization.
Future<void> exerciseWebCleanup() async {
  SharedPreferences.setMockInitialValues({});
  final sdk = await Supabase.initialize(
    url: 'https://web-cleanup.unit-test.invalid',
    publishableKey: 'sb_publishable_local_web_fixture_000000000',
    debug: false,
    authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(), detectSessionInUri: false),
  );
  final client = sdk.client;
  final callback = capturedCleanup;
  if (callback == null) {
    throw StateError('SDK did not install web hot-restart cleanup.');
  }
  callback.callAsFunction();
  if (!client.isDisposingOrDisposed) {
    throw StateError('Hot-restart cleanup did not mark client disposal.');
  }
  final cleanup = client.dispose();
  if (!identical(cleanup, client.dispose())) {
    throw StateError('Hot-restart cleanup was not shared.');
  }
  await cleanup;
  if (!client.isDisposingOrDisposed) {
    throw StateError('Hot-restart disposal evidence was lost.');
  }
  await sdk.dispose();
}
