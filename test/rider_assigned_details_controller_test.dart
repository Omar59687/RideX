import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_assigned_trip.dart';
import 'package:ridex/core/models/rider_trip_tracking_event.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/rider_trip_tracking_repository.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/features/trips/presentation/providers/rider_assigned_details_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/fake_rider_trip_tracking_repository.dart';

class _Session extends SessionController {
  @override
  SessionState build() => SessionState.fromUser(_user(riderIdFixture));

  void replace(SessionState next) => state = next;
}

AppUser _user(String id, {bool blocked = false}) => AppUser(
      id: id,
      name: 'Test Rider',
      email: 'rider@example.test',
      role: RideRole.rider,
      isBlocked: blocked,
    );

// Test-local reconciliation prototype. This private class is NOT used by the
// production provider and does not establish SDK session-lineage authority.
class _FakeDetailsState {
  const _FakeDetailsState._(this.status, this.trip);
  const _FakeDetailsState.loading()
      : this._(RiderAssignedDetailsStatus.loading, null);
  const _FakeDetailsState.unavailable()
      : this._(RiderAssignedDetailsStatus.unavailable, null);
  const _FakeDetailsState.verified(RiderAssignedTrip trip)
      : this._(RiderAssignedDetailsStatus.verified, trip);

  final RiderAssignedDetailsStatus status;
  final RiderAssignedTrip? trip;
}

class _FakeDetailsController extends StateNotifier<_FakeDetailsState> {
  _FakeDetailsController({
    required this.tripId,
    required this.repository,
    required this.session,
    required this.currentSession,
    required this.sessionOwnsRider,
  }) : super(const _FakeDetailsState.loading()) {
    if (!isCanonicalTripId(tripId)) {
      throw ArgumentError.value(tripId, 'tripId', 'Must be a canonical UUID.');
    }
    if (!_authorized()) {
      state = const _FakeDetailsState.unavailable();
    } else {
      unawaited(refresh());
    }
  }

  final String tripId;
  final RiderTripTrackingRepository repository;
  final SessionState session;
  final SessionState Function() currentSession;
  final bool Function(String riderId) sessionOwnsRider;
  StreamSubscription<RiderTripTrackingEvent>? _subscription;
  int _generation = 0;
  int _watchGeneration = 0;
  int _highestVerifiedVersion = 0;
  RiderAssignedTrip? _lastVerified;
  bool _retired = false;
  bool _reading = false;
  bool _needsRead = false;

  bool _authorized() {
    final user = session.user;
    return !_retired &&
        mounted &&
        identical(currentSession(), session) &&
        session.status == SessionStatus.authenticated &&
        session.role == RideRole.rider &&
        user != null &&
        !user.isBlocked &&
        isCanonicalTripId(user.id) &&
        sessionOwnsRider(user.id);
  }

  void retireSession() {
    if (_retired) return;
    _retired = true;
    _generation++;
    _needsRead = false;
    _lastVerified = null;
    if (mounted) state = const _FakeDetailsState.unavailable();
    _retireWatch();
  }

  void _retireWatch() {
    _watchGeneration++;
    final old = _subscription;
    _subscription = null;
    if (old != null) unawaited(old.cancel());
  }

  Future<void> refresh() async {
    if (!_authorized()) {
      retireSession();
      return;
    }
    if (_reading) {
      _needsRead = true;
      state = const _FakeDetailsState.loading();
      return;
    }
    _reading = true;
    final generation = ++_generation;
    state = const _FakeDetailsState.loading();
    try {
      final trip = await repository.findByTrip(tripId: tripId);
      if (!_authorized() || generation != _generation) return;
      if (!_needsRead) {
        if (trip == null ||
            trip.tripId.toLowerCase() != tripId.toLowerCase() ||
            trip.riderId.toLowerCase() != session.user!.id.toLowerCase() ||
            trip.version < _highestVerifiedVersion ||
            (trip.version == _highestVerifiedVersion &&
                _lastVerified != null &&
                trip != _lastVerified)) {
          state = const _FakeDetailsState.unavailable();
        } else {
          _highestVerifiedVersion = trip.version;
          _lastVerified = trip;
          state = _FakeDetailsState.verified(trip);
          _watchOnce();
        }
      }
    } on Object {
      if (_authorized() && generation == _generation && !_needsRead) {
        state = const _FakeDetailsState.unavailable();
      }
    } finally {
      _reading = false;
      if (_needsRead && _authorized()) {
        _needsRead = false;
        unawaited(refresh());
      }
    }
  }

