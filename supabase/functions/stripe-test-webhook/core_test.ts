import { createStripeTestWebhookHandler } from "./core.ts";
import type { WebhookQuarantineStore } from "../_shared/payments/stripe_webhook_quarantine.ts";
const store: WebhookQuarantineStore = {
  quarantine: () => {
    throw new Error("must not be called");
  },
};
function assert(value: unknown): asserts value {
  if (!value) throw new Error("assertion failed");
}
function request(method = "POST") {
  return new Request("http://localhost", {
    method,
    headers: { "content-type": "application/json" },
    ...(method === "POST" ? { body: "{}" } : {}),
  });
}
Deno.test("disabled intake does not process requests", async () => {
  const handler = createStripeTestWebhookHandler({
    enabled: false,
    secret: "",
    account: "",
    now: () => 1,
    store,
  });
  assert((await handler(request())).status === 503);
});
Deno.test("per-instance intake bound limits repeated unsigned requests", async () => {
  const handler = createStripeTestWebhookHandler({
    enabled: true,
    secret: "whsec_synthetic_local_only",
    account: "acct_TestAccount",
    now: () => 1_800_000_000,
    store,
    admission: {
      acquire: () => Promise.resolve("11111111-1111-4111-8111-111111111111"),
      release: () => Promise.resolve(),
    },
  });
  for (let i = 0; i < 60; i++) assert((await handler(request())).status === 400);
  assert((await handler(request())).status === 429);
});
Deno.test("only POST JSON reaches intake", async () => {
  const handler = createStripeTestWebhookHandler({
    enabled: true,
    secret: "",
    account: "",
    now: () => 1,
    store,
  });
  assert((await handler(request("GET"))).status === 405);
  assert(
    (await handler(new Request("http://localhost", { method: "POST", body: "bad" }))).status ===
      400,
  );
});

Deno.test("missing or failed shared admission fails closed", async () => {
  for (
    const admission of [undefined, {
      acquire: () => Promise.reject(new Error("down")),
      release: () => Promise.resolve(),
    }]
  ) {
    const handler = createStripeTestWebhookHandler({
      enabled: true,
      secret: "whsec_synthetic_local_only",
      account: "acct_TestAccount",
      now: () => 1_800_000_000,
      store,
      admission,
    });
    assert((await handler(request())).status === 503);
  }
});
Deno.test("uncertain lease release is retryable", async () => {
  const handler = createStripeTestWebhookHandler({
    enabled: true,
    secret: "whsec_synthetic_local_only",
    account: "acct_TestAccount",
    now: () => 1_800_000_000,
    store,
    admission: {
      acquire: () => Promise.resolve("11111111-1111-4111-8111-111111111111"),
      release: () => Promise.reject(new Error("unknown")),
    },
  });
  assert((await handler(request())).status === 503);
});
