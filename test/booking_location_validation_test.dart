import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/booking_draft.dart';

import 'helpers/fake_places.dart';

void main() {
  test('missing pickup and destination are rejected', () {
    const draft = BookingDraft();
    expect(draft.locationValidation, BookingLocationValidation.missingPickup);

    final pickupOnly = draft.copyWith(
      pickup: testLocation(latitude: 31.95, longitude: 35.91),
    );
    expect(
      pickupOnly.locationValidation,
      BookingLocationValidation.missingDestination,
    );
  });

  test('exactly identical canonical points are rejected', () {
    final pickup = testLocation(latitude: 31.95, longitude: 35.91);
    final destination = testLocation(
      latitude: 31.95,
      longitude: 35.91,
      label: 'Different label',
    );
    final draft = BookingDraft(pickup: pickup, destination: destination);

    expect(draft.locationValidation, BookingLocationValidation.sameLocation);
    expect(draft.isRoutingReady, isFalse);
  });

  test('different valid canonical points are routing-ready', () {
    final draft = BookingDraft(
      pickup: testLocation(latitude: 31.95, longitude: 35.91),
      destination: testLocation(latitude: 31.96, longitude: 35.92),
    );

    expect(draft.locationValidation, BookingLocationValidation.valid);
    expect(draft.isRoutingReady, isTrue);
  });
}
