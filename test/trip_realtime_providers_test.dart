import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/providers/trip_realtime_providers.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';

void main() {
  test('adapter composition remains unavailable without Supabase config', () {
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(null)],
    );
    addTearDown(container.dispose);

    expect(container.read(tripRealtimeSourceProvider), isNull);
    expect(container.read(tripRealtimeAdapterProvider), isNull);
    expect(container.read(riderTripLocationSourceProvider), isNull);
    expect(container.read(riderTripLocationAdapterProvider), isNull);
  });
}
