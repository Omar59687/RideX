import {
  authorizeCaller,
  createBackendQuoteCaller,
  createFareHandler,
  type FetchLike,
} from "./core.ts";

const TOKEN = `Bearer ${"a".repeat(40)}`;
const SERVICE_KEY = "test-service-role-key-never-return";
const CALLER_ID = "25b79de4-8856-4bad-b18d-54c667691df5";
const BOOKING_ID = "7f9c9c9c-1234-4abc-9def-0123456789ab";
const QUOTE_ID = "aaaaaaaa-bbbb-4ccc-9ddd-eeeeeeeeeeee";

function assert(condition: unknown, message = "Assertion failed"): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown): void {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) throw new Error(`Expected ${right}, received ${left}`);
}

async function responseBody(response: Response): Promise<Record<string, unknown>> {
  return await response.json() as Record<string, unknown>;
}

function request(body: unknown, headers: HeadersInit = {}): Request {
  return new Request("http://localhost/functions/v1/fare", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: TOKEN, ...headers },
    body: JSON.stringify(body),
  });
}

function quoteRow(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: QUOTE_ID,
    booking_request_id: BOOKING_ID,
    quote_version: 1,
    pricing_version: 2,
    fixed_fare_fils: 2050,
    breakdown: {
      base_fare_fils: 500,
      distance_fils: 1200,
      duration_fils: 300,
      stops_fils: 0,
      subtotal_fils: 2000,
      minimum_fare_fils: 1000,
      rounding_increment_fils: 50,
      fixed_fare_fils: 2050,
    },
    currency: "JOD",
    status: "calculated",
    expires_at: "2026-10-04T12:10:00.000Z",
    created_at: "2026-10-04T12:00:00.000Z",
    route_distance_meters: 5400,
    route_duration_seconds: 720,
    // Extra backend columns must be stripped, never forwarded.
    rider_id: CALLER_ID,
    pricing_configuration_id: QUOTE_ID,
    ...overrides,
  };
}

function validBody(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    operation: "quote",
    booking_request_id: BOOKING_ID,
    expected_booking_version: 1,
    route_distance_meters: 5400,
    route_duration_seconds: 720,
    ...overrides,
  };
}

function handlerWithQuote(
  row: unknown,
  capture?: { url?: string; init?: RequestInit },
): (request: Request) => Promise<Response> {
  const calculateFare = createBackendQuoteCaller({
    supabaseUrl: "https://project.supabase.co",
    serviceRoleKey: SERVICE_KEY,
    fetch: ((input, init) => {
      if (capture) {
        capture.url = String(input);
        capture.init = init;
      }
      return Response.json(row);
    }) as FetchLike,
  });
  return createFareHandler({
    authorize: () => Promise.resolve(CALLER_ID),
    calculateFare,
  });
}

Deno.test("quote forwards fixed RPC shape and returns the whitelisted quote row", async () => {
  const capture: { url?: string; init?: RequestInit } = {};
  const handler = handlerWithQuote(quoteRow(), capture);

  const response = await handler(request(validBody()));

  assertEquals(response.status, 200);
  const body = await responseBody(response);
  assertEquals(body, {
    data: {
      id: QUOTE_ID,
      booking_request_id: BOOKING_ID,
      quote_version: 1,
      pricing_version: 2,
      fixed_fare_fils: 2050,
      breakdown: {
        base_fare_fils: 500,
        distance_fils: 1200,
        duration_fils: 300,
        stops_fils: 0,
        subtotal_fils: 2000,
        minimum_fare_fils: 1000,
        rounding_increment_fils: 50,
        fixed_fare_fils: 2050,
      },
      currency: "JOD",
      status: "calculated",
      expires_at: "2026-10-04T12:10:00.000Z",
      created_at: "2026-10-04T12:00:00.000Z",
      route_distance_meters: 5400,
      route_duration_seconds: 720,
    },
  });
  assertEquals(capture.url, "https://project.supabase.co/rest/v1/rpc/backend_calculate_fare_quote");
  assertEquals(capture.init?.method, "POST");
  assertEquals(JSON.parse(String(capture.init?.body)), {
    target_booking_request_id: BOOKING_ID,
    expected_booking_version: 1,
    requested_route_distance_meters: 5400,
    requested_route_duration_seconds: 720,
    requested_route_geometry_reference: null,
  });
  const headers = new Headers(capture.init?.headers);
  assertEquals(headers.get("apikey"), SERVICE_KEY);
  assertEquals(headers.get("authorization"), `Bearer ${SERVICE_KEY}`);
});