  void _watchOnce() {
    if (_subscription != null || !_authorized()) return;
    final watchGeneration = ++_watchGeneration;
    bool currentWatch() => watchGeneration == _watchGeneration && _authorized();
    void ended() {
      if (!currentWatch()) return;
      _retireWatch();
      _generation++;
      _needsRead = false;
      state = const _FakeDetailsState.unavailable();
    }

    try {
      final subscription = repository.watch(tripId: tripId).listen(
        (event) {
          if (currentWatch()) _onEvent(event);
        },
        onError: (Object _) => ended(),
        onDone: ended,
      );
      if (currentWatch()) {
        _subscription = subscription;
      } else {
        unawaited(subscription.cancel());
      }
    } on Object {
      if (currentWatch()) {
        _retireWatch();
        state = const _FakeDetailsState.unavailable();
      }
    }
  }

  void _onEvent(RiderTripTrackingEvent event) {
    if (!_authorized()) {
      retireSession();
      return;
    }
    if (event.tripId.toLowerCase() != tripId.toLowerCase()) return;
    if (event is RiderTripTrackingDisconnected) {
      _retireWatch();
      _generation++;
      _needsRead = false;
      state = const _FakeDetailsState.unavailable();
      return;
    }
    if (event is RiderTripLocationChanged) return;
    if (event is RiderTripSnapshot) {
      if (event.trip.version < _highestVerifiedVersion ||
          (event.trip.version == _highestVerifiedVersion &&
              event.trip == _lastVerified)) {
        return;
      }
    } else if (event is RiderTripStatusChanged) {
      if (event.tripVersion < _highestVerifiedVersion ||
          (event.tripVersion == _highestVerifiedVersion &&
              event.status == _lastVerified?.status)) {
        return;
      }
    }
    unawaited(refresh());
  }

  @override
  void dispose() {
    retireSession();
    super.dispose();
  }
}

class _Reads implements RiderTripTrackingRepository {
  _Reads(this.fake);
  final FakeRiderTripTrackingRepository fake;
  final List<Completer<RiderAssignedTrip?>> pending = [];

  @override
  Future<RiderAssignedTrip?> findByTrip({required String tripId}) {
    final completer = Completer<RiderAssignedTrip?>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<RiderAssignedTrip?> findByBooking({
    required String bookingRequestId,
  }) =>
      fake.findByBooking(bookingRequestId: bookingRequestId);

  @override
  Stream<RiderTripTrackingEvent> watch({required String tripId}) =>
      fake.watch(tripId: tripId);
}

/// Deliberately retains callbacks after cancellation to simulate a broken
/// transport delivering events from an obsolete watch.
class _WatchProbe extends Stream<RiderTripTrackingEvent> {
  void Function(RiderTripTrackingEvent)? _onData;
  Function? _onError;
  void Function()? _onDone;
  String? synchronousAction;

  @override
  StreamSubscription<RiderTripTrackingEvent> listen(
    void Function(RiderTripTrackingEvent event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _onData = onData;
    _onError = onError;
    _onDone = onDone;
    if (synchronousAction == 'error') fail();
    if (synchronousAction == 'completion') finish();
    return const Stream<RiderTripTrackingEvent>.empty().listen((_) {});
  }

  void emit(RiderTripTrackingEvent event) => _onData?.call(event);
  void fail() => _onError?.call(StateError('watch failed'));
  void finish() => _onDone?.call();
}

class _WatchedReads implements RiderTripTrackingRepository {
  _WatchedReads(this.fake);

  final FakeRiderTripTrackingRepository fake;
  final List<_WatchProbe> watches = [];
  int reads = 0;
  Object? nextWatchAction;

