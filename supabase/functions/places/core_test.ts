import { authorizeCaller, createPlacesHandler, type FetchLike } from "./core.ts";

const TOKEN = `Bearer ${"a".repeat(40)}`;
const SECRET = "test-google-key-never-return";
const SESSION_TOKEN = "3519edfe-0f75-4a30-bfe4-7cbd89340b2c";
const CALLER_ID = "25b79de4-8856-4bad-b18d-54c667691df5";

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

async function waitFor(condition: () => boolean): Promise<void> {
  for (let attempt = 0; attempt < 50; attempt++) {
    if (condition()) return;
    await Promise.resolve();
  }
  throw new Error("Condition was not reached");
}

function request(body: unknown, headers: HeadersInit = {}): Request {
  return new Request("http://localhost/functions/v1/places", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: TOKEN, ...headers },
    body: JSON.stringify(body),
  });
}

function handlerWith(
  upstream: FetchLike,
  timeoutMs = 100,
): (request: Request) => Promise<Response> {
  return createPlacesHandler({
    apiKey: SECRET,
    authorize: () => Promise.resolve(CALLER_ID),
    fetch: upstream,
    upstreamTimeoutMs: timeoutMs,
  });
}

Deno.test("autocomplete uses fixed Google request and normalizes suggestions", async () => {
  let capturedUrl = "";
  let capturedInit: RequestInit | undefined;
  const handler = handlerWith((input, init) => {
    capturedUrl = String(input);
    capturedInit = init;
    return Response.json({
      suggestions: [{
        placePrediction: {
          placeId: "ChIJ12345",
          text: { text: "Rainbow Street, Amman, Jordan" },
          structuredFormat: {
            mainText: { text: "Rainbow Street" },
            secondaryText: { text: "Amman, Jordan" },
          },
        },
      }],
    });
  });

  const response = await handler(request({
    operation: "autocomplete",
    input: "Rainbow",
    sessionToken: SESSION_TOKEN,
    bias: { latitude: 31.95, longitude: 35.92 },
  }));

  assertEquals(response.status, 200);
  assertEquals(await responseBody(response), {
    data: {
      suggestions: [{
        placeId: "ChIJ12345",
        label: "Rainbow Street, Amman, Jordan",
        primaryText: "Rainbow Street",
        secondaryText: "Amman, Jordan",
      }],
    },
  });
  assertEquals(capturedUrl, "https://places.googleapis.com/v1/places:autocomplete");
  assertEquals(capturedInit?.method, "POST");
  assertEquals(JSON.parse(String(capturedInit?.body)), {
    input: "Rainbow",
    sessionToken: SESSION_TOKEN,
    locationBias: {
      circle: {
        center: { latitude: 31.95, longitude: 35.92 },
        radius: 50000,
      },
    },
    languageCode: "en",
    regionCode: "jo",
  });
  const headers = new Headers(capturedInit?.headers);
  assertEquals(headers.get("x-goog-api-key"), SECRET);
  assert(!headers.get("x-goog-fieldmask")?.includes("*"));
});

Deno.test("autocomplete without client bias uses a broad non-restrictive Jordan bias", async () => {
  let upstreamBody: Record<string, unknown> = {};
  const handler = handlerWith((_input, init) => {
    upstreamBody = JSON.parse(String(init?.body));
    return Response.json({});
  });
  const response = await handler(request({
    operation: "autocomplete",
    input: "Aqaba",
    sessionToken: SESSION_TOKEN,
  }));

  assertEquals(response.status, 200);
  assertEquals(upstreamBody.locationBias, {
    rectangle: {
      low: { latitude: 29, longitude: 34.8 },
      high: { latitude: 33.4, longitude: 39.4 },
    },
  });
  assert(!("includedRegionCodes" in upstreamBody));
  assert(!("locationRestriction" in upstreamBody));
});

