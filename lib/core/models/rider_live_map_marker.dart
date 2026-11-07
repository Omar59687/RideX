import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/rider_live_map_state.dart';

enum RiderLiveMapMarkerFreshness { live, lastKnown }

/// Provider-neutral marker projection for one renderer build.
///
/// The value is created only from a currently accessible [RiderLiveMapState].
/// Renderers should request it again for each build and avoid retaining its
/// coordinate after the revocable state changes.
final class RiderLiveMapMarkerData {
  const RiderLiveMapMarkerData._({
    required this.point,
    required this.freshness,
  });

  final LocationPoint point;
  final RiderLiveMapMarkerFreshness freshness;

  bool get isLive => freshness == RiderLiveMapMarkerFreshness.live;

  String get accessibleLabel => isLive
      ? 'Live Driver location marker'
      : 'Last known Driver location marker';

  /// Returns no marker unless current authorization and valid coordinates are
  /// available through the state's revocable access boundary.
  static RiderLiveMapMarkerData? project(RiderLiveMapState state) {
    if (state.authorizationStatus !=
        RiderLiveMapAuthorizationStatus.authorized) {
      return null;
    }

    final status = state.locationStatus;
    if (status != RiderLiveMapLocationStatus.fresh &&
        status != RiderLiveMapLocationStatus.stale) {
      return null;
    }
    final point = state.driverLocation;
    if (point == null ||
        !point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude < -90 ||
        point.latitude > 90 ||
        point.longitude < -180 ||
        point.longitude > 180) {
      return null;
    }

    final isLive = state.hasLiveLocation;
    if (state.authorizationStatus !=
            RiderLiveMapAuthorizationStatus.authorized ||
        state.driverLocation != point) {
      return null;
    }
    return RiderLiveMapMarkerData._(
      point: point,
      freshness: isLive
          ? RiderLiveMapMarkerFreshness.live
          : RiderLiveMapMarkerFreshness.lastKnown,
    );
  }
}
