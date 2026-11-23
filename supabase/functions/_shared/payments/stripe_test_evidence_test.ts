import { readStripeTestEvidence } from "./stripe_test_evidence.ts";
import type { CanonicalEvidenceContext } from "./provider_evidence.ts";
const t = "11111111-1111-4111-8111-111111111111",
  p = "22222222-2222-4222-8222-222222222222",
  a = "33333333-3333-4333-8333-333333333333";
const context: CanonicalEvidenceContext = {
  provider: "stripe",
  account: "acct_Test",
  tripId: t,
  paymentId: p,
  attemptId: a,
  attemptKey: "key",
  reservationTripId: t,
  reservationPaymentId: p,
  reservationAttemptId: a,
  reservationKey: "key",
  reservationState: "prepared",
  providerReference: "pi_Test",
  amountFils: 1600,
  currency: "JOD",
  operation: "authorize",
};
const intent = () => ({
  object: "payment_intent",
  id: "pi_Test",
  livemode: false,
  amount: 160,
  currency: "jod",
  capture_method: "manual",
  status: "requires_capture",
  amount_capturable: 160,
  amount_received: 0,
  metadata: { ridex_trip_id: t, ridex_payment_id: p, ridex_attempt_id: a },
});
function assert(x: unknown): asserts x {
  if (!x) throw new Error("assertion failed");
}
function fake(i: object, account: object = { object: "account", id: "acct_Test" }) {
  const calls: string[] = [];
  const send: typeof fetch = (input, init) => {
    const url = String(input);
    calls.push(url);
    assert(init?.method === "GET" && init.redirect === "error");
    return Promise.resolve(Response.json(url.endsWith("/account") ? account : i));
  };
  return { send, calls };
}
Deno.test("exact original authorization and capture are observed without authority", async () => {
  for (
    const [c, i] of [[context, intent()], [{ ...context, operation: "capture" as const }, {
      ...intent(),
      status: "succeeded",
      amount_received: 160,
      amount_capturable: 0,
    }]] as const
  ) {
    const f = fake(i);
    const r = await readStripeTestEvidence(c, () => "sk_test_example", f.send);
    assert(
      r.disposition === "OBSERVED" && r.authoritative === false && f.calls.length === 2 &&
        f.calls[1].endsWith("/payment_intents/pi_Test"),
    );
  }
});
Deno.test("wrong account or environment and object fail closed", async () => {
  for (
    const [i, account] of [
      [intent(), { object: "account", id: "acct_Other" }],
      [{ ...intent(), livemode: true }, undefined],
      [{ ...intent(), id: "pi_Other" }, undefined],
      [{ ...intent(), object: "charge" }, undefined],
    ] as const
  ) {
    const f = fake(i, account);
    assert(
      (await readStripeTestEvidence(context, () => "sk_test_example", f.send)).disposition ===
        "UNRESOLVED",
    );
  }
});
Deno.test("amount currency status and identity mismatches fail closed", async () => {
  for (
    const patch of [
      { amount: 159 },
      { currency: "usd" },
      { amount_capturable: 159 },
      { status: "processing" },
      { metadata: {} },
      { metadata: { ridex_trip_id: t, ridex_payment_id: p, ridex_attempt_id: t } },
    ]
  ) {
    const f = fake({ ...intent(), ...patch });
    assert(
      (await readStripeTestEvidence(context, () => "sk_test_example", f.send)).disposition ===
        "UNRESOLVED",
    );
  }
});
Deno.test("invalid secret and unknown context never call provider", async () => {
  const f = fake(intent());
  for (
    const [c, key] of [[context, "sk_live_example"], [
      { ...context, reservationState: "unknown" },
      "sk_test_example",
    ], [{ ...context, providerReference: "pi_Test/path" }, "sk_test_example"]] as const
  ) assert((await readStripeTestEvidence(c, () => key, f.send)).disposition === "UNRESOLVED");
  assert(f.calls.length === 0);
});
