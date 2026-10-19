import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/sdk_disposal_socket.dart';
import 'helpers/sdk_web_disposal_stub.dart'
    if (dart.library.js_interop) 'helpers/sdk_web_disposal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    test(
        'real SDK web hot-restart cleanup marks its captured client immediately',
        exerciseWebCleanup);
  }
  for (final fails in [false, true]) {
    test('real SDK client shares gated disposal, failure=$fails', () async {
      final client = SupabaseClient('https://sdk.unit-test.invalid',
          'sb_publishable_local_disposal_fixture_00000000');
      final socket = DisposalSocket()..attach(client);
      expect(client.isDisposingOrDisposed, isFalse);
      final first = client.dispose();
      // No await has occurred since invoking disposal.
      expect(client.isDisposingOrDisposed, isTrue);
      expect(client.dispose(), same(first));
      await socket.entered.future;
      expect(socket.closeCalls, 1);
      final assertion = fails
          ? expectLater(first, throwsStateError)
          : expectLater(first, completes);
      if (fails) {
        socket.gate.completeError(StateError('local cleanup failure fixture'));
      } else {
        socket.gate.complete();
      }
      await assertion;
      expect(client.isDisposingOrDisposed, isTrue);
      expect(client.dispose(), same(first));
      expect(socket.closeCalls, 1);
      // A retained failure is handled again, never a new cleanup attempt.
      if (fails) await expectLater(client.dispose(), throwsStateError);
    });
  }
}
