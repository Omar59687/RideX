import { test } from "node:test";
import { ReservationFixture } from "./test_intent_reservation_fixture.ts";
import assert from "node:assert/strict";
import {
  authorizeStripeTestRider,
  createCanonicalIntentContextReader,
  createStripeTestIntentHandler,
  type StripeIntentReadRequest,
} from "./stripe_test_intent_handler.ts";
import {
  type CanonicalIntentContext,
  type PreparedTestIntent,
  TestIntentError,
  type TestIntentProvider,
} from "./test_intent_provider.ts";

const riderId = "eeeeeeee-bbbb-4ccc-9ddd-eeeeeeeeeeee";
const paymentId = "aaaaaaaa-bbbb-4ccc-9ddd-eeeeeeeeeeee";
const tripId = "bbbbbbbb-bbbb-4ccc-9ddd-eeeeeeeeeeee";
const driverId = "cccccccc-bbbb-4ccc-9ddd-eeeeeeeeeeee";
const attemptId = "dddddddd-bbbb-4ccc-9ddd-eeeeeeeeeeee";
const key = "original-operation-key";
const TOKEN = `Bearer ${"a".repeat(40)}`;
const command = {
  payment_id: paymentId,
  trip_id: tripId,
  attempt_id: attemptId,
  expected_payment_version: 2,
  expected_trip_version: 4,
  idempotency_key: key,
};
const context: CanonicalIntentContext = Object.freeze({
  paymentId,
  attemptId,
  riderId,
  paymentVersion: 2,
  tripId,
  tripVersion: 4,
  driverId,
  tripStatus: "accepted",
  method: "card",
  paymentStatus: "cardPaymentPending",
  amountFils: 13300,
  currency: "JOD",
  idempotencyKey: key,
});
const prepared: PreparedTestIntent = Object.freeze({
  provider: "stripe",
  reference: "pi_TestFixture",
  requiresCanonicalVerification: true,
});

function request(body: unknown = command, overrides: RequestInit = {}): Request {
  return new Request("https://edge.test/functions/v1/stripe-test-intent", {
    method: "POST",
    headers: { authorization: TOKEN, "content-type": "application/json" },
    body: JSON.stringify(body),
    ...overrides,
  });
}
function bodyOf(response: Response): Promise<Record<string, unknown>> {
  return response.json() as Promise<Record<string, unknown>>;
}
function provider(action: () => Promise<PreparedTestIntent> = () => Promise.resolve(prepared)) {
  let calls = 0;
  const value: TestIntentProvider = {
    prepare: async () => {
      calls++;
      return await action();
    },
  };
  return { value, calls: () => calls };
}
function handler(options: {
  authorize?: (request: Request) => Promise<string>;
  read?: (request: StripeIntentReadRequest) => Promise<CanonicalIntentContext | null>;
  provider?: TestIntentProvider;
  enabled?: boolean;
  store?: ReservationFixture;
} = {}) {
  const injected = options.provider ?? provider().value;
  return createStripeTestIntentHandler({
    authorize: options.authorize ?? (() => Promise.resolve(riderId)),
    readAuthorizedContext: options.read ?? (() => Promise.resolve(context)),
    provider: injected,
    reservationStore: options.store ?? new ReservationFixture(),
    assertProviderReady: () => {},
    providerDispatchEnabled: options.enabled ?? true,
  });
}

for (
  const [name, req] of [
    ["missing bearer", request(command, { headers: { "content-type": "application/json" } })],
    [
      "invalid bearer",
      request(command, {
        headers: { authorization: "Bearer invalid", "content-type": "application/json" },
      }),
    ],
  ] as const
) {
  test(`${name} is rejected before canonical reads`, async () => {
    let reads = 0;
    const run = createStripeTestIntentHandler({
      authorize: () => Promise.resolve(riderId),
      readAuthorizedContext: () => {
        reads++;
        return Promise.resolve(context);
      },
      provider: provider().value,
    });
    const response = await run(req);
    assert.equal(response.status, 401);
    assert.equal(reads, 0);
  });
}

