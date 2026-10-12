# Phase 6 — Sprint Tracker (authoritative status)

This file is the ONLY status authority. Other docs reference it; do not duplicate
status elsewhere. Initial status for all rows: `TODO`. Never mark future work complete.

Owner rotation: Sprint 1 Dev 1 → Sprint 2 Dev 2 → Sprint 3 Dev 3 → Sprint 4 Dev 1…

## Sprint 1 (48h) — Integration Owner: Dev 1

| Task | Dev | Branch (suggested) | Depends | Status | PR | Gate / outcome |
|---|---|---|---|---|---|---|
| P6-01 cash domain contract | Dev 1 | `feature/p6-cash-contract` | none | TODO | — | focused tests + analyze; draft interface to Dev 2/3 Day 1 |
| P6-05 rider selection + handoff (mock) | Dev 2 | `feature/p6-rider-payment-ui` | P6-01 draft | TODO | — | widget + fake tests; no router change; no success claim |
| P6-08 admin sanitized visibility | Dev 3 | `feature/p6-admin-payment-visibility` | P6-01 draft (cash scope) | TODO | — | redaction + guard tests; TO VERIFY admin surface first |
| V4-02 blank-map diagnosis | Dev 3 | n/a (evidence) | device/logs | TODO | — | redacted evidence note |
| V5-01 hosted RLS checks | Dev 2 | n/a (evidence) | hosted access | TODO | — | redacted evidence note |

Conflict check Sprint 1: production writers disjoint (new contract files / booking UI /
new admin widgets). `repositories_providers.dart`/`app_router.dart`: no production edits.

## Sprint 2 (48h) — Integration Owner: Dev 2

| Task | Dev | Branch (suggested) | Depends | Status | PR | Gate / outcome |
|---|---|---|---|---|---|---|
| P6-03 card domain contract | Dev 1 | `feature/p6-card-contract` | P6-01 | TODO | — | adapter boundary review; no secrets |
| P6-06 rider states + receipts | Dev 2 | `feature/p6-rider-payment-states` | P6-01, P6-03, P6-05 | TODO | — | state/receipt widget tests; no history rewrite |
| P6-07 driver cash-completion hook | Dev 3 | `feature/p6-driver-cash-completion` | P6-01 (+P6-02 draft) | TODO | — | hook tests; execution claim waits on V-evidence |
| V4-01 two-device (4.38) | Dev 3 | n/a (evidence) | devices | TODO | — | dated evidence or remains open |
| V5-02 confirm + B1/B2 | Dev 2 | n/a (evidence) | hosted+device | TODO | — | dated evidence or remains open |

Conflict check Sprint 2: writers disjoint (new card files / history-trips UI /
driver UI). No shared production-file overlap. Full non-live suite at boundary.

## Later (high-level; re-plan from latest main when Phase 6 S1–S2 merge)

- Sprint 3 (Owner Dev 3): P6-02 cash backend wiring, P6-04 Stripe intent interface,
  V5-03/V5-04 evidence.
- Sprint 4 (Owner Dev 1): P6-09 compatibility harness, P6→P8 readiness review.
- Phase 6 exit: contracts + mock-backed UI + harness green; hosted/device tails
  still tracked above; no P4/P5 APPROVED claim.