Deno.test("placeDetails uses an Essentials field mask and normalizes a place without label", async () => {
  let capturedUrl = "";
  let capturedHeaders = new Headers();
  const handler = handlerWith((input, init) => {
    capturedUrl = String(input);
    capturedHeaders = new Headers(init?.headers);
    return Response.json({
      id: "ChIJ12345",
      formattedAddress: "Rainbow St., Amman, Jordan",
      location: { latitude: 31.95, longitude: 35.92 },
    });
  });
  const response = await handler(request({
    operation: "placeDetails",
    placeId: "ChIJ12345",
    sessionToken: SESSION_TOKEN,
  }));

  assertEquals(response.status, 200);
  assertEquals(
    capturedUrl,
    `https://places.googleapis.com/v1/places/ChIJ12345?sessionToken=${SESSION_TOKEN}&languageCode=en&regionCode=jo`,
  );
  assertEquals(capturedHeaders.get("x-goog-fieldmask"), "id,formattedAddress,location");
  assertEquals(await responseBody(response), {
    data: {
      place: {
        placeId: "ChIJ12345",
        address: "Rainbow St., Amman, Jordan",
        location: { latitude: 31.95, longitude: 35.92 },
      },
    },
  });
});

Deno.test("a bounded opaque session token is reused unchanged across autocomplete and details", async () => {
  const opaqueToken = "client_session-token_0123456789";
  let autocompleteToken = "";
  let detailsToken = "";
  const handler = handlerWith((input, init) => {
    const url = new URL(String(input));
    if (url.pathname.endsWith(":autocomplete")) {
      autocompleteToken = JSON.parse(String(init?.body)).sessionToken;
      return Response.json({});
    }
    detailsToken = url.searchParams.get("sessionToken") ?? "";
    return Response.json({
      id: "ChIJ12345",
      formattedAddress: "Rainbow St., Amman, Jordan",
      location: { latitude: 31.95, longitude: 35.92 },
    });
  });

  const autocompleteResponse = await handler(request({
    operation: "autocomplete",
    input: "Rainbow",
    sessionToken: opaqueToken,
  }));
  const detailsResponse = await handler(request({
    operation: "placeDetails",
    placeId: "ChIJ12345",
    sessionToken: opaqueToken,
  }));

  assertEquals(autocompleteResponse.status, 200);
  assertEquals(detailsResponse.status, 200);
  assertEquals(autocompleteToken, opaqueToken);
  assertEquals(detailsToken, opaqueToken);
});

Deno.test("placeDetails rejects a provider ID that differs from the requested ID", async () => {
  const handler = handlerWith(() =>
    Response.json({
      id: "ChIJDifferent",
      formattedAddress: "Amman, Jordan",
      location: { latitude: 31.95, longitude: 35.92 },
    })
  );
  const response = await handler(request({
    operation: "placeDetails",
    placeId: "ChIJ12345",
    sessionToken: SESSION_TOKEN,
  }));

  assertEquals(response.status, 502);
  assertEquals((await responseBody(response)).error, {
    code: "provider_response_invalid",
    message: "Location provider response is invalid.",
  });
});

Deno.test("forwardGeocode uses Geocoding v4 and normalizes results", async () => {
  let capturedUrl = "";
  const handler = handlerWith((input, init) => {
    capturedUrl = String(input);
    assertEquals(
      new Headers(init?.headers).get("x-goog-fieldmask"),
      "results.place,results.formattedAddress,results.location",
    );
    return Response.json({
      results: [{
        place: "places/ChIJabcde",
        formattedAddress: "Abdali, Amman, Jordan",
        location: { latitude: 31.963, longitude: 35.91 },
      }],
    });
  });
  const response = await handler(request({
    operation: "forwardGeocode",
    address: "Abdali Amman",
    bias: { latitude: 31.95, longitude: 35.92 },
  }));

  assertEquals(response.status, 200);
  assertEquals(
    capturedUrl,
    "https://geocode.googleapis.com/v4/geocode/address/Abdali%20Amman?languageCode=en&regionCode=jo&locationBias.rectangle.low.latitude=31.45&locationBias.rectangle.low.longitude=35.42&locationBias.rectangle.high.latitude=32.45&locationBias.rectangle.high.longitude=36.42",
  );
  assertEquals(await responseBody(response), {
    data: {
      results: [{
        placeId: "ChIJabcde",
        address: "Abdali, Amman, Jordan",
        location: { latitude: 31.963, longitude: 35.91 },
      }],
    },
  });
});