test("HTTP method and content type are bounded", async () => {
  const run = handler();
  assert.equal((await run(new Request("https://edge.test", { method: "GET" }))).status, 405);
  assert.equal(
    (await run(new Request("https://edge.test", { method: "POST", body: "{}" }))).status,
    415,
  );
});

test("client amount and unrecognized financial fields are rejected", async () => {
  let reads = 0;
  const run = createStripeTestIntentHandler({
    authorize: () => Promise.resolve(riderId),
    readAuthorizedContext: () => {
      reads++;
      return Promise.resolve(context);
    },
    provider: provider().value,
  });
  for (const payload of [{ ...command, amount_fils: 1 }, { ...command, status: "paid" }]) {
    assert.equal((await run(request(payload))).status, 400);
  }
  assert.equal(reads, 0);
});

test("backend actor must be an active Rider", async () => {
  const run = handler({ authorize: () => Promise.reject(new Error("private")) });
  const response = await run(request());
  assert.equal(response.status, 503);
  assert.equal(JSON.stringify(await bodyOf(response)).includes("private"), false);
});

for (
  const [name, change] of [
    ["foreign Rider", { riderId: "11111111-bbbb-4ccc-9ddd-eeeeeeeeeeee" }],
    ["foreign Trip", { tripId: "11111111-bbbb-4ccc-9ddd-eeeeeeeeeeee" }],
    ["wrong attempt", { attemptId: "11111111-bbbb-4ccc-9ddd-eeeeeeeeeeee" }],
  ] as const
) {
  test(`${name} canonical context cannot dispatch`, async () => {
    let calls = 0;
    const run = handler({
      read: () => Promise.resolve({ ...context, ...change }),
      provider: {
        prepare: async () => {
          calls++;
          return prepared;
        },
      },
    });
    assert.equal((await run(request())).status, 404);
    assert.equal(calls, 0);
  });
}

for (
  const [name, change] of [
    ["unaccepted Trip", { tripStatus: "searching" }],
    ["non-Card payment", { method: "cash" }],
    ["nonpending payment", { paymentStatus: "cardPaymentAuthorized" }],
    ["precision mismatch", { amountFils: 13301 }],
  ] as const
) {
  test(`${name} fails closed before provider dispatch`, async () => {
    let calls = 0;
    const run = handler({
      read: () => Promise.resolve({ ...context, ...change }),
      provider: {
        prepare: async () => {
          calls++;
          return prepared;
        },
      },
    });
    assert.equal((await run(request())).status, 404);
    assert.equal(calls, 0);
  });
}

test("stale payment or Trip version never dispatches", async () => {
  let calls = 0;
  const run = handler({
    provider: {
      prepare: async () => {
        calls++;
        return prepared;
      },
    },
  });
  assert.equal((await run(request({ ...command, expected_payment_version: 1 }))).status, 409);
  assert.equal((await run(request({ ...command, expected_trip_version: 3 }))).status, 409);
  assert.equal(calls, 0);
});

test("wrong idempotency key is denied by the canonical attempt reader", async () => {
  let calls = 0;
  const run = handler({
    read: (input) => Promise.resolve(input.idempotencyKey === key ? context : null),
    provider: {
      prepare: async () => {
        calls++;
        return prepared;
      },
    },
  });
  assert.equal(
    (await run(request({ ...command, idempotency_key: "different-operation-key" }))).status,
    404,
  );
  assert.equal(calls, 0);
});

test("production dispatch is disabled even for valid canonical context", async () => {
  let calls = 0;
  const run = handler({
    enabled: false,
    provider: {
      prepare: async () => {
        calls++;
        return prepared;
      },
    },
  });
  const response = await run(request());
  assert.equal(response.status, 503);
  assert.equal(calls, 0);
});

