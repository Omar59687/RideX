import {
  type CanonicalIntentContext,
  type IntentCommand,
  type PreparedTestIntent,
  prepareTestIntent,
  TestIntentError,
  type TestIntentProvider,
} from "./test_intent_provider.ts";
import {
  DurableTestIntentProvider,
  type TestIntentReservationStore,
} from "./test_intent_reservation.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const MAX_BODY_BYTES = 4096;
const MAX_UPSTREAM_BYTES = 8192;
const DEFAULT_TIMEOUT_MS = 4000;
type RecordValue = Record<string, unknown>;
type FetchLike = (input: RequestInfo | URL, init?: RequestInit) => Response | Promise<Response>;
type RiderRate = { count: number; active: number; resetAt: number };
class InstanceRiderLimiter {
  readonly #riders = new Map<string, RiderRate>();
  acquire(riderId: string): () => void {
    const now = Date.now();
    for (const [id, rate] of this.#riders) {
      if (rate.active === 0 && rate.resetAt <= now) this.#riders.delete(id);
    }
    let rate = this.#riders.get(riderId);
    if (!rate || rate.resetAt <= now) {
      rate = { count: 0, active: 0, resetAt: now + 60_000 };
      this.#riders.set(riderId, rate);
    }
    if (rate.count >= 10 || rate.active >= 2) {
      throw new HttpError(429, "rate_limited", "Too many requests.");
    }
    rate.count++;
    rate.active++;
    let released = false;
    return () => {
      if (released) return;
      released = true;
      rate!.active = Math.max(0, rate!.active - 1);
    };
  }
}

class HttpError extends Error {
  constructor(readonly status: number, readonly code: string, readonly safeMessage: string) {
    super(code);
  }
}

export interface StripeIntentReadRequest extends IntentCommand {
  readonly riderId: string;
  readonly tripId: string;
  readonly attemptId: string;
}

export interface StripeIntentHandlerDependencies {
  readonly authorize: (request: Request) => Promise<string>;
  readonly readAuthorizedContext: (
    request: StripeIntentReadRequest,
  ) => Promise<CanonicalIntentContext | null>;
  readonly provider: TestIntentProvider;
  /** Production entrypoints leave this false until durable attempt claim/recovery and approvals exist. */
  readonly providerDispatchEnabled?: boolean;
  readonly reservationStore?: TestIntentReservationStore;
  readonly assertProviderReady?: () => void;
}

interface Outcome {
  readonly fingerprint: string;
  readonly state: "in_flight" | "unknown" | "rejected" | "prepared";
  readonly result?: PreparedTestIntent;
}

function json(status: number, value: RecordValue): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

async function readBoundedText(response: Response, maxBytes: number): Promise<string> {
  const text = await response.text();
  if (new TextEncoder().encode(text).byteLength > maxBytes) throw new Error("response_too_large");
  return text;
}

async function readJson(response: Response, maxBytes: number): Promise<unknown> {
  return JSON.parse(await readBoundedText(response, maxBytes));
}

