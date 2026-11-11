import { CashMatchingError } from "../_shared/matching/cash_matching_adapter.ts";
import { createCashMatchingHandler } from "./core.ts";

const bookingId = "a1230000-0000-4000-8000-000000000001";
const quoteId = "a1230000-0000-4000-8000-000000000002";
const riderId = "a1230000-0000-4000-8000-000000000004";
const payload = {
  booking_request_id: bookingId,
  fare_quote_id: quoteId,
  expected_booking_version: 2,
};
const post = (body: unknown) =>
  new Request("https://ridex.test/cash-matching", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: "Bearer session" },
    body: JSON.stringify(body),
  });

Deno.test("rejects non-canonical identifiers and unsafe versions before matching", async () => {
  let calls = 0;
  const handler = createCashMatchingHandler({
    authorize: async () => riderId,
    match: async () => {
      calls++;
      return { bookingId, fareQuoteId: quoteId, state: "noCandidates" };
    },
  });
  for (
    const body of [
      { ...payload, booking_request_id: "../../users" },
      { ...payload, fare_quote_id: "a1230000-0000-0000-0000-000000000002" },
      { ...payload, expected_booking_version: Number.MAX_SAFE_INTEGER + 1 },
    ]
  ) {
    const response = await handler(post(body));
    if (response.status !== 400) throw new Error("invalid canonical input accepted");
  }
  if (calls !== 0) throw new Error("invalid input reached matching");
});

Deno.test("rejects a non-canonical authenticated subject before matching", async () => {
  let calls = 0;
  const handler = createCashMatchingHandler({
    authorize: async () => "not-a-uuid",
    match: async () => {
      calls++;
      return { bookingId, fareQuoteId: quoteId, state: "noCandidates" };
    },
  });
  const response = await handler(post(payload));
  if (response.status !== 403 || calls) throw new Error("invalid subject reached adapter");
});

Deno.test("upstream states outside the response allowlist fail closed", async () => {
  const handler = createCashMatchingHandler({
    authorize: async () => riderId,
    match: async () => ({ bookingId, fareQuoteId: quoteId, state: "accepted" } as never),
  });
  const response = await handler(post(payload));
  const body = await response.json();
  if (response.status !== 502 || body.error.code !== "invalid_response") {
    throw new Error("unknown upstream state escaped HTTP boundary");
  }
});

Deno.test("maps concurrent version conflicts without leaking backend detail", async () => {
  const handler = createCashMatchingHandler({
    authorize: async () => riderId,
    match: async () => {
      throw new CashMatchingError("conflict");
    },
  });
  const response = await handler(post(payload));
  const body = await response.json();
  if (
    response.status !== 409 || body.error.code !== "conflict" ||
    JSON.stringify(body).includes("service_role")
  ) {
    throw new Error("conflict response was not safely mapped");
  }
});

for (
  const bad of [null, [], { bookingId, fareQuoteId: quoteId, state: "assigned", tripId: "bad" }, {
    bookingId,
    fareQuoteId: quoteId,
    state: "noCandidates",
    tripId: riderId,
  }]
) {
  Deno.test("rejects malformed matching result " + JSON.stringify(bad), async () => {
    const handler = createCashMatchingHandler({
      authorize: async () => riderId,
      match: async () => bad as never,
    });
    const response = await handler(post(payload));
    const body = await response.json();
    if (response.status !== 502 || body.error.code !== "invalid_response") {
      throw new Error("malformed result escaped validation");
    }
  });
}

Deno.test("rate budget denies with sanitized 429 and retry delay", async () => {
  const handler = createCashMatchingHandler({
    authorize: async () => riderId,
    match: async () => {
      throw new CashMatchingError("rate_limited");
    },
  });
  const response = await handler(post(payload));
  const body = await response.json();
  if (
    response.status !== 429 || response.headers.get("retry-after") !== "60" ||
    body.error.code !== "rate_limited"
  ) throw new Error("rate response contract mismatch");
});
