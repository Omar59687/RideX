import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/features/driver_flow/domain/driver_flow_contract.dart';
import 'driver_flow_repository_provider.dart';

/// Local fixture context only. The future integration owner must replace this
/// scope on logout, role/approval loss and account replacement, including A-B-A.
final class DriverAvailabilityScope {
  const DriverAvailabilityScope(this.session, this.vehicleId);
  final DriverFlowSession session;
  final String vehicleId;
}

/// Default unconfigured; no SDK session, vehicle or backend authority is invented.
final driverAvailabilityScopeProvider =
    Provider<DriverAvailabilityScope?>((ref) => null);
// Session/repository ownership, not screen ownership: removing the last widget
// must not discard a pending command, unknown outcome or authorization latch.
final driverAvailabilityControllerProvider =
    NotifierProvider<DriverAvailabilityController, DriverAvailabilityView>(
        DriverAvailabilityController.new);

final class DriverAvailabilityView {
  const DriverAvailabilityView(this.phase,
      {this.availability,
      this.revision = -1,
      this.changing = false,
      this.reading = false});
  final DriverFlowPhase phase;
  final DriverFlowAvailability? availability;
  final int revision;
  final bool changing;
  final bool reading;
  bool get canChange =>
      phase == DriverFlowPhase.ready &&
      !changing &&
      !reading &&
      (availability?.state == DriverAvailabilityState.offline ||
          availability?.state == DriverAvailabilityState.available);
  bool get canRefresh => !reading && phase != DriverFlowPhase.unauthorized;
}

// A captured build lifetime. Scope/repository identity and epoch are checked
// after reading Notifier.state, because that read can rebuild this same notifier.
typedef _AvailabilityLifetime = ({
  int epoch,
  DriverAvailabilityScope? scope,
  DriverFlowRepository repository,
});

class DriverAvailabilityController extends Notifier<DriverAvailabilityView> {
  int _epoch = 0;
  int _publication = 0;
  int _token = 0;
  final String _nonce =
      '${Random.secure().nextInt(1 << 32)}-${Random.secure().nextInt(1 << 32)}';
  int? _uncertainVersion;
  int _highestVersion = 0;
  late DriverFlowRepository _repository;
  DriverAvailabilityScope? _scope;

  _AvailabilityLifetime get _lifetime =>
      (epoch: _epoch, scope: _scope, repository: _repository);

  @override
  DriverAvailabilityView build() {
    ++_epoch;
    _uncertainVersion = null;
    _highestVersion = 0;
    _publication = 0;
    _scope = ref.watch(driverAvailabilityScopeProvider);
    _repository = ref.watch(driverFlowRepositoryProvider);
    final lifetime = _lifetime;
    StreamSubscription<DriverFlowSnapshot>? subscription;
    ref.onDispose(() {
      ++_epoch;
      unawaited(subscription?.cancel());
    });
    final scope = lifetime.scope;
    if (scope == null) {
      return const DriverAvailabilityView(DriverFlowPhase.unavailable);
    }
    Future.microtask(() async {
      if (_viewFor(lifetime) == null) return;
      try {
        subscription =
            lifetime.repository.watch(scope.session).listen((snapshot) {
          _observe(snapshot, lifetime);
        }, onError: (Object error) {
          final view = _viewFor(lifetime);
          if (view != null) {
            _fail(
                view.changing
                    ? DriverFlowPhase.unknown
                    : DriverFlowPhase.unavailable,
                lifetime);
          }
        });
      } on Object {
        _fail(DriverFlowPhase.unavailable, lifetime);
      }
      if (_viewFor(lifetime) != null) await refresh();
    });
    return const DriverAvailabilityView(DriverFlowPhase.loading);
  }

  DriverAvailabilityView? _viewFor(_AvailabilityLifetime lifetime) {
    // The first check avoids touching state after actual disposal. It is not
    // sufficient for deferred dependency changes: state itself flushes those.
    if (lifetime.epoch != _epoch) return null;
    final view = state;
    if (lifetime.epoch != _epoch ||
        !identical(lifetime.scope, _scope) ||
        !identical(lifetime.repository, _repository)) {
      return null;
    }
    return view;
  }

  void _fail(DriverFlowPhase phase, _AvailabilityLifetime lifetime) {
    final view = _viewFor(lifetime);
    if (view == null || view.phase == DriverFlowPhase.unauthorized) return;
    ++_publication;
    state = DriverAvailabilityView(phase,
        availability:
            phase == DriverFlowPhase.unauthorized ? null : view.availability,
        revision: view.revision,
        changing: view.changing);
  }