test("same exact operation replays the sanitized result without a second provider request", async () => {
  const injected = provider();
  const run = handler({ provider: injected.value });
  const first = await run(request());
  const second = await run(request());
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal(injected.calls(), 1);
  const body = await bodyOf(first);
  assert.deepEqual(body.data, {
    provider: "stripe",
    reference: "pi_TestFixture",
    requires_canonical_verification: true,
    replayed: false,
  });
  assert.equal(JSON.stringify(body).includes("client_secret"), false);
});

test("unknown provider result is quarantined and never automatically retried", async () => {
  let calls = 0;
  const run = handler({
    provider: {
      prepare: async () => {
        calls++;
        throw new TestIntentError("unknown_result");
      },
    },
  });
  const first = await run(request());
  const second = await run(request());
  assert.equal(first.status, 503);
  assert.equal(second.status, 409);
  assert.equal(calls, 1);
  assert.equal(JSON.stringify(await bodyOf(first)).includes("provider"), false);
});

test("duplicate in-flight operation is blocked", async () => {
  let calls = 0;
  let release!: (result: PreparedTestIntent) => void;
  const pending = new Promise<PreparedTestIntent>((resolve) => release = resolve);
  const run = handler({
    provider: {
      prepare: async () => {
        calls++;
        return await pending;
      },
    },
  });
  const first = run(request());
  await new Promise((resolve) => setTimeout(resolve, 0));
  const second = await run(request());
  assert.equal(second.status, 409);
  release(prepared);
  assert.equal((await first).status, 200);
  assert.equal(calls, 1);
});

test("post-provider revocation or context change is not published as prepared", async () => {
  let authCalls = 0;
  const run = handler({
    authorize: () =>
      Promise.resolve(++authCalls === 1 ? riderId : "11111111-bbbb-4ccc-9ddd-eeeeeeeeeeee"),
    provider: provider().value,
  });
  const response = await run(request());
  assert.equal(response.status, 409);
  assert.equal(JSON.stringify(await bodyOf(response)).includes("pi_TestFixture"), false);
});

test("canonical reader scopes payment, Trip and attempt queries and uses server credential only", async () => {
  const payment = {
    id: paymentId,
    trip_id: tripId,
    rider_id: riderId,
    method: "card",
    card_status: "cardPaymentPending",
    authorized_amount_fils: 13300,
    final_amount_fils: 13300,
    currency: "JOD",
    version: 2,
  };
  const trip = {
    id: tripId,
    rider_id: riderId,
    driver_id: driverId,
    status: "accepted",
    payment_method: "card",
    currency: "JOD",
    original_fare_fils: 13300,
    current_fare_fils: 13300,
    version: 4,
  };
  const attempt = {
    id: attemptId,
    payment_id: paymentId,
    type: "initialAuthorization",
    status: "pending",
    requested_amount_fils: 13300,
    currency: "JOD",
    idempotency_key: key,
    authorization_cycle: 1,
  };
  const seen: URL[] = [];
  const reader = createCanonicalIntentContextReader({
    supabaseUrl: "https://project.supabase.co",
    anonKey: "public-test-key",
    serviceRoleKey: "server-test-secret",
    fetch: async (input, init) => {
      const url = new URL(String(input));
      seen.push(url);
      assert.equal(new Headers(init?.headers).get("apikey"), "server-test-secret");
      assert.equal(new Headers(init?.headers).get("authorization"), "Bearer server-test-secret");
      if (url.pathname.endsWith("/payments")) return Response.json([payment]);
      if (url.pathname.endsWith("/trips")) return Response.json([trip]);
      if (url.pathname.endsWith("/payment_attempts")) return Response.json([attempt]);
      throw new Error("unexpected path");
    },
  });
  const result = await reader({
    riderId,
    paymentId,
    tripId,
    attemptId,
    expectedPaymentVersion: 2,
    expectedTripVersion: 4,
    idempotencyKey: key,
  });
  assert.equal(result?.amountFils, 13300);
  assert.equal(seen.length, 3);
  assert.equal(seen[0].searchParams.get("rider_id"), `eq.${riderId}`);
  assert.equal(seen[1].searchParams.get("rider_id"), `eq.${riderId}`);
  assert.equal(seen[2].searchParams.get("payment_id"), `eq.${paymentId}`);
  assert.equal(seen[2].searchParams.get("idempotency_key"), `eq.${key}`);
});

