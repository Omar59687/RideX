import { test } from "node:test";
import assert from "node:assert/strict";
import {
  type CanonicalIntentContext,
  StripeTestIntentProvider,
  TestIntentError,
} from "./test_intent_provider.ts";
import {
  DurableTestIntentProvider,
  reconcileReservedTestIntent,
  SupabaseTestIntentReservationStore,
} from "./test_intent_reservation.ts";
import { ReservationFixture } from "./test_intent_reservation_fixture.ts";

const context: CanonicalIntentContext = Object.freeze({
  paymentId: "aaaaaaaa-bbbb-4ccc-9ddd-eeeeeeeeeeee",
  attemptId: "dddddddd-bbbb-4ccc-9ddd-eeeeeeeeeeee",
  riderId: "eeeeeeee-bbbb-4ccc-9ddd-eeeeeeeeeeee",
  paymentVersion: 2,
  tripVersion: 4,
  tripId: "bbbbbbbb-bbbb-4ccc-9ddd-eeeeeeeeeeee",
  driverId: "cccccccc-bbbb-4ccc-9ddd-eeeeeeeeeeee",
  tripStatus: "accepted",
  method: "card",
  paymentStatus: "cardPaymentPending",
  amountFils: 13300,
  currency: "JOD",
  idempotencyKey: "original-operation-key",
});
const prepared = {
  provider: "stripe" as const,
  reference: "pi_TestFixture",
  requiresCanonicalVerification: true as const,
};
const unknown = (e: unknown) => e instanceof TestIntentError && e.code === "unknown_result";
const secret = ["sk", "test", "fixture"].join("_");
function response(change: Record<string, unknown> = {}) {
  return Response.json({
    object: "payment_intent",
    id: prepared.reference,
    livemode: false,
    amount: 1330,
    currency: "jod",
    capture_method: "manual",
    confirmation_method: "manual",
    status: "requires_payment_method",
    payment_method: null,
    amount_received: 0,
    amount_capturable: 0,
    latest_charge: null,
    metadata: {
      ridex_payment_id: context.paymentId,
      ridex_attempt_id: context.attemptId,
      ridex_trip_id: context.tripId,
    },
    client_secret: "never-publish-this",
    ...change,
  });
}
test("concurrent Edge owners and restart share one persisted claim; no repeated dispatch", async () => {
  const store = new ReservationFixture();
  let calls = 0;
  const inner = {
    prepare: async () => {
      calls++;
      return prepared;
    },
  };
  const results = await Promise.allSettled([
    new DurableTestIntentProvider(store, inner, () => {}).prepare(context),
    new DurableTestIntentProvider(store, inner, () => {}).prepare(context),
  ]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal(calls, 1);
  await assert.rejects(
    new DurableTestIntentProvider(store, inner, () => {}).prepare(context),
    unknown,
  );
  assert.equal(calls, 1);
});
for (const outcome of ["timeout", "bad response", "provider rejection"]) {
  test("post-claim " + outcome + " remains unresolved with no replay", async () => {
    const store = new ReservationFixture();
    let calls = 0;
    const inner = {
      prepare: async () => {
        calls++;
        throw new Error("private payload");
      },
    };
    await assert.rejects(
      new DurableTestIntentProvider(store, inner, () => {}).prepare(context),
      unknown,
    );
    await assert.rejects(
      new DurableTestIntentProvider(store, inner, () => {}).prepare(context),
      unknown,
    );
    assert.equal(store.rows.get(context.attemptId)?.state, "unknown");
    assert.equal(calls, 1);
  });
}
test("lost claim acknowledgement stops before dispatch; restart cannot reclaim", async () => {
  const store = new ReservationFixture();
  store.loseClaimAcknowledgement = true;
  let calls = 0;
  const inner = {
    prepare: async () => {
      calls++;
      return prepared;
    },
  };
  await assert.rejects(new DurableTestIntentProvider(store, inner, () => {}).prepare(context));
  store.loseClaimAcknowledgement = false;
  await assert.rejects(
    new DurableTestIntentProvider(store, inner, () => {}).prepare(context),
    unknown,
  );
  assert.equal(calls, 0);
  assert.equal(store.rows.size, 1);
});
test("lost successful evidence acknowledgement cannot erase reference or repeat operation", async () => {
  const store = new ReservationFixture();
  store.loseRecordAcknowledgement = true;
  let calls = 0;
  const inner = {
    prepare: async () => {
      calls++;
      return prepared;
    },
  };
  await assert.rejects(
    new DurableTestIntentProvider(store, inner, () => {}).prepare(context),
    unknown,
  );
  assert.equal(store.rows.get(context.attemptId)?.reference, prepared.reference);
  assert.equal(store.rows.get(context.attemptId)?.state, "prepared");
  await assert.rejects(
    new DurableTestIntentProvider(store, inner, () => {}).prepare(context),
    unknown,
  );
  assert.equal(calls, 1);
});
test("missing approval fails before claim or dispatch", async () => {
  const store = new ReservationFixture();
  await assert.rejects(
    new DurableTestIntentProvider(store, { prepare: async () => prepared }, () => {
      throw new TestIntentError("not_configured");
    }).prepare(context),
  );
  assert.equal(store.rows.size, 0);
});
test("changed owner/version/key cannot reuse existing evidence", async () => {
  const store = new ReservationFixture();
  const inner = { prepare: async () => prepared };
  await new DurableTestIntentProvider(store, inner, () => {}).prepare(context);
  for (
    const change of [{ riderId: context.driverId }, { paymentVersion: 3 }, { tripVersion: 5 }, {
      idempotencyKey: "different-original-key",
    }]
  ) {
    await assert.rejects(
      new DurableTestIntentProvider(store, inner, () => {}).prepare({ ...context, ...change }),
      unknown,
    );
  }
});
test("reconciliation cannot read an untrusted reference or replay an unknown claim", async () => {
  const store = new ReservationFixture();
  await store.claim(context);
  let reads = 0;
  const result = await reconcileReservedTestIntent(context, store, {
    read: async () => {
      reads++;
      return prepared;
    },
  });
  assert.equal(result.state, "unresolved");
  assert.equal(reads, 0);
  assert.equal(store.records, 0);
});
for (const missing of [false, true]) {
  test(
    "GET reconciliation is read-only; absent evidence remains unresolved " + missing,
    async () => {
      const store = new ReservationFixture();
      await new DurableTestIntentProvider(store, { prepare: async () => prepared }, () => {})
        .prepare(context);
      const writes = store.records;
      let calls = 0;
      const stripe = new StripeTestIntentProvider({
        readSecret: () => secret,
        jodTestModeApproved: true,
        transport: async (url, init) => {
          calls++;
          assert.equal(init?.method, "GET");
          assert.equal(String(url), "https://api.stripe.com/v1/payment_intents/pi_TestFixture");
          assert(!new Headers(init?.headers).has("Idempotency-Key"));
          return missing ? new Response("", { status: 404 }) : response();
        },
      });
      const result = await reconcileReservedTestIntent(context, store, stripe);
      assert.equal(result.state, missing ? "unresolved" : "preparation_verified");
      assert.equal(store.records, writes);
      assert.equal(calls, 1);
      assert(!JSON.stringify(result).includes("never-publish-this"));
      assert(!JSON.stringify(result).includes("pi_"));
    },
  );
}
for (
  const change of [{ metadata: {} }, { id: "pi_Foreign" }, { livemode: true }, {
    status: "succeeded",
  }, { amount_received: 1330 }]
) {
  test("retrieval mismatch is unresolved without mutation " + JSON.stringify(change), async () => {
    const store = new ReservationFixture();
    await new DurableTestIntentProvider(store, { prepare: async () => prepared }, () => {}).prepare(
      context,
    );
    const stripe = new StripeTestIntentProvider({
      readSecret: () => secret,
      jodTestModeApproved: true,
      transport: async () => response(change),
    });
    const writes = store.records;
    assert.equal((await reconcileReservedTestIntent(context, store, stripe)).state, "unresolved");
    assert.equal(store.records, writes);
  });
}
test("REST store sends original identifiers and versions to backend-only claim RPC", async () => {
  const store = new SupabaseTestIntentReservationStore(
    "https://project.test",
    "server-fixture",
    async (url, init) => {
      assert.equal(
        String(url),
        "https://project.test/rest/v1/rpc/backend_claim_stripe_test_preparation",
      );
      assert.equal(init?.redirect, "error");
      const body = JSON.parse(String(init?.body));
      assert.equal(body.operation_key, context.idempotencyKey);
      assert.equal(body.expected_trip_version, 4);
      assert.equal(body.expected_payment_version, 2);
      assert(!("amount" in body));
      assert(!("status" in body));
      return Response.json({
        disposition: "claimed",
        state: "reserved",
        context,
        claimToken: "10000000-0000-4000-8000-000000000001",
        reference: null,
      });
    },
  );
  assert.equal((await store.claim(context)).disposition, "claimed");
});
test("REST errors stay sanitized; missing persistence never allows dispatch", async () => {
  const store = new SupabaseTestIntentReservationStore(
    "https://project.test",
    "server-fixture",
    async () => new Response("private server payload", { status: 500 }),
  );
  let calls = 0;
  await assert.rejects(
    new DurableTestIntentProvider(store, {
      prepare: async () => {
        calls++;
        return prepared;
      },
    }, () => {}).prepare(context),
    unknown,
  );
  assert.equal(calls, 0);
});
for (const approved of [false, true]) {
  test("read-only retrieval rejects absent approval/live credentials " + approved, async () => {
    let calls = 0;
    const stripe = new StripeTestIntentProvider({
      readSecret: () => ["sk", "live", "fixture"].join("_"),
      jodTestModeApproved: approved,
      transport: async () => {
        calls++;
        return response();
      },
    });
    await assert.rejects(
      stripe.read(context, prepared.reference),
      (e) => e instanceof TestIntentError && e.code === "not_configured",
    );
    assert.equal(calls, 0);
  });
}
test("retrieval timeout stays unresolved and does not write retained evidence", async () => {
  const store = new ReservationFixture();
  await new DurableTestIntentProvider(store, { prepare: async () => prepared }, () => {}).prepare(
    context,
  );
  const writes = store.records;
  const stripe = new StripeTestIntentProvider({
    readSecret: () => secret,
    jodTestModeApproved: true,
    transport: async () => {
      throw new Error("private provider timeout");
    },
  });
  assert.equal((await reconcileReservedTestIntent(context, store, stripe)).state, "unresolved");
  assert.equal(store.records, writes);
});
test("HTTP 500 at Stripe preparation is unknown, not a definitive failed payment", async () => {
  const stripe = new StripeTestIntentProvider({
    readSecret: () => secret,
    jodTestModeApproved: true,
    transport: async () => new Response("private", { status: 500 }),
  });
  await assert.rejects(stripe.prepare(context), unknown);
});
test("reservation store serialization never exposes its server credential", () => {
  const store = new SupabaseTestIntentReservationStore(
    "https://project.test",
    "server-only-fixture",
  );
  assert.equal(JSON.stringify(store), "{}");
});
for (const [sqlstate, expected] of [["40001", "stale_version"], ["42501", "forbidden"]]) {
  test(
    "atomic claim " + sqlstate + " is sanitized and stops before provider dispatch",
    async () => {
      const store = new SupabaseTestIntentReservationStore(
        "https://project.test",
        "server-fixture",
        async () =>
          Response.json({ code: sqlstate, message: "private database payload" }, { status: 409 }),
      );
      let calls = 0;
      await assert.rejects(
        new DurableTestIntentProvider(store, {
          prepare: async () => {
            calls++;
            return prepared;
          },
        }, () => {}).prepare(context),
        (e) =>
          e instanceof TestIntentError && e.code === expected &&
          !String(e).includes("private"),
      );
      assert.equal(calls, 0);
    },
  );
}
test("operation key cannot move to another attempt or Payment after a claim", async () => {
  const store = new ReservationFixture();
  let calls = 0;
  const inner = {
    prepare: async () => {
      calls++;
      return prepared;
    },
  };
  await new DurableTestIntentProvider(store, inner, () => {}).prepare(context);
  for (
    const change of [
      { attemptId: context.driverId },
      { attemptId: context.driverId, paymentId: context.tripId },
    ]
  ) {
    await assert.rejects(
      new DurableTestIntentProvider(store, inner, () => {}).prepare({ ...context, ...change }),
      unknown,
    );
  }
  assert.equal(calls, 1);
  assert.equal(store.rows.size, 1);
});
