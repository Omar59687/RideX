# P6-08 guarded visibility closeout

Originally implemented at `acce1e6` from `22d98c5`. Recovered into one isolated
integration branch from main `fc1d28b` after #41/#43 closed without merge.

The existing `/admin` route and guard are unchanged. Its screen now hosts the
existing sanitized Cash/Card widgets through a feature-local read boundary.
No fixture reader is installed in production. PR #48 corrects the recovered
reader to borrow the existing application client and call restricted RPCs in
proposed migration 027; migration 019 denies direct payments SELECT. Migration
review and database-first rollout remain required; nothing is deployed here.
An absent configured client explicitly renders unavailable rather than fake or
empty payment data.

The screen and provider both require an authenticated, non-blocked Admin with a
nonblank identity. Loading, empty, unavailable, sanitized error/retry and refresh
are distinct. A changed session or reader invalidates the read; stale summaries
are hidden immediately and late completions cannot publish across role/account
changes or disposal. Backend error text is neither rendered nor logged.

The original Admin integration, mapper, display and route-guard component gate
passed 52 tests. Current combined results on `fc1d28b` are recorded in
`P6_FOUNDATION_INTEGRATION_ACCEPTANCE.md`; historical results are not merge evidence.

Canonical composition now supplies complete persisted identity/version fields;
no inferred fields or fake payment authority. Hosted Admin acceptance and
independent review remain open. This task does not claim Cash settlement,
issued receipts, Stripe execution, merge or final Phase 6 approval.