Deno.test("reverseGeocode uses Geocoding v4 and normalized coordinates", async () => {
  let capturedUrl = "";
  const handler = handlerWith((input) => {
    capturedUrl = String(input);
    return Response.json({
      results: [{
        place: "places/ChIJabcde",
        formattedAddress: "Amman, Jordan",
        location: { latitude: 31.95, longitude: 35.93 },
      }],
    });
  });
  const response = await handler(request({
    operation: "reverseGeocode",
    latitude: 31.95,
    longitude: 35.93,
  }));

  assertEquals(response.status, 200);
  assertEquals(
    capturedUrl,
    "https://geocode.googleapis.com/v4/geocode/location/31.95,35.93?languageCode=en&regionCode=jo",
  );
});

Deno.test("geocoding rejects malformed place resource names", async () => {
  for (const place of ["ChIJabcde", "places/", "places/../bad", "other/ChIJabcde"]) {
    const handler = handlerWith(() =>
      Response.json({
        results: [{
          place,
          formattedAddress: "Amman, Jordan",
          location: { latitude: 31.95, longitude: 35.93 },
        }],
      })
    );
    const response = await handler(request({
      operation: "reverseGeocode",
      latitude: 31.95,
      longitude: 35.93,
    }));

    assertEquals(response.status, 502);
    assertEquals((await responseBody(response)).error, {
      code: "provider_response_invalid",
      message: "Location provider response is invalid.",
    });
  }
});

Deno.test("blank, unknown, extra, and invalid coordinate inputs are rejected without upstream calls", async () => {
  let calls = 0;
  const handler = handlerWith(() => {
    calls++;
    return Response.json({});
  });
  const invalidBodies = [
    { operation: "autocomplete", input: "   ", sessionToken: SESSION_TOKEN },
    { operation: "autocomplete", input: " a ", sessionToken: SESSION_TOKEN },
    { operation: "autocomplete", input: "ab", sessionToken: SESSION_TOKEN },
    { operation: "autocomplete", input: "Amman" },
    { operation: "autocomplete", input: "Amman", sessionToken: "short" },
    { operation: "autocomplete", input: "Amman", sessionToken: "not url safe token!" },
    {
      operation: "autocomplete",
      input: "Amman",
      sessionToken: SESSION_TOKEN,
      bias: { latitude: 91, longitude: 35 },
    },
    {
      operation: "autocomplete",
      input: "Amman",
      sessionToken: SESSION_TOKEN,
      bias: { latitude: 31, longitude: 35, radius: 1 },
    },
    {
      operation: "autocomplete",
      input: "Amman",
      sessionToken: SESSION_TOKEN,
      options: { url: "https://evil.invalid" },
    },
    { operation: "forwardGeocode", address: "" },
    { operation: "forwardGeocode", address: "Amman", bias: { latitude: 31 } },
    { operation: "placeDetails", placeId: "../bad", sessionToken: SESSION_TOKEN },
    { operation: "placeDetails", placeId: "ChIJ12345" },
    { operation: "reverseGeocode", latitude: 91, longitude: 35 },
    { operation: "reverseGeocode", latitude: 31, longitude: -181 },
    { operation: "reverseGeocode", latitude: "31", longitude: 35 },
  ];
  for (const body of invalidBodies) {
    const response = await handler(request(body));
    assertEquals(response.status, 400);
    assertEquals((await responseBody(response)).error, {
      code: "invalid_request",
      message: "Request is invalid.",
    });
  }
  assertEquals(calls, 0);
});

Deno.test("unsupported operations are rejected without upstream calls", async () => {
  let calls = 0;
  const handler = handlerWith(() => {
    calls++;
    return Response.json({});
  });
  const response = await handler(request({ operation: "route", url: "https://evil.invalid" }));
  assertEquals(response.status, 400);
  assertEquals((await responseBody(response)).error, {
    code: "unsupported_operation",
    message: "Operation is not supported.",
  });
  assertEquals(calls, 0);
});

