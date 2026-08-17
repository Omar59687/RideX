const AUTOCOMPLETE_URL = "https://places.googleapis.com/v1/places:autocomplete";
const PLACE_DETAILS_URL = "https://places.googleapis.com/v1/places";
const FORWARD_GEOCODE_URL = "https://geocode.googleapis.com/v4/geocode/address";
const REVERSE_GEOCODE_URL = "https://geocode.googleapis.com/v4/geocode/location";

const AUTOCOMPLETE_MASK = [
  "suggestions.placePrediction.placeId",
  "suggestions.placePrediction.text.text",
  "suggestions.placePrediction.structuredFormat.mainText.text",
  "suggestions.placePrediction.structuredFormat.secondaryText.text",
].join(",");
const PLACE_DETAILS_MASK = "id,formattedAddress,location";
const GEOCODE_MASK = "results.place,results.formattedAddress,results.location";

const MAX_REQUEST_BYTES = 4096;
const MAX_UPSTREAM_BYTES = 256 * 1024;
const DEFAULT_UPSTREAM_TIMEOUT_MS = 8000;
const DEFAULT_AUTH_TIMEOUT_MS = 4000;
const AUTOCOMPLETE_BIAS_RADIUS_METERS = 50000;
const FORWARD_GEOCODE_BIAS_DELTA = 0.5;
const DEFAULT_AUTOCOMPLETE_BIAS = {
  rectangle: {
    low: { latitude: 29.0, longitude: 34.8 },
    high: { latitude: 33.4, longitude: 39.4 },
  },
};
const RATE_WINDOW_MS = 60000;
const MAX_CONCURRENT_REQUESTS_PER_USER = 2;
const OPERATION_RATE_LIMITS = {
  autocomplete: 30,
  placeDetails: 15,
  forwardGeocode: 10,
  reverseGeocode: 20,
} as const;

type JsonRecord = Record<string, unknown>;
type Operation = keyof typeof OPERATION_RATE_LIMITS;
export type FetchLike = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Response | Promise<Response>;
export type Authorize = (request: Request) => Promise<string>;
type RunLimited = (
  operation: Operation,
  operationCall: () => Promise<JsonRecord>,
) => Promise<JsonRecord>;

export interface PlacesHandlerDependencies {
  apiKey: string;
  authorize: Authorize;
  fetch?: FetchLike;
  upstreamTimeoutMs?: number;
  now?: () => number;
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

interface RateWindow {
  count: number;
  startedAt: number;
}

interface UserLimitState {
  concurrent: number;
  expiresAt: number;
  windows: Partial<Record<Operation, RateWindow>>;
}

class InstanceRateLimiter {
  private readonly users = new Map<string, UserLimitState>();

  constructor(private readonly now: () => number) {}

  // This bounds one warm Edge instance only; distributed enforcement remains a Google quota concern.
  acquire(userId: string, operation: Operation): () => void {
    const now = this.now();
    this.cleanup(now);

    const state = this.users.get(userId) ?? {
      concurrent: 0,
      expiresAt: now + RATE_WINDOW_MS,
      windows: {},
    };
    let window = state.windows[operation];
    if (!window || now - window.startedAt >= RATE_WINDOW_MS) {
      window = { count: 0, startedAt: now };
      state.windows[operation] = window;
    }

    if (
      state.concurrent >= MAX_CONCURRENT_REQUESTS_PER_USER ||
      window.count >= OPERATION_RATE_LIMITS[operation]
    ) {
      throw new HttpError(429, "rate_limited", "Too many requests.");
    }

    window.count++;
    state.concurrent++;
    state.expiresAt = Math.max(state.expiresAt, window.startedAt + RATE_WINDOW_MS);
    this.users.set(userId, state);

    let released = false;
    return () => {
      if (released) return;
      released = true;
      state.concurrent = Math.max(0, state.concurrent - 1);
      this.cleanup(this.now());
    };
  }

  private cleanup(now: number): void {
    for (const [userId, state] of this.users) {
      if (state.concurrent === 0 && state.expiresAt <= now) {
        this.users.delete(userId);
      }
    }
  }
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: JsonRecord, keys: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  return actual.length === expected.length && actual.every((key, index) => key === expected[index]);
}

function requiredString(value: unknown, maximumLength: number): string {
  if (typeof value !== "string") {
    throw invalidRequest();
  }
  const result = value.trim();
  const hasControlCharacter = Array.from(result).some((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    return codePoint <= 31 || codePoint === 127;
  });
  if (
    result.length === 0 || result.length > maximumLength || hasControlCharacter
  ) {
    throw invalidRequest();
  }
  return result;
}

function coordinate(value: unknown, minimum: number, maximum: number): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) {
    throw invalidRequest();
  }
  return value;
}

