# Developer 2 — Rider Application (Phase 6)

Role: rider Flutter, booking/payment interfaces, rider matching/tracking UI,
history/receipts, rider secondary features + tests. Status authority: `SPRINT_TRACKER.md`.

## P6-05 — Rider payment selection + fare-lock handoff | Status: TODO

- Goal: cash selection (+ card placeholder) on the booking flow, handing the locked
  fare forward; mock-backed against the P6-01 draft. Full card selection follows P6-03.
- Prerequisites: P6-01 draft interface (Day 1 handoff); existing
  `FareRepository.paymentMethod` + `/rider/fare` flow.
- Implementation: selection UI + canonical pending states; never declares success
  client-side; callbacks advisory; deterministic demo path stays isolated.
- Owned: `lib/features/booking/**` touchpoints, rider fare widgets,
  `test/*rider_payment*_test.dart`, `test/fare_estimate_screen_test.dart` additions.
- Shared: `app_router.dart` (no production change; reuse `/rider/fare`),
  `repositories_providers.dart` (test overrides only).
- Acceptance: selection persists as method choice; locked-fare review shown; no
  secret handling; no mock matching presented as real.
- Tests: widget (selection, loading, failure) + fake-contract tests. Complexity: M.
- Integration: builds on P6-01 fake; real wiring waits for P6-09.

## P6-06 — Rider payment states + receipt presentation | Status: TODO

- Goal: display canonical loading/pending/authorized/succeeded/failed/cancelled
  + receipt/history presentation from persistent records (presentation only).
- Prerequisites: P6-01, P6-03; P6-05.
- Implementation: `lib/features/history/**`, `lib/features/trips/**` presentation;
  receipts render trusted fields only (no reconstructed fare math, no paid-before-completion).
- Owned: history/receipt widgets + tests.
- Shared: `MockTripsRepository` — do not rewrite (Phase 8 owns); read-only.
- Acceptance: cancelled/unpaid shows no paid receipt; failed capture keeps completed
  trip visible with failure state (design per contract).
- Tests: widget + state-mapping tests. Complexity: M.

## Carry-over verification (parallel, evidence only)

- V5-01 hosted Rider-RLS recovery/confirm compatibility | Status: TODO.
- V5-02 Android confirm + repeat-booking B1/B2 end-to-end | Status: TODO.
- V5-04 lost-response/restart recovery (with Dev 3) | Status: TODO.
- Origin: Phase 5 exit checklist; exit implication: gate P8 execution claims, not P6 UI.
- Deliverable: dated evidence notes + canonical row/state excerpts (redacted), no reimplementation.