  void _observe(DriverFlowSnapshot snapshot, _AvailabilityLifetime lifetime,
      {bool read = false, bool correlatedReply = false}) {
    final view = _viewFor(lifetime);
    final scope = lifetime.scope;
    if (view == null ||
        scope == null ||
        view.phase == DriverFlowPhase.unauthorized) {
      return;
    }
    if (!snapshot.session.sameSession(scope.session) ||
        snapshot.source != DriverFlowSource.simulated) {
      _fail(DriverFlowPhase.stale, lifetime);
      return;
    }
    if (snapshot.revision < view.revision ||
        (!read && snapshot.revision == view.revision)) {
      return;
    }
    // Authorization belongs to the scope, independently of optional entity data.
    if (snapshot.phase == DriverFlowPhase.unauthorized) {
      ++_publication;
      state = DriverAvailabilityView(DriverFlowPhase.unauthorized,
          revision: snapshot.revision, changing: view.changing);
      return;
    }
    final availability = snapshot.availability;
    if (availability != null && availability.version < _highestVersion) {
      _fail(DriverFlowPhase.stale, lifetime);
      return;
    }
    if (availability != null) _highestVersion = availability.version;
    var phase = snapshot.phase;
    if (phase == DriverFlowPhase.ready && availability == null) {
      phase = DriverFlowPhase.unavailable;
    }
    if (correlatedReply) _uncertainVersion = null;
    if (_uncertainVersion != null) {
      // Entity version advancement alone cannot identify a lost write's outcome.
      // B01 has no authoritative reconciliation API. Fail closed until retirement
      // or the still-pending command's validated, correlated simulated reply.
      phase = DriverFlowPhase.unknown;
    }
    ++_publication;
    state = DriverAvailabilityView(phase,
        availability: availability,
        revision: snapshot.revision,
        changing: view.changing);
  }

  Future<void> refresh() async {
    final lifetime = _lifetime;
    final view = _viewFor(lifetime);
    final scope = lifetime.scope;
    if (view == null || scope == null || !view.canRefresh) return;
    final publication = _publication;
    state = DriverAvailabilityView(view.phase,
        availability: view.availability,
        revision: view.revision,
        changing: view.changing,
        reading: true);
    try {
      final result = await lifetime.repository.read(scope.session);
      final current = _viewFor(lifetime);
      if (current == null ||
          current.phase == DriverFlowPhase.unauthorized ||
          publication != _publication) {
        return;
      }
      if (result.outcome == DriverFlowOutcome.observed &&
          result.snapshot != null) {
        _observe(result.snapshot!, lifetime, read: true);
      } else {
        _fail(
            result.outcome == DriverFlowOutcome.unauthorized
                ? DriverFlowPhase.unauthorized
                : DriverFlowPhase.unavailable,
            lifetime);
      }
    } on Object {
      if (_viewFor(lifetime) != null && publication == _publication) {
        _fail(DriverFlowPhase.unavailable, lifetime);
      }
    }
  }

  Future<void> setOnline(bool online) async {
    final lifetime = _lifetime;
    final view = _viewFor(lifetime);
    final scope = lifetime.scope;
    if (view == null ||
        scope == null ||
        !view.canChange ||
        scope.vehicleId.trim().isEmpty) {
      return;
    }
    final availability = view.availability!;
    if ((availability.state == DriverAvailabilityState.available) == online) {
      return;
    }
    final publication = _publication;
    _uncertainVersion = availability.version;
    final command = DriverFlowSetAvailability(
        session: scope.session,
        targetId: scope.session.driverId,
        expectedVersion: availability.version,
        idempotencyToken:
            'availability-$_nonce-${scope.session.generation}-${++_token}',
        state: online
            ? DriverAvailabilityState.available
            : DriverAvailabilityState.offline,
        vehicleId: online ? scope.vehicleId : null);
    state = DriverAvailabilityView(DriverFlowPhase.pending,
        availability: availability, revision: view.revision, changing: true);
    try {
      DriverFlowResult result;
      try {
        result = await lifetime.repository.execute(command);
      } on Object {
        result = const DriverFlowResult(DriverFlowOutcome.unknown);
      }
      final current = _viewFor(lifetime);
      if (current == null || current.phase == DriverFlowPhase.unauthorized) {
        return;
      }
      final snapshot = result.snapshot;
      if (result.outcome == DriverFlowOutcome.simulated &&
          snapshot != null &&
          snapshot.session.sameSession(scope.session) &&
          snapshot.source == DriverFlowSource.simulated &&
          snapshot.phase == DriverFlowPhase.ready &&
          snapshot.revision >= current.revision &&
          snapshot.availability != null &&
          snapshot.availability!.version > command.expectedVersion &&
          snapshot.availability!.version >= _highestVersion &&
          snapshot.availability!.state == command.state &&
          snapshot.availability!.vehicleId == command.vehicleId &&
          (snapshot.revision > current.revision ||
              _sameAvailability(snapshot.availability, current.availability))) {
        // The fake may publish this same observation before returning the reply.
        _observe(snapshot, lifetime, read: true, correlatedReply: true);
      } else {
        if (publication != _publication) return;
        final phase = switch (result.outcome) {
          DriverFlowOutcome.unauthorized => DriverFlowPhase.unauthorized,
          DriverFlowOutcome.stale ||
          DriverFlowOutcome.rejected ||
          DriverFlowOutcome.expired =>
            DriverFlowPhase.stale,
          _ => DriverFlowPhase.unknown,
        };
        if (phase == DriverFlowPhase.unknown) {
          _uncertainVersion = availability.version;
        }
        _fail(phase, lifetime);
      }
    } finally {
      final current = _viewFor(lifetime);
      if (current != null) {
        state = DriverAvailabilityView(current.phase,
            availability: current.phase == DriverFlowPhase.unauthorized
                ? null
                : current.availability,
            revision: current.revision,
            reading: current.reading);
      }
    }
  }

  bool _sameAvailability(
          DriverFlowAvailability? a, DriverFlowAvailability? b) =>
      a != null &&
      b != null &&
      a.version == b.version &&
      a.state == b.state &&
      a.vehicleId == b.vehicleId &&
      a.bookingId == b.bookingId &&
      a.tripId == b.tripId;
}
