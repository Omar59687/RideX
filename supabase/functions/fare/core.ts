// Fare Edge function core: authenticated, server-authoritative quote creation.
//
// Flutter supplies only a booking id and optimistic version. The function binds
// the booking to the authenticated rider, loads the canonical route snapshot,
// asks Google Routes for trusted metrics, and only then invokes the
// service-role-only fare RPC. Phone-supplied distance/duration are never trusted.
const BACKEND_QUOTE_RPC = "/rest/v1/rpc/backend_calculate_fare_quote";
const BOOKING_REQUESTS_REST = "/rest/v1/booking_requests";
const BOOKING_STOPS_REST = "/rest/v1/booking_stops";
const GOOGLE_ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes";
const GOOGLE_ROUTES_MASK = "routes.distanceMeters,routes.duration";

const MAX_REQUEST_BYTES = 4096;
const MAX_UPSTREAM_BYTES = 32 * 1024;
const DEFAULT_UPSTREAM_TIMEOUT_MS = 8000;
const DEFAULT_AUTH_TIMEOUT_MS = 4000;
const RATE_WINDOW_MS = 60000;
const MAX_CONCURRENT_REQUESTS_PER_USER = 2;
const QUOTE_RATE_LIMIT = 10;

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const QUOTE_STATUSES = ["calculated", "locked", "expired", "superseded"] as const;
const BREAKDOWN_KEYS = [
  "base_fare_fils",
  "distance_fils",
  "duration_fils",
  "stops_fils",
  "subtotal_fils",
  "minimum_fare_fils",
  "rounding_increment_fils",
  "fixed_fare_fils",
] as const;

type JsonRecord = Record<string, unknown>;
export type FetchLike = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Response | Promise<Response>;
export type Authorize = (request: Request) => Promise<string>;
export type CalculateFare = (input: {
  riderId: string;
  bookingRequestId: string;
  expectedBookingVersion: number;
}) => Promise<JsonRecord>;

export interface FareHandlerDependencies {
  authorize: Authorize;
  calculateFare: CalculateFare;
  fetch?: FetchLike;
  now?: () => number;
}

export interface BackendQuoteCallerDependencies {
  supabaseUrl: string;
  serviceRoleKey: string;
  googleRoutesApiKey: string;
  fetch?: FetchLike;
  timeoutMs?: number;
}

export interface CallerAuthorizationDependencies {
  supabaseUrl: string;
  supabaseAnonKey: string;
  fetch?: FetchLike;
  timeoutMs?: number;
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

class InstanceRateLimiter {
  private count = 0;
  private concurrent = 0;
  private windowStartedAt: number | null = null;

  constructor(private readonly now: () => number) {}

  // Bounds one warm Edge instance only, mirroring the places function.
  acquire(): () => void {
    const now = this.now();
    if (this.windowStartedAt === null || now - this.windowStartedAt >= RATE_WINDOW_MS) {
      this.windowStartedAt = now;
      this.count = 0;
    }
    if (this.concurrent >= MAX_CONCURRENT_REQUESTS_PER_USER || this.count >= QUOTE_RATE_LIMIT) {
      throw new HttpError(429, "rate_limited", "Too many requests.");
    }
    this.count++;
    this.concurrent++;
    let released = false;
    return () => {
      if (released) return;
      released = true;
      this.concurrent = Math.max(0, this.concurrent - 1);
    };
  }
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function invalidRequest(): HttpError {
  return new HttpError(400, "invalid_request", "Request is invalid.");
}

function uuid(value: unknown): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw invalidRequest();
  }
  return value;
}

function positiveVersion(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 1) {
    throw invalidRequest();
  }
  return value;
}

function jsonResponse(status: number, body: unknown, extraHeaders?: HeadersInit): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
      "x-content-type-options": "nosniff",
      ...extraHeaders,
    },
  });
}

async function readJson(response: Response, maximumBytes: number): Promise<unknown> {
  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new Error("response_too_large");
  }
  const text = await response.text();
  if (new TextEncoder().encode(text).byteLength > maximumBytes) {
    throw new Error("response_too_large");
  }
  return JSON.parse(text);
}

async function fetchWithTimeout(
  fetchImpl: FetchLike,
  input: RequestInfo | URL,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetchImpl(input, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === "AbortError";
}

function nonNegativeFils(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new HttpError(502, "quote_response_invalid", "Fare service response is invalid.");
  }
  return value;
}

