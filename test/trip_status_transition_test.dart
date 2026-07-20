import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/mock_trip.dart';

void main() {
  test('trip status transition rules stay valid', () {
    expect(canTransition(TripStatus.searching, TripStatus.accepted), isTrue);
    expect(
        canTransition(TripStatus.accepted, TripStatus.driverArriving), isTrue);
    expect(
        canTransition(TripStatus.driverArrived, TripStatus.inProgress), isTrue);
    expect(canTransition(TripStatus.inProgress, TripStatus.completed), isTrue);
    expect(canTransition(TripStatus.completed, TripStatus.searching), isFalse);
    expect(canTransition(TripStatus.searching, TripStatus.completed), isFalse);
  });
}