function sessionToken(value: unknown): string {
  const token = requiredString(value, 128);
  if (token.length < 16 || !/^[A-Za-z0-9_-]+$/u.test(token)) {
    throw invalidRequest();
  }
  return token;
}

function optionalBias(value: unknown): { latitude: number; longitude: number } | undefined {
  if (value === undefined) return undefined;
  if (!isRecord(value) || !hasExactKeys(value, ["latitude", "longitude"])) {
    throw invalidRequest();
  }
  return {
    latitude: coordinate(value.latitude, -90, 90),
    longitude: coordinate(value.longitude, -180, 180),
  };
}

function autocompleteLocationBias(
  bias: { latitude: number; longitude: number } | undefined,
): JsonRecord {
  if (!bias) return DEFAULT_AUTOCOMPLETE_BIAS;
  return {
    circle: {
      center: bias,
      radius: AUTOCOMPLETE_BIAS_RADIUS_METERS,
    },
  };
}

function addForwardGeocodeBias(url: URL, bias: { latitude: number; longitude: number }): void {
  const lowLatitude = Math.max(-90, bias.latitude - FORWARD_GEOCODE_BIAS_DELTA);
  const highLatitude = Math.min(90, bias.latitude + FORWARD_GEOCODE_BIAS_DELTA);
  const lowLongitude = Math.max(-180, bias.longitude - FORWARD_GEOCODE_BIAS_DELTA);
  const highLongitude = Math.min(180, bias.longitude + FORWARD_GEOCODE_BIAS_DELTA);

  url.searchParams.set("locationBias.rectangle.low.latitude", String(lowLatitude));
  url.searchParams.set("locationBias.rectangle.low.longitude", String(lowLongitude));
  url.searchParams.set("locationBias.rectangle.high.latitude", String(highLatitude));
  url.searchParams.set("locationBias.rectangle.high.longitude", String(highLongitude));
}

function invalidRequest(): HttpError {
  return new HttpError(400, "invalid_request", "Request is invalid.");
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

async function fetchUpstreamJson(
  fetchImpl: FetchLike,
  input: RequestInfo | URL,
  init: RequestInit,
  timeoutMs: number,
): Promise<unknown> {
  let response: Response;
  try {
    response = await fetchWithTimeout(fetchImpl, input, init, timeoutMs);
  } catch (error) {
    if (isAbortError(error)) {
      throw new HttpError(504, "provider_timeout", "Location provider timed out.");
    }
    throw new HttpError(502, "provider_unavailable", "Location provider is unavailable.");
  }

  if (!response.ok) {
    throw new HttpError(502, "provider_unavailable", "Location provider is unavailable.");
  }

  try {
    return await readJson(response, MAX_UPSTREAM_BYTES);
  } catch {
    throw new HttpError(502, "provider_response_invalid", "Location provider response is invalid.");
  }
}

function providerString(value: unknown, maximumLength = 1000): string {
  if (typeof value !== "string" || value.length === 0 || value.length > maximumLength) {
    throw new HttpError(502, "provider_response_invalid", "Location provider response is invalid.");
  }
  return value;
}

function providerCoordinate(value: unknown, minimum: number, maximum: number): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) {
    throw new HttpError(502, "provider_response_invalid", "Location provider response is invalid.");
  }
  return value;
}

function placeIdFromResource(value: unknown): string {
  const resourceName = providerString(value, 263);
  if (!resourceName.startsWith("places/")) {
    throw new HttpError(502, "provider_response_invalid", "Location provider response is invalid.");
  }
  const placeId = resourceName.slice("places/".length);
  if (!/^[A-Za-z0-9_-]{5,256}$/u.test(placeId)) {
    throw new HttpError(502, "provider_response_invalid", "Location provider response is invalid.");
  }
  return placeId;
}

function normalizedLocation(value: unknown): { latitude: number; longitude: number } {
  if (!isRecord(value)) {
    throw new HttpError(502, "provider_response_invalid", "Location provider response is invalid.");
  }
  return {
    latitude: providerCoordinate(value.latitude, -90, 90),
    longitude: providerCoordinate(value.longitude, -180, 180),
  };
}