function positiveVersionField(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) {
    throw new HttpError(502, "quote_response_invalid", "Fare service response is invalid.");
  }
  return value;
}

function quoteId(value: unknown): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw new HttpError(502, "quote_response_invalid", "Fare service response is invalid.");
  }
  return value;
}

function quoteTimestamp(value: unknown): string {
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) {
    throw new HttpError(502, "quote_response_invalid", "Fare service response is invalid.");
  }
  return value;
}

function normalizeQuote(payload: unknown): JsonRecord {
  if (!isRecord(payload)) {
    throw new HttpError(502, "quote_response_invalid", "Fare service response is invalid.");
  }
  const breakdown = payload.breakdown;
  if (!isRecord(breakdown)) {
    throw new HttpError(502, "quote_response_invalid", "Fare service response is invalid.");
  }
  const breakdownKeys = Object.keys(breakdown).sort();
  const expectedKeys = [...BREAKDOWN_KEYS].sort();
  if (
    breakdownKeys.length !== expectedKeys.length ||
    !breakdownKeys.every((key, index) => key === expectedKeys[index])
  ) {
    throw new HttpError(502, "quote_response_invalid", "Fare service response is invalid.");
  }
  const status = payload.status;
  if (typeof status !== "string" || !(QUOTE_STATUSES as readonly string[]).includes(status)) {
    throw new HttpError(502, "quote_response_invalid", "Fare service response is invalid.");
  }
  if (payload.currency !== "JOD") {
    throw new HttpError(502, "quote_response_invalid", "Fare service response is invalid.");
  }
  const distanceMeters = payload.route_distance_meters;
  const durationSeconds = payload.route_duration_seconds;
  if (
    typeof distanceMeters !== "number" ||
    !Number.isSafeInteger(distanceMeters) ||
    distanceMeters < 0 ||
    typeof durationSeconds !== "number" ||
    !Number.isSafeInteger(durationSeconds) ||
    durationSeconds < 0
  ) {
    throw new HttpError(502, "quote_response_invalid", "Fare service response is invalid.");
  }
  return {
    id: quoteId(payload.id),
    booking_request_id: quoteId(payload.booking_request_id),
    quote_version: positiveVersionField(payload.quote_version),
    pricing_version: positiveVersionField(payload.pricing_version),
    fixed_fare_fils: nonNegativeFils(payload.fixed_fare_fils),
    breakdown: {
      base_fare_fils: nonNegativeFils(breakdown.base_fare_fils),
      distance_fils: nonNegativeFils(breakdown.distance_fils),
      duration_fils: nonNegativeFils(breakdown.duration_fils),
      stops_fils: nonNegativeFils(breakdown.stops_fils),
      subtotal_fils: nonNegativeFils(breakdown.subtotal_fils),
      minimum_fare_fils: nonNegativeFils(breakdown.minimum_fare_fils),
      rounding_increment_fils: positiveVersionField(breakdown.rounding_increment_fils),
      fixed_fare_fils: nonNegativeFils(breakdown.fixed_fare_fils),
    },
    currency: "JOD",
    status,
    expires_at: quoteTimestamp(payload.expires_at),
    created_at: quoteTimestamp(payload.created_at),
    route_distance_meters: distanceMeters,
    route_duration_seconds: durationSeconds,
  };
}

function mapRpcFailure(status: number, payload: unknown): HttpError {
  let code = "";
  let message = "";
  if (isRecord(payload)) {
    if (typeof payload.code === "string") code = payload.code;
    if (typeof payload.message === "string") message = payload.message;
  }
  if (status === 40001 || code === "40001") {
    return new HttpError(409, "version_conflict", "Booking changed. Request a new fare.");
  }
  if (code === "P0002") {
    return new HttpError(404, "not_found", "Booking draft was not found.");
  }
  if (code === "42501") {
    return new HttpError(403, "forbidden", "Rider access is required.");
  }
  if (code === "55000") {
    if (message.toLowerCase().includes("pricing configuration")) {
      // Pricing-config seeding is owner-ops; never leak backend wording.
      return new HttpError(503, "no_pricing_configuration", "Fare is unavailable.");
    }
    return new HttpError(422, "fare_unavailable", "Fare cannot be calculated for this booking.");
  }
  if (code === "22003") {
    return new HttpError(422, "fare_unavailable", "Fare cannot be calculated for this booking.");
  }
  if (code === "22023") {
    return invalidRequest();
  }
  return new HttpError(500, "internal_error", "Request could not be completed.");
}