function record(value: unknown): value is RecordValue {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function validId(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

function parseCommand(value: unknown): StripeIntentReadRequest {
  if (!record(value)) throw new HttpError(400, "invalid_request", "Request is invalid.");
  const keys = Object.keys(value).sort();
  const expected = [
    "attempt_id",
    "expected_payment_version",
    "expected_trip_version",
    "idempotency_key",
    "payment_id",
    "trip_id",
  ];
  if (keys.length !== expected.length || !keys.every((key, index) => key === expected[index])) {
    throw new HttpError(400, "invalid_request", "Request is invalid.");
  }
  const paymentId = value.payment_id;
  const tripId = value.trip_id;
  const attemptId = value.attempt_id;
  const expectedPaymentVersion = value.expected_payment_version;
  const expectedTripVersion = value.expected_trip_version;
  const idempotencyKey = value.idempotency_key;
  if (
    !validId(paymentId) || !validId(tripId) || !validId(attemptId) ||
    !Number.isSafeInteger(expectedPaymentVersion) || (expectedPaymentVersion as number) < 1 ||
    !Number.isSafeInteger(expectedTripVersion) || (expectedTripVersion as number) < 1 ||
    typeof idempotencyKey !== "string" || !/^[A-Za-z0-9:_-]{8,128}$/u.test(idempotencyKey)
  ) {
    throw new HttpError(400, "invalid_request", "Request is invalid.");
  }
  return {
    paymentId,
    tripId,
    attemptId,
    expectedPaymentVersion: expectedPaymentVersion as number,
    expectedTripVersion: expectedTripVersion as number,
    idempotencyKey,
    riderId: "", // replaced from verified Auth/profile identity by the handler
  };
}

function fingerprint(request: StripeIntentReadRequest, context: CanonicalIntentContext): string {
  return JSON.stringify([
    request.riderId,
    request.paymentId,
    request.tripId,
    request.attemptId,
    request.expectedPaymentVersion,
    request.expectedTripVersion,
    request.idempotencyKey,
    context.paymentVersion,
    context.amountFils,
    context.currency,
  ]);
}

function providerError(error: unknown): never {
  if (error instanceof TestIntentError) {
    switch (error.code) {
      case "invalid_request":
        throw new HttpError(400, "invalid_request", "Request is invalid.");
      case "forbidden":
        throw new HttpError(404, "not_found", "Payment context is unavailable.");
      case "stale_version":
        throw new HttpError(409, "stale_version", "Payment context changed.");
      case "not_configured":
        throw new HttpError(503, "not_configured", "Test preparation is unavailable.");
      case "provider_rejected":
        throw new HttpError(502, "provider_rejected", "Test provider rejected the request.");
      case "unknown_result":
        throw new HttpError(
          503,
          "outcome_unknown",
          "Preparation outcome is unknown; reconciliation is required.",
        );
      case "invalid_response":
        throw new HttpError(502, "provider_response_invalid", "Test provider response is invalid.");
    }
  }
  throw new HttpError(503, "service_unavailable", "Test preparation is unavailable.");
}

export function createStripeTestIntentHandler(
  dependencies: StripeIntentHandlerDependencies,
): (request: Request) => Promise<Response> {
  const outcomes = new Map<string, Outcome>();
  const limiter = new InstanceRiderLimiter();

  return async (request: Request): Promise<Response> => {
    let release: (() => void) | undefined;
    if (request.method !== "POST") {
      return json(405, { error: { code: "method_not_allowed", message: "POST is required." } });
    }
    if (!/^application\/json(?:\s*;|\s*$)/iu.test(request.headers.get("content-type") ?? "")) {
      return json(415, { error: { code: "unsupported_media_type", message: "JSON is required." } });
    }
    try {
      const authorization = request.headers.get("authorization") ?? "";
      if (!/^Bearer [^\s]{20,8192}$/u.test(authorization)) {
        throw new HttpError(401, "unauthorized", "Authentication is required.");
      }
      const declaredLength = Number(request.headers.get("content-length") ?? "0");
      if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
        throw new HttpError(413, "request_too_large", "Request is too large.");
      }
      const raw = await request.text();
      if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) {
        throw new HttpError(413, "request_too_large", "Request is too large.");
      }
      let parsed: unknown;
      try {
        parsed = JSON.parse(raw);
      } catch {
        throw new HttpError(400, "invalid_request", "Request is invalid.");
      }
      const command = parseCommand(parsed);
      const riderId = await dependencies.authorize(request);
      if (!validId(riderId)) throw new HttpError(403, "forbidden", "Rider access is required.");
      release = limiter.acquire(riderId);
      const readRequest = Object.freeze({ ...command, riderId });
      let context: CanonicalIntentContext | null;
      try {
        context = await dependencies.readAuthorizedContext(readRequest);
      } catch {
        throw new HttpError(503, "context_unavailable", "Payment context is unavailable.");
      }
      if (
        !context || context.paymentId !== command.paymentId || context.tripId !== command.tripId ||
        context.attemptId !== command.attemptId || context.riderId !== riderId ||
        context.idempotencyKey !== command.idempotencyKey
      ) {
        throw new HttpError(404, "not_found", "Payment context is unavailable.");
      }
      if (
        context.paymentVersion !== command.expectedPaymentVersion ||
        context.tripVersion !== command.expectedTripVersion
      ) {
        throw new HttpError(409, "stale_version", "Payment context changed.");
      }

      const key = command.idempotencyKey;
      const requestFingerprint = fingerprint(readRequest, context);
      const previous = outcomes.get(key);
      if (previous) {
        if (previous.fingerprint !== requestFingerprint) {
          throw new HttpError(
            409,
            "idempotency_conflict",
            "Operation key conflicts with an earlier request.",
          );
        }
        if (previous.state === "prepared" && previous.result) {
          return json(200, {
            data: {
              provider: previous.result.provider,
              reference: previous.result.reference,
              requires_canonical_verification: true,
              replayed: true,
            },
          });
        }
        throw new HttpError(
          409,
          previous.state === "unknown" ? "outcome_unknown" : "request_in_progress",
          previous.state === "unknown"
            ? "Preparation outcome is unknown; reconciliation is required."
            : "The request is already being processed.",
        );
      }
      if (outcomes.size >= 256) {
        throw new HttpError(
          429,
          "temporarily_unavailable",
          "Test preparation is temporarily unavailable.",
        );
      }
      if (
        !dependencies.providerDispatchEnabled || !dependencies.reservationStore ||
        !dependencies.assertProviderReady
      ) {
        throw new HttpError(503, "not_configured", "Test preparation is unavailable.");
      }

      outcomes.set(key, { fingerprint: requestFingerprint, state: "in_flight" });
      let result: PreparedTestIntent;
      try {
        result = await prepareTestIntent(
          command,
          () => Promise.resolve(context),
          new DurableTestIntentProvider(
            dependencies.reservationStore,
            dependencies.provider,
            dependencies.assertProviderReady,
          ),
        );
      } catch (error) {
        const state = error instanceof TestIntentError && error.code === "unknown_result"
          ? "unknown"
          : "rejected";
        outcomes.set(key, { fingerprint: requestFingerprint, state });
        providerError(error);
      }
      try {
        const currentRider = await dependencies.authorize(request);
        const currentContext = await dependencies.readAuthorizedContext(readRequest);
        if (
          currentRider !== riderId || !currentContext ||
          fingerprint(readRequest, currentContext) !== requestFingerprint
        ) {
          outcomes.set(key, { fingerprint: requestFingerprint, state: "unknown" });
          throw new HttpError(
            409,
            "outcome_unknown",
            "Preparation outcome is unknown; reconciliation is required.",
          );
        }
      } catch {
        outcomes.set(key, { fingerprint: requestFingerprint, state: "unknown" });
        throw new HttpError(
          409,
          "outcome_unknown",
          "Preparation outcome is unknown; reconciliation is required.",
        );
      }
      outcomes.set(key, { fingerprint: requestFingerprint, state: "prepared", result });
      return json(200, {
        data: {
          provider: result.provider,
          reference: result.reference,
          requires_canonical_verification: true,
          replayed: false,
        },
      });
    } catch (error) {
      if (error instanceof HttpError) {
        return json(error.status, { error: { code: error.code, message: error.safeMessage } });
      }
      if (error instanceof TestIntentError) {
        try {
          providerError(error);
        } catch (mapped) {
          if (mapped instanceof HttpError) {
            return json(mapped.status, {
              error: { code: mapped.code, message: mapped.safeMessage },
            });
          }
        }
      }
      return json(503, {
        error: { code: "service_unavailable", message: "Test preparation is unavailable." },
      });
    } finally {
      release?.();
    }
  };
}

