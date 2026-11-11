import { CashMatchingError } from "../_shared/matching/cash_matching_adapter.ts";
import { createCashMatchingHandler } from "./core.ts";

const bookingId = "a1230000-0000-4000-8000-000000000001";
const quoteId = "a1230000-0000-4000-8000-000000000002";
const tripId = "a1230000-0000-4000-8000-000000000003";
const riderId = "a1230000-0000-4000-8000-000000000004";
const input = {
  booking_request_id: bookingId,
  fare_quote_id: quoteId,
  expected_booking_version: 3,
};
const request = (body: unknown, method = "POST") => new Request(
  "https://ridex.test/functions/v1/cash-matching",
  {
    method,
    headers: { "content-type": "application/json", authorization: "Bearer rider" },
    body: method === "POST" ? JSON.stringify(body) : undefined,
  },
);

Deno.test("cash matching authorizes before calling the existing adapter contract", async () => {
  let calls = 0;
  let captured: unknown;
  const handler = createCashMatchingHandler({
    authorize: async () => riderId,
    match: async (value) => {
      calls++;
      captured = value;
      return { bookingId, fareQuoteId: quoteId, state: "awaitingDriver" };
    },
  });
  const response = await handler(request(input));
  const body = await response.json();
  if (
    response.status !== 200 || calls !== 1 ||
    JSON.stringify(captured) !== JSON.stringify({
      bookingId,
      quoteId,
      expectedBookingVersion: 3,
    }) || body.data.state !== "awaitingDriver" || body.data.trip_id !== undefined
  ) throw new Error("authorized bounded matching response failed");
});

Deno.test("assignment response returns only the validated canonical Trip locator", async () => {
  const handler = createCashMatchingHandler({
    authorize: async () => riderId,
    match: async () => ({ bookingId, fareQuoteId: quoteId, state: "assigned", tripId }),
  });
  const response = await handler(request(input));
  const body = await response.json();
  if (response.status !== 200 || body.data.trip_id !== tripId) {
    throw new Error("assigned result was not serialized");
  }
});

Deno.test("unauthorized Rider never invokes matching", async () => {
  let calls = 0;
  const handler = createCashMatchingHandler({
    authorize: async () => { throw new Error("denied"); },
    match: async () => {
      calls++;
      return { bookingId, fareQuoteId: quoteId, state: "noCandidates" };
    },
  });
  const response = await handler(request(input));
  if (response.status !== 401 || calls !== 0) {
    throw new Error("unauthorized request reached matching");
  }
});

Deno.test("extra caller authority fields are rejected", async () => {
  let calls = 0;
  const handler = createCashMatchingHandler({
    authorize: async () => riderId,
    match: async () => {
      calls++;
      return { bookingId, fareQuoteId: quoteId, state: "noCandidates" };
    },
  });
  const response = await handler(request({ ...input, driver_id: tripId }));
  if (response.status !== 400 || calls !== 0) {
    throw new Error("caller-selected Driver field was accepted");
  }
});

Deno.test("malformed and oversized data is rejected without dispatch", async () => {
  let calls = 0;
  const handler = createCashMatchingHandler({
    authorize: async () => riderId,
    match: async () => {
      calls++;
      return { bookingId, fareQuoteId: quoteId, state: "noCandidates" };
    },
  });
  const malformed = await handler(request({ ...input, expected_booking_version: 0 }));
  const oversized = await handler(new Request(
    "https://ridex.test/functions/v1/cash-matching",
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ...input, padding: "x".repeat(5000) }),
    },
  ));
  if (malformed.status !== 400 || oversized.status !== 400 || calls !== 0) {
    throw new Error("malformed request reached matching");
  }
});

Deno.test("unknown outcomes stay unresolved and matching errors are sanitized", async () => {
  const handler = createCashMatchingHandler({
    authorize: async () => riderId,
    match: async () => { throw new CashMatchingError("unknown"); },
  });
  const response = await handler(request(input));
  const body = await response.json();
  if (
    response.status !== 503 || body.error.code !== "unknown" ||
    JSON.stringify(body).includes("service_role")
  ) throw new Error("unknown outcome was not safely represented");
});
