import 'package:equatable/equatable.dart';
import 'package:ridex/core/models/location_point.dart';

enum LocationPermissionStatus {
  notRequested,
  granted,
  denied,
  permanentlyDenied,
}

enum CurrentLocationStatus {
  initial,
  checking,
  requestingPermission,
  loading,
  available,
  serviceDisabled,
  unavailable,
}

enum LocationFailure {
  permissionDenied,
  permissionPermanentlyDenied,
  serviceDisabled,
  timeout,
  unavailable,
}

class CurrentLocationState extends Equatable {
  const CurrentLocationState({
    required this.status,
    required this.permission,
    this.point,
    this.failure,
  });

  const CurrentLocationState.initial()
      : status = CurrentLocationStatus.initial,
        permission = LocationPermissionStatus.notRequested,
        point = null,
        failure = null;

  final CurrentLocationStatus status;
  final LocationPermissionStatus permission;
  final LocationPoint? point;
  final LocationFailure? failure;

  CurrentLocationState copyWith({
    CurrentLocationStatus? status,
    LocationPermissionStatus? permission,
    LocationPoint? point,
    LocationFailure? failure,
    bool clearPoint = false,
    bool clearFailure = false,
  }) {
    return CurrentLocationState(
      status: status ?? this.status,
      permission: permission ?? this.permission,
      point: clearPoint ? null : point ?? this.point,
      failure: clearFailure ? null : failure ?? this.failure,
    );
  }

  @override
  List<Object?> get props => [status, permission, point, failure];
}
