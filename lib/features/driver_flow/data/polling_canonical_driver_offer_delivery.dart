import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/driver_eligibility_repository.dart';
import '../domain/canonical_driver_delivery.dart';
import 'canonical_driver_offer_discovery_port.dart';

/// Inactive B09 SELECT polling, not Realtime or assignment evidence.
/// One instance/subscription per session lifetime. The owner must invalidate on
/// lifecycle/authority loss; remounting a widget must not recreate B07 intent.
/// Cancellation suppresses late HTTP results; it cannot abort the SDK request.
final class PollingCanonicalDriverOfferDelivery
    implements CanonicalDriverDelivery {
  PollingCanonicalDriverOfferDelivery({
    required this.port,
    required ValueListenable<SessionState> session,
    required Listenable authorityInvalidations,
    this.enabled = false,
    DateTime Function()? clock,
  })  : _sessionSource = session,
        _session = session.value,
        _invalidations = authorityInvalidations,
        _owner = port.currentOwner,
        _sdkSession = port.sessionIdentity,
        _clock = clock ?? DateTime.now {
    _events = StreamController<CanonicalDriverDeliverySignal>(
      sync: true,
      onListen: () => scheduleMicrotask(_start),
      onCancel: dispose,
      // Pausing cannot queue stale authority/offer observations for replay.
      onPause: dispose,
    );
  }

  static const pollInterval = Duration(seconds: 2);
  static const readDeadline = Duration(seconds: 4);
  static const maxRememberedOffers = 64;
  final CanonicalDriverOfferDiscoveryPort port;
  final bool enabled;
  final ValueListenable<SessionState> _sessionSource;
  final SessionState _session;
  final Listenable _invalidations;
  final DriverAuthorityOwner _owner;
  final Object? _sdkSession;
  final DateTime Function() _clock;
  late final StreamController<CanonicalDriverDeliverySignal> _events;
  final Map<String, _OfferObservation> _seen = {};
  final Set<String> _terminal = {};
  Timer? _pollTimer, _deadlineTimer, _expiryTimer;
  bool _stopped = false, _listening = false, _connected = false;
  int _revision = 0;
  String? _lastHint;

  @override
  Stream<CanonicalDriverDeliverySignal> get signals => _events.stream;

  bool get _current {
    try {
      final user = _session.user;
      return !_stopped &&
          identical(_sessionSource.value, _session) &&
          _session.status == SessionStatus.authenticated &&
          user?.role == RideRole.driver &&
          user?.isBlocked == false &&
          user?.driverApprovalStatus == DriverApprovalStatus.approved &&
          user?.id.toLowerCase() == _owner.driverId?.toLowerCase() &&
          _owner.isUsable &&
          port.currentOwner.isUsable &&
          _owner.sameOwner(port.currentOwner) &&
          _sdkSession != null &&
          identical(port.sessionIdentity, _sdkSession);
    } on Object {
      return false;
    }
  }

  void _start() {
    if (!enabled || !_current) {
      dispose();
      return;
    }
    _listening = true;
    _sessionSource.addListener(_onSession);
    _invalidations.addListener(dispose);
    unawaited(_poll());
  }

  void _onSession() {
    if (!_current) dispose();
  }

  void _disconnect() {
    if (_stopped) return;
    _expiryTimer?.cancel();
    _connected = false;
    _lastHint = null;
    _events.add(CanonicalDriverConnectionHint(_revision++, connected: false));
  }

  Future<void> _poll() async {
    if (!_current) {
      dispose();
      return;
    }
    var timedOut = false;
    _deadlineTimer = Timer(readDeadline, () {
      timedOut = true;
      _disconnect();
    });
    try {
      final eligibility = await DriverEligibilityRepository(port).validate();
      if (!_current) {
        dispose();
        return;
      }
      if (timedOut) return;
      if (eligibility is! DriverEligible ||
          !_owner.sameOwner(eligibility.owner)) {
        if (eligibility is DriverIneligible &&
            eligibility.failure ==
                DriverEligibilityFailure.transportUnavailable) {
          _disconnect();
        } else {
          dispose();
        }
        return;
      }
      final rows = await port.readOfferedRows(_clock().toUtc());
      if (!_current) {
        dispose();
        return;
      }
      if (timedOut) return;
      _observe(rows);
    } on Object {
      if (!_current) {
        dispose();
      } else {
        _disconnect();
      }
    } finally {
      _deadlineTimer?.cancel();
      // Do not overlap HTTP reads, even after the publication deadline. A hung
      // SDK request remains disconnected until it settles or owner disposal.
      if (!_stopped) _pollTimer = Timer(pollInterval, () => unawaited(_poll()));
    }
  }

  void _observe(List<Map<String, Object?>> rows) {
    if (rows.length > CanonicalDriverOfferDiscoveryPort.rowLimit) {
      throw const FormatException('Unbounded discovery response');
    }
    if (rows.isEmpty) {
      // Accepted offers disappear from this SELECT. Healthy transport must not
      // disable explicit UNKNOWN recovery or hide an already verified Trip.
      // B08 refreshes through B07; this signal asserts no offer or assignment.
      final refresh = !_connected || _lastHint != null;
      _expiryTimer?.cancel();
      _lastHint = null;
      _connected = true;
      // Duplicate connectivity must not continually supersede a slow B07 read.
      if (refresh) {
        _events
            .add(CanonicalDriverConnectionHint(_revision++, connected: true));
      }
      return;
    }
    final candidates = <_OfferObservation>[];
    final ids = <String>{};
    for (final row in rows) {
      final observation = _OfferObservation.parse(row, _owner.driverId!);
      if (!ids.add(observation.id)) {
        throw const FormatException('Duplicate discovery identity');
      }
      final previous = _seen[observation.id];
      if (previous != null &&
          (observation.version < previous.version ||
              !observation.sameIdentity(previous))) {
        throw const FormatException('Regressed discovery observation');
      }
      if (previous == null && _seen.length >= maxRememberedOffers) {
        dispose(); // Bounded lifetime; never evict rollback protection.
        return;
      }
      _seen[observation.id] = observation;
      if (observation.status != 'offered' ||
          !_clock().toUtc().isBefore(observation.expiresAt)) {
        _terminal.add(observation.id);
        continue;
      }
      if (_terminal.contains(observation.id) ||
          observation.offeredAt.isAfter(_clock().toUtc())) {
        throw const FormatException('Retired or future offer');
      }
      candidates.add(observation);
    }
    // Backend reservation is single-owner. Multiple eligible offers are an
    // ambiguous contract violation, never an arbitrary choice for a command.
    if (candidates.length != 1) {
      _disconnect();
      return;
    }
    final offer = candidates.single;
    final fingerprint = '${offer.id}:${offer.version}';
    _expiryTimer?.cancel();
    _expiryTimer = Timer(offer.expiresAt.difference(_clock().toUtc()), () {
      _terminal.add(offer.id);
      if (!_current) {
        dispose();
      } else {
        _disconnect();
      }
    });
    if (!_connected) {
      _connected = true;
      _events.add(CanonicalDriverConnectionHint(_revision++, connected: true));
    }
    if (!_current) {
      dispose();
      return;
    }
    if (_lastHint != fingerprint) {
      _lastHint = fingerprint;
      _events.add(CanonicalDriverOfferHint(_revision++, offer.id));
    }
  }

  void dispose() {
    if (_stopped) return;
    _stopped = true;
    _connected = false;
    _lastHint = null;
    _events.add(CanonicalDriverConnectionHint(_revision++, connected: false));
    _pollTimer?.cancel();
    _deadlineTimer?.cancel();
    _expiryTimer?.cancel();
    if (_listening) {
      _sessionSource.removeListener(_onSession);
      _invalidations.removeListener(dispose);
    }
    _seen.clear();
    _terminal.clear();
    unawaited(_events.close());
  }
}

