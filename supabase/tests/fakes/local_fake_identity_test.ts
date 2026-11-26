import { verifyLocalFakeIdentity } from "./local_fake_identity.ts";
function assert(x: unknown): asserts x {
  if (!x) throw new Error("assertion failed");
}
Deno.test("fake identity is explicit and local", () => {
  const value = verifyLocalFakeIdentity(true, "local_fake_demo");
  assert(
    value.provider === "local_fake" && value.environment === "local_test" &&
      Object.isFrozen(value),
  );
});
Deno.test("disabled or invalid fake identity fails closed", () => {
  for (
    const [enabled, account] of [
      [false, "local_fake_demo"],
      [true, "acct_real"],
      [true, ""],
      [true, "local_fake_UPPER"],
    ] as const
  ) {
    let rejected = false;
    try {
      verifyLocalFakeIdentity(enabled, account);
    } catch {
      rejected = true;
    }
    assert(rejected);
  }
});

Deno.test("existing observer treats synthetic evidence as non-authoritative", async () => {
  const { observeProviderEvidence } = await import(
    "../../functions/_shared/payments/provider_evidence.ts"
  );
  const { LocalFakeEvidenceReader } = await import("./local_fake_identity.ts");
  const t = "11111111-1111-4111-8111-111111111111",
    p = "22222222-2222-4222-8222-222222222222",
    a = "33333333-3333-4333-8333-333333333333";
  const identity = verifyLocalFakeIdentity(true, "local_fake_demo");
  const context = {
    provider: identity.provider,
    account: identity.account,
    tripId: t,
    paymentId: p,
    attemptId: a,
    attemptKey: "fake-key",
    reservationTripId: t,
    reservationPaymentId: p,
    reservationAttemptId: a,
    reservationKey: "fake-key",
    reservationState: "prepared",
    providerReference: "local_fake_reference",
    amountFils: 1000,
    currency: "JOD",
    operation: "authorize" as const,
  };
  const reader = new LocalFakeEvidenceReader(identity, {
    reference: "local_fake_reference",
    amountFils: 1000,
    currency: "JOD",
    status: "requires_capture",
    metadata: { tripId: t, paymentId: p, attemptId: a },
  });
  const result = await observeProviderEvidence(context, reader);
  assert(result.disposition === "OBSERVED" && result.authoritative === false);
  const unknown = await observeProviderEvidence({
    ...context,
    providerReference: "local_fake_missing",
  }, reader);
  assert(unknown.disposition === "UNRESOLVED");
});