Deno.test("quote accepts an explicitly null geometry reference", async () => {
  const handler = handlerWithQuote(quoteRow());
  const response = await handler(request(validBody({ route_geometry_reference: null })));
  assertEquals(response.status, 200);
});

Deno.test("invalid quote requests are rejected without calling the backend", async () => {
  const bodies: Array<Record<string, unknown>> = [
    { operation: "lock", booking_request_id: BOOKING_ID },
    validBody({ booking_request_id: "not-a-uuid" }),
    validBody({ expected_booking_version: 0 }),
    validBody({ expected_booking_version: 1.5 }),
    validBody({ route_distance_meters: -1 }),
    validBody({ route_duration_seconds: -5 }),
    validBody({ route_distance_meters: 1.5 }),
    validBody({ route_geometry_reference: "polyline-reference" }),
    validBody({ extra_key: "nope" }),
    { operation: "quote" },
  ];
  for (const entry of bodies) {
    let calls = 0;
    const handler = createFareHandler({
      authorize: () => Promise.resolve(CALLER_ID),
      calculateFare: () => {
        calls++;
        return Promise.resolve({});
      },
    });
    const response = await handler(request(entry));
    assertEquals(response.status, 400);
    assertEquals(calls, 0);
  }

  // Non-POST and oversized bodies never reach the backend either.
  const handler = createFareHandler({
    authorize: () => Promise.resolve(CALLER_ID),
    calculateFare: () => Promise.resolve({}),
  });
  const getResponse = await handler(new Request("http://localhost", { method: "GET" }));
  assertEquals(getResponse.status, 405);
  const bigResponse = await handler(request(validBody(), { "content-length": "8192" }));
  assertEquals(bigResponse.status, 400);
});

Deno.test("backend version, draft, pricing, and eligibility failures map to sanitized codes", async () => {
  const cases = [
    {
      rpcStatus: 409,
      rpcBody: { code: "40001", message: "Booking version is stale." },
      status: 409,
      code: "version_conflict",
      message: "Booking changed. Request a new fare.",
    },
    {
      rpcStatus: 404,
      rpcBody: { code: "P0002", message: "Booking was not found." },
      status: 404,
      code: "not_found",
      message: "Booking draft was not found.",
    },
    {
      rpcStatus: 403,
      rpcBody: { code: "42501", message: "A blocked Rider cannot receive a FareQuote." },
      status: 403,
      code: "forbidden",
      message: "Rider access is required.",
    },
    {
      rpcStatus: 500,
      rpcBody: {
        code: "55000",
        message: "No active pricing configuration supports this vehicle type.",
      },
      status: 503,
      code: "no_pricing_configuration",
      message: "Fare is unavailable.",
    },
    {
      rpcStatus: 500,
      rpcBody: { code: "55000", message: "Fare can be calculated only for a draft booking." },
      status: 422,
      code: "fare_unavailable",
      message: "Fare cannot be calculated for this booking.",
    },
  ];
  for (const testCase of cases) {
    const handler = createFareHandler({
      authorize: () => Promise.resolve(CALLER_ID),
      calculateFare: createBackendQuoteCaller({
        supabaseUrl: "https://project.supabase.co",
        serviceRoleKey: SERVICE_KEY,
        fetch: () => new Response(JSON.stringify(testCase.rpcBody), { status: testCase.rpcStatus }),
      }),
    });
    const response = await handler(request(validBody()));
    assertEquals(response.status, testCase.status);
    assertEquals(await responseBody(response), {
      error: { code: testCase.code, message: testCase.message },
    });
  }
});