export function createBackendQuoteCaller(
  dependencies: BackendQuoteCallerDependencies,
): CalculateFare {
  const fetchImpl = dependencies.fetch ?? fetch;
  const timeoutMs = dependencies.timeoutMs ?? DEFAULT_UPSTREAM_TIMEOUT_MS;

  const serviceHeaders = {
    apikey: dependencies.serviceRoleKey,
    authorization: `Bearer ${dependencies.serviceRoleKey}`,
    accept: "application/json",
  };

  async function serviceJson(url: URL): Promise<unknown> {
    let response: Response;
    try {
      response = await fetchWithTimeout(fetchImpl, url, {
        method: "GET",
        headers: serviceHeaders,
      }, timeoutMs);
    } catch (error) {
      if (isAbortError(error)) {
        throw new HttpError(504, "provider_timeout", "Fare request timed out.");
      }
      throw new HttpError(503, "service_unavailable", "Fare service is unavailable.");
    }
    if (!response.ok) {
      throw new HttpError(503, "service_unavailable", "Fare service is unavailable.");
    }
    try {
      return await readJson(response, MAX_UPSTREAM_BYTES);
    } catch {
      throw new HttpError(502, "quote_response_invalid", "Fare service response is invalid.");
    }
  }

  function routePoint(value: unknown): { latitude: number; longitude: number } {
    if (!isRecord(value)) {
      throw new HttpError(422, "fare_unavailable", "Fare cannot be calculated for this booking.");
    }
    const latitude = value.latitude;
    const longitude = value.longitude;
    if (
      typeof latitude !== "number" || !Number.isFinite(latitude) ||
      latitude < -90 || latitude > 90 ||
      typeof longitude !== "number" || !Number.isFinite(longitude) ||
      longitude < -180 || longitude > 180
    ) {
      throw new HttpError(422, "fare_unavailable", "Fare cannot be calculated for this booking.");
    }
    return { latitude, longitude };
  }

  return async (input) => {
    if (
      !dependencies.supabaseUrl ||
      !dependencies.serviceRoleKey ||
      !dependencies.googleRoutesApiKey
    ) {
      throw new HttpError(503, "service_unavailable", "Fare service is unavailable.");
    }

    let bookingsUrl: URL;
    let stopsUrl: URL;
    let rpcUrl: URL;
    try {
      bookingsUrl = new URL(BOOKING_REQUESTS_REST, dependencies.supabaseUrl);
      stopsUrl = new URL(BOOKING_STOPS_REST, dependencies.supabaseUrl);
      rpcUrl = new URL(BACKEND_QUOTE_RPC, dependencies.supabaseUrl);
    } catch {
      throw new HttpError(503, "service_unavailable", "Fare service is unavailable.");
    }

    bookingsUrl.searchParams.set(
      "select",
      "id,rider_id,status,pickup,destination,version",
    );
    bookingsUrl.searchParams.set("id", `eq.${input.bookingRequestId}`);
    bookingsUrl.searchParams.set("rider_id", `eq.${input.riderId}`);
    bookingsUrl.searchParams.set("limit", "2");

    const bookingPayload = await serviceJson(bookingsUrl);
    if (
      !Array.isArray(bookingPayload) ||
      bookingPayload.length !== 1 ||
      !isRecord(bookingPayload[0])
    ) {
      throw new HttpError(404, "not_found", "Booking draft was not found.");
    }
    const booking = bookingPayload[0];
    if (booking.status !== "draft") {
      throw new HttpError(422, "fare_unavailable", "Fare cannot be calculated for this booking.");
    }
    if (
      typeof booking.version !== "number" ||
      !Number.isSafeInteger(booking.version) ||
      booking.version !== input.expectedBookingVersion
    ) {
      throw new HttpError(409, "version_conflict", "Booking changed. Request a new fare.");
    }

    const origin = routePoint(booking.pickup);
    const destination = routePoint(booking.destination);
    if (
      origin.latitude === destination.latitude &&
      origin.longitude === destination.longitude
    ) {
      throw new HttpError(422, "fare_unavailable", "Fare cannot be calculated for this booking.");
    }

    stopsUrl.searchParams.set("select", "sequence,location");
    stopsUrl.searchParams.set("booking_request_id", `eq.${input.bookingRequestId}`);
    stopsUrl.searchParams.set("order", "sequence.asc");
    stopsUrl.searchParams.set("limit", "4");
    const stopsPayload = await serviceJson(stopsUrl);
    if (!Array.isArray(stopsPayload) || stopsPayload.length > 3) {
      throw new HttpError(422, "fare_unavailable", "Fare cannot be calculated for this booking.");
    }
    const intermediates = stopsPayload.map((entry, index) => {
      if (
        !isRecord(entry) ||
        entry.sequence !== index + 1
      ) {
        throw new HttpError(422, "fare_unavailable", "Fare cannot be calculated for this booking.");
      }
      return routePoint(entry.location);
    });
    const allPoints = [origin, ...intermediates, destination];
    for (let index = 0; index < allPoints.length; index++) {
      for (let other = index + 1; other < allPoints.length; other++) {
        if (
          allPoints[index].latitude === allPoints[other].latitude &&
          allPoints[index].longitude === allPoints[other].longitude
        ) {
          throw new HttpError(422, "fare_unavailable", "Fare cannot be calculated for this booking.");
        }
      }
    }

    let routeResponse: Response;
    try {
      routeResponse = await fetchWithTimeout(fetchImpl, GOOGLE_ROUTES_URL, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-goog-api-key": dependencies.googleRoutesApiKey,
          "x-goog-fieldmask": GOOGLE_ROUTES_MASK,
        },
        body: JSON.stringify({
          origin: { location: { latLng: origin } },
          destination: { location: { latLng: destination } },
          ...(intermediates.length > 0
            ? {
              intermediates: intermediates.map((point) => ({
                location: { latLng: point },
              })),
            }
            : {}),
          travelMode: "DRIVE",
          routingPreference: "TRAFFIC_AWARE",
          computeAlternativeRoutes: false,
          units: "METRIC",
        }),
      }, timeoutMs);
    } catch (error) {
      if (isAbortError(error)) {
        throw new HttpError(504, "provider_timeout", "Fare request timed out.");
      }
      throw new HttpError(502, "provider_unavailable", "Routing provider is unavailable.");
    }
    if (!routeResponse.ok) {
      throw new HttpError(502, "provider_unavailable", "Routing provider is unavailable.");
    }

    let routePayload: unknown;
    try {
      routePayload = await readJson(routeResponse, MAX_UPSTREAM_BYTES);
    } catch {
      throw new HttpError(502, "provider_response_invalid", "Routing provider response is invalid.");
    }
    if (
      !isRecord(routePayload) ||
      !Array.isArray(routePayload.routes) ||
      routePayload.routes.length === 0 ||
      !isRecord(routePayload.routes[0])
    ) {
      throw new HttpError(502, "provider_response_invalid", "Routing provider response is invalid.");
    }
    const route = routePayload.routes[0];
    const distanceMeters = route.distanceMeters;
    const durationMatch = typeof route.duration === "string"
      ? /^([1-9]\d*)s$/u.exec(route.duration)
      : null;
    const durationSeconds = durationMatch ? Number(durationMatch[1]) : 0;
    if (
      typeof distanceMeters !== "number" ||
      !Number.isSafeInteger(distanceMeters) ||
      distanceMeters <= 0 ||
      !Number.isSafeInteger(durationSeconds) ||
      durationSeconds <= 0
    ) {
      throw new HttpError(502, "provider_response_invalid", "Routing provider response is invalid.");
    }

    let response: Response;
    try {
      response = await fetchWithTimeout(fetchImpl, rpcUrl, {
        method: "POST",
        headers: {
          ...serviceHeaders,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          target_booking_request_id: input.bookingRequestId,
          expected_booking_version: input.expectedBookingVersion,
          requested_route_distance_meters: distanceMeters,
          requested_route_duration_seconds: durationSeconds,
          requested_route_geometry_reference: null,
        }),
      }, timeoutMs);
    } catch (error) {
      if (isAbortError(error)) {
        throw new HttpError(504, "provider_timeout", "Fare request timed out.");
      }
      throw new HttpError(503, "service_unavailable", "Fare service is unavailable.");
    }
    if (!response.ok) {
      let payload: unknown = null;
      try {
        payload = await readJson(response, MAX_UPSTREAM_BYTES);
      } catch {
        payload = null;
      }
      throw mapRpcFailure(response.status, payload);
    }
    let payload: unknown;
    try {
      payload = await readJson(response, MAX_UPSTREAM_BYTES);
    } catch {
      throw new HttpError(502, "quote_response_invalid", "Fare service response is invalid.");
    }
    const row = Array.isArray(payload) && payload.length === 1 ? payload[0] : payload;
    return normalizeQuote(row);
  };
}