  @override
  Future<RiderAssignedTrip?> findByTrip({required String tripId}) {
    reads++;
    return fake.findByTrip(tripId: tripId);
  }

  @override
  Future<RiderAssignedTrip?> findByBooking(
          {required String bookingRequestId}) =>
      fake.findByBooking(bookingRequestId: bookingRequestId);

  @override
  Stream<RiderTripTrackingEvent> watch({required String tripId}) {
    final probe = _WatchProbe();
    watches.add(probe);
    probe.synchronousAction = nextWatchAction as String?;
    nextWatchAction = null;
    return probe;
  }
}

class _Harness {
  _Harness(this.repository) {
    _session = SessionState.fromUser(_user(riderIdFixture));
    controller = _FakeDetailsController(
      tripId: riderTripIdFixture,
      repository: repository,
      session: _session,
      currentSession: () => _session,
      sessionOwnsRider: (riderId) => riderId == riderIdFixture,
    );
  }

  final RiderTripTrackingRepository repository;
  late SessionState _session;
  late final _FakeDetailsController controller;

  _FakeDetailsState get state => controller.state;
  void session(SessionState next) {
    _session = next;
    controller.retireSession();
  }

  void close() => controller.dispose();
}

Future<void> _tick() async {
  // Drain microtasks only: no timers, sleeps, or wall-clock assumptions.
  await Future<void>.value();
  await Future<void>.value();
  await Future<void>.value();
}

void main() {
  test(
    'fresh owned Trip verifies identity and retains unknown display fields',
    () async {
      final trip = riderAssignedTripFixture(includeVehicleDetails: false);
      final fake = FakeRiderTripTrackingRepository(trip: trip);
      final h = _Harness(fake);
      addTearDown(() async {
        h.close();
        await fake.close();
      });
      expect(h.state.status, RiderAssignedDetailsStatus.loading);
      await _tick();
      expect(h.state.status, RiderAssignedDetailsStatus.verified);
      expect(h.state.trip, same(trip));
      expect(h.state.trip!.driver.displayName, isNull);
      expect(h.state.trip!.vehicle.make, isNull);
      expect(fake.requestedTripIds, [riderTripIdFixture]);
      expect(fake.watchCount, 1);
    },
  );

  test('missing, failed and foreign Rider reads cannot verify', () async {
    for (final fake in [
      FakeRiderTripTrackingRepository(),
      FakeRiderTripTrackingRepository(trip: riderAssignedTripFixture())
        ..tripLoadError = StateError('offline'),
      FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(riderId: unrelatedRiderIdFixture),
      ),
    ]) {
      final h = _Harness(fake);
      await _tick();
      expect(h.state.status, RiderAssignedDetailsStatus.unavailable);
      expect(h.state.trip, isNull);
      expect(fake.watchCount, 0);
      h.close();
      await fake.close();
    }
  });

  test('rejects a repository result with the wrong Trip or Rider', () async {
    for (final result in [
      riderAssignedTripFixture(
        tripId: secondaryRiderTripIdFixture,
        bookingRequestId: secondaryRiderBookingIdFixture,
      ),
      riderAssignedTripFixture(riderId: unrelatedRiderIdFixture),
    ]) {
      final fake = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );
      final reads = _Reads(fake);
      final h = _Harness(reads);
      reads.pending.single.complete(result);
      await _tick();
      expect(h.state.status, RiderAssignedDetailsStatus.unavailable);
      expect(h.state.trip, isNull);
      expect(fake.watchCount, 0);
      h.close();
      await fake.close();
    }
  });

  test('rejects invalid explicit Trip ID', () async {
    final fake = FakeRiderTripTrackingRepository(
      trip: riderAssignedTripFixture(),
    );
    final session = SessionState.fromUser(_user(riderIdFixture));
    expect(
      () => _FakeDetailsController(
        tripId: 'mock-trip',
        repository: fake,
        session: session,
        currentSession: () => session,
        sessionOwnsRider: (_) => true,
      ),
      throwsArgumentError,
    );
    await fake.close();
  });

