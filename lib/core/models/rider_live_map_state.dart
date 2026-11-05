import 'package:flutter/foundation.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/rider_assigned_trip.dart';
import 'package:ridex/core/models/rider_trip_tracking_event.dart';

part '../services/rider_live_map_projection.dart';

enum RiderLiveMapAuthorizationStatus { unavailable, authorized }

enum RiderLiveMapLocationStatus { unknown, fresh, stale, gpsUnavailable }

enum RiderLiveMapGpsStatus { unknown, available, unavailable }

enum RiderLiveMapConnectionStatus { online, offline }

enum RiderLiveMapRouteStatus { unavailable }

/// Revocable presentation view of live Rider map information.
///
/// The only public construction path is [RiderLiveMapState.unavailable]. The
/// authorized constructor is library-private and is reachable only from this
/// library's projection part. A previously returned authorized view is backed
/// by a revocable lease: all getters stop exposing its captured point as soon
/// as its owning projection invalidates that lease. A caller that already
/// copied a returned [LocationPoint] cannot have that independent copy erased.
/// This state contains no Trip/Rider/Driver identifiers, route reference, ETA,
/// or inferred route geometry.
final class RiderLiveMapState {
  const RiderLiveMapState.unavailable()
      : _lease = null,
        _locationStatus = RiderLiveMapLocationStatus.unknown,
        _gpsStatus = RiderLiveMapGpsStatus.unknown,
        _connectionStatus = RiderLiveMapConnectionStatus.online,
        _driverLocation = null,
        _locationSequence = null,
        _locationRecordedAt = null;

  const RiderLiveMapState._authorized({
    required _RiderLiveMapDisplayLease lease,
    required RiderLiveMapLocationStatus locationStatus,
    required RiderLiveMapGpsStatus gpsStatus,
    required RiderLiveMapConnectionStatus connectionStatus,
    required LocationPoint? driverLocation,
    required int? locationSequence,
    required DateTime? locationRecordedAt,
  })  : _lease = lease,
        _locationStatus = locationStatus,
        _gpsStatus = gpsStatus,
        _connectionStatus = connectionStatus,
        _driverLocation = driverLocation,
        _locationSequence = locationSequence,
        _locationRecordedAt = locationRecordedAt;

  final _RiderLiveMapDisplayLease? _lease;
  final RiderLiveMapLocationStatus _locationStatus;
  final RiderLiveMapGpsStatus _gpsStatus;
  final RiderLiveMapConnectionStatus _connectionStatus;
  final LocationPoint? _driverLocation;
  final int? _locationSequence;
  final DateTime? _locationRecordedAt;

  bool get _isAuthorized => _lease?.isActive == true;

  RiderLiveMapAuthorizationStatus get authorizationStatus => _isAuthorized
      ? RiderLiveMapAuthorizationStatus.authorized
      : RiderLiveMapAuthorizationStatus.unavailable;

  RiderLiveMapLocationStatus get locationStatus {
    if (!_isAuthorized) return RiderLiveMapLocationStatus.unknown;
    if (_locationStatus == RiderLiveMapLocationStatus.fresh &&
        !_lease!.isFresh(_locationRecordedAt)) {
      return RiderLiveMapLocationStatus.stale;
    }
    return _locationStatus;
  }

  RiderLiveMapGpsStatus get gpsStatus =>
      _isAuthorized ? _gpsStatus : RiderLiveMapGpsStatus.unknown;

  RiderLiveMapConnectionStatus get connectionStatus =>
      _isAuthorized ? _connectionStatus : RiderLiveMapConnectionStatus.online;

  LocationPoint? get driverLocation => _isAuthorized ? _driverLocation : null;

  int? get locationSequence => _isAuthorized ? _locationSequence : null;

  DateTime? get locationRecordedAt =>
      _isAuthorized ? _locationRecordedAt : null;

  RiderLiveMapRouteStatus get routeStatus =>
      RiderLiveMapRouteStatus.unavailable;

  bool get hasLiveLocation =>
      authorizationStatus == RiderLiveMapAuthorizationStatus.authorized &&
      locationStatus == RiderLiveMapLocationStatus.fresh &&
      gpsStatus == RiderLiveMapGpsStatus.available &&
      connectionStatus == RiderLiveMapConnectionStatus.online &&
      driverLocation != null;
}

final class _RiderLiveMapDisplayLease {
  _RiderLiveMapDisplayLease({
    required bool Function() isAuthorized,
    required DateTime Function() clock,
    required Duration freshnessWindow,
  })  : _isAuthorized = isAuthorized,
        _clock = clock,
        _freshnessWindow = freshnessWindow;

  final bool Function() _isAuthorized;
  final DateTime Function() _clock;
  final Duration _freshnessWindow;
  bool _isActive = true;

  bool get isActive {
    if (!_isActive) return false;
    try {
      if (!_isAuthorized()) invalidate();
    } on Object {
      invalidate();
    }
    return _isActive;
  }

  bool isFresh(DateTime? recordedAt) {
    if (!isActive || recordedAt == null) return false;
    try {
      final age = _clock().toUtc().difference(recordedAt.toUtc());
      return age >= Duration.zero && age <= _freshnessWindow;
    } on Object {
      return false;
    }
  }

  void invalidate() => _isActive = false;
}
