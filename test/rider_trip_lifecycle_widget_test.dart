import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_assigned_trip.dart';
import 'package:ridex/core/models/rider_trip_lifecycle_state.dart';
import 'package:ridex/core/models/rider_trip_tracking_event.dart';
import 'package:ridex/core/providers/rider_trip_tracking_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/services/rider_trip_lifecycle_signals.dart';
import 'package:ridex/features/trips/presentation/widgets/rider_trip_lifecycle_status_view.dart';

import 'helpers/fake_rider_trip_tracking_repository.dart';

void main() {
  testWidgets(
    'duplicate advisory events preserve canonical status and single semantics',
    (tester) async {
      final repository = _GatedWidgetRepository(
        trip: riderAssignedTripFixture(),
      );
      final rig = _LifecycleWidgetRig(repository);
      addTearDown(rig.dispose);
      final semantics = tester.ensureSemantics();

      try {
        await rig.mount(tester);
        expect(find.text('Trip accepted'), findsOneWidget);
        expect(repository.tripLoadCount, 1);

        repository.emitStatus(
          tripVersion: 4,
          eventSequence: 1,
          status: DriverTripLifecycleStatus.inProgress,
          occurredAt: DateTime.utc(2026, 11, 6, 12),
        );
        repository.emitStatus(
          tripVersion: 4,
          eventSequence: 1,
          status: DriverTripLifecycleStatus.inProgress,
          occurredAt: DateTime.utc(2026, 11, 6, 12),
        );
        await tester.pumpAndSettle();

        expect(find.text('Trip accepted'), findsOneWidget);
        expect(find.text('Trip in progress'), findsNothing);
        expect(repository.tripLoadCount, 2);
        expect(find.bySemanticsLabel('Trip accepted'), findsOneWidget);
        expect(find.bySemanticsLabel('Trip in progress'), findsNothing);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'out-of-order events cannot regress status while canonical read is pending',
    (tester) async {
      final repository = _GatedWidgetRepository(
        trip: riderAssignedTripFixture(),
      );
      final rig = _LifecycleWidgetRig(repository);
      addTearDown(rig.dispose);
      final semantics = tester.ensureSemantics();

      try {
        await rig.mount(tester);
        expect(find.text('Trip accepted'), findsOneWidget);

        final latest = riderAssignedTripFixture(
          version: 5,
          status: DriverTripLifecycleStatus.inProgress,
        );
        final pendingRead = Completer<RiderAssignedTrip?>();
        repository
          ..trip = latest
          ..nextRead = pendingRead
          ..emitStatus(
            tripVersion: 5,
            eventSequence: 2,
            status: DriverTripLifecycleStatus.driverArrived,
            occurredAt: DateTime.utc(2026, 11, 6, 12, 1),
          );
        await tester.pumpAndSettle();

        expect(repository.tripLoadCount, 2);
        expect(rig.state.phase, RiderTripLifecyclePhase.stale);
        expect(find.text('Verifying current trip status'), findsOneWidget);
        expect(find.text('Trip accepted'), findsNothing);
        expect(find.text('Driver arrived'), findsNothing);
        expect(find.text('Trip in progress'), findsNothing);
        expect(
          find.bySemanticsLabel('Verifying current trip status'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('Trip accepted'), findsNothing);
        expect(find.bySemanticsLabel('Driver arrived'), findsNothing);

        repository.emitStatus(
          tripVersion: 4,
          eventSequence: 1,
          status: DriverTripLifecycleStatus.driverArriving,
          occurredAt: DateTime.utc(2026, 11, 6, 12, 2),
        );
        await tester.pumpAndSettle();

        expect(rig.state.phase, RiderTripLifecyclePhase.stale);
        expect(find.text('Verifying current trip status'), findsOneWidget);
        expect(find.text('Driver arriving'), findsNothing);
        expect(repository.tripLoadCount, 2);

        pendingRead.complete(latest);
        await tester.pumpAndSettle();

        expect(rig.state.phase, RiderTripLifecyclePhase.verified);
        expect(find.text('Trip in progress'), findsOneWidget);
        expect(find.text('Driver arrived'), findsNothing);
        expect(find.text('Driver arriving'), findsNothing);
        expect(find.bySemanticsLabel('Trip in progress'), findsOneWidget);
        expect(find.bySemanticsLabel('Driver arrived'), findsNothing);
        expect(find.bySemanticsLabel('Driver arriving'), findsNothing);
        expect(repository.tripLoadCount, 2);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'logout hides status and rejects late read and advisory publication',
    (tester) async {
      final repository = _GatedWidgetRepository(
        trip: riderAssignedTripFixture(),
      );
      final rig = _LifecycleWidgetRig(repository);
      addTearDown(rig.dispose);
      final semantics = tester.ensureSemantics();

      try {
        await rig.mount(tester);
        expect(find.text('Trip accepted'), findsOneWidget);

        final lateTrip = riderAssignedTripFixture(
          version: 4,
          status: DriverTripLifecycleStatus.driverArriving,
        );
        final pendingRead = Completer<RiderAssignedTrip?>();
        repository
          ..trip = lateTrip
          ..nextRead = pendingRead
          ..emitStatus(
            tripVersion: 4,
            eventSequence: 1,
            status: DriverTripLifecycleStatus.driverArriving,
            occurredAt: DateTime.utc(2026, 11, 6, 12, 1),
          );
        await tester.pumpAndSettle();
        expect(rig.state.phase, RiderTripLifecyclePhase.stale);
        expect(find.text('Verifying current trip status'), findsOneWidget);
        expect(repository.tripLoadCount, 2);

        rig.sessionController.setSession(const SessionState.unauthenticated());
        await tester.pumpAndSettle();

        expect(rig.state.phase, RiderTripLifecyclePhase.unavailable);
        expect(find.text('Trip status unavailable'), findsOneWidget);
        expect(find.text('Verifying current trip status'), findsNothing);
        expect(find.text('Trip accepted'), findsNothing);
        expect(find.text('Driver arriving'), findsNothing);
        expect(
            find.bySemanticsLabel('Trip status unavailable'), findsOneWidget);
        expect(find.bySemanticsLabel('Trip accepted'), findsNothing);
        expect(find.bySemanticsLabel('Driver arriving'), findsNothing);

        pendingRead.complete(lateTrip);
        await tester.pumpAndSettle();
        expect(rig.state.phase, RiderTripLifecyclePhase.unavailable);
        expect(find.text('Trip status unavailable'), findsOneWidget);
        expect(find.text('Driver arriving'), findsNothing);

        final readsAfterLogout = repository.tripLoadCount;
        repository.emitStatus(
          tripVersion: 5,
          eventSequence: 2,
          status: DriverTripLifecycleStatus.inProgress,
          occurredAt: DateTime.utc(2026, 11, 6, 12, 2),
        );
        await tester.pumpAndSettle();

        expect(repository.tripLoadCount, readsAfterLogout);
        expect(rig.state.phase, RiderTripLifecyclePhase.unavailable);
        expect(find.text('Trip status unavailable'), findsOneWidget);
        expect(find.text('Trip in progress'), findsNothing);
        expect(find.bySemanticsLabel('Trip in progress'), findsNothing);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'logout directly hides a verified status in text and semantics',
    (tester) async {
      final repository = _GatedWidgetRepository(
        trip: riderAssignedTripFixture(),
      );
      final rig = _LifecycleWidgetRig(repository);
      addTearDown(rig.dispose);
      final semantics = tester.ensureSemantics();

      try {
        await rig.mount(tester);

        expect(rig.state.phase, RiderTripLifecyclePhase.verified);
        expect(rig.state.trip, isNotNull);
        expect(find.text('Trip accepted'), findsOneWidget);
        expect(find.bySemanticsLabel('Trip accepted'), findsOneWidget);
        expect(repository.tripLoadCount, 1);

        rig.sessionController.setSession(const SessionState.unauthenticated());
        await tester.pumpAndSettle();

        expect(rig.state.phase, RiderTripLifecyclePhase.unavailable);
        expect(rig.state.trip, isNull);
        expect(find.text('Trip status unavailable'), findsOneWidget);
        expect(find.text('Trip accepted'), findsNothing);
        expect(
            find.bySemanticsLabel('Trip status unavailable'), findsOneWidget);
        expect(find.bySemanticsLabel('Trip accepted'), findsNothing);
        expect(repository.tripLoadCount, 1);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'captured old watch callback cannot publish after logout',
    (tester) async {
      final repository = _CapturedCallbackWidgetRepository(
        trip: riderAssignedTripFixture(),
      );
      final rig = _LifecycleWidgetRig(repository);
      addTearDown(rig.dispose);
      final semantics = tester.ensureSemantics();

      try {
        await rig.mount(tester);

        expect(rig.state.phase, RiderTripLifecyclePhase.verified);
        expect(find.text('Trip accepted'), findsOneWidget);
        expect(find.bySemanticsLabel('Trip accepted'), findsOneWidget);
        expect(repository.tripLoadCount, 1);
        expect(repository.watchStreams, hasLength(1));

        final oldWatch = repository.watchStreams.single;
        final capturedSubscription = oldWatch.subscription;
        expect(capturedSubscription, isNotNull);

        rig.sessionController.setSession(const SessionState.unauthenticated());
        await tester.pumpAndSettle();

        expect(rig.state.phase, RiderTripLifecyclePhase.unavailable);
        expect(rig.state.trip, isNull);
        expect(find.text('Trip status unavailable'), findsOneWidget);
        expect(find.text('Trip accepted'), findsNothing);
        expect(
            find.bySemanticsLabel('Trip status unavailable'), findsOneWidget);
        expect(find.bySemanticsLabel('Trip accepted'), findsNothing);
        expect(capturedSubscription!.isCancelled, isTrue);

        final readsAfterLogout = repository.tripLoadCount;
        oldWatch.deliverToCapturedCallback(
          RiderTripStatusChanged(
            tripId: riderTripIdFixture,
            tripVersion: 4,
            eventSequence: 1,
            status: DriverTripLifecycleStatus.inProgress,
            occurredAt: DateTime.utc(2026, 11, 6, 12, 3),
          ),
        );
        await tester.pumpAndSettle();

        expect(rig.state.phase, RiderTripLifecyclePhase.unavailable);
        expect(rig.state.trip, isNull);
        expect(find.text('Trip status unavailable'), findsOneWidget);
        expect(find.text('Trip accepted'), findsNothing);
        expect(find.text('Trip in progress'), findsNothing);
        expect(
            find.bySemanticsLabel('Trip status unavailable'), findsOneWidget);
        expect(find.bySemanticsLabel('Trip accepted'), findsNothing);
        expect(find.bySemanticsLabel('Trip in progress'), findsNothing);
        expect(repository.tripLoadCount, readsAfterLogout);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'pause/resume hides verified Trip until one canonical read succeeds',
    (tester) async {
      final initial = riderAssignedTripFixture();
      final resumed = riderAssignedTripFixture(
        version: 4,
        status: DriverTripLifecycleStatus.driverArriving,
      );
      final repository = _DelayedResumeRepository(trip: initial);
      final request = RiderTripLifecycleRequest(
        tripId: riderTripIdFixture,
        bookingRequestId: riderBookingIdFixture,
      );
      final container = ProviderContainer(
        overrides: [
          riderTripTrackingRepositoryProvider.overrideWithValue(repository),
          sessionControllerProvider.overrideWith(
            () => _WidgetSessionController(),
          ),
        ],
      );
      final subscription = container.listen(
        riderTripLifecycleControllerProvider(request),
        (_, __) {},
      );
      var resumeSignals = 0;
      final lifecycleSubscription = container
          .read(riderTripAppLifecycleSignalSourceProvider)
          .resumed
          .listen((_) => resumeSignals++);
      addTearDown(() async {
        await lifecycleSubscription.cancel();
        subscription.close();
        container.dispose();
        await _settle();
        await repository.close();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: _LifecycleProbe(request: request)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Trip accepted'), findsOneWidget);
      expect(repository.tripLoadCount, 1);

      // A resumed notification with no observed non-resumed transition is not
      // sufficient evidence for a foreground return.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(resumeSignals, 0);
      expect(repository.tripLoadCount, 1);

      final resumedRead = Completer<RiderAssignedTrip?>();
      repository.nextRead = resumedRead;
      repository.trip = resumed;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var index = 0; index < 10; index++) {
        await tester.pump(const Duration(milliseconds: 1));
      }

      expect(resumeSignals, 1);
      expect(
        container.read(riderTripLifecycleControllerProvider(request)).phase,
        RiderTripLifecyclePhase.stale,
      );
      expect(repository.tripLoadCount, 2);
      expect(find.text('Verifying current trip status'), findsOneWidget);
      expect(
        container.read(riderTripLifecycleControllerProvider(request)).trip,
        isNull,
      );

      // A repeated resumed notification without an intervening background
      // transition is not another reconciliation signal.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(repository.tripLoadCount, 2);
      expect(find.text('Verifying current trip status'), findsOneWidget);

      resumedRead.complete(resumed);
      await tester.pumpAndSettle();
      expect(find.text('Driver arriving'), findsOneWidget);
      expect(
        container.read(riderTripLifecycleControllerProvider(request)).trip,
        resumed,
      );
      expect(repository.tripLoadCount, 2);
    },
  );
}

class _LifecycleProbe extends ConsumerWidget {
  const _LifecycleProbe({required this.request});

  final RiderTripLifecycleRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(riderTripLifecycleControllerProvider(request));
    return Scaffold(
      body: Center(child: RiderTripLifecycleStatusView(state: state)),
    );
  }
}

class _WidgetSessionController extends SessionController {
  _WidgetSessionController({SessionState? initialState})
      : _initialState = initialState ??
            SessionState.fromUser(
              const AppUser(
                id: riderIdFixture,
                name: 'Local Rider',
                email: 'rider@example.invalid',
                role: RideRole.rider,
              ),
            );

  final SessionState _initialState;

  @override
  SessionState build() => _initialState;

  void setSession(SessionState next) => state = next;
}

class _LifecycleWidgetRig {
  _LifecycleWidgetRig(this.repository) {
    sessionController = _WidgetSessionController();
    container = ProviderContainer(
      overrides: [
        riderTripTrackingRepositoryProvider.overrideWithValue(repository),
        riderTripAppLifecycleSignalSourceProvider.overrideWithValue(
          const NoopRiderTripAppLifecycleSignalSource(),
        ),
        riderTripConnectionSignalSourceProvider.overrideWithValue(
          const NoopRiderTripConnectionSignalSource(),
        ),
        sessionControllerProvider.overrideWith(() => sessionController),
      ],
    );
    lifecycleSubscription = container.listen(
      riderTripLifecycleControllerProvider(request),
      (_, __) {},
    );
  }

  final FakeRiderTripTrackingRepository repository;
  final request = RiderTripLifecycleRequest(
    tripId: riderTripIdFixture,
    bookingRequestId: riderBookingIdFixture,
  );
  late final ProviderContainer container;
  late final ProviderSubscription<RiderTripLifecycleState>
      lifecycleSubscription;
  late final _WidgetSessionController sessionController;

  RiderTripLifecycleState get state =>
      container.read(riderTripLifecycleControllerProvider(request));

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: _LifecycleProbe(request: request)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    lifecycleSubscription.close();
    container.dispose();
    await _settle();
    await repository.close();
  }
}

class _GatedWidgetRepository extends FakeRiderTripTrackingRepository {
  _GatedWidgetRepository({required super.trip});

  Completer<RiderAssignedTrip?>? nextRead;

  @override
  Future<RiderAssignedTrip?> findByTrip({required String tripId}) {
    final pending = nextRead;
    if (pending == null) return super.findByTrip(tripId: tripId);
    nextRead = null;
    tripLoadCount++;
    requestedTripIds.add(tripId);
    return pending.future;
  }
}

class _CapturedCallbackWidgetRepository
    extends FakeRiderTripTrackingRepository {
  _CapturedCallbackWidgetRepository({required super.trip});

  final watchStreams = <_CapturedEventStream>[];

  @override
  Stream<RiderTripTrackingEvent> watch({required String tripId}) {
    watchCount++;
    watchedTripIds.add(tripId);
    final current = trip;
    if (isClosed ||
        current == null ||
        current.tripId.toLowerCase() != tripId.toLowerCase() ||
        current.riderId.toLowerCase() != authenticatedRiderId.toLowerCase()) {
      return Stream<RiderTripTrackingEvent>.empty();
    }

    final stream = _CapturedEventStream();
    watchStreams.add(stream);
    return stream;
  }
}

class _CapturedEventStream extends Stream<RiderTripTrackingEvent> {
  _CapturedEventSubscription? subscription;

  void deliverToCapturedCallback(RiderTripTrackingEvent event) {
    final captured = subscription;
    if (captured == null) {
      throw StateError('No production watch callback has been captured.');
    }
    captured.deliverIgnoringCancellation(event);
  }

  @override
  StreamSubscription<RiderTripTrackingEvent> listen(
    void Function(RiderTripTrackingEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final next = _CapturedEventSubscription(
      onDataCallback: onData,
      onErrorCallback: onError,
      onDoneCallback: onDone,
    );
    subscription = next;
    return next;
  }
}

class _CapturedEventSubscription
    implements StreamSubscription<RiderTripTrackingEvent> {
  _CapturedEventSubscription({
    required this.onDataCallback,
    required this.onErrorCallback,
    required this.onDoneCallback,
  });

  void Function(RiderTripTrackingEvent)? onDataCallback;
  Function? onErrorCallback;
  void Function()? onDoneCallback;
  bool _cancelled = false;
  bool _paused = false;

  bool get isCancelled => _cancelled;

  void deliverIgnoringCancellation(RiderTripTrackingEvent event) {
    onDataCallback?.call(event);
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
  }

  @override
  void onData(void Function(RiderTripTrackingEvent)? handleData) {
    onDataCallback = handleData;
  }

  @override
  void onError(Function? handleError) {
    onErrorCallback = handleError;
  }

  @override
  void onDone(void Function()? handleDone) {
    onDoneCallback = handleDone;
  }

  @override
  void pause([Future<void>? resumeSignal]) {
    _paused = true;
    resumeSignal?.whenComplete(resume);
  }

  @override
  void resume() => _paused = false;

  @override
  bool get isPaused => _paused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => Completer<E>().future;
}

class _DelayedResumeRepository extends FakeRiderTripTrackingRepository {
  _DelayedResumeRepository({required super.trip});

  Completer<RiderAssignedTrip?>? nextRead;

  @override
  Future<RiderAssignedTrip?> findByTrip({required String tripId}) {
    final pending = nextRead;
    if (pending == null) return super.findByTrip(tripId: tripId);
    nextRead = null;
    tripLoadCount++;
    requestedTripIds.add(tripId);
    return pending.future;
  }

  @override
  Stream<RiderTripTrackingEvent> watch({required String tripId}) {
    watchCount++;
    watchedTripIds.add(tripId);
    return _ImmediateCancelStream<RiderTripTrackingEvent>();
  }
}

class _ImmediateCancelStream<T> extends Stream<T> {
  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _ImmediateCancelSubscription<T>();
}

class _ImmediateCancelSubscription<T> implements StreamSubscription<T> {
  bool _paused = false;

  @override
  Future<void> cancel() async {}

  @override
  void onData(void Function(T data)? handleData) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void onError(Function? handleError) {}

  @override
  void pause([Future<void>? resumeSignal]) {
    _paused = true;
    resumeSignal?.whenComplete(resume);
  }

  @override
  void resume() => _paused = false;

  @override
  bool get isPaused => _paused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => Completer<E>().future;
}

Future<void> _settle() async {
  for (var index = 0; index < 6; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
