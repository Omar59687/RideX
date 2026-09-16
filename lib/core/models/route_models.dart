import 'package:equatable/equatable.dart';
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
    this.message,
  });

  const RouteState.loading(RouteRequest request)
      : this(status: RouteStatus.loading, request: request);

  RouteState.ready(RouteResult result)
      : this(
          status: RouteStatus.ready,
          request: result.request,
          result: result,
        );

  const RouteState.failure(RouteRequest request, String message)
      : this(
          status: RouteStatus.failure,
          request: request,
          message: message,
        );

  final RouteStatus status;
  final RouteRequest? request;
  final RouteResult? result;
  final String? message;

  bool isReadyFor(BookingDraft draft) {
    final current = RouteRequest.fromDraft(draft);
    return status == RouteStatus.ready &&
        result != null &&
        result!.request == current;
  }

  @override
  List<Object?> get props => [status, request, result, message];
}