function normalizeAutocomplete(payload: unknown): JsonRecord {
  if (!isRecord(payload)) {
    throw new HttpError(502, "provider_response_invalid", "Location provider response is invalid.");
  }
  const providerSuggestions = payload.suggestions ?? [];
  if (!Array.isArray(providerSuggestions) || providerSuggestions.length > 5) {
    throw new HttpError(502, "provider_response_invalid", "Location provider response is invalid.");
  }
  const suggestions = providerSuggestions.map((entry) => {
    if (!isRecord(entry) || !isRecord(entry.placePrediction)) {
      throw new HttpError(
        502,
        "provider_response_invalid",
        "Location provider response is invalid.",
      );
    }
    const prediction = entry.placePrediction;
    const text = isRecord(prediction.text) ? providerString(prediction.text.text) : undefined;
    const structured = isRecord(prediction.structuredFormat)
      ? prediction.structuredFormat
      : undefined;
    const main = structured && isRecord(structured.mainText)
      ? providerString(structured.mainText.text)
      : text;
    const secondary = structured && isRecord(structured.secondaryText)
      ? providerString(structured.secondaryText.text)
      : "";
    return {
      placeId: providerString(prediction.placeId, 256),
      label: text,
      primaryText: main,
      secondaryText: secondary,
    };
  });
  return { suggestions };
}

function normalizePlaceDetails(payload: unknown, requestedPlaceId: string): JsonRecord {
  if (!isRecord(payload)) {
    throw new HttpError(502, "provider_response_invalid", "Location provider response is invalid.");
  }
  const placeId = providerString(payload.id, 256);
  if (placeId !== requestedPlaceId) {
    throw new HttpError(502, "provider_response_invalid", "Location provider response is invalid.");
  }
  return {
    place: {
      placeId,
      address: providerString(payload.formattedAddress),
      location: normalizedLocation(payload.location),
    },
  };
}

function normalizeGeocode(payload: unknown): JsonRecord {
  if (!isRecord(payload)) {
    throw new HttpError(502, "provider_response_invalid", "Location provider response is invalid.");
  }
  const providerResults = payload.results ?? [];
  if (!Array.isArray(providerResults)) {
    throw new HttpError(502, "provider_response_invalid", "Location provider response is invalid.");
  }
  const results = providerResults.map((entry) => {
    if (!isRecord(entry)) {
      throw new HttpError(
        502,
        "provider_response_invalid",
        "Location provider response is invalid.",
      );
    }
    return {
      placeId: placeIdFromResource(entry.place),
      address: providerString(entry.formattedAddress),
      location: normalizedLocation(entry.location),
    };
  });
  return { results: results.slice(0, 5) };
}

function googleHeaders(apiKey: string, fieldMask: string): HeadersInit {
  return {
    "content-type": "application/json",
    "x-goog-api-key": apiKey,
    "x-goog-fieldmask": fieldMask,
  };
}

