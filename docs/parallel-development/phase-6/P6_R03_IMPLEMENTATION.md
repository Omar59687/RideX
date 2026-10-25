# P6-R03 read-only Cash recovery implementation

Date: 2026-10-25. Branch `feature/p6-r03-cash-recovery-integration`, stacked
on the exact open PR #54 head `9ba703a673999bf0fbdf5222144fdd67f7f70edd`.
This record describes branch-local work; PR #54 is still the dependency and the
production Driver provider remains disabled by its intentionally empty approved
backend registry.

## Implemented

- `FileDriverCompletionCommandStore.inspectDriver` discovers all commands for
  one captured backend namespace and Driver. It validates the bounded journal
  frame/ownership and does not create directories or locks, append or flush
  bytes, repair corruption, delete commands or retire entries. An existing
  writer lock blocks discovery without being removed; a racing partial append
  fails closed. Existing per-Trip inspect/stage behavior is unchanged.
- `DriverCashRecoveryController` uses the existing R01 source, B1-B
  `AuthService.driverBinding`, R02 verified Supabase client/composition and same
  durable store factory. Provider creation starts one read-only reconciliation;
  app resume and the panel's explicit action join a single in-flight read. Each
  pass handles at most 10 journal commands, rotating across retained entries.
  Eligibility is revalidated around canonical and receipt reads. A-B-A/session,
  owner and generation checks prevent stale publication.
- Canonical reconciliation now requests `payment_method`, verifies Driver/Trip
  identity, Cash method and positive version, and rejects a canonical version
  older than the exact original command. Original Trip ID, version and
  idempotency key remain unchanged. Stronger observed completion state cannot
  be downgraded by a later weaker/error result in the controller lifetime.
- The existing `user_trip_receipt_summary(target_trip_id)` RPC is used through
  the same authenticated SDK client after canonical `completed` evidence only.
  The reader verifies receipt ID, linked Trip ID and receipt number. Its `P0002`
  absence result is reported as receipt-unverified, never payment failure. No
  financial table is selected and no receipt is fabricated.
- The optional canonical Cash panel distinguishes no pending recovery, checking,
  completed with/without verified receipt, not visible, unknown, revoked,
  additional pending records, journal unavailable/corrupt and network/read
  failure. The mock Driver screen remains unchanged and the canonical panel is
  not mounted in the live app.

## Verification and limits

- Focused tests: **185 PASS / 0 FAIL** across
  `driver_readonly_recovery_test.dart`, `canonical_trip_reconciliation_test.dart`
  and `driver_cash_production_integration_test.dart`. This includes restart
  discovery, evidence preservation/no write, missing receipt, original key
  retention, stale version rejection and absence of completion RPC dispatch.
- Flutter Analyze: **No issues found** after the final changed-code checks.
- These are local SDK/HTTP fixture and native temporary-directory results. No
  hosted Supabase, deployed RPC, production registry, device/process-kill,
  financial operation or release acceptance was verified.
- Startup behavior runs when the session-scoped canonical Cash provider is
  created. Because the production registry is empty and the canonical panel is
  not mounted, this branch does not activate recovery in the live application.
- Journal entries remain indefinitely under this work. An owner-approved
  retention, export/backup and operator-resolution/retirement policy is still
  absent; no record is deleted or replayed automatically. A missing journal is
  not proof that an earlier command never existed (app-data loss/rollback remain
  possible). Host flush and local reads do not establish power-loss durability.

## Status and dependency

**R03 PARTIAL.** Local read-only composition and UI seam are implemented. R03
production activation and Phase 6 acceptance remain blocked by PR #54 merge,
explicit approval of the exact configured endpoint-to-stable-namespace mapping
(`https://ykasivejjchupswqyxpm.supabase.co` is present in the existing setup),
canonical screen mounting, hosted read/role verification, and an owner-approved
journal/operator policy. No namespace was invented. Phase 6 remains NOT APPROVED.

Next: merge #54, then rebase/retarget this branch with a clean diff. Once owner
approves the registry and policy, compose a canonical Driver Trip screen to host
the existing bounded panel. Hosted read/restart acceptance belongs to R07.
