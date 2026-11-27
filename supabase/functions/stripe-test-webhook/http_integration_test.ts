import { createStripeTestWebhookHandler } from "./core.ts";
import {
  type QuarantinedWebhook,
  WebhookQuarantineRejected,
  type WebhookQuarantineStore,
  WebhookQuarantineUnavailable,
} from "../_shared/payments/stripe_webhook_quarantine.ts";
const container = Deno.env.get("P8_HTTP_CONTAINER") ?? "";
const db = Deno.env.get("P8_HTTP_DB") ?? "";
const isolatedTargetConfigured =
  /^ridex-r06-x2-[0-9a-f]{12}$/.test(container) &&
  /^r06_x2_test_[0-9a-f]{10}$/.test(db);
const encoder = new TextEncoder();
const secret = "whsec_synthetic_local_only";
const account = "acct_TestAccount";
const now = 1_800_000_000;
const booking = "a7032000-0000-0000-0000-000000000099";
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
async function sql(statement: string): Promise<string> {
  const p = new Deno.Command("docker", {
    args: [
      "exec",
      "-i",
      container,
      "psql",
      "-h",
      "/tmp",
      "-U",
      "postgres",
      "-d",
      db,
      "-X",
      "-q",
      "-A",
      "-t",
      "-v",
      "ON_ERROR_STOP=1",
    ],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = p.stdin.getWriter();
  await writer.write(encoder.encode("\\set VERBOSITY verbose\n" + statement));
  await writer.close();
  const result = await p.output();
  if (!result.success) {
    const error = new TextDecoder().decode(result.stderr);
    if (/ERROR:\s+(42501|22023|23505|23514):/.test(error)) throw new WebhookQuarantineRejected();
    throw new WebhookQuarantineUnavailable();
  }
  return new TextDecoder().decode(result.stdout).trim();
}
const quoted = (s: string) => "'" + s.replaceAll("'", "''") + "'";
class LocalSqlStore implements WebhookQuarantineStore {
  async quarantine(e: QuarantinedWebhook): Promise<"quarantined" | "duplicate"> {
    const args = [
      e.eventId,
      e.eventType,
      e.bodySha256,
      e.providerRef,
      e.tripId,
      e.paymentId,
      e.attemptId,
    ].map(quoted).join(",");
    const output = await sql(
      `select set_config('request.jwt.claim.role','service_role',false); set role service_role; select public.backend_quarantine_test_webhook(${args},${e.amountFils},'JOD');`,
    );
    const result = output.split(/\r?\n/).at(-1);
    if (result !== "quarantined" && result !== "duplicate") {
      throw new WebhookQuarantineUnavailable();
    }
    return result;
  }
}
async function sign(raw: Uint8Array, t = now): Promise<string> {
  const prefix = encoder.encode(`${t}.`);
  const signed = new Uint8Array(prefix.length + raw.length);
  signed.set(prefix);
  signed.set(raw, prefix.length);
  const k = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const h = new Uint8Array(await crypto.subtle.sign("HMAC", k, signed));
  return `t=${t},v1=${Array.from(h, (x) => x.toString(16).padStart(2, "0")).join("")}`;
}
class LocalSqlAdmission {
  async acquire(): Promise<string | null> {
    const output = await sql(
      "select set_config('request.jwt.claim.role','service_role',false); set role service_role; select coalesce(public.backend_acquire_test_webhook_admission()::text,'DENIED');",
    );
    const value = output.split(/\r?\n/).at(-1);
    if (value === "DENIED") return null;
    if (!value || !/^[0-9a-f-]{36}$/i.test(value)) throw new Error("admission_unavailable");
    return value;
  }
  async release(token: string): Promise<void> {
    const output = await sql(
      `select set_config('request.jwt.claim.role','service_role',false); set role service_role; select public.backend_release_test_webhook_admission(${
        quoted(token)
      });`,
    );
    if (output.split(/\r?\n/).at(-1) !== "t") throw new Error("admission_unavailable");
  }
}
async function listen(store: WebhookQuarantineStore, enabled = true) {
  const controller = new AbortController();
  const handler = createStripeTestWebhookHandler({
    enabled,
    secret,
    account,
    now: () => now,
    store,
    admission: new LocalSqlAdmission(),
  });
  const server = Deno.serve({
    hostname: "127.0.0.1",
    port: 0,
    signal: controller.signal,
    onListen() {},
  }, handler);
  return {
    url: `http://127.0.0.1:${(server.addr as Deno.NetAddr).port}`,
    close: async () => {
      controller.abort();
      await server.finished;
    },
  };
}
Deno.test({
  name: "real loopback HTTP with network-isolated PostgreSQL quarantine and restart",
  ignore: !isolatedTargetConfigured,
  permissions: {
    env: ["P8_HTTP_CONTAINER", "P8_HTTP_DB"],
    run: ["docker"],
    net: ["127.0.0.1"],
  },
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const ids = JSON.parse(
      await sql(
        `select json_build_object('trip',(select id from public.trips where booking_request_id='${booking}'),'payment',(select id from public.payments where booking_request_id='${booking}'),'attempt',(select id from public.payment_attempts where idempotency_key='p8-card-attempt'));`,
      ),
    );
    const make = (id: string, change: Record<string, unknown> = {}) =>
      encoder.encode(JSON.stringify({
        id,
        type: "payment_intent.succeeded",
        account,
        livemode: false,
        created: now,
        data: {
          object: {
            object: "payment_intent",
            id: "pi_SyntheticOne",
            livemode: false,
            currency: "jod",
            amount: 160,
            metadata: {
              ridex_trip_id: ids.trip,
              ridex_payment_id: ids.payment,
              ridex_attempt_id: ids.attempt,
            },
            ...change,
          },
        },
      }));
    let server = await listen(new LocalSqlStore());
    let requests = 0;
    const send = async (raw: Uint8Array, signature?: string) => {
      requests++;
      return await fetch(server.url, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "stripe-signature": signature ?? await sign(raw),
        },
        body: new Uint8Array(raw),
      });
    };
    try {
      const raw = make("evt_HttpFirst");
      assert((await send(raw)).status === 200, "signed request");
      assert((await send(raw)).status === 200, "durable replay");
      assert(
        (await send(raw, `t=${now},v1=${"0".repeat(64)}`)).status === 400,
        "invalid signature",
      );
      assert((await send(raw, await sign(raw, now - 301))).status === 400, "stale signature");
      assert(
        (await send(make("evt_HttpWrongAmount", { amount: 159 }))).status === 422,
        "wrong amount",
      );
      assert(
        (await send(make("evt_HttpWrongRef", { id: "pi_Wrong" }))).status === 422,
        "wrong provider link",
      );
      for (const field of ["ridex_trip_id", "ridex_payment_id", "ridex_attempt_id"]) {
        const bad = {
          ridex_trip_id: ids.trip,
          ridex_payment_id: ids.payment,
          ridex_attempt_id: ids.attempt,
          [field]: "99999999-9999-4999-8999-999999999999",
        };
        assert(
          (await send(make(`evt_${field.replaceAll("_", "")}`, { metadata: bad }))).status === 422,
          `wrong ${field}`,
        );
      }
      assert(
        (await send(make("evt_HttpWrongCurrency", { currency: "usd" }))).status === 400,
        "wrong currency",
      );
      const duplicate = make("evt_HttpRace");
      const duplicateResults = await Promise.all([
        send(duplicate),
        send(duplicate),
        send(duplicate),
      ]);
      assert(
        duplicateResults.every((value) => value.status === 200),
        "concurrent duplicate delivery",
      );
      const conflicting = JSON.parse(new TextDecoder().decode(duplicate));
      conflicting.type = "payment_intent.created";
      assert(
        (await send(encoder.encode(JSON.stringify(conflicting)))).status === 422,
        "event identity conflict",
      );
      const concurrent = await Promise.all(
        ["evt_HttpA", "evt_HttpB", "evt_HttpC"].map((id) => send(make(id))),
      );
      assert(concurrent.every((x) => x.status === 200), "concurrent distinct events");
      const older = JSON.parse(new TextDecoder().decode(make("evt_HttpOlder")));
      older.type = "payment_intent.created";
      assert(
        (await send(encoder.encode(JSON.stringify(older)))).status === 200,
        "out-of-order quarantined",
      );
      const unsupported = JSON.parse(new TextDecoder().decode(make("evt_HttpUnsupported")));
      unsupported.type = "payment_intent.unrelated";
      assert(
        (await send(encoder.encode(JSON.stringify(unsupported)))).status === 400,
        "unapproved type",
      );
      await server.close();
      server = await listen(new LocalSqlStore());
      assert((await send(raw)).status === 200, "replay after restart");
      assert(
        (await sql("select count(*) from private.p8_test_webhook_quarantine;")).split(/\r?\n/).at(
          -1,
        ) === "6",
        "durable event count",
      );
      assert(
        (await sql(
          `select (select card_status='cardPaymentPending' from public.payments where booking_request_id='${booking}') and (select status='pending' from public.payment_attempts where idempotency_key='p8-card-attempt');`,
        )).endsWith("t"),
        "no financial transition",
      );
      // Two distinct HTTP handler instances use the same DB quota and never trust IP headers.
      await sql(
        "update private.p8_webhook_admission set accepted=0,window_started_at=clock_timestamp();",
      );
      const second = await listen(new LocalSqlStore());
      try {
        for (let i = 0; i < 60; i++) {
          const target = i % 2 === 0 ? server.url : second.url;
          const response = await fetch(target, {
            method: "POST",
            headers: { "content-type": "application/json", "x-forwarded-for": String(i) },
            body: "{}",
          });
          requests++;
          assert(response.status === 400, `shared quota request ${i}`);
        }
        const limited = await fetch(second.url, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: "{}",
        });
        requests++;
        assert(
          limited.status === 429 && limited.headers.get("retry-after") === "60",
          "shared quota across instances",
        );
      } finally {
        await second.close();
      }
      await sql(
        "update private.p8_webhook_admission set accepted=0,window_started_at=clock_timestamp();",
      );
      const limiter = new LocalSqlAdmission();
      const leases = await Promise.all(Array.from({ length: 8 }, () => limiter.acquire()));
      assert(leases.every((token) => token !== null), "shared concurrency slots acquired");
      assert((await send(raw)).status === 429, "global concurrent work bound");
      await Promise.all(leases.map((token) => limiter.release(token!)));
      await server.close();
      server = await listen({
        quarantine: () => Promise.reject(new WebhookQuarantineUnavailable()),
      });
      assert((await send(make("evt_DbDown"))).status === 503, "database failure retries");
      await server.close();
      server = await listen(new LocalSqlStore(), false);
      assert((await send(raw)).status === 503, "default-off");
      console.log(
        `HTTP integration: ${requests} real requests; SQL-backed replay survives listener restart; no financial writes`,
      );
    } finally {
      await server.close();
    }
  },
});
