# P6-R03 read-only Cash recovery implementation

Date: 2026-10-25. PR #55 branch `feature/p6-r03-cash-recovery-integration`
was originally based on PR #54 head `9ba703a`. PR #54 is now merged at main
`f9e680723b8e741963451f424d00926049e4f6a7`; current main was merged into this
branch without conflicts. During verification, another actor merged the original
PR #55 at `34801bc` before the local corrections were pushed. That identical-content
main was also merged here without conflicts. The correction therefore requires a
follow-up review PR; the original merge is not approval of this fix. The
intentionally empty approved backend registry still disables production activation.

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
  idempotency key remain unchanged. Strongest canonical Trip facts and verified
  receipt facts are retained separately per Trip, behind the current-authority
  gate. Later weak/error reads cannot erase those facts or transfer them to a
  different Trip. Read-only snapshots cannot mutate the retained facts.
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

## Independent review correction

The original global `_strongestState` rank could keep a verified receipt banner
for Trip A while Trip B remained unresolved, failed or outside the ten-command
page. That rank is removed. Latest reconciliation outcomes are now keyed by Trip
and are separate from the strongest canonical/receipt facts.

The aggregate reports journal/read/unknown failures ahead of success. Any command
not yet checked reports additional pending recovery; missing or non-completed
canonical evidence and receipt-unverified outcomes also prevent all-verified
status. A failure from a previously checked Trip remains visible while another
page is read, until that Trip is checked successfully. After all discovered
commands have results, the aggregate can report verified only if every result is
verified; simply having more than ten records does not prevent eventual progress.

Each pass still reads at most ten commands and advances its rotation. Previously
discovered command evidence is never silently dropped: disappearance reports
unknown, a changed original command tuple blocks reconciliation, and neither
case clears cached facts or writes/deletes journal data. Revocation hides all
account-owned facts and suppresses late responses; it never permits replay.

## Verification and limits

- Focused tests: **210 PASS / 0 FAIL / 0 SKIP** across
  `driver_readonly_recovery_test.dart`, `canonical_trip_reconciliation_test.dart`
  and `driver_cash_production_integration_test.dart`. This includes restart
  discovery, evidence preservation/no write, missing receipt, original key
  retention, stale version rejection and absence of completion RPC dispatch.
  The 25 added regressions cover mixed outcomes in both orders, 25 retained
  commands/ten-per-pass rotation, independent versions, verified receipts followed
  by weaker/unknown/failed/absent/corrupt reads, disappearance/changed commands,
  immutable cached facts, repeated single-flight reconciliation and revocation.
  Native journal byte comparisons and request assertions verify no write,
  dispatch, replay or retirement throughout the new recovery cases.
- Architecture boundary: **5 PASS**, making **215 focused PASS** across four
  files. The exact receipt infrastructure adapter was added to the SDK allowlist;
  UI/model restrictions remain unchanged.
- Flutter analyze: **PASS, no issues found**. Read-only formatting of all 14
  R03/architecture Dart paths: **0 changed**. Four previously unformatted R03
  adapter/journal/test paths were formatted without non-whitespace changes.
- Final full non-live suite: **1,554 PASS / 0 FAIL / 2 live Supabase skips**.
  The first full sweep found one missing SDK-infrastructure allowlist entry
  for the existing receipt adapter. It was corrected, then the full sweep was
  repeated only to verify that actual integration failure. No restriction was
  broadened beyond that exact infrastructure file.
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
production activation and Phase 6 acceptance still require
explicit approval of the exact configured endpoint-to-stable-namespace mapping
(`https://ykasivejjchupswqyxpm.supabase.co` is present in the existing setup),
canonical screen mounting, hosted read/role verification, and an owner-approved
journal/operator policy. No namespace was invented. Phase 6 remains NOT APPROVED.

Next: independent re-review of the follow-up correction to merged PR #55. Once
the owner approves the registry and policy, compose a canonical Driver Trip screen
to host the bounded panel. Hosted read/restart acceptance belongs to R07.
