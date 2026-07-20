abstract class RideMapService {
  bool get isConfigured;
}

class MockRideMapService implements RideMapService {
  @override
  bool get isConfigured => false;
}