Deno.test("malformed JSON and non-JSON content are rejected", async () => {
  let calls = 0;
  const handler = handlerWith(() => {
    calls++;
    return Response.json({});
  });
  const malformed = new Request("http://localhost/functions/v1/places", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: TOKEN },
    body: "{",
  });
  const wrongContentType = new Request("http://localhost/functions/v1/places", {
    method: "POST",
    headers: { "content-type": "text/plain", authorization: TOKEN },
    body: JSON.stringify({ operation: "autocomplete", input: "Amman" }),
  });

  for (const invalidRequest of [malformed, wrongContentType]) {
    const response = await handler(invalidRequest);
    assertEquals(response.status, 400);
    assertEquals((await responseBody(response)).error, {
      code: "invalid_request",
      message: "Request is invalid.",
    });
  }
  assertEquals(calls, 0);
});

Deno.test("caller authorization returns the trusted RLS user ID for an unblocked Rider", async () => {
  let headers = new Headers();
  const callerId = await authorizeCaller(
    request({
      operation: "autocomplete",
      input: "abc",
      sessionToken: SESSION_TOKEN,
    }),
    {
      supabaseUrl: "https://project.supabase.co",
      supabaseAnonKey: "anon-key",
      fetch: (input, init) => {
        assert(String(input).startsWith("https://project.supabase.co/rest/v1/users?"));
        headers = new Headers(init?.headers);
        return Response.json([{ id: CALLER_ID, role: "rider", is_blocked: false }]);
      },
    },
  );
  assertEquals(headers.get("authorization"), TOKEN);
  assertEquals(headers.get("apikey"), "anon-key");
  assertEquals(callerId, CALLER_ID);
});

Deno.test("caller authorization rejects missing auth, Driver, blocked Rider, and missing profile", async () => {
  let calls = 0;
  try {
    await authorizeCaller(new Request("http://localhost"), {
      supabaseUrl: "https://project.supabase.co",
      supabaseAnonKey: "anon-key",
      fetch: () => {
        calls++;
        return Response.json([]);
      },
    });
    throw new Error("Expected missing auth to fail");
  } catch {
    assertEquals(calls, 0);
  }

  for (
    const profile of [
      [{ id: CALLER_ID, role: "driver", is_blocked: false }],
      [{ id: CALLER_ID, role: "rider", is_blocked: true }],
      [{ id: "not-a-user-id", role: "rider", is_blocked: false }],
      [],
    ]
  ) {
    const handler = createPlacesHandler({
      apiKey: SECRET,
      authorize: (req) =>
        authorizeCaller(req, {
          supabaseUrl: "https://project.supabase.co",
          supabaseAnonKey: "anon-key",
          fetch: () => Response.json(profile),
        }),
      fetch: () => Response.json({}),
    });
    const response = await handler(request({
      operation: "autocomplete",
      input: "abc",
      sessionToken: SESSION_TOKEN,
    }));
    assertEquals(response.status, 403);
    assertEquals((await responseBody(response)).error, {
      code: "forbidden",
      message: "Rider access is required.",
    });
  }
});

Deno.test("per-user operation limits return sanitized 429 and expire after one minute", async () => {
  let now = 1000;
  const limits = [
    {
      operation: "autocomplete",
      limit: 30,
      body: { operation: "autocomplete", input: "Amman", sessionToken: SESSION_TOKEN },
      upstream: {},
    },
    {
      operation: "placeDetails",
      limit: 15,
      body: { operation: "placeDetails", placeId: "ChIJ12345", sessionToken: SESSION_TOKEN },
      upstream: {
        id: "ChIJ12345",
        formattedAddress: "Amman, Jordan",
        location: { latitude: 31.95, longitude: 35.92 },
      },
    },
    {
      operation: "forwardGeocode",
      limit: 10,
      body: { operation: "forwardGeocode", address: "Amman Jordan" },
      upstream: { results: [] },
    },
    {
      operation: "reverseGeocode",
      limit: 20,
      body: { operation: "reverseGeocode", latitude: 31.95, longitude: 35.92 },
      upstream: { results: [] },
    },
  ] as const;

  for (const testCase of limits) {
    let upstreamCalls = 0;
    const handler = createPlacesHandler({
      apiKey: SECRET,
      authorize: () => Promise.resolve(CALLER_ID),
      fetch: () => {
        upstreamCalls++;
        return Response.json(testCase.upstream);
      },
      now: () => now,
    });

    for (let index = 0; index < testCase.limit; index++) {
      assertEquals((await handler(request(testCase.body))).status, 200);
    }
    const limited = await handler(request(testCase.body));
    assert(limited.status === 429, `${testCase.operation} should be limited`);
    assertEquals(await responseBody(limited), {
      error: { code: "rate_limited", message: "Too many requests." },
    });
    assertEquals(upstreamCalls, testCase.limit);

    now += 60000;
    assertEquals((await handler(request(testCase.body))).status, 200);
    assertEquals(upstreamCalls, testCase.limit + 1);
    now += 60000;
  }
});

