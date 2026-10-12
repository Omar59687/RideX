# Developer 3 — Driver / Admin Application (Phase 6)

Role: driver Flutter, availability/matching UI, location/lifecycle, driver history,
admin interface, physical-device verification. Status authority: `SPRINT_TRACKER.md`.

## P6-08 — Admin sanitized payment visibility | Status: TODO

- Goal: read-only admin view of sanitized payment state (method/status/amount/
  currency/provider/brand/last4/refs); no secrets or raw payloads.
- Prerequisites: P6-01 draft (cash scope in Sprint 1; card metadata columns after
  P6-03). Exact admin surface TO VERIFY (no dedicated
  admin feature folder; likely settings/profile-adjacent) before editing.
- Implementation: new read-only widgets + tests; no guard/router/RLS change.
- Owned: new admin payment widgets + `test/*admin_payment*_test.dart`.
- Shared: router/guards/session providers — read-only; no production change.
- Acceptance: secrets never rendered/logged; unauthorized roles cannot view
  (guard behavior unchanged and tested).
- Tests: widget (sanitized fields, redaction) + guard regression. Complexity: S–M.

## P6-07 — Driver cash-completion hook | Status: TODO

- Goal: driver completion path triggers the existing trusted completion flow;
  Flutter never marks cash paid directly.
- Prerequisites: P6-01; P6-02 draft semantics (even though P6-02 lands Sprint 3+,
  build against the contract fake).
- Implementation: `lib/features/driver_home/**`, `driver_application/**`, trip
  completion presentation; single trusted call; idempotency-safe retries only.
- Owned: driver completion touchpoints + tests.
- Shared: trip/completion models — read-only; no lifecycle rewrite.
- Acceptance: cancel shows cancelled (no paid timestamp/receipt); completion shows
  paid only via canonical result. Execution claim blocked until V5-01/V5-04 evidence.
- Tests: widget + controller/fake tests. Complexity: M.

## Carry-over verification (parallel, evidence only)

- V4-01 two-device GPS Rider/Driver (task 4.38, owner-deferred) | Status: TODO.
- V4-02 blank native map diagnosis (logs, cert SHA-1, SDK config; redacted) | Status: TODO.
- V5-03 multi-stop physical flow | Status: TODO.
- V5-04 restart/recovery (with Dev 2) | Status: TODO.
- Origin: Phase 4 4.38/4.40 gates + Phase 5 exit checklist; gates P4/P5 approval
  and P8/P10 claims, not P6 contract/UI work.
- Deliverable: dated evidence notes (redacted), no reimplementation; open fix branch
  only if a defect is confirmed.