export function createFareHandler(
  dependencies: FareHandlerDependencies,
): (request: Request) => Promise<Response> {
  const limiter = new InstanceRateLimiter(dependencies.now ?? Date.now);

  return async (request: Request): Promise<Response> => {
    try {
      if (request.method !== "POST") {
        throw new HttpError(405, "method_not_allowed", "Method is not allowed.");
      }
      const contentType = request.headers.get("content-type")?.split(";", 1)[0].trim()
        .toLowerCase();
      if (contentType !== "application/json") throw invalidRequest();

      const declaredLength = Number(request.headers.get("content-length"));
      if (Number.isFinite(declaredLength) && declaredLength > MAX_REQUEST_BYTES) {
        throw invalidRequest();
      }

      const callerId = await dependencies.authorize(request);

      const text = await request.text();
      if (new TextEncoder().encode(text).byteLength > MAX_REQUEST_BYTES) throw invalidRequest();
      let body: unknown;
      try {
        body = JSON.parse(text);
      } catch {
        throw invalidRequest();
      }
      if (!isRecord(body) || body.operation !== "quote") {
        throw new HttpError(400, "unsupported_operation", "Operation is not supported.");
      }
      const allowedKeys = new Set([
        "operation",
        "booking_request_id",
        "expected_booking_version",
      ]);
      for (const key of Object.keys(body)) {
        if (!allowedKeys.has(key)) throw invalidRequest();
      }
      const quoteInput = {
        riderId: callerId,
        bookingRequestId: uuid(body.booking_request_id),
        expectedBookingVersion: positiveVersion(body.expected_booking_version),
      };

      const release = limiter.acquire();
      try {
        const data = await dependencies.calculateFare(quoteInput);
        return jsonResponse(200, { data });
      } finally {
        release();
      }
    } catch (error) {
      const safeError = error instanceof HttpError
        ? error
        : new HttpError(500, "internal_error", "Request could not be completed.");
      const headers = safeError.status === 405 ? { allow: "POST" } : undefined;
      return jsonResponse(safeError.status, {
        error: { code: safeError.code, message: safeError.safeMessage },
      }, headers);
    }
  };
}

