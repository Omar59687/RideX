# Rider Trip History And Details

## Scope

Phase 6A redesigns rider trip history and adds repository-backed trip details. Driver history remains functional without a visual redesign. Profile, notifications, settings, persistence, and new backend integrations remain out of scope.

## History

- Load trips through `TripsRepository`, with loading, retryable error, empty, and filtered-empty states.
- Offer All, Completed, and Cancelled filters.
- Present Urban Aurora route cards with status, pickup, destination, category, duration, and fare.
- Navigate selected rider trips to `/history/:tripId`.
- Preserve the existing driver history presentation and navigation.

## Details

- Resolve direct links by trip ID through `TripsRepository` and show a recoverable not-found state.
- Completed trips show the native map, route timeline, driver and vehicle, deterministic fare breakdown, and an explicit demo payment label.
- Cancelled trips show route and cancellation information with zero charge, without implying a driver, payment, or cancellation fee existed.
- Both states offer "Book this route again," which seeds the existing booking provider and continues into the rider booking flow.

## Verification

Focused tests cover repository states, filters, navigation, completed and cancelled details, missing IDs, rebooking state, and driver history access. Run formatting, focused tests, and `flutter analyze` before committing.
