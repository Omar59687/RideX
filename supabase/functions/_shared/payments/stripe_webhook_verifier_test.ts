import {
  verifyStripeTestWebhookEnvelope,
  WebhookVerificationError,
} from "./stripe_webhook_verifier.ts";

const secret = "whsec_synthetic_local_only";
const account = "acct_TestAccount";
const now = 1_800_000_000;
const encoder = new TextEncoder();
const payload = (fields: Record<string, unknown> = {}) =>
  encoder.encode(JSON.stringify({
    id: "evt_Test1",
    type: "payment_intent.succeeded",
    account,
    livemode: false,
    created: now,
    ...fields,
  }));
async function sign(body: Uint8Array, timestamp = now): Promise<string> {
  const prefix = encoder.encode(`${timestamp}.`);
  const input = new Uint8Array(prefix.length + body.length);
  input.set(prefix);
  input.set(body, prefix.length);
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const output = new Uint8Array(await crypto.subtle.sign("HMAC", key, input));
  return `t=${timestamp},v1=${Array.from(output, (x) => x.toString(16).padStart(2, "0")).join("")}`;
}
function assert(value: unknown): asserts value {
  if (!value) throw new Error("assertion failed");
}
async function rejected(
  body: Uint8Array,
  signature: string | null,
  key = secret,
  acct = account,
  clock = now,
) {
  try {
    await verifyStripeTestWebhookEnvelope(body, signature, key, acct, clock);
  } catch (error) {
    assert(error instanceof WebhookVerificationError);
    return;
  }
  throw new Error("expected rejection");
}
Deno.test("valid synthetic test envelope returns only redacted verified metadata", async () => {
  const body = payload();
  const value = await verifyStripeTestWebhookEnvelope(body, await sign(body), secret, account, now);
  assert(
    value.eventId === "evt_Test1" && value.provider === "stripe" && value.bodySha256.length === 64,
  );
  assert(!("data" in value) && !JSON.stringify(value).includes(secret));
});
Deno.test("signature authenticates exact raw bytes and tolerates rotated signatures", async () => {
  const body = payload();
  const sig = await sign(body);
  const valid = await verifyStripeTestWebhookEnvelope(
    body,
    `${sig},v1=${"0".repeat(64)}`,
    secret,
    account,
    now,
  );
  assert(valid.eventId === "evt_Test1");
  await rejected(encoder.encode(new TextDecoder().decode(body) + " "), sig);
  await rejected(body, await sign(payload({ id: "evt_Other" })));
});
Deno.test("missing, malformed and invalid signatures fail closed", async () => {
  const body = payload();
  for (
    const value of [
      null,
      "",
      `t=${now}`,
      `t=${now},v1=${"0".repeat(64)}`,
      `t=${now},t=${now},v1=${"0".repeat(64)}`,
      `t=${now},v1=xyz`,
    ]
  ) await rejected(body, value);
  await rejected(body, await sign(body), "whsec_wrongsecret");
});
Deno.test("timestamp tolerance rejects stale and future signatures", async () => {
  const body = payload();
  await rejected(body, await sign(body, now - 301));
  await rejected(body, await sign(body, now + 301));
  assert(
    (await verifyStripeTestWebhookEnvelope(body, await sign(body, now - 300), secret, account, now))
      .eventId === "evt_Test1",
  );
});
Deno.test("signature cannot substitute for provider identity and test environment", async () => {
  for (
    const change of [
      { livemode: true },
      { account: "acct_Other" },
      { account: null },
      { id: "invalid" },
      { type: "" },
      { created: "1" },
    ]
  ) {
    const body = payload(change);
    await rejected(body, await sign(body));
  }
});
Deno.test("signed malformed JSON and invalid UTF-8 cannot become evidence", async () => {
  for (const body of [encoder.encode("{"), new Uint8Array([0xff, 0xfe])]) {
    await rejected(body, await sign(body));
  }
});
Deno.test("oversized bodies and malformed configuration fail closed", async () => {
  const body = payload();
  const sig = await sign(body);
  await rejected(new Uint8Array(1_048_577), sig);
  await rejected(body, sig, "bad");
  await rejected(body, sig, secret, "invalid");
});

Deno.test("signature verification alone does not implement replay protection", async () => {
  const body = payload();
  const signature = await sign(body);
  const first = await verifyStripeTestWebhookEnvelope(body, signature, secret, account, now);
  const replay = await verifyStripeTestWebhookEnvelope(body, signature, secret, account, now);
  assert(first.eventId === replay.eventId && first.bodySha256 === replay.bodySha256);
});
