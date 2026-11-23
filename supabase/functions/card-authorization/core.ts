import {
  CashMatchingError,
  type Owner,
  type Row,
} from "../_shared/matching/cash_matching_adapter.ts";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export interface AuthorizationPort {
  owner(): Promise<Owner>;
  admitRequest(): Promise<void>;
  prepare(actor: string, input: Row): Promise<unknown>;
}
function reply(status: number, body: Row): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}
async function bounded(request: Request): Promise<string> {
  const reader = request.body?.getReader();
  if (!reader) throw new Error("invalid");
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    for (;;) {
      const part = await reader.read();
      if (part.done) break;
      length += part.value.byteLength;
      if (length > 4096) {
        await reader.cancel();
        throw new Error("invalid");
      }
      chunks.push(part.value);
    }
  } finally {
    reader.releaseLock();
  }
  const joined = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    joined.set(chunk, offset);
    offset += chunk.length;
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(joined);
}
export function createCardAuthorizationHandler(
  makePort: (request: Request) => AuthorizationPort,
): (request: Request) => Promise<Response> {
  return async (request) => {
    try {
      if (
        request.method !== "POST" ||
        request.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase() !==
          "application/json"
      ) return reply(400, { error: "invalid_request" });
      let value: unknown;
      try {
        value = JSON.parse(await bounded(request));
      } catch {
        return reply(400, { error: "invalid_request" });
      }
      if (!value || typeof value !== "object" || Array.isArray(value)) {
        return reply(400, { error: "invalid_request" });
      }
      const input = value as Row;
      if (
        Object.keys(input).sort().join(",") !==
          "expected_payment_version,expected_trip_version,idempotency_key,payment_id,trip_id" ||
        typeof input.trip_id !== "string" || !uuid.test(input.trip_id) ||
        typeof input.payment_id !== "string" || !uuid.test(input.payment_id) ||
        typeof input.expected_trip_version !== "number" ||
        !Number.isSafeInteger(input.expected_trip_version) || input.expected_trip_version < 1 ||
        typeof input.expected_payment_version !== "number" ||
        !Number.isSafeInteger(input.expected_payment_version) ||
        input.expected_payment_version < 1 ||
        typeof input.idempotency_key !== "string" ||
        !/^[A-Za-z0-9:_-]{8,128}$/.test(input.idempotency_key)
      ) return reply(400, { error: "invalid_request" });
      const port = makePort(request);
      const initial = await port.owner();
      if (!uuid.test(initial.id)) throw new CashMatchingError("unauthorized");
      await port.admitRequest();
      const current = await port.owner();
      if (current.id !== initial.id || current.session !== initial.session) {
        throw new CashMatchingError("unauthorized");
      }
      const raw = await port.prepare(initial.id, input);
      const final = await port.owner();
      if (final.id !== initial.id || final.session !== initial.session) {
        throw new CashMatchingError("unauthorized");
      }
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
        throw new CashMatchingError("unknown");
      }
      const result = raw as Row;
      if (
        result.trip_id !== input.trip_id || result.payment_id !== input.payment_id ||
        result.trip_version !== input.expected_trip_version ||
        result.payment_version !== input.expected_payment_version ||
        typeof result.attempt_id !== "string" || !uuid.test(result.attempt_id) ||
        !["PENDING", "UNKNOWN"].includes(String(result.outcome))
      ) throw new CashMatchingError("unknown");
      return reply(200, {
        data: {
          trip_id: result.trip_id,
          payment_id: result.payment_id,
          attempt_id: result.attempt_id,
          outcome: result.outcome,
        },
      });
    } catch (error) {
      if (error instanceof CashMatchingError && error.code === "unauthorized") {
        return reply(401, { error: "unauthorized" });
      }
      if (error instanceof CashMatchingError && error.code === "rate_limited") {
        return reply(429, { error: "rate_limited" });
      }
      return reply(503, { error: "unavailable" });
    }
  };
}
