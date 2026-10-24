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

Validation: 18 new composition tests and the combined four-file authority/
coordinator/adapter suite (202 tests) pass. Tests use real journal files, existing
coordinator, the installed Supabase SDK and loopback HTTP fixtures. They cover
single-flight, exact command preservation, preflight rejection, role/approval/
session/epoch revocation, SDK A→B→A, canonical versions, receipt absence/mismatch,
read-only recovery and no blind retry. These are not live settlement evidence.

## Remaining owner integration

Main at `22d98c5` has B1-A but no merged B1-B lifecycle owner or production Driver
completion source/provider. No B1-B branch/worktree was registered in this Git
repository during inspection; any separate local work remains untouched. Do not
invent a replacement epoch or second session owner. B1-B must supply monotonic,
synchronously revoked auth/lifecycle authority and the canonical active-Trip source
before wiring the Driver screen. Existing MockTripsRepository UI stays isolated.

Runtime activation, approved backend registry, independently reviewed composition,
and separately authorized hosted Driver/Trip/Cash/receipt acceptance remain open.
No real financial RPC, hosted payment operation, migration or deployment occurred.
P6-07 and full Phase 6 are therefore not declared complete by this slice.
