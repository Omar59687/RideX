enum RouteFailure {
  unavailable,
  timedOut,
  unauthorized,
  invalidResponse,
  notFound,
  unsupportedStops,
}

class RouteException implements Exception {
  const RouteException(this.failure);

  final RouteFailure failure;
}