test("canonical reader denies foreign payment and inconsistent attempt", async () => {
  let call = 0;
  const rows = [
    [{
      id: paymentId,
      trip_id: tripId,
      rider_id: "11111111-bbbb-4ccc-9ddd-eeeeeeeeeeee",
      method: "card",
      card_status: "cardPaymentPending",
      authorized_amount_fils: 13300,
      final_amount_fils: 13300,
      currency: "JOD",
      version: 2,
    }],
  ];
  const reader = createCanonicalIntentContextReader({
    supabaseUrl: "https://project.supabase.co",
    anonKey: "key",
    serviceRoleKey: "secret",
    fetch: async () => {
      call++;
      return Response.json(rows[0]);
    },
  });
  assert.equal(
    await reader({
      riderId,
      paymentId,
      tripId,
      attemptId,
      expectedPaymentVersion: 2,
      expectedTripVersion: 4,
      idempotencyKey: key,
    }),
    null,
  );
  assert.equal(call, 1);
});

test("per-Rider instance limiter bounds canonical reads", async () => {
  let reads = 0;
  const run = handler({
    read: (input) => {
      reads++;
      return Promise.resolve({ ...context, idempotencyKey: input.idempotencyKey });
    },
    enabled: false,
  });
  for (let index = 0; index < 10; index++) {
    const operationKey = `operation-key-${index}`;
    const response = await run(request({ ...command, idempotency_key: operationKey }));
    assert.equal(response.status, 503);
  }
  const limited = await run(request({ ...command, idempotency_key: "operation-key-10" }));
  assert.equal(limited.status, 429);
  assert.equal(reads, 10);
});
test("Auth profile reader rejects blocked and non-Rider accounts", async () => {
  for (
    const user of [
      { id: riderId, role: "admin", is_blocked: false },
      { id: riderId, role: "rider", is_blocked: true },
    ]
  ) {
    await assert.rejects(authorizeStripeTestRider(request(), {
      supabaseUrl: "https://project.supabase.co",
      anonKey: "anon",
      serviceRoleKey: "service",
      fetch: async () => Response.json([user]),
    }));
  }
  assert.equal(
    await authorizeStripeTestRider(request(), {
      supabaseUrl: "https://project.supabase.co",
      anonKey: "anon",
      serviceRoleKey: "service",
      fetch: async () => Response.json([{ id: riderId, role: "rider", is_blocked: false }]),
    }),
    riderId,
  );
});
test("enabled handler without durable persistence fails closed", async () => {
  const injected = provider();
  const run = createStripeTestIntentHandler({
    authorize: async () => riderId,
    readAuthorizedContext: async () => context,
    provider: injected.value,
    providerDispatchEnabled: true,
    assertProviderReady: () => {},
  });
  assert.equal((await run(request())).status, 503);
  assert.equal(injected.calls(), 0);
});
test("distinct Edge handlers share durable evidence after restart and never redispatch", async () => {
  const store = new ReservationFixture();
  const injected = provider();
  assert.equal((await handler({ store, provider: injected.value })(request())).status, 200);
  const restarted = await handler({ store, provider: injected.value })(request());
  assert.equal(restarted.status, 503);
  assert.equal(injected.calls(), 1);
  assert(JSON.stringify(await bodyOf(restarted)).includes("outcome_unknown"));
});
