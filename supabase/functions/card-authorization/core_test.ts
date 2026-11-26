import { type AuthorizationPort, createCardAuthorizationHandler } from "./core.ts";
import {
  CashMatchingError,
  type Owner,
  type Row,
} from "../_shared/matching/cash_matching_adapter.ts";
const rider = "11111111-1111-4111-8111-111111111111";
const trip = "22222222-2222-4222-8222-222222222222";
const payment = "33333333-3333-4333-8333-333333333333";
const attempt = "44444444-4444-4444-8444-444444444444";
const body = {
  trip_id: trip,
  payment_id: payment,
  expected_trip_version: 1,
  expected_payment_version: 1,
  idempotency_key: "auth-key-1",
};
class Fake implements AuthorizationPort {
  id = rider;
  session = {};
  calls = 0;
  actor = "";
  fail = false;
  revokeAfter = false;
  unknown = false;
  owner(): Promise<Owner> {
    if (this.fail || (this.revokeAfter && this.calls > 0)) {
      throw new CashMatchingError("unauthorized");
    }
    return Promise.resolve({ id: this.id, session: this.session });
  }
  admitRequest(): Promise<void> {
    return Promise.resolve();
  }
  prepare(actor: string, input: Row): Promise<unknown> {
    this.actor = actor;
    this.calls++;
    return Promise.resolve({
      ...input,
      attempt_id: attempt,
      outcome: this.unknown ? "UNKNOWN" : "PENDING",
      trip_version: 1,
      payment_version: 1,
    });
  }
}
function req(value: unknown): Request {
  return new Request("https://example.invalid", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(value),
  });
}
function assert(value: unknown): asserts value {
  if (!value) throw new Error("assertion failed");
}
Deno.test("verified Rider owns authorization and response is sanitized", async () => {
  const p = new Fake();
  const response = await createCardAuthorizationHandler(() => p)(req(body));
  const result = await response.json();
  assert(
    response.status === 200 && p.actor === rider && p.calls === 1 &&
      result.data.outcome === "PENDING",
  );
  assert(!JSON.stringify(result).includes("idempotency_key"));
});
Deno.test("forged rider or capture operation is rejected before service call", async () => {
  const p = new Fake();
  const h = createCardAuthorizationHandler(() => p);
  for (
    const value of [{ ...body, rider_id: rider }, { ...body, operation: "capture" }, {
      ...body,
      payment_id: "bad",
    }]
  ) assert((await h(req(value))).status === 400);
  assert(p.calls === 0);
});
Deno.test("missing, expired, foreign or revoked session cannot claim success", async () => {
  const p = new Fake();
  p.fail = true;
  const h = createCardAuthorizationHandler(() => p);
  assert((await h(req(body))).status === 401 && p.calls === 0);
  p.fail = false;
  p.revokeAfter = true;
  assert((await h(req(body))).status === 401 && Number(p.calls) === 1);
});
Deno.test("unknown remains unknown and mismatched SQL response fails closed", async () => {
  const p = new Fake();
  p.unknown = true;
  const h = createCardAuthorizationHandler(() => p);
  assert((await (await h(req(body))).json()).data.outcome === "UNKNOWN");
  p.prepare = () =>
    Promise.resolve({
      trip_id: trip,
      payment_id: "foreign",
      attempt_id: attempt,
      trip_version: 1,
      payment_version: 1,
      outcome: "PENDING",
    });
  assert((await h(req(body))).status === 503);
});
Deno.test("malformed and oversized bodies never reach the command", async () => {
  const p = new Fake();
  const h = createCardAuthorizationHandler(() => p);
  const request = new Request("https://example.invalid", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: "x".repeat(4097),
  });
  assert((await h(request)).status === 400 && p.calls === 0);
});
import { ServerAuthorizationPort } from "./port.ts";
Deno.test("server port binds verified session identity to service RPC", async () => {
  let seenActor: unknown;
  let seenOperation: unknown;
  let expired = false;
  const transport: typeof fetch = (input, init) => {
    const path = String(input);
    const headers = new Headers(init?.headers);
    if (path.includes("/auth/v1/user")) {
      return Promise.resolve(
        expired ? new Response("", { status: 401 }) : Response.json({ id: rider }),
      );
    }
    if (path.includes("/rest/v1/users?")) {
      return Promise.resolve(Response.json([{ id: rider, role: "rider", is_blocked: false }]));
    }
    if (
      path.includes("rider_matching_session_is_active") ||
      path.includes("rider_matching_request_guard")
    ) return Promise.resolve(Response.json(true));
    if (path.includes("backend_prepare_card_authorization_for_session")) {
      assert(headers.get("apikey") === "secret-local");
      const value = JSON.parse(String(init?.body));
      seenActor = value.verified_actor_id;
      seenOperation = value.verified_session_id;
      return Promise.resolve(
        Response.json({
          trip_id: trip,
          payment_id: payment,
          attempt_id: attempt,
          trip_version: 1,
          payment_version: 1,
          outcome: "PENDING",
        }),
      );
    }
    throw new Error("unexpected route");
  };
  const port = new ServerAuthorizationPort(
    "https://example.invalid",
    "public-local",
    "x." +
      btoa(
        JSON.stringify({
          sub: rider,
          session_id: "55555555-5555-4555-8555-555555555555",
          exp: Math.floor(Date.now() / 1000) + 300,
        }),
      ) + ".x",
    "secret-local",
    transport,
  );
  const h = createCardAuthorizationHandler(() => port);
  assert(
    (await h(req(body))).status === 200 && seenActor === rider &&
      seenOperation === "55555555-5555-4555-8555-555555555555",
  );
  expired = true;
  seenActor = undefined;
  assert((await h(req(body))).status === 401 && seenActor === undefined);
});
Deno.test("verified identity cannot use forged or expired JWT claims", async () => {
  let rpcCalls = 0;
  const transport: typeof fetch = (input) => {
    const path = String(input);
    if (path.includes("/auth/v1/user")) return Promise.resolve(Response.json({ id: rider }));
    if (path.includes("/rest/v1/users?")) {
      return Promise.resolve(Response.json([{ id: rider, role: "rider", is_blocked: false }]));
    }
    if (
      path.includes("rider_matching_session_is_active") ||
      path.includes("rider_matching_request_guard")
    ) return Promise.resolve(Response.json(true));
    rpcCalls++;
    throw new Error("unexpected privileged call");
  };
  const session = "55555555-5555-4555-8555-555555555555";
  for (
    const claims of [
      { sub: trip, session_id: session, exp: Math.floor(Date.now() / 1000) + 300 },
      { sub: rider, session_id: session, exp: Math.floor(Date.now() / 1000) - 1 },
      { sub: rider, exp: Math.floor(Date.now() / 1000) + 300 },
    ]
  ) {
    const token = "x." + btoa(JSON.stringify(claims)) + ".x";
    const p = new ServerAuthorizationPort(
      "https://example.invalid",
      "public",
      token,
      "secret",
      transport,
    );
    assert((await createCardAuthorizationHandler(() => p)(req(body))).status === 401);
  }
  assert(rpcCalls === 0);
});
