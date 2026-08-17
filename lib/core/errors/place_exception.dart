enum PlaceFailure {
  unavailable,
  timedOut,
  unauthorized,
  invalidResponse,
  notFound,
}

class PlaceException implements Exception {
  const PlaceException(this.failure);

  final PlaceFailure failure;
}