Deno.test("per-user concurrency is capped at two and released when requests finish", async () => {
  const resolvers: Array<(response: Response) => void> = [];
  let upstreamCalls = 0;
  const handler = createPlacesHandler({
    apiKey: SECRET,
    authorize: () => Promise.resolve(CALLER_ID),
    fetch: () => {
      upstreamCalls++;
      return new Promise<Response>((resolve) => resolvers.push(resolve));
    },
  });
  const body = { operation: "autocomplete", input: "Amman", sessionToken: SESSION_TOKEN };

  const first = handler(request(body));
  const second = handler(request(body));
  await waitFor(() => upstreamCalls === 2);
  const third = await handler(request(body));

  assertEquals(third.status, 429);
  assertEquals(await responseBody(third), {
    error: { code: "rate_limited", message: "Too many requests." },
  });
  assertEquals(upstreamCalls, 2);

  for (const resolve of resolvers) resolve(Response.json({}));
  assertEquals((await first).status, 200);
  assertEquals((await second).status, 200);

  const fourth = handler(request(body));
  await waitFor(() => upstreamCalls === 3);
  assertEquals(upstreamCalls, 3);
  resolvers[2](Response.json({}));
  assertEquals((await fourth).status, 200);
});

Deno.test("upstream timeout is sanitized", async () => {
  const handler = handlerWith((_input, init) =>
    new Promise((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () =>
        reject(new DOMException("secret timeout", "AbortError")));
    }), 5);
  const response = await handler(request({
    operation: "autocomplete",
    input: "Amman",
    sessionToken: SESSION_TOKEN,
  }));
  assertEquals(response.status, 504);
  assertEquals((await responseBody(response)).error, {
    code: "provider_timeout",
    message: "Location provider timed out.",
  });
});

Deno.test("upstream failure and malformed responses are sanitized and leak no secrets", async () => {
  const bodies = [];
  const failed = handlerWith(() => new Response(`failure ${SECRET}`, { status: 500 }));
  bodies.push(
    await responseBody(
      await failed(request({
        operation: "autocomplete",
        input: "private query",
        sessionToken: SESSION_TOKEN,
      })),
    ),
  );

  const malformed = handlerWith(() => new Response(`{"secret":"${SECRET}"`, { status: 200 }));
  bodies.push(
    await responseBody(
      await malformed(request({
        operation: "autocomplete",
        input: "private query",
        sessionToken: SESSION_TOKEN,
      })),
    ),
  );

  const wrongShape = handlerWith(() => Response.json({ suggestions: [{ error: SECRET }] }));
  bodies.push(
    await responseBody(
      await wrongShape(request({
        operation: "autocomplete",
        input: "private query",
        sessionToken: SESSION_TOKEN,
      })),
    ),
  );

  assertEquals((bodies[0].error as Record<string, unknown>).code, "provider_unavailable");
  assertEquals((bodies[1].error as Record<string, unknown>).code, "provider_response_invalid");
  assertEquals((bodies[2].error as Record<string, unknown>).code, "provider_response_invalid");
  const serialized = JSON.stringify(bodies);
  assert(!serialized.includes(SECRET));
  assert(!serialized.includes("private query"));
});

Deno.test("unexpected authorization errors do not leak tokens or details", async () => {
  const handler = createPlacesHandler({
    apiKey: SECRET,
    authorize: () => Promise.reject(new Error(`bad token ${TOKEN}`)),
    fetch: () => Response.json({}),
  });
  const response = await handler(request({
    operation: "autocomplete",
    input: "Amman",
    sessionToken: SESSION_TOKEN,
  }));
  const serialized = JSON.stringify(await responseBody(response));
  assertEquals(response.status, 500);
  assert(!serialized.includes(TOKEN));
  assert(!serialized.includes(SECRET));
});
