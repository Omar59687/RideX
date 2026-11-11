import {
  CashMatchingError,
  type MatchingResult,
} from "../_shared/matching/cash_matching_adapter.ts";

const MAX_REQUEST_BYTES = 4096;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

export type MatchInput = {
  bookingId: string;
  quoteId: string;
  expectedBookingVersion: number;
};
export type Authorize = (request: Request) => Promise<string>;
export type Match = (input: MatchInput, request: Request) => Promise<MatchingResult>;

export interface CashMatchingHandlerDependencies {
  authorize: Authorize;
  match: Match;
}

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly safeMessage: string,
  ) {
    super(code);
  }
}

function json(status: number, body: unknown, headers?: HeadersInit): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
      "x-content-type-options": "nosniff",
      ...headers,
    },
  });
}

function parseInput(value: unknown): MatchInput {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(400, "invalid_request", "Request is invalid.");
  }
  const body = value as Record<string, unknown>;
  const keys = Object.keys(body).sort();
  if (
    keys.join(",") !==
      "booking_request_id,expected_booking_version,fare_quote_id" ||
    typeof body.booking_request_id !== "string" ||
    !UUID.test(body.booking_request_id) ||
    typeof body.fare_quote_id !== "string" ||
    !UUID.test(body.fare_quote_id) ||
    typeof body.expected_booking_version !== "number" ||
    !Number.isSafeInteger(body.expected_booking_version) ||
    body.expected_booking_version < 1
  ) {
    throw new HttpError(400, "invalid_request", "Request is invalid.");
  }
  return {
    bookingId: body.booking_request_id,
    quoteId: body.fare_quote_id,
    expectedBookingVersion: body.expected_booking_version,
  };
}

async function readBoundedBody(request: Request): Promise<string> {
  const reader = request.body?.getReader();
  if (!reader) throw new HttpError(400, "invalid_request", "Request is invalid.");
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      length += part.value.byteLength;
      if (length > MAX_REQUEST_BYTES) {
        await reader.cancel();
        throw new HttpError(400, "invalid_request", "Request is invalid.");
      }
      chunks.push(part.value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw new HttpError(400, "invalid_request", "Request is invalid.");
  }
}

function mapMatchingError(error: unknown): HttpError {
  if (error instanceof CashMatchingError) {
    return switchMatchingError(error.code);
  }
  return new HttpError(503, "unknown", "Matching outcome is unresolved.");
}

function switchMatchingError(
  code: CashMatchingError["code"],
): HttpError {
  switch (code) {
    case "unauthorized":
      return new HttpError(403, code, "Rider access is required.");
    case "invalid_request":
      return new HttpError(400, code, "Request is invalid.");
    case "conflict":
      return new HttpError(409, code, "Booking changed. Check its status.");
    case "invalid_state":
      return new HttpError(422, code, "Booking cannot enter matching.");
    case "unknown":
      return new HttpError(503, code, "Matching outcome is unresolved.");
  }
}

/**
 * HTTP boundary for the existing A05 CashMatchingAdapter. It accepts no Rider,
 * Driver, coordinate, fare, payment, service-key, or caller-selected RPC data.
 */
export function createCashMatchingHandler(
  dependencies: CashMatchingHandlerDependencies,
): (request: Request) => Promise<Response> {
  return async (request: Request): Promise<Response> => {
    try {
      if (request.method !== "POST") {
        throw new HttpError(405, "method_not_allowed", "Method is not allowed.");
      }
      if (
        request.headers.get("content-type")?.split(";", 1)[0].trim()
          .toLowerCase() !== "application/json"
      ) {
        throw new HttpError(400, "invalid_request", "Request is invalid.");
      }
      const declaredLength = Number(request.headers.get("content-length"));
      if (Number.isFinite(declaredLength) && declaredLength > MAX_REQUEST_BYTES) {
        throw new HttpError(400, "invalid_request", "Request is invalid.");
      }
      let callerId: string;
      try {
        callerId = await dependencies.authorize(request);
      } catch {
        throw new HttpError(401, "unauthorized", "Authentication is required.");
      }
      if (!UUID.test(callerId)) {
        throw new HttpError(403, "forbidden", "Rider access is required.");
      }
      const text = await readBoundedBody(request);
      let parsed: unknown;
      try {
        parsed = JSON.parse(text);
      } catch {
        throw new HttpError(400, "invalid_request", "Request is invalid.");
      }
      const input = parseInput(parsed);
      const result = await dependencies.match(input, request);
      if (
        result.bookingId !== input.bookingId ||
        result.fareQuoteId !== input.quoteId ||
        (result.state === "assigned" && !UUID.test(result.tripId ?? "")) ||
        (result.state !== "assigned" && result.tripId !== undefined)
      ) {
        throw new HttpError(502, "invalid_response", "Matching response is invalid.");
      }
      return json(200, {
        data: {
          booking_id: result.bookingId,
          fare_quote_id: result.fareQuoteId,
          state: result.state,
          ...(result.tripId ? { trip_id: result.tripId } : {}),
        },
      });
    } catch (error) {
      const safe = error instanceof HttpError ? error : mapMatchingError(error);
      return json(safe.status, {
        error: { code: safe.code, message: safe.safeMessage },
      }, safe.status === 405 ? { allow: "POST" } : undefined);
    }
  };
}
