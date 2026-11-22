import {
  type QuarantinedWebhook,
  quarantineStripeTestWebhook,
  SupabaseWebhookQuarantineStore,
  WebhookQuarantineRejected,
  WebhookQuarantineUnavailable,
} from "./stripe_webhook_quarantine.ts";
const secret = "whsec_synthetic_local_only", account = "acct_TestAccount", now = 1_800_000_000;
const encoder = new TextEncoder();
function body(change: Record<string, unknown> = {}) {
  return encoder.encode(JSON.stringify({
    id: "evt_Quarantine",
    type: "payment_intent.succeeded",
    account,
    livemode: false,
    created: now,
    data: {
      object: {
        object: "payment_intent",
        id: "pi_TestIntent",
        livemode: false,
        currency: "jod",
        amount: 160,
        metadata: {
          ridex_trip_id: "11111111-1111-4111-8111-111111111111",
          ridex_payment_id: "22222222-2222-4222-8222-222222222222",
          ridex_attempt_id: "33333333-3333-4333-8333-333333333333",
        },
        ...change,
      },
    },
  }));
}
async function sign(raw: Uint8Array) {
  const p = encoder.encode(`${now}.`), joined = new Uint8Array(p.length + raw.length);
  joined.set(p);
  joined.set(raw, p.length);
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const h = new Uint8Array(await crypto.subtle.sign("HMAC", key, joined));
  return `t=${now},v1=${Array.from(h, (x) => x.toString(16).padStart(2, "0")).join("")}`;
}
function assert(v: unknown): asserts v {
  if (!v) throw new Error("assertion failed");
}
Deno.test("signed matching envelope is converted to JOD fils and quarantined once", async () => {
  const raw = body();
  let observed: QuarantinedWebhook | undefined;
  const r = await quarantineStripeTestWebhook(raw, await sign(raw), secret, account, now, {
    quarantine(e) {
      observed = e;
      return Promise.resolve("quarantined");
    },
  });
  assert(
    r === "quarantined" && observed?.amountFils === 1600 && observed.currency === "JOD" &&
      observed.providerRef === "pi_TestIntent",
  );
});
Deno.test("invalid signature, amount, currency and identity never reach store", async () => {
  let calls = 0;
  const store = {
    quarantine() {
      calls++;
      return Promise.resolve("quarantined" as const);
    },
  };
  for (const c of [{ currency: "usd" }, { amount: 0 }, { metadata: {} }, { id: "pi_wrong!" }]) {
    const raw = body(c);
    try {
      await quarantineStripeTestWebhook(raw, await sign(raw), secret, account, now, store);
      throw new Error("accepted");
    } catch (e) {
      if ((e as Error).message === "accepted") throw e;
    }
  }
  const raw = body();
  try {
    await quarantineStripeTestWebhook(
      raw,
      `t=${now},v1=${"0".repeat(64)}`,
      secret,
      account,
      now,
      store,
    );
    throw new Error("accepted");
  } catch (e) {
    if ((e as Error).message === "accepted") throw e;
  }
  assert(calls === 0);
});
Deno.test("duplicate is surfaced and unknown store result does not retry", async () => {
  const raw = body(), sig = await sign(raw);
  let calls = 0;
  const duplicate = {
    quarantine() {
      calls++;
      return Promise.resolve("duplicate" as const);
    },
  };
  assert(
    await quarantineStripeTestWebhook(raw, sig, secret, account, now, duplicate) === "duplicate" &&
      calls === 1,
  );
  const unavailable = {
    quarantine(): Promise<"quarantined"> {
      calls++;
      return Promise.reject(new Error("ambiguous"));
    },
  };
  try {
    await quarantineStripeTestWebhook(raw, sig, secret, account, now, unavailable);
    throw new Error("accepted");
  } catch (e) {
    if ((e as Error).message === "accepted") throw e;
  }
  assert(Number(calls) === 2);
});
Deno.test("server store makes one privileged request without leaking body or credential", async () => {
  let calls = 0;
  const send: typeof fetch = (_url, init) => {
    calls++;
    assert(new Headers(init?.headers).get("apikey") === "secret-local");
    return Promise.resolve(Response.json("quarantined"));
  };
  const store = new SupabaseWebhookQuarantineStore("https://example.invalid", "secret-local", send);
  const raw = body();
  assert(
    await quarantineStripeTestWebhook(raw, await sign(raw), secret, account, now, store) ===
        "quarantined" && calls === 1,
  );
});

Deno.test("store distinguishes rejected evidence from database failure without retry", async () => {
  const raw = body();
  const signature = await sign(raw);
  for (const code of ["22023", "23505", "23514", "42501"]) {
    let calls = 0;
    const store = new SupabaseWebhookQuarantineStore("https://example.invalid", "server", () => {
      calls++;
      return Promise.resolve(Response.json({ code }, { status: 400 }));
    });
    try {
      await quarantineStripeTestWebhook(raw, signature, secret, account, now, store);
      throw new Error("accepted");
    } catch (error) {
      assert(error instanceof WebhookQuarantineRejected && calls === 1);
    }
  }
  let calls = 0;
  const down = new SupabaseWebhookQuarantineStore("https://example.invalid", "server", () => {
    calls++;
    return Promise.resolve(new Response("down", { status: 503 }));
  });
  try {
    await quarantineStripeTestWebhook(raw, signature, secret, account, now, down);
    throw new Error("accepted");
  } catch (error) {
    assert(error instanceof WebhookQuarantineUnavailable && calls === 1);
  }
});