Deno.test("malformed quote rows and backend outages are sanitized and leak nothing", async () => {
  const malformedRows: unknown[] = [
    { ...quoteRow(), breakdown: { base_fare_fils: 1 } },
    { ...quoteRow(), currency: "USD" },
    { ...quoteRow(), status: "pending" },
    { ...quoteRow(), fixed_fare_fils: -5 },
    { ...quoteRow(), id: "not-a-uuid" },
    "not-an-object",
  ];
  for (const row of malformedRows) {
    const response = await handlerWithQuote(row)(request(validBody()));
    assertEquals(response.status, 502);
    assertEquals(await responseBody(response), {
      error: { code: "quote_response_invalid", message: "Fare service response is invalid." },
    });
  }

  const timeoutHandler = createFareHandler({
    authorize: () => Promise.resolve(CALLER_ID),
    calculateFare: createBackendQuoteCaller({
      supabaseUrl: "https://project.supabase.co",
      serviceRoleKey: SERVICE_KEY,
      timeoutMs: 5,
      fetch: (_input, init) =>
        new Promise((_resolve, reject) => {
          init?.signal?.addEventListener("abort", () =>
            reject(new DOMException(`secret timeout ${SERVICE_KEY}`, "AbortError")));
        }),
    }),
  });
  const timeoutResponse = await timeoutHandler(request(validBody()));
  assertEquals(timeoutResponse.status, 504);
  assertEquals(await responseBody(timeoutResponse), {
    error: { code: "provider_timeout", message: "Fare request timed out." },
  });

  const downHandler = createFareHandler({
    authorize: () => Promise.resolve(CALLER_ID),
    calculateFare: createBackendQuoteCaller({
      supabaseUrl: "https://project.supabase.co",
      serviceRoleKey: SERVICE_KEY,
      fetch: () => Promise.reject(new Error(`down ${SERVICE_KEY}`)),
    }),
  });
  const downResponse = await downHandler(request(validBody()));
  assertEquals(downResponse.status, 503);

  const missingKeyHandler = createFareHandler({
    authorize: () => Promise.resolve(CALLER_ID),
    calculateFare: createBackendQuoteCaller({
      supabaseUrl: "https://project.supabase.co",
      serviceRoleKey: "",
    }),
  });
  assertEquals((await missingKeyHandler(request(validBody()))).status, 503);

  const serialized = JSON.stringify([
    await responseBody(downResponse),
    await responseBody(await missingKeyHandler(request(validBody()))),
  ]);
  assert(!serialized.includes(SERVICE_KEY));
});

Deno.test("caller authorization requires an unblocked Rider", async () => {
  const callerId = await authorizeCaller(request(validBody()), {
    supabaseUrl: "https://project.supabase.co",
    supabaseAnonKey: "anon-key",
    fetch: () => Response.json([{ id: CALLER_ID, role: "rider", is_blocked: false }]),
  });
  assertEquals(callerId, CALLER_ID);

  try {
    await authorizeCaller(new Request("http://localhost"), {
      supabaseUrl: "https://project.supabase.co",
      supabaseAnonKey: "anon-key",
      fetch: () => Response.json([]),
    });
    throw new Error("Expected missing auth to fail");
  } catch (error) {
    assert(error instanceof Error);
  }

  for (
    const profile of [
      [{ id: CALLER_ID, role: "driver", is_blocked: false }],
      [{ id: CALLER_ID, role: "rider", is_blocked: true }],
      [],
    ]
  ) {
    const handler = createFareHandler({
      authorize: (req) =>
        authorizeCaller(req, {
          supabaseUrl: "https://project.supabase.co",
          supabaseAnonKey: "anon-key",
          fetch: () => Response.json(profile),
        }),
      calculateFare: () => Promise.resolve({}),
    });
    const response = await handler(request(validBody()));
    assertEquals(response.status, 403);
    assertEquals(await responseBody(response), {
      error: { code: "forbidden", message: "Rider access is required." },
    });
  }
});

Deno.test("per-user quote limits return sanitized 429 and expire after one minute", async () => {
  let now = 1000;
  let upstreamCalls = 0;
  const handler = createFareHandler({
    authorize: () => Promise.resolve(CALLER_ID),
    calculateFare: () => {
      upstreamCalls++;
      return Promise.resolve(quoteRow());
    },
    now: () => now,
  });

  for (let index = 0; index < 10; index++) {
    assertEquals((await handler(request(validBody()))).status, 200);
  }
  const limited = await handler(request(validBody()));
  assertEquals(limited.status, 429);
  assertEquals(await responseBody(limited), {
    error: { code: "rate_limited", message: "Too many requests." },
  });
  assertEquals(upstreamCalls, 10);

  now += 60000;
  assertEquals((await handler(request(validBody()))).status, 200);
  assertEquals(upstreamCalls, 11);
});

Deno.test("unexpected failures never leak tokens or backend wording", async () => {
  const handler = createFareHandler({
    authorize: () => Promise.reject(new Error(`bad token ${TOKEN} ${SERVICE_KEY}`)),
    calculateFare: () => Promise.resolve({}),
  });
  const response = await handler(request(validBody()));
  const serialized = JSON.stringify(await responseBody(response));
  assertEquals(response.status, 500);
  assert(!serialized.includes(TOKEN));
  assert(!serialized.includes(SERVICE_KEY));
});
