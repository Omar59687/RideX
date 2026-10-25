# P6-02 / P6-07 trusted Cash composition boundary

This task composes the existing B1-A verified singleton capability, canonical
Driver eligibility checks, completion adapter and read-only reconciliation.
It does not implement, activate, replace or edit the separate B1-B lifecycle owner.
No other developer checkout or untracked file was changed.

The completion composition requires an existing verified access capability and
the authority binding over that same backend. It borrows the shared SDK client;
it never initializes, authenticates, signs out or disposes it. The caller supplies
the existing coordinator and durable journal; no new key, version, epoch or Trip
is generated. Only the original newly staged command may dispatch.

Before dispatch, canonical Driver role, non-blocked status and approval are read
through the existing binding. A canonical Trip read must match Driver/Trip identity,
the exact expected version, inProgress status and Cash method. Capability, SDK
session object and lifecycle ownership are checked around every asynchronous
boundary. The only mutation is the reviewed `driver_transition_trip` RPC, with
the original Trip ID/version/idempotency key. Canonical Trip and Driver-safe receipt
reads follow; no Driver payment-table read, client settlement or invented receipt.
Receipt P0002 proves no visible receipt, not payment failure. Revocation suppresses
success even if it races an absent-receipt response after canonical completion.

Read-only recovery uses the same verified client and canonical eligibility, then
delegates to the existing reconciliation classifier. It never dispatches, replays,
changes a command, clears a journal or creates financial authority.

Original validation: 18 composition tests and the combined four-file authority/
coordinator/adapter suite (202 tests) passed on `22d98c5`. Recovery on `fc1d28b`
adds eight tests using PR #45's actual AuthService-owned epoch and binding;
all 26 composition tests pass. Tests use real journal files, existing
coordinator, the installed Supabase SDK and loopback HTTP fixtures. They cover
single-flight, exact command preservation, preflight rejection, role/approval/
session/epoch revocation, SDK A→B→A, canonical versions, receipt absence/mismatch,
read-only recovery and no blind retry. These are not live settlement evidence.

## Remaining owner integration

Main at `fc1d28b` includes PR #45's B1-B AuthService-owned monotonic, synchronously
revoked lifecycle authority. Its source and session/recovery tests are retained
unchanged. The recovered composition works with `AuthService.driverBinding`;
it does not create a second epoch/session owner. Tests cover revocation during
user/profile/Trip reads, completion/receipt responses and read-only recovery.

B1-C still needs explicitly approved endpoint-to-namespace mappings and the
canonical active-Trip source/provider/consumer composition before Driver UI
activation. No mapping or active Trip is fabricated. Existing MockTripsRepository
UI stays isolated. No other developer branch or checkout was changed.

Runtime activation, approved backend registry, independently reviewed composition,
and separately authorized hosted Driver/Trip/Cash/receipt acceptance remain open.
No real financial RPC, hosted payment operation, migration or deployment occurred.
P6-07 and full Phase 6 are therefore not declared complete by this slice.
