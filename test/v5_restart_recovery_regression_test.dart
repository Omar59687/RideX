import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/booking_handoff.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/services/fare/pending_fare_lock_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// V5-04 offline restart/lost-response regression coverage.
///
/// What this file proves: the production persistence envelope
/// ([SharedPreferencesPendingFareLockStore]'s schema-2 JSON) survives
/// store-instance recreation over the plugin's official in-memory async
/// backend. One backend object is shared per test while every store handle
/// is recreated, which is the closest offline analogue to an application
/// restart: writes go through one production store instance, verification
/// reads go through a NEW production store instance.
///
/// What this file does NOT prove: physical-device restart, process death,
/// or hosted Supabase behavior. Existing controller-level coverage lives in
/// `pending_fare_lock_test.dart`, `fare_lock_recovery_test.dart`,
/// `booking_confirmation_handoff_test.dart`,
/// `authorized_evidence_resolution_test.dart`, and
/// `booking_mutation_gate_test.dart`; nothing here duplicates those cases.
/// No production code is exercised beyond the real store class and models.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemorySharedPreferencesAsync backend;
  SharedPreferencesAsyncPlatform? previousPlatform;
  setUp(() {
    previousPlatform = SharedPreferencesAsyncPlatform.instance;
    backend = InMemorySharedPreferencesAsync.empty();
    SharedPreferencesAsyncPlatform.instance = backend;
    // Restore the pre-test platform even when a test fails, so no state
    // leaks into other suites sharing this process.
    addTearDown(() {
      SharedPreferencesAsyncPlatform.instance = previousPlatform;
    });
  });

  PendingFareLock testCommand({String bookingId = 'booking-1'}) {
    final quoteId = bookingId == 'booking-1' ? 'quote-1' : 'quote-2';
    return PendingFareLock(
      bookingRequestId: bookingId,
      expectedBookingVersion: 1,
      fareQuoteId: quoteId,
      expectedQuoteVersion: 1,
      riderId: 'rider-1',
      status: PendingLockRecoveryStatus.uncertain,
      createdAt: DateTime.utc(2026, 10, 10, 12),
    );
  }

  FareQuote lockedQuote() => FareQuote.fromJson({
        'id': 'quote-1',
        'booking_request_id': 'booking-1',
        'quote_version': 1,
        'pricing_version': 1,
        'fixed_fare_fils': 2000,
        'breakdown': {
          'base_fare_fils': 500,
          'distance_fils': 1200,
          'duration_fils': 300,
          'stops_fils': 0,
          'subtotal_fils': 2000,
          'minimum_fare_fils': 1000,
          'rounding_increment_fils': 50,
          'fixed_fare_fils': 2000,
        },
        'currency': 'JOD',
        'status': 'locked',
        'expires_at': '2026-10-10T12:10:00Z',
        'created_at': '2026-10-10T12:00:00Z',
        'route_distance_meters': 5400,
        'route_duration_seconds': 720,
      });

  ConfirmedBookingReference testReference() => ConfirmedBookingReference(
        command: testCommand(),
        quote: lockedQuote(),
      );

  SharedPreferencesPendingFareLockStore freshStore() =>
      SharedPreferencesPendingFareLockStore(SharedPreferencesAsync());

  test('staged command survives store-instance recreation', () async {
    await freshStore().save(testCommand());

    final slot = await freshStore().inspectForRider('rider-1');

    expect(slot.isValid, isTrue);
    expect(slot.command, testCommand());
    expect(slot.confirmed, isEmpty);
  });

  test(
      'retired envelope survives recreation; repeat booking stays safe '
      'without resubmission', () async {
    await freshStore().save(testCommand());
    await freshStore().retireConfirmed(
      testReference(),
      isAuthorized: () => true,
    );

    final restarted = freshStore();
    final slot = await restarted.inspectForRider('rider-1');
    expect(slot.isAbsent, isTrue);
    expect(slot.confirmed, hasLength(1));
    expect(slot.confirmed.single.command, testCommand());
    expect(slot.confirmed.single.quote, lockedQuote());

    // A new booking lineage stages normally after completed recovery.
    await restarted.save(testCommand(bookingId: 'booking-2'));
    final restaged = await freshStore().inspectForRider('rider-1');
    expect(restaged.isValid, isTrue);
    expect(restaged.command!.bookingRequestId, 'booking-2');

    // The retired lineage itself stays retired: no duplicate confirmation.
    await expectLater(
      freshStore().save(testCommand()),
      throwsA(isA<PendingFareLockConflictException>()),
    );
  });

  test('duplicate retirement is a silent no-op preserving one reference',
      () async {
    final store = freshStore();
    await store.save(testCommand());
    await store.retireConfirmed(
      testReference(),
      isAuthorized: () => true,
    );
    final raw = await SharedPreferencesAsync()
        .getString('pending_fare_lock.v1.rider-1');

    await freshStore().retireConfirmed(
      testReference(),
      isAuthorized: () => true,
    );

    final slot = await freshStore().inspectForRider('rider-1');
    expect(slot.confirmed, hasLength(1));
    expect(
      await SharedPreferencesAsync().getString('pending_fare_lock.v1.rider-1'),
      raw,
    );
  });

  test('clear preserves confirmed references across recreation', () async {
    await freshStore().save(testCommand());
    await freshStore().retireConfirmed(
      testReference(),
      isAuthorized: () => true,
    );
    await freshStore().clearForRider('rider-1');

    final slot = await freshStore().inspectForRider('rider-1');

    expect(slot.isAbsent, isTrue);
    expect(slot.confirmed, hasLength(1));
    expect(slot.confirmed.single.command, testCommand());
  });

  test('planted corrupt JSON stays corrupt and blocks overwrite', () async {
    const key = 'pending_fare_lock.v1.rider-1';
    await SharedPreferencesAsync().setString(key, '{broken-json');

    final slot = await freshStore().inspectForRider('rider-1');
    expect(slot.isCorrupt, isTrue);

    await expectLater(
      freshStore().save(testCommand()),
      throwsA(isA<PendingFareLockCorruptException>()),
    );
    expect(await SharedPreferencesAsync().getString(key), '{broken-json');
  });

  test('per-rider namespaces stay isolated across recreation', () async {
    await freshStore().save(testCommand());

    final other = await freshStore().inspectForRider('rider-2');
    expect(other.isAbsent, isTrue);

    final riderTwoCommand = PendingFareLock(
      bookingRequestId: 'booking-9',
      expectedBookingVersion: 1,
      fareQuoteId: 'quote-9',
      expectedQuoteVersion: 1,
      riderId: 'rider-2',
      status: PendingLockRecoveryStatus.uncertain,
      createdAt: DateTime.utc(2026, 10, 10, 12),
    );
    await freshStore().save(riderTwoCommand);

    expect(
      (await freshStore().inspectForRider('rider-1')).command,
      testCommand(),
    );
    expect(
      (await freshStore().inspectForRider('rider-2')).command,
      riderTwoCommand,
    );
  });

  test('confirmed reference round-trips JSON and rejects lineage mismatch',
      () async {
    final restored = ConfirmedBookingReference.fromJson(
      Map<String, dynamic>.from(
        testReference().toJson(),
      ),
    );
    expect(restored.command, testCommand());
    expect(restored.quote, lockedQuote());

    final mismatched = FareQuote.fromJson({
      ...lockedQuote().toJson(),
      'id': 'quote-other',
    });
    expect(
      () => ConfirmedBookingReference.fromJson({
        'command': testCommand().toJson(),
        'quote': mismatched.toJson(),
      }),
      throwsA(
        isA<FareException>().having(
          (error) => error.failure,
          'failure',
          FareFailure.invalidResponse,
        ),
      ),
    );
  });
}