  test('wrong Trip event cannot change evidence or trigger reread', () async {
    final trip = riderAssignedTripFixture();
    final fake = FakeRiderTripTrackingRepository(trip: trip);
    final h = _Harness(fake);
    addTearDown(() async {
      h.close();
      await fake.close();
    });
    await _tick();
    fake.emitForeignFor(
      watchedTripId: trip.tripId,
      event: RiderTripSnapshot(
        riderAssignedTripFixture(
          tripId: secondaryRiderTripIdFixture,
          bookingRequestId: secondaryRiderBookingIdFixture,
          version: 99,
        ),
      ),
    );
    await _tick();
    expect(h.state.trip, same(trip));
    expect(fake.tripLoadCount, 1);
  });

  test('older and duplicate snapshots and status do not reread', () async {
    final trip = riderAssignedTripFixture();
    final fake = FakeRiderTripTrackingRepository(trip: trip);
    final h = _Harness(fake);
    addTearDown(() async {
      h.close();
      await fake.close();
    });
    await _tick();
    fake.emitSnapshot(riderAssignedTripFixture(version: 2));
    fake.emitSnapshot();
    fake.emitStatus(
      tripVersion: 2,
      eventSequence: 7,
      status: DriverTripLifecycleStatus.driverArriving,
    );
    fake.emitStatus(tripVersion: 3, eventSequence: 8, status: trip.status);
    await _tick();
    expect(fake.tripLoadCount, 1);
    expect(h.state.trip, same(trip));
  });

  test(
    'newer event triggers canonical reread, never publishes event snapshot',
    () async {
      final old = riderAssignedTripFixture(driverDisplayName: 'Old');
      final fresh = riderAssignedTripFixture(
        version: 4,
        driverDisplayName: 'Canonical',
      );
      final fake = FakeRiderTripTrackingRepository(trip: old);
      final reads = _Reads(fake);
      final h = _Harness(reads);
      addTearDown(() async {
        h.close();
        await fake.close();
      });
      reads.pending[0].complete(old);
      await _tick();
      fake.emitSnapshot(
        riderAssignedTripFixture(version: 9, driverDisplayName: 'Unverified'),
      );
      await _tick();
      expect(h.state.trip, isNull);
      expect(reads.pending, hasLength(2));
      reads.pending[1].complete(fresh);
      await _tick();
      expect(h.state.trip, same(fresh));
    },
  );

  test(
    'conflicting same-version event rereads; conflicting read fails closed',
    () async {
      final original = riderAssignedTripFixture(driverDisplayName: 'Original');
      final conflict = riderAssignedTripFixture(driverDisplayName: 'Changed');
      final fake = FakeRiderTripTrackingRepository(trip: original);
      final reads = _Reads(fake);
      final h = _Harness(reads);
      addTearDown(() async {
        h.close();
        await fake.close();
      });
      reads.pending[0].complete(original);
      await _tick();
      fake.emitSnapshot(conflict);
      await _tick();
      expect(h.state.trip, isNull);
      reads.pending[1].complete(conflict);
      await _tick();
      expect(h.state.status, RiderAssignedDetailsStatus.unavailable);
      expect(h.state.trip, isNull);
    },
  );

  test('a lagging canonical reread cannot roll back a verified version',
      () async {
    final original = riderAssignedTripFixture(version: 4);
    final fake = FakeRiderTripTrackingRepository(trip: original);
    final reads = _Reads(fake);
    final h = _Harness(reads);
    addTearDown(() async {
      h.close();
      await fake.close();
    });
    reads.pending.single.complete(original);
    await _tick();
    fake.emitStatus(
      tripVersion: 5,
      eventSequence: 1,
      status: DriverTripLifecycleStatus.driverArriving,
    );
    await _tick();
    reads.pending[1].complete(riderAssignedTripFixture(version: 3));
    await _tick();
    expect(h.state.status, RiderAssignedDetailsStatus.unavailable);
    expect(h.state.trip, isNull);
  });

