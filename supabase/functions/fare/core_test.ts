import {
  authorizeCaller,
  createBackendQuoteCaller,
  createFareHandler,
  type FetchLike,
} from "./core.ts";

const TOKEN = `Bearer ${"a".repeat(40)}`;
const SERVICE_KEY = "test-service-role-key-never-return";
const ROUTES_KEY = "test-routes-key-never-return";
const CALLER_ID = "25b79de4-8856-4bad-b18d-54c667691df5";
const OTHER_RIDER_ID = "15b79de4-8856-4bad-b18d-54c667691df5";
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
    headers: {
      "content-type": "application/json",
      authorization: TOKEN,
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

function validBody(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    operation: "quote",
    booking_request_id: BOOKING_ID,
    expected_booking_version: 1,
    ...overrides,
  };
}

function quoteRow(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: QUOTE_ID,
    booking_request_id: BOOKING_ID,
    quote_version: 1,
    pricing_version: 1,
    fixed_fare_fils: 2500,
    breakdown: {
      base_fare_fils: 500,
      distance_fils: 1620,
      duration_fils: 600,
      stops_fils: 200,
      subtotal_fils: 2920,
      minimum_fare_fils: 1000,
      rounding_increment_fils: 50,
      fixed_fare_fils: 2500,
    },
    currency: "JOD",
    status: "calculated",
    expires_at: "2026-10-04T12:10:00.000Z",
    created_at: "2026-10-04T12:00:00.000Z",
    route_distance_meters: 5400,
    route_duration_seconds: 720,
    rider_id: CALLER_ID,
    pricing_configuration_id: QUOTE_ID,
    ...overrides,
  };
}

Deno.test("handler binds the authenticated rider and accepts no phone metrics", async () => {
  let captured: unknown;
  const handler = createFareHandler({
    authorize: () => Promise.resolve(CALLER_ID),
    calculateFare: (input) => {
      captured = input;
      return Promise.resolve(quoteRow());
    },
  });

  const response = await handler(request(validBody()));

  assertEquals(response.status, 200);
  assertEquals(captured, {
    riderId: CALLER_ID,
    bookingRequestId: BOOKING_ID,
    expectedBookingVersion: 1,
  });
  const body = await responseBody(response);
  const data = body.data as Record<string, unknown>;
  assertEquals(data.id, QUOTE_ID);
});

Deno.test("handler rejects phone-supplied metrics and malformed inputs", async () => {
  const bodies = [
    validBody({ route_distance_meters: 1 }),
    validBody({ route_duration_seconds: 1 }),
    validBody({ booking_request_id: "not-a-uuid" }),
    validBody({ expected_booking_version: 0 }),
    validBody({ expected_booking_version: 1.5 }),
    validBody({ extra_key: true }),
    { operation: "lock", booking_request_id: BOOKING_ID },
    { operation: "quote" },
  ];
  for (const body of bodies) {
    let calls = 0;
    const handler = createFareHandler({
      authorize: () => Promise.resolve(CALLER_ID),
      calculateFare: () => {
        calls++;
        return Promise.resolve(quoteRow());
      },
    });
    const response = await handler(request(body));
    assertEquals(response.status, 400);
    assertEquals(calls, 0);
  }
});

Deno.test("backend quote reloads owned canonical stops and uses trusted Google metrics", async () => {
  const calls: Array<{ url: string; init?: RequestInit }> = [];
  const fetchImpl: FetchLike = (input, init) => {
    const url = String(input);
    calls.push({ url, init });
    if (url.includes("/booking_requests?")) {
      const parsed = new URL(url);
      assertEquals(parsed.searchParams.get("id"), `eq.${BOOKING_ID}`);
      assertEquals(parsed.searchParams.get("rider_id"), `eq.${CALLER_ID}`);
      return Response.json([{
        id: BOOKING_ID,
        rider_id: CALLER_ID,
        status: "draft",
        version: 1,
        pickup: { latitude: 31.95, longitude: 35.92 },
        destination: { latitude: 32.08, longitude: 36.1 },
      }]);
    }
    if (url.includes("/booking_stops?")) {
      return Response.json([{
        sequence: 1,
        location: { latitude: 31.99, longitude: 35.98 },
      }]);
    }
    if (url === "https://routes.googleapis.com/directions/v2:computeRoutes") {
      const headers = new Headers(init?.headers);
      assertEquals(headers.get("x-goog-api-key"), ROUTES_KEY);
      const routeRequest = JSON.parse(String(init?.body));
      assertEquals(routeRequest.intermediates, [{
        location: {
          latLng: { latitude: 31.99, longitude: 35.98 },
        },
      }]);
      return Response.json({
        routes: [{ distanceMeters: 5400, duration: "720s" }],
      });
    }
    if (url.endsWith("/rest/v1/rpc/backend_calculate_fare_quote")) {
      assertEquals(JSON.parse(String(init?.body)), {
        target_booking_request_id: BOOKING_ID,
        expected_booking_version: 1,
        requested_route_distance_meters: 5400,
        requested_route_duration_seconds: 720,
        requested_route_geometry_reference: null,
      });
      return Response.json(quoteRow());
    }
    throw new Error(`Unexpected URL: ${url}`);
  };

  const calculateFare = createBackendQuoteCaller({
    supabaseUrl: "https://project.supabase.co",
    serviceRoleKey: SERVICE_KEY,
    googleRoutesApiKey: ROUTES_KEY,
    fetch: fetchImpl,
  });
  const result = await calculateFare({
    riderId: CALLER_ID,
    bookingRequestId: BOOKING_ID,
    expectedBookingVersion: 1,
  });

  assertEquals(result.route_distance_meters, 5400);
  assertEquals(result.route_duration_seconds, 720);
  assertEquals(calls.length, 4);
  const rpcHeaders = new Headers(calls[3].init?.headers);
  assertEquals(rpcHeaders.get("apikey"), SERVICE_KEY);
  assertEquals(rpcHeaders.get("authorization"), `Bearer ${SERVICE_KEY}`);
});