final class _OfferObservation {
  _OfferObservation(
    this.id,
    this.identity,
    this.status,
    this.version,
    this.offeredAt,
    this.expiresAt,
  );
  final String id, identity, status;
  final int version;
  final DateTime offeredAt, expiresAt;

  bool sameIdentity(_OfferObservation other) => identity == other.identity;

  static _OfferObservation parse(Map<String, Object?> row, String driver) {
    String id(String key) {
      final value = row[key];
      if (value is! String || !isCanonicalTripId(value)) {
        throw const FormatException('Invalid discovery identity');
      }
      return value.toLowerCase();
    }

    DateTime timestamp(String key) {
      final value = row[key];
      // Reject timezone-ambiguous timestamps; database timestamptz has an offset.
      if (value is! String ||
          !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
        throw const FormatException('Invalid discovery timestamp');
      }
      final parsed = DateTime.tryParse(value);
      if (parsed == null) throw const FormatException('Invalid timestamp');
      return parsed.toUtc();
    }

    final offerId = id('id');
    final owner = id('driver_id');
    final identity = [
      owner,
      id('booking_request_id'),
      id('fare_quote_id'),
      id('vehicle_id'),
    ];
    final version = row['version'];
    final status = row['status'];
    final offered = timestamp('offered_at');
    final expires = timestamp('expires_at');
    if (owner != driver.toLowerCase() ||
        version is! int ||
        version < 1 ||
        version > 2147483647 ||
        !{
          'offered',
          'accepted',
          'declined',
          'expired',
          'cancelled',
        }.contains(status) ||
        expires.difference(offered) != const Duration(seconds: 15)) {
      throw const FormatException('Invalid discovery row');
    }
    return _OfferObservation(
      offerId,
      '${identity.join(':')}:${offered.toIso8601String()}:${expires.toIso8601String()}',
      status as String,
      version,
      offered,
      expires,
    );
  }
}
