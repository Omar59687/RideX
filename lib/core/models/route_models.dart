import 'package:equatable/equatable.dart';
import 'package:ridex/core/errors/route_exception.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/location_point.dart';

class RouteRequest extends Equatable {
  RouteRequest({
    required this.origin,
    required this.destination,
    List<LocationPoint> intermediatePoints = const [],
  }) : intermediatePoints = List.unmodifiable(intermediatePoints);

  final LocationPoint origin;
  final LocationPoint destination;
  final List<LocationPoint> intermediatePoints;

  static RouteRequest? fromDraft(BookingDraft draft) {
    if (!draft.isRoutingReady) return null;
    return RouteRequest(
      origin: draft.pickup!.point,
      destination: draft.destination!.point,
      intermediatePoints: [for (final stop in draft.stops) stop.point],
    );
  }

  bool get hasDistinctEndpoints => origin != destination;

  @override
  List<Object?> get props => [origin, destination, intermediatePoints];
}

class RouteResult extends Equatable {
  RouteResult({
    required this.request,
    required List<LocationPoint> geometry,
    required this.distanceMeters,
    required this.durationSeconds,
  }) : geometry = List.unmodifiable(geometry) {
    if (geometry.length < 2 || distanceMeters <= 0 || durationSeconds <= 0) {
      throw ArgumentError('Route result is invalid.');
    }
  }

  final RouteRequest request;
  final List<LocationPoint> geometry;
  final int distanceMeters;
  final int durationSeconds;

  LocationPoint get origin => request.origin;
  LocationPoint get destination => request.destination;

  @override
  List<Object?> get props => [
        request,
        geometry,
        distanceMeters,
        durationSeconds,
      ];
}

enum RouteStatus { idle, loading, ready, failure }

class RouteState extends Equatable {
  const RouteState({
    this.status = RouteStatus.idle,
    this.request,
    this.result,
    this.failure,
  });

  const RouteState.loading(RouteRequest request, {RouteResult? previousResult})
      : this(
          status: RouteStatus.loading,
          request: request,
          result: previousResult,
        );

  RouteState.ready(RouteResult result)
      : this(
          status: RouteStatus.ready,
          request: result.request,
          result: result,
        );

  const RouteState.failure(
    RouteRequest request,
    RouteFailure failure, {
    RouteResult? previousResult,
  }) : this(
          status: RouteStatus.failure,
          request: request,
          result: previousResult,
          failure: failure,
        );

  final RouteStatus status;
  final RouteRequest? request;
  final RouteResult? result;
  final RouteFailure? failure;

  RouteResult? resultFor(BookingDraft draft) {
    final current = RouteRequest.fromDraft(draft);
    return result?.request == current ? result : null;
  }

  bool isReadyFor(BookingDraft draft) {
    return status == RouteStatus.ready && resultFor(draft) != null;
  }

  @override
  List<Object?> get props => [status, request, result, failure];
}