export interface StripeIntentServerDependencies {
  readonly supabaseUrl: string;
  readonly anonKey: string;
  readonly serviceRoleKey: string;
  readonly fetch?: FetchLike;
  readonly timeoutMs?: number;
}

async function fetchTimed(
  fetcher: FetchLike,
  input: RequestInfo | URL,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetcher(input, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

function safeBaseUrl(value: string): URL {
  const base = new URL(value);
  if (base.protocol !== "https:" || base.username || base.password) {
    throw new Error("invalid_configuration");
  }
  return base;
}

export async function authorizeStripeTestRider(
  request: Request,
  dependencies: StripeIntentServerDependencies,
): Promise<string> {
  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer [^\s]{20,8192}$/u.test(authorization)) {
    throw new HttpError(401, "unauthorized", "Authentication is required.");
  }
  if (!dependencies.supabaseUrl || !dependencies.anonKey || !dependencies.serviceRoleKey) {
    throw new HttpError(503, "service_unavailable", "Test preparation is unavailable.");
  }
  let url: URL;
  try {
    url = new URL("/rest/v1/users", safeBaseUrl(dependencies.supabaseUrl));
  } catch {
    throw new HttpError(503, "service_unavailable", "Test preparation is unavailable.");
  }
  url.searchParams.set("select", "id,role,is_blocked");
  url.searchParams.set("limit", "2");
  let response: Response;
  try {
    response = await fetchTimed(dependencies.fetch ?? fetch, url, {
      method: "GET",
      headers: { apikey: dependencies.anonKey, authorization, accept: "application/json" },
    }, dependencies.timeoutMs ?? DEFAULT_TIMEOUT_MS);
  } catch {
    throw new HttpError(503, "service_unavailable", "Test preparation is unavailable.");
  }
  if (response.status === 401 || response.status === 403) {
    throw new HttpError(401, "unauthorized", "Authentication is required.");
  }
  if (!response.ok) {
    throw new HttpError(503, "service_unavailable", "Test preparation is unavailable.");
  }
  let payload: unknown;
  try {
    payload = await readJson(response, 4096);
  } catch {
    throw new HttpError(503, "service_unavailable", "Test preparation is unavailable.");
  }
  if (!Array.isArray(payload) || payload.length !== 1 || !record(payload[0])) {
    throw new HttpError(403, "forbidden", "Rider access is required.");
  }
  const user = payload[0];
  if (!validId(user.id) || user.role !== "rider" || user.is_blocked !== false) {
    throw new HttpError(403, "forbidden", "Rider access is required.");
  }
  return user.id;
}

function oneRow(value: unknown): RecordValue | null {
  return Array.isArray(value) && value.length === 1 && record(value[0]) ? value[0] : null;
}

async function getRows(
  dependencies: StripeIntentServerDependencies,
  path: string,
): Promise<unknown> {
  const url = new URL(path, safeBaseUrl(dependencies.supabaseUrl));
  const fetcher = dependencies.fetch ?? fetch;
  const response = await fetchTimed(fetcher, url, {
    method: "GET",
    headers: {
      apikey: dependencies.serviceRoleKey,
      authorization: `Bearer ${dependencies.serviceRoleKey}`,
      accept: "application/json",
    },
  }, dependencies.timeoutMs ?? DEFAULT_TIMEOUT_MS);
  if (!response.ok) throw new Error("canonical_read_failed");
  return await readJson(response, MAX_UPSTREAM_BYTES);
}

export function createCanonicalIntentContextReader(
  dependencies: StripeIntentServerDependencies,
): (request: StripeIntentReadRequest) => Promise<CanonicalIntentContext | null> {
  return async (request) => {
    if (
      !dependencies.supabaseUrl || !dependencies.serviceRoleKey ||
      !validId(request.riderId) || !validId(request.paymentId) ||
      !validId(request.tripId) || !validId(request.attemptId)
    ) throw new Error("invalid_configuration");

    const paymentQuery = new URLSearchParams({
      select:
        "id,trip_id,rider_id,method,card_status,authorized_amount_fils,final_amount_fils,currency,version",
      id: `eq.${request.paymentId}`,
      rider_id: `eq.${request.riderId}`,
      limit: "2",
    });
    const payments = await getRows(dependencies, `/rest/v1/payments?${paymentQuery}`);
    const payment = oneRow(payments);
    if (!payment) return null;
    if (
      payment.id !== request.paymentId || payment.rider_id !== request.riderId ||
      payment.trip_id !== request.tripId || payment.method !== "card" ||
      payment.card_status !== "cardPaymentPending" || payment.currency !== "JOD" ||
      !Number.isSafeInteger(payment.version) || (payment.version as number) < 1 ||
      !Number.isSafeInteger(payment.authorized_amount_fils) ||
      (payment.authorized_amount_fils as number) <= 0 ||
      !Number.isSafeInteger(payment.final_amount_fils) ||
      payment.final_amount_fils !== payment.authorized_amount_fils
    ) return null;

    const tripQuery = new URLSearchParams({
      select:
        "id,rider_id,driver_id,status,payment_method,currency,original_fare_fils,current_fare_fils,version",
      id: `eq.${request.tripId}`,
      rider_id: `eq.${request.riderId}`,
      limit: "2",
    });
    const trip = oneRow(await getRows(dependencies, `/rest/v1/trips?${tripQuery}`));
    if (
      !trip || trip.id !== request.tripId || trip.rider_id !== request.riderId ||
      !validId(trip.driver_id) || !Number.isSafeInteger(trip.version) ||
      (trip.version as number) < 1 || trip.status !== "accepted" ||
      trip.payment_method !== "card" ||
      trip.currency !== "JOD" || !Number.isSafeInteger(trip.original_fare_fils) ||
      trip.original_fare_fils !== payment.authorized_amount_fils ||
      !Number.isSafeInteger(trip.current_fare_fils) ||
      trip.current_fare_fils !== payment.final_amount_fils
    ) return null;

    const attemptQuery = new URLSearchParams({
      select:
        "id,payment_id,type,status,requested_amount_fils,currency,idempotency_key,authorization_cycle",
      id: `eq.${request.attemptId}`,
      payment_id: `eq.${request.paymentId}`,
      idempotency_key: `eq.${request.idempotencyKey}`,
      limit: "2",
    });
    const attempt = oneRow(
      await getRows(dependencies, `/rest/v1/payment_attempts?${attemptQuery}`),
    );
    if (
      !attempt || attempt.id !== request.attemptId || attempt.payment_id !== request.paymentId ||
      attempt.type !== "initialAuthorization" || attempt.status !== "pending" ||
      attempt.requested_amount_fils !== payment.authorized_amount_fils ||
      attempt.currency !== payment.currency || attempt.idempotency_key !== request.idempotencyKey ||
      attempt.authorization_cycle !== 1
    ) return null;

    return Object.freeze({
      paymentId: payment.id as string,
      attemptId: attempt.id as string,
      riderId: payment.rider_id as string,
      paymentVersion: payment.version as number,
      tripVersion: trip.version as number,
      tripId: trip.id as string,
      driverId: trip.driver_id as string,
      tripStatus: trip.status as string,
      method: payment.method as string,
      paymentStatus: payment.card_status as string,
      amountFils: payment.authorized_amount_fils as number,
      currency: payment.currency as string,
      idempotencyKey: attempt.idempotency_key as string,
    });
  };
}
