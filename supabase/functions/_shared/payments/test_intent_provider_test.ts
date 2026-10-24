import { test } from "node:test";
import assert from "node:assert/strict";
import { type CanonicalIntentContext, type IntentCommand, prepareTestIntent,
  StripeTestIntentProvider, TestIntentError } from "./test_intent_provider.ts";
import { FakeTestIntentProvider } from "./test_intent_fake.ts";

const paymentId = "aaaaaaaa-bbbb-4ccc-9ddd-eeeeeeeeeeee";
const context: CanonicalIntentContext = Object.freeze({ paymentId, paymentVersion: 2,
  tripId: "bbbbbbbb-bbbb-4ccc-9ddd-eeeeeeeeeeee",
  driverId: "cccccccc-bbbb-4ccc-9ddd-eeeeeeeeeeee", tripStatus: "accepted",
  method: "card", paymentStatus: "cardPaymentPending", amountFils: 13300,
  currency: "JOD", idempotencyKey: "original-operation-key" });
const command: IntentCommand = { paymentId, expectedPaymentVersion: 2,
  idempotencyKey: context.idempotencyKey };
const fixtureSecret = ["sk", "test", "fixture"].join("_");
function code(expected: string) {
  return (error: unknown) => error instanceof TestIntentError && error.code === expected;
}
function response(change: Record<string, unknown> = {}) {
  return Response.json({ object: "payment_intent", id: "pi_TestFixture", livemode: false,
    amount: 13300, currency: "jod", capture_method: "manual", confirmation_method: "manual",
    status: "requires_payment_method", payment_method: null, amount_received: 0,
    amount_capturable: 0, latest_charge: null, client_secret: "private-fixture", ...change });
}
function provider(transport: typeof fetch = async () => response(),
  secret: string | undefined = fixtureSecret, approved = true) {
  return new StripeTestIntentProvider({ readSecret: () => secret,
    jodTestModeApproved: approved, transport });
}

test("canonical context only; fake supports exact replay and no payment mutation", async () => {
  const fake = new FakeTestIntentProvider();
  const read = async () => context;
  assert.deepEqual(await prepareTestIntent(command, read, fake),
    await prepareTestIntent(command, read, fake));
  assert.deepEqual(fake.calls[0], context);
  assert.equal(context.paymentStatus, "cardPaymentPending");
  await assert.rejects(prepareTestIntent(command,
    async () => ({ ...context, amountFils: 14000 }), fake), code("provider_rejected"));
});
test("missing or rejected canonical authority never reaches the provider", async () => {
  const fake = new FakeTestIntentProvider();
  await assert.rejects(prepareTestIntent(command, async () => null, fake), code("forbidden"));
  await assert.rejects(prepareTestIntent(command, async () => { throw Error("private"); }, fake), code("forbidden"));
  assert.equal(fake.calls.length, 0);
});
test("stale version and changed original key fail before provider dispatch", async () => {
  const fake = new FakeTestIntentProvider();
  await assert.rejects(prepareTestIntent({ ...command, expectedPaymentVersion: 1 },
    async () => context, fake), code("stale_version"));
  await assert.rejects(prepareTestIntent({ ...command, idempotencyKey: "rotated-operation-key" },
    async () => context, fake), code("forbidden"));
  assert.equal(fake.calls.length, 0);
});
for (const change of [{ method: "cash" }, { tripStatus: "searching" },
  { tripStatus: "completed" }, { driverId: "" }, { currency: "USD" },
  { paymentStatus: "cardPaymentAuthorized" }, { amountFils: 13301 },
  { amountFils: -10 }, { paymentId: context.tripId }]) {
  test(`invalid canonical context rejected ${JSON.stringify(change)}`, async () => {
    const fake = new FakeTestIntentProvider();
    await assert.rejects(prepareTestIntent(command, async () => ({ ...context, ...change }), fake), code("forbidden"));
    assert.equal(fake.calls.length, 0);
  });
}
test("Stripe transport is test-only, unconfirmed, manual and exact amount/key", async () => {
  let calls = 0;
  const result = await prepareTestIntent(command, async () => context,
    provider(async (url, init) => {
      calls++;
      assert.equal(url, "https://api.stripe.com/v1/payment_intents");
      assert.equal(init?.method, "POST"); assert.equal(init?.redirect, "error");
      const headers = new Headers(init?.headers);
      assert.equal(headers.get("Idempotency-Key"), context.idempotencyKey);
      assert.equal(headers.get("Authorization"), `Bearer ${fixtureSecret}`);
      assert.deepEqual(Object.fromEntries(new URLSearchParams(String(init?.body))), {
        amount: "13300", currency: "jod", capture_method: "manual",
        confirmation_method: "manual", confirm: "false", "payment_method_types[]": "card" });
      return response();
    }));
  assert.equal(calls, 1);
  assert.deepEqual(result, { provider: "stripe", reference: "pi_TestFixture", requiresCanonicalVerification: true });
  assert(!JSON.stringify(result).includes("private-fixture"));
});
for (const secret of ["", ["sk", "live", "fixture"].join("_"), "untrusted"]) {
  test("missing/live/untrusted configuration never dispatches", async () => {
    let calls = 0;
    await assert.rejects(provider(async () => { calls++; return response(); }, secret).prepare(context), code("not_configured"));
    assert.equal(calls, 0);
  });
}
test("account approval is mandatory", async () => {
  await assert.rejects(provider(async () => { throw Error("must not dispatch"); }, fixtureSecret, false).prepare(context), code("not_configured"));
});
test("timeout has unknown outcome with no automatic retry or raw error", async () => {
  let calls = 0;
  await assert.rejects(provider(async () => { calls++; throw Error("private-provider-payload"); }).prepare(context), code("unknown_result"));
  assert.equal(calls, 1);
});
test("provider rejection is sanitized", async () => {
  await assert.rejects(provider(async () => new Response("private-payload", { status: 402 })).prepare(context), code("provider_rejected"));
});
for (const change of [{ livemode: true }, { amount: 1 }, { currency: "usd" },
  { capture_method: "automatic" }, { status: "requires_capture" }, { status: "succeeded" },
  { confirmation_method: "automatic" }, { amount_received: 13300 }, { amount_capturable: 13300 },
  { latest_charge: "ch_fixture" }, { payment_method: "pm_fixture" }, { id: "not-intent" }]) {
  test(`rejects unexpected provider outcome ${JSON.stringify(change)}`, async () => {
    await assert.rejects(provider(async () => response(change)).prepare(context), code("invalid_response"));
  });
}
test("invalid response JSON cannot leak provider data", async () => {
  await assert.rejects(provider(async () => new Response("private-json")).prepare(context), code("invalid_response"));
});