  test(
    'coalesces events during a read and ignores obsolete completion',
    () async {
      final original = riderAssignedTripFixture(version: 3);
      final fresh = riderAssignedTripFixture(version: 5);
      final fake = FakeRiderTripTrackingRepository(trip: original);
      final reads = _Reads(fake);
      final h = _Harness(reads);
      addTearDown(() async {
        h.close();
        await fake.close();
      });
      reads.pending[0].complete(original);
      await _tick();
      fake.emitStatus(
        tripVersion: 4,
        eventSequence: 1,
        status: DriverTripLifecycleStatus.driverArriving,
      );
      await _tick();
      fake.emitStatus(
        tripVersion: 5,
        eventSequence: 2,
        status: DriverTripLifecycleStatus.driverArrived,
      );
      fake.emitStatus(
        tripVersion: 5,
        eventSequence: 3,
        status: DriverTripLifecycleStatus.driverArrived,
      );
      await _tick();
      expect(reads.pending, hasLength(2));
      reads.pending[1].complete(riderAssignedTripFixture(version: 4));
      await _tick();
      expect(h.state.trip, isNull);
      expect(reads.pending, hasLength(3));
      reads.pending[2].complete(fresh);
      await _tick();
      expect(h.state.trip, same(fresh));
    },
  );

  test('logout during pending read invalidates result', () async {
    final fake = FakeRiderTripTrackingRepository(
      trip: riderAssignedTripFixture(),
    );
    final reads = _Reads(fake);
    final h = _Harness(reads);
    addTearDown(() async {
      h.close();
      await fake.close();
    });
    h.session(const SessionState.unauthenticated());
    expect(h.state.status, RiderAssignedDetailsStatus.unavailable);
    reads.pending.single.complete(fake.trip);
    await _tick();
    expect(h.state.trip, isNull);
    expect(fake.watchCount, 0);
  });

  test(
    'Rider replacement and blocked session retire visible details',
    () async {
      for (final replacement in [
        SessionState.fromUser(_user(unrelatedRiderIdFixture)),
        SessionState.fromUser(_user(riderIdFixture, blocked: true)),
      ]) {
        final fake = FakeRiderTripTrackingRepository(
          trip: riderAssignedTripFixture(),
        );
        final h = _Harness(fake);
        await _tick();
        expect(h.state.status, RiderAssignedDetailsStatus.verified);
        h.session(replacement);
        expect(h.state.status, RiderAssignedDetailsStatus.unavailable);
        expect(h.state.trip, isNull);
        await _tick();
        expect(fake.hasListener, isFalse);
        h.close();
        await fake.close();
      }
    },
  );