function executeOperation(
  body: JsonRecord,
  apiKey: string,
  fetchImpl: FetchLike,
  timeoutMs: number,
  runLimited: RunLimited,
): Promise<JsonRecord> {
  if (body.operation === "autocomplete") {
    const keys = Object.keys(body);
    if (
      !keys.every((key) => ["operation", "input", "sessionToken", "bias"].includes(key)) ||
      !keys.includes("input") || !keys.includes("sessionToken")
    ) throw invalidRequest();
    const input = requiredString(body.input, 200);
    if (input.length < 3) throw invalidRequest();
    const token = sessionToken(body.sessionToken);
    const bias = optionalBias(body.bias);
    return runLimited("autocomplete", async () => {
      const payload = await fetchUpstreamJson(fetchImpl, AUTOCOMPLETE_URL, {
        method: "POST",
        headers: googleHeaders(apiKey, AUTOCOMPLETE_MASK),
        body: JSON.stringify({
          input,
          sessionToken: token,
          locationBias: autocompleteLocationBias(bias),
          languageCode: "en",
          regionCode: "jo",
        }),
      }, timeoutMs);
      return normalizeAutocomplete(payload);
    });
  }

  if (body.operation === "placeDetails") {
    if (!hasExactKeys(body, ["operation", "placeId", "sessionToken"])) throw invalidRequest();
    const placeId = requiredString(body.placeId, 256);
    if (!/^[A-Za-z0-9_-]{5,256}$/u.test(placeId)) throw invalidRequest();
    const token = sessionToken(body.sessionToken);
    const url = new URL(`${PLACE_DETAILS_URL}/${encodeURIComponent(placeId)}`);
    url.searchParams.set("sessionToken", token);
    url.searchParams.set("languageCode", "en");
    url.searchParams.set("regionCode", "jo");
    return runLimited("placeDetails", async () => {
      const payload = await fetchUpstreamJson(fetchImpl, url, {
        method: "GET",
        headers: googleHeaders(apiKey, PLACE_DETAILS_MASK),
      }, timeoutMs);
      return normalizePlaceDetails(payload, placeId);
    });
  }

  if (body.operation === "forwardGeocode") {
    const keys = Object.keys(body);
    if (
      !keys.every((key) => ["operation", "address", "bias"].includes(key)) ||
      !keys.includes("address")
    ) throw invalidRequest();
    const address = requiredString(body.address, 500);
    const bias = optionalBias(body.bias);
    const url = new URL(`${FORWARD_GEOCODE_URL}/${encodeURIComponent(address)}`);
    url.searchParams.set("languageCode", "en");
    url.searchParams.set("regionCode", "jo");
    if (bias) addForwardGeocodeBias(url, bias);
    return runLimited("forwardGeocode", async () => {
      const payload = await fetchUpstreamJson(fetchImpl, url, {
        method: "GET",
        headers: googleHeaders(apiKey, GEOCODE_MASK),
      }, timeoutMs);
      return normalizeGeocode(payload);
    });
  }

  if (body.operation === "reverseGeocode") {
    if (!hasExactKeys(body, ["operation", "latitude", "longitude"])) throw invalidRequest();
    const latitude = coordinate(body.latitude, -90, 90);
    const longitude = coordinate(body.longitude, -180, 180);
    const url = `${REVERSE_GEOCODE_URL}/${latitude},${longitude}?languageCode=en&regionCode=jo`;
    return runLimited("reverseGeocode", async () => {
      const payload = await fetchUpstreamJson(fetchImpl, url, {
        method: "GET",
        headers: googleHeaders(apiKey, GEOCODE_MASK),
      }, timeoutMs);
      return normalizeGeocode(payload);
    });
  }

  throw new HttpError(400, "unsupported_operation", "Operation is not supported.");
}

export function createPlacesHandler(
  dependencies: PlacesHandlerDependencies,
): (request: Request) => Promise<Response> {
  const fetchImpl = dependencies.fetch ?? fetch;
  const timeoutMs = dependencies.upstreamTimeoutMs ?? DEFAULT_UPSTREAM_TIMEOUT_MS;
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
      if (!isRecord(body) || typeof body.operation !== "string") throw invalidRequest();
      if (dependencies.apiKey.length === 0) {
        throw new HttpError(503, "service_unavailable", "Location service is unavailable.");
      }

      const data = await executeOperation(
        body,
        dependencies.apiKey,
        fetchImpl,
        timeoutMs,
        async (operation, operationCall) => {
          const release = limiter.acquire(callerId, operation);
          try {
            return await operationCall();
          } finally {
            release();
          }
        },
      );
      return jsonResponse(200, { data });
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
    throw new HttpError(503, "service_unavailable", "Location service is unavailable.");
  }

  let usersUrl: URL;
  try {
    usersUrl = new URL("/rest/v1/users", dependencies.supabaseUrl);
  } catch {
    throw new HttpError(503, "service_unavailable", "Location service is unavailable.");
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
    throw new HttpError(503, "service_unavailable", "Location service is unavailable.");
  }

  if (response.status === 401 || response.status === 403) {
    throw new HttpError(401, "unauthorized", "Authentication is required.");
  }
  if (!response.ok) {
    throw new HttpError(503, "service_unavailable", "Location service is unavailable.");
  }

  let payload: unknown;
  try {
    payload = await readJson(response, 4096);
  } catch {
    throw new HttpError(503, "service_unavailable", "Location service is unavailable.");
  }
  if (!Array.isArray(payload) || payload.length !== 1 || !isRecord(payload[0])) {
    throw new HttpError(403, "forbidden", "Rider access is required.");
  }
  const caller = payload[0];
  if (
    typeof caller.id !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(
      caller.id,
    ) ||
    caller.role !== "rider" || caller.is_blocked !== false
  ) {
    throw new HttpError(403, "forbidden", "Rider access is required.");
  }
  return caller.id;
}
