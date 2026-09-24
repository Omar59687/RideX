enum DriverLocationFailure {
  gpsUnavailable,
  networkFailure,
  unauthorized,
  ineligible,
  invalidData,
  staleSequence,
}

class DriverLocationException implements Exception {
  const DriverLocationException(this.failure);

  final DriverLocationFailure failure;
}