export async function authorizeCaller(
  request: Request,
  dependencies: CallerAuthorizationDependencies,
): Promise<string> {
  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer [^\s]{20,8192}$/u.test(authorization)) {
    throw new HttpError(401, "unauthorized", "Authentication is required.");
  }
  if (!dependencies.supabaseUrl || !dependencies.supabaseAnonKey) {
    throw new HttpError(503, "service_unavailable", "Fare service is unavailable.");
  }

  let usersUrl: URL;
  try {
    usersUrl = new URL("/rest/v1/users", dependencies.supabaseUrl);
  } catch {
    throw new HttpError(503, "service_unavailable", "Fare service is unavailable.");
  }
  usersUrl.searchParams.set("select", "id,role,is_blocked");
  usersUrl.searchParams.set("limit", "2");

  let response: Response;
  try {
    response = await fetchWithTimeout(dependencies.fetch ?? fetch, usersUrl, {
      method: "GET",
      headers: {
        apikey: dependencies.supabaseAnonKey,
        authorization,
        accept: "application/json",
      },
    }, dependencies.timeoutMs ?? DEFAULT_AUTH_TIMEOUT_MS);
  } catch {
    throw new HttpError(503, "service_unavailable", "Fare service is unavailable.");
  }

  if (response.status === 401 || response.status === 403) {
    throw new HttpError(401, "unauthorized", "Authentication is required.");
  }
  if (!response.ok) {
    throw new HttpError(503, "service_unavailable", "Fare service is unavailable.");
  }

  let payload: unknown;
  try {
    payload = await readJson(response, 4096);
  } catch {
    throw new HttpError(503, "service_unavailable", "Fare service is unavailable.");
  }
  if (!Array.isArray(payload) || payload.length !== 1 || !isRecord(payload[0])) {
    throw new HttpError(403, "forbidden", "Rider access is required.");
  }
  const caller = payload[0];
  if (
    typeof caller.id !== "string" ||
    !UUID_PATTERN.test(caller.id) ||
    caller.role !== "rider" || caller.is_blocked !== false
  ) {
    throw new HttpError(403, "forbidden", "Rider access is required.");
  }
  return caller.id;
}