Deno.test("backend quote refuses another rider's booking before routing", async () => {
  let calls = 0;
  const calculateFare = createBackendQuoteCaller({
    supabaseUrl: "https://project.supabase.co",
    serviceRoleKey: SERVICE_KEY,
    googleRoutesApiKey: ROUTES_KEY,
    fetch: (input) => {
      calls++;
      const url = new URL(String(input));
      assertEquals(url.searchParams.get("rider_id"), `eq.${OTHER_RIDER_ID}`);
      return Response.json([]);
    },
  });

  let error: unknown;
  try {
    await calculateFare({
      riderId: OTHER_RIDER_ID,
      bookingRequestId: BOOKING_ID,
      expectedBookingVersion: 1,
    });
  } catch (caught) {
    error = caught;
  }
  assert(error instanceof Error);
  const handler = createFareHandler({
    authorize: () => Promise.resolve(OTHER_RIDER_ID),
    calculateFare,
  });
  const response = await handler(request(validBody()));
  assertEquals(response.status, 404);
  assertEquals((await responseBody(response)).error, {
    code: "not_found",
    message: "Booking draft was not found.",
  });
  assertEquals(calls, 2);
});

Deno.test("backend quote rejects stale versions without calling Google", async () => {
  let calls = 0;
  const calculateFare = createBackendQuoteCaller({
    supabaseUrl: "https://project.supabase.co",
    serviceRoleKey: SERVICE_KEY,
    googleRoutesApiKey: ROUTES_KEY,
    fetch: (input) => {
      calls++;
      const url = String(input);
      assert(url.includes("/booking_requests?"));
      return Response.json([{
        id: BOOKING_ID,
        rider_id: CALLER_ID,
        status: "draft",
        version: 2,
        pickup: { latitude: 31.95, longitude: 35.92 },
        destination: { latitude: 32.08, longitude: 36.1 },
      }]);
    },
  });
  const handler = createFareHandler({
    authorize: () => Promise.resolve(CALLER_ID),
    calculateFare,
  });
  const response = await handler(request(validBody()));
  assertEquals(response.status, 409);
  assertEquals(calls, 1);
});

Deno.test("missing server configuration fails closed", async () => {
  const calculateFare = createBackendQuoteCaller({
    supabaseUrl: "",
    serviceRoleKey: "",
    googleRoutesApiKey: "",
  });
  const handler = createFareHandler({
    authorize: () => Promise.resolve(CALLER_ID),
    calculateFare,
  });
  const response = await handler(request(validBody()));
  assertEquals(response.status, 503);
});

Deno.test("authorizeCaller validates the authenticated non-blocked rider", async () => {
  const caller = await authorizeCaller(request(validBody()), {
    supabaseUrl: "https://project.supabase.co",
    supabaseAnonKey: "anon-key",
    fetch: (input, init) => {
      assertEquals(
        String(input),
        "https://project.supabase.co/rest/v1/users?select=id%2Crole%2Cis_blocked&limit=2",
      );
      const headers = new Headers(init?.headers);
      assertEquals(headers.get("authorization"), TOKEN);
      return Response.json([{
        id: CALLER_ID,
        role: "rider",
        is_blocked: false,
      }]);
    },
  });
  assertEquals(caller, CALLER_ID);
});

Deno.test("authorizeCaller rejects blocked and non-rider callers", async () => {
  for (const row of [
    { id: CALLER_ID, role: "rider", is_blocked: true },
    { id: CALLER_ID, role: "driver", is_blocked: false },
  ]) {
    let error: unknown;
    try {
      await authorizeCaller(request(validBody()), {
        supabaseUrl: "https://project.supabase.co",
        supabaseAnonKey: "anon-key",
        fetch: () => Response.json([row]),
      });
    } catch (caught) {
      error = caught;
    }
    assert(error instanceof Error);
  }
});
