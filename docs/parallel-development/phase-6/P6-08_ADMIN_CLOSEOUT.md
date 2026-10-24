# P6-08 guarded visibility closeout

Implemented 2026-10-24 from main `22d98c5` in an isolated task worktree.

The existing `/admin` route and guard are unchanged. Its screen now hosts the
existing sanitized Cash/Card widgets through a feature-local read boundary.
No fixture reader is installed in production. Until canonical reader composition
lands, an absent reader explicitly renders unavailable rather than fake or empty
payment data.

The screen and provider both require an authenticated, non-blocked Admin with a
nonblank identity. Loading, empty, unavailable, sanitized error/retry and refresh
are distinct. A changed session or reader invalidates the read; stale summaries
are hidden immediately and late completions cannot publish across role/account
changes or disposal. Backend error text is neither rendered nor logged.

Validation: the Admin integration, mapper, display and existing route-guard
suite passes 52 tests. Flutter analysis is clean. The full non-live suite is
reserved for the final Phase 6 integration boundary as requested.

Remaining composition: supply an authenticated, RLS-protected canonical reader
with complete persisted identity/version fields; no inferred fields or fake
payment authority. This task does not claim Cash settlement, issued receipts,
Stripe execution, independent review, merge or final Phase 6 approval.