  test(
    'same-Rider session replacement retires old repository and late result',
    () async {
      final fake = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );
      final reads = _Reads(fake);
      final h = _Harness(reads);
      addTearDown(() async {
        h.close();
        await fake.close();
      });
      h.session(SessionState.fromUser(_user(riderIdFixture)));
      reads.pending.single.complete(fake.trip);
      await _tick();
      expect(h.state.trip, isNull);
      await h.controller.refresh();
      expect(reads.pending, hasLength(1));
    },
  );

  test('disposal rejects late result', () async {
    final fake = FakeRiderTripTrackingRepository(
      trip: riderAssignedTripFixture(),
    );
    final reads = _Reads(fake);
    final h = _Harness(reads);
    h.close();
    reads.pending.single.complete(fake.trip);
    await _tick();
    expect(fake.watchCount, 0);
    await fake.close();
  });

  test(
    'disconnect clears details; failed explicit recovery stays unavailable',
    () async {
      final fake = FakeRiderTripTrackingRepository(
        trip: riderAssignedTripFixture(),
      );
      final h = _Harness(fake);
      addTearDown(() async {
        h.close();
        await fake.close();
      });
      await _tick();
      fake.emitDisconnected(reason: 'network');
      await _tick();
      expect(h.state.status, RiderAssignedDetailsStatus.unavailable);
      fake.tripLoadError = StateError('offline');
      await h.controller.refresh();
      expect(h.state.status, RiderAssignedDetailsStatus.unavailable);
      expect(h.state.trip, isNull);
      expect(fake.tripLoadCount, 2);
    },
  );

  for (final ending in ['error', 'completion']) {
    test('watch $ending retires and explicit read installs a new watch',
        () async {
      final fake =
          FakeRiderTripTrackingRepository(trip: riderAssignedTripFixture());
      final reads = _WatchedReads(fake);
      final h = _Harness(reads);
      addTearDown(() async {
        h.close();
        await fake.close();
      });
      await _tick();
      expect(reads.watches, hasLength(1));
      final old = reads.watches.single;
      if (ending == 'error') {
        old.fail();
      } else {
        old.finish();
      }
      expect(h.state.status, RiderAssignedDetailsStatus.unavailable);
      await h.controller.refresh();
      expect(h.state.status, RiderAssignedDetailsStatus.verified);
      expect(reads.watches, hasLength(2));

      // A canceled transport may still call back; it must not affect the new
      // watch or spawn a reread.
      old.finish();
      old.fail();
      old.emit(RiderTripSnapshot(riderAssignedTripFixture(version: 99)));
      expect(h.state.status, RiderAssignedDetailsStatus.verified);
      expect(reads.reads, 2);

      fake.trip = riderAssignedTripFixture(version: 4);
      reads.watches.last.emit(RiderTripSnapshot(fake.trip!));
      await _tick();
      expect(reads.reads, 3);
      expect(h.state.trip, same(fake.trip));
    });
  }

  for (final ending in ['error', 'completion']) {
    test('synchronous watch $ending fails closed and permits explicit recovery',
        () async {
      final fake =
          FakeRiderTripTrackingRepository(trip: riderAssignedTripFixture());
      final reads = _WatchedReads(fake)..nextWatchAction = ending;
      final h = _Harness(reads);
      addTearDown(() async {
        h.close();
        await fake.close();
      });
      await _tick();
      expect(reads.watches, hasLength(1));
      expect(h.state.status, RiderAssignedDetailsStatus.unavailable);

      await h.controller.refresh();
      expect(h.state.status, RiderAssignedDetailsStatus.verified);
      expect(reads.watches, hasLength(2));
      final obsolete = reads.watches.first;
      obsolete.fail();
      obsolete.finish();
      obsolete.emit(RiderTripSnapshot(riderAssignedTripFixture(version: 99)));
      expect(h.state.status, RiderAssignedDetailsStatus.verified);
      expect(reads.reads, 2);
    });
  }

  for (final hasClient in [false, true]) {
    test('production provider stays read-only with client=$hasClient',
        () async {
      final client = hasClient
          ? SupabaseClient(
              'https://c03-gate.unit-test.invalid',
              'offline-publishable-test-key',
              authOptions: const AuthClientOptions(autoRefreshToken: false),
            )
          : null;
      final fake =
          FakeRiderTripTrackingRepository(trip: riderAssignedTripFixture());
      final reads = _WatchedReads(fake);
      final container = ProviderContainer(overrides: [
        sessionControllerProvider.overrideWith(_Session.new),
        supabaseClientProvider.overrideWithValue(client),
      ]);
      final request = (tripId: riderTripIdFixture, repository: reads);
      final subscription = container.listen(
        riderAssignedDetailsProvider(request),
        (_, __) {},
      );

      expect(container.read(riderAssignedDetailsProvider(request)).status,
          RiderAssignedDetailsStatus.unavailable);
      container.invalidate(riderAssignedDetailsProvider(request));
      expect(container.read(riderAssignedDetailsProvider(request)).status,
          RiderAssignedDetailsStatus.unavailable);
      await _tick();
      expect(reads.reads, 0);
      expect(fake.tripLoadCount, 0);
      expect(fake.bookingLoadCount, 0);
      expect(reads.watches, isEmpty);
      expect(fake.watchCount, 0);

      expect(
        () => container.read(riderAssignedDetailsProvider(
          (tripId: 'mock-trip', repository: reads),
        )),
        throwsArgumentError,
      );
      expect(reads.reads, 0);
      expect(reads.watches, isEmpty);

      subscription.close();
      container.dispose();
      await client?.dispose();
      await fake.close();
    });
  }
}
