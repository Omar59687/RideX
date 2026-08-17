import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/models/booking_draft.dart';

void main() {
  test('trip creation rejects an unresolved booking draft', () {
    expect(
      () => MockTripsRepository().createTrip(const BookingDraft()),
      throwsStateError,
    );
  });
}
