import { type CanonicalEvidenceContext, observeProviderEvidence } from "./provider_evidence.ts";
const t = "11111111-1111-4111-8111-111111111111",
  p = "22222222-2222-4222-8222-222222222222",
  a = "33333333-3333-4333-8333-333333333333";
const context: CanonicalEvidenceContext = {
  provider: "test-provider",
  account: "acct_local",
  tripId: t,
  paymentId: p,
  attemptId: a,
  attemptKey: "op-key-01",
  reservationTripId: t,
  reservationPaymentId: p,
  reservationAttemptId: a,
  reservationKey: "op-key-01",
  reservationState: "prepared",
  providerReference: "local-reference",
  amountFils: 1600,
  currency: "JOD",
  operation: "authorize",
};
const evidence = () => ({
  provider: "test-provider",
  account: "acct_local",
  environment: "test",
  reference: "local-reference",
  amountFils: 1600,
  currency: "JOD",
  status: "requires_capture",
  metadata: { tripId: t, paymentId: p, attemptId: a },
});
function assert(v: unknown): asserts v {
  if (!v) throw new Error("assertion failed");
}
Deno.test("exact authorization and capture observations never become authority", async () => {
  const auth = await observeProviderEvidence(context, { read: () => Promise.resolve(evidence()) });
  assert(auth.disposition === "OBSERVED" && auth.authoritative === false);
  const capture = await observeProviderEvidence({ ...context, operation: "capture" }, {
    read: () => Promise.resolve({ ...evidence(), status: "succeeded" }),
  });
  assert(capture.disposition === "OBSERVED" && capture.authoritative === false);
});
Deno.test("unresolved reservation never calls provider", async () => {
  let calls = 0;
  for (
    const c of [{ reservationState: "unknown" }, { providerReference: null }, {
      reservationKey: "other",
    }, { reservationTripId: p }]
  ) {
    const result = await observeProviderEvidence({ ...context, ...c }, {
      read: () => {
        calls++;
        return Promise.resolve(evidence());
      },
    });
    assert(result.disposition === "UNRESOLVED");
  }
  assert(calls === 0);
});
Deno.test("foreign provider, account, live environment, reference, amount and links fail closed", async () => {
  for (
    const change of [
      { provider: "other" },
      { account: "other" },
      { environment: "live" },
      { reference: "wrong" },
      { amountFils: 1590 },
      { currency: "USD" },
      { status: "succeeded" },
      { metadata: { tripId: t, paymentId: p, attemptId: t } },
    ]
  ) {
    const result = await observeProviderEvidence(context, {
      read: () => Promise.resolve({ ...evidence(), ...change }),
    });
    assert(result.disposition === "UNRESOLVED");
  }
});
Deno.test("ambiguous or failed read never retries automatically", async () => {
  let calls = 0;
  const result = await observeProviderEvidence(context, {
    read: () => {
      calls++;
      return Promise.reject(new Error("unknown"));
    },
  });
  assert(result.disposition === "UNRESOLVED" && calls === 1);
});
