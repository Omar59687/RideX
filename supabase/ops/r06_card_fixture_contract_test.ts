import {
  assertActor,
  assertAttempt,
  assertBooking,
  assertCleanFixture,
  assertEnvironment,
  assertExecutionApproval,
  assertLockedQuote,
  assertPayment,
  assertTrip,
  assertVehicle,
  type CardFixtureEnvironment,
  CardFixtureError,
  fixtureMarker,
  fixtureOperationKeys,
  parseCardFixtureArgs,
  R06_DRIVER_EMAIL,
  R06_EXECUTION_APPROVAL_PREFIX,
  R06_NAMESPACE,
  R06_PROJECT_URL,
  R06_RIDER_EMAIL,
  R06_VEHICLE_ID,
} from "./r06_card_fixture_contract.ts";
import {
  type FetchLike,
  runCardFixtureOperator,
} from "./r06_prepare_card_fixture.ts";

const RIDER_ID = "22000000-0000-4000-8000-000000000001";
const DRIVER_ID = "22000000-0000-4000-8000-000000000002";
const BOOKING_ID = "22400000-0000-4000-8000-000000000001";
const QUOTE_ID = "22400000-0000-4000-8000-000000000002";
const OFFER_ID = "22400000-0000-4000-8000-000000000003";
const TRIP_ID = "22400000-0000-4000-8000-000000000004";
const PAYMENT_ID = "22400000-0000-4000-8000-000000000005";
const ATTEMPT_ID = "22400000-0000-4000-8000-000000000006";
const FIXTURE_ID = "9e480000-0000-4000-8000-000000000001";
const NOW = Date.now();

function errorCode(fn: () => unknown): string {
  try {
    fn();
  } catch (error) {
    if (error instanceof CardFixtureError) return error.code;
    throw error;
  }
  throw new Error("Expected CardFixtureError");
}

function expectAsyncCode(
  fn: () => Promise<unknown>,
  expected: string,
): Promise<void> {
  return fn().then(
    () => {
      throw new Error(`Expected ${expected}`);
    },
    (error) => {
      if (!(error instanceof CardFixtureError) || error.code !== expected) {
        throw error;
      }
    },
  );
}

function environment(
  overrides: Partial<CardFixtureEnvironment> = {},
): CardFixtureEnvironment {
  return {
    SUPABASE_URL: R06_PROJECT_URL,
    RIDEX_BACKEND_NAMESPACE: R06_NAMESPACE,
    SUPABASE_ANON_KEY: "test-anon-key",
    SUPABASE_SERVICE_ROLE_KEY: "test-service-key",
    R06_RIDER_ACCESS_TOKEN: "rider-session-token-placeholder",
    R06_DRIVER_ACCESS_TOKEN: "driver-session-token-placeholder",
    LOCALAPPDATA: "C:\\Users\\Test\\AppData\\Local",
    R06_FIXTURE_STATE_FILE:
      "C:\\Users\\Test\\AppData\\Local\\RideX\\R06\\card-fixture-state.json",
    ...overrides,
  };
}

function booking(status: string, version = 1, quoteId: string | null = null) {
  const marker = fixtureMarker(FIXTURE_ID);
  return {
    id: BOOKING_ID,
    rider_id: RIDER_ID,
    status,
    version,
    payment_method: "card",
    vehicle_type_code: "economy",
    fare_quote_id: quoteId,
    pickup: { label: `${marker}_PICKUP` },
    destination: { label: `${marker}_DESTINATION` },
  };
}

function quote(status = "locked") {
  return {
    id: QUOTE_ID,
    booking_request_id: BOOKING_ID,
    rider_id: RIDER_ID,
    status,
    vehicle_type_code: "economy",
    quote_version: 1,
    fixed_fare_fils: 16000,
    currency: "JOD",
    expires_at: new Date(NOW + 60_000).toISOString(),
  };
}

function trip(status = "accepted") {
  return {
    id: TRIP_ID,
    booking_request_id: BOOKING_ID,
    rider_id: RIDER_ID,
    driver_id: DRIVER_ID,
    vehicle_id: R06_VEHICLE_ID,
    fare_quote_id: QUOTE_ID,
    payment_method: "card",
    status,
    version: 1,
    currency: "JOD",
    original_fare_fils: 16000,
    current_fare_fils: 16000,
  };
}

function payment(status = "cardPaymentPending") {
  return {
    id: PAYMENT_ID,
    trip_id: TRIP_ID,
    rider_id: RIDER_ID,
    method: "card",
    card_status: status,
    currency: "JOD",
    authorized_amount_fils: 16000,
    final_amount_fils: 16000,
    version: 1,
    cash_status: null,
    provider_name: null,
    card_brand: null,
    card_last_four: null,
    authorized_at: null,
    paid_at: null,
    cancelled_at: null,
    refunded_at: null,
    sanitized_failure_code: null,
  };
}

function attempt(createdAt = new Date(NOW - 1_000).toISOString()) {
  return {
    id: ATTEMPT_ID,
    payment_id: PAYMENT_ID,
    type: "initialAuthorization",
    status: "pending",
    authorization_cycle: 1,
    attempt_sequence: 1,
    provider_name: "stripe",
    idempotency_key: fixtureOperationKeys(FIXTURE_ID).authorization,
    requested_amount_fils: 16000,
    currency: "JOD",
    provider_transaction_reference: null,
    sanitized_failure_code: null,
    sanitized_failure_message: null,
    completed_at: null,
    verified_at: null,
    refund_id: null,
    created_at: createdAt,
  };
}

Deno.test("rejects wrong project and namespace before network access", () => {
  const env = environment();
  assertEnvironment(env, false);
  if (
    errorCode(() =>
      assertEnvironment(
        { ...env, SUPABASE_URL: "https://other.supabase.co" },
        false,
      )
    ) !== "project_or_namespace_mismatch"
  ) {
    throw new Error("wrong endpoint was accepted");
  }
  if (
    errorCode(() =>
      assertEnvironment({ ...env, RIDEX_BACKEND_NAMESPACE: "other" }, false)
    ) !== "project_or_namespace_mismatch"
  ) {
    throw new Error("wrong namespace was accepted");
  }
});

Deno.test("read-only mode is the default and execution requires explicit approval plus local state path", () => {
  const options = parseCardFixtureArgs(["--fixture-id", FIXTURE_ID]);
  if (options.execute) throw new Error("default mode enabled execution");
  if (
    errorCode(() =>
      parseCardFixtureArgs([
        "--fixture-id",
        FIXTURE_ID,
        "--execute",
        "--execute",
      ])
    ) !== "invalid_arguments"
  ) {
    throw new Error("duplicate execution flag accepted");
  }
  if (
    errorCode(() =>
      assertEnvironment(
        environment({ R06_FIXTURE_STATE_FILE: "relative.state" }),
        true,
      )
    ) !== "state_file_required"
  ) {
    throw new Error("relative state path accepted");
  }
  if (
    errorCode(() =>
      assertEnvironment(
        environment({ R06_FIXTURE_STATE_FILE: "C:\\Temp\\another.state" }),
        true,
      )
    ) !== "state_file_required"
  ) {
    throw new Error("noncanonical state path accepted");
  }
  assertEnvironment(
    environment({
      R06_FIXTURE_STATE_FILE:
        "C:\\Users\\Test\\AppData\\Local\\RideX\\R06\\concurrency-acceptance-state.json",
    }),
    true,
  );
  if (
    errorCode(() =>
      assertExecutionApproval({ ...options, execute: true }, environment())
    ) !== "execution_approval_missing"
  ) {
    throw new Error("execution without approval accepted");
  }
  const approved = environment({
    R06_EXECUTION_APPROVAL_REF: `${R06_EXECUTION_APPROVAL_PREFIX}${FIXTURE_ID}`,
  });
  assertExecutionApproval({ ...options, execute: true }, approved);
});

Deno.test("only approved Rider and approved Driver identities pass", () => {
  assertActor({
    id: RIDER_ID,
    email: R06_RIDER_EMAIL,
    role: "rider",
    is_blocked: false,
  }, "rider");
  assertActor({
    id: DRIVER_ID,
    email: R06_DRIVER_EMAIL,
    role: "driver",
    is_blocked: false,
    approval_status: "approved",
  }, "driver");
  if (
    errorCode(() =>
      assertActor({
        id: RIDER_ID,
        email: "foreign@example.test",
        role: "rider",
        is_blocked: false,
      }, "rider")
    ) !== "fixture_actor_not_eligible"
  ) {
    throw new Error("foreign Rider accepted");
  }
  if (
    errorCode(() =>
      assertActor({
        id: DRIVER_ID,
        email: R06_DRIVER_EMAIL,
        role: "driver",
        is_blocked: false,
        approval_status: "pending",
      }, "driver")
    ) !== "fixture_actor_not_eligible"
  ) {
    throw new Error("unapproved Driver accepted");
  }
});

Deno.test("fixture identity is pinned to the designated economy Driver vehicle", () => {
  const row = {
    id: R06_VEHICLE_ID,
    driver_id: DRIVER_ID,
    vehicle_type_code: "economy",
    is_active: true,
  };
  const availability = {
    driver_id: DRIVER_ID,
    state: "available",
    vehicle_id: R06_VEHICLE_ID,
    reserved_booking_request_id: null,
    active_trip_id: null,
    version: 2,
  };
  assertVehicle(row, availability, DRIVER_ID);
  if (
    errorCode(() => assertCleanFixture([{}])) !== "duplicate_fixture_exists"
  ) {
    throw new Error("duplicate booking marker accepted");
  }
});

Deno.test("booking and locked quote reject wrong Rider, method, version, or missing lock", () => {
  assertBooking(booking("draft"), {
    id: BOOKING_ID,
    riderId: RIDER_ID,
    fixtureId: FIXTURE_ID,
    status: "draft",
  });
  if (
    errorCode(() =>
      assertBooking({ ...booking("draft"), rider_id: DRIVER_ID }, {
        riderId: RIDER_ID,
        fixtureId: FIXTURE_ID,
        status: "draft",
      })
    ) !== "canonical_booking_mismatch"
  ) {
    throw new Error("foreign Rider booking accepted");
  }
  if (
    errorCode(() =>
      assertBooking({ ...booking("draft"), payment_method: "cash" }, {
        riderId: RIDER_ID,
        fixtureId: FIXTURE_ID,
        status: "draft",
      })
    ) !== "canonical_booking_mismatch"
  ) {
    throw new Error("Cash booking accepted");
  }
  if (
    errorCode(() =>
      assertBooking(booking("confirmed", 9, QUOTE_ID), {
        riderId: RIDER_ID,
        fixtureId: FIXTURE_ID,
        status: "confirmed",
        version: 8,
        expectQuote: true,
      })
    ) !== "canonical_booking_mismatch"
  ) {
    throw new Error("stale booking version accepted");
  }
  assertLockedQuote(quote(), { bookingId: BOOKING_ID, riderId: RIDER_ID });
  if (
    errorCode(() =>
      assertLockedQuote(quote("calculated"), {
        bookingId: BOOKING_ID,
        riderId: RIDER_ID,
      })
    ) !== "locked_fare_unavailable"
  ) {
    throw new Error("unlocked fare accepted");
  }
  if (
    errorCode(() =>
      assertLockedQuote({ ...quote(), booking_request_id: TRIP_ID }, {
        bookingId: BOOKING_ID,
        riderId: RIDER_ID,
      })
    ) !== "locked_fare_unavailable"
  ) {
    throw new Error("foreign booking quote accepted");
  }
});

Deno.test("Trip and Payment guards reject foreign identities and non-pending financial state", () => {
  assertTrip(trip(), {
    tripId: TRIP_ID,
    bookingId: BOOKING_ID,
    riderId: RIDER_ID,
    driverId: DRIVER_ID,
    vehicleId: R06_VEHICLE_ID,
    fareQuoteId: QUOTE_ID,
    fareFils: 16000,
    status: "accepted",
  });
  if (
    errorCode(() =>
      assertTrip({ ...trip(), rider_id: DRIVER_ID }, {
        bookingId: BOOKING_ID,
        riderId: RIDER_ID,
        driverId: DRIVER_ID,
        vehicleId: R06_VEHICLE_ID,
        fareQuoteId: QUOTE_ID,
        fareFils: 16000,
        status: "accepted",
      })
    ) !== "canonical_trip_mismatch"
  ) throw new Error("foreign Trip owner accepted");
  assertPayment(payment(), {
    tripId: TRIP_ID,
    riderId: RIDER_ID,
    amountFils: 16000,
  });
  if (
    errorCode(() =>
      assertPayment(payment("cardPaymentAuthorized"), {
        tripId: TRIP_ID,
        riderId: RIDER_ID,
        amountFils: 16000,
      })
    ) !== "canonical_payment_mismatch"
  ) {
    throw new Error("unexpected authorized Payment accepted");
  }
  if (
    errorCode(() =>
      assertPayment({ ...payment(), trip_id: BOOKING_ID }, {
        tripId: TRIP_ID,
        riderId: RIDER_ID,
        amountFils: 16000,
      })
    ) !== "canonical_payment_mismatch"
  ) {
    throw new Error("Payment linked to wrong Trip accepted");
  }
  if (
    errorCode(() =>
      assertPayment({ ...payment(), authorized_at: new Date().toISOString() }, {
        tripId: TRIP_ID,
        riderId: RIDER_ID,
        amountFils: 16000,
      })
    ) !== "canonical_payment_mismatch"
  ) {
    throw new Error("already authorized Payment accepted");
  }
});

Deno.test("Attempt guard requires original pending cycle-one key and live two-minute window", () => {
  const expected = {
    paymentId: PAYMENT_ID,
    amountFils: 16000,
    operationKey: fixtureOperationKeys(FIXTURE_ID).authorization,
    now: NOW,
  };
  assertAttempt(attempt(), expected);
  if (
    errorCode(() =>
      assertAttempt(attempt(new Date(NOW - 120_000).toISOString()), expected)
    ) !== "canonical_attempt_mismatch_or_expired"
  ) {
    throw new Error("expired Attempt accepted");
  }
  if (
    errorCode(() =>
      assertAttempt({ ...attempt(), payment_id: TRIP_ID }, expected)
    ) !== "canonical_attempt_mismatch_or_expired"
  ) {
    throw new Error("foreign Payment Attempt accepted");
  }
  if (
    errorCode(() =>
      assertAttempt({ ...attempt(), idempotency_key: "rotated" }, expected)
    ) !== "canonical_attempt_mismatch_or_expired"
  ) {
    throw new Error("rotated operation key accepted");
  }
});

function readOnlyTransport(): {
  fetcher: FetchLike;
  calls: { url: string; method: string }[];
} {
  const calls: { url: string; method: string }[] = [];
  const fetcher: FetchLike = async (input, init) => {
    const url = new URL(String(input));
    const method = init?.method ?? "GET";
    calls.push({ url: `${url.origin}${url.pathname}${url.search}`, method });
    const json = (value: unknown) =>
      new Response(JSON.stringify(value), { status: 200 });
    if (url.pathname === "/auth/v1/user") {
      const token = new Headers(init?.headers).get("authorization");
      return json(
        token?.includes("rider-session")
          ? { id: RIDER_ID, email: R06_RIDER_EMAIL }
          : { id: DRIVER_ID, email: R06_DRIVER_EMAIL },
      );
    }
    if (url.pathname === "/rest/v1/users") {
      const id = url.searchParams.get("id")?.slice(3);
      return json([
        id === RIDER_ID
          ? {
            id: RIDER_ID,
            email: R06_RIDER_EMAIL,
            role: "rider",
            is_blocked: false,
          }
          : {
            id: DRIVER_ID,
            email: R06_DRIVER_EMAIL,
            role: "driver",
            is_blocked: false,
          },
      ]);
    }
    if (url.pathname === "/rest/v1/driver_profiles") {
      return json([{ user_id: DRIVER_ID, approval_status: "approved" }]);
    }
    if (url.pathname === "/rest/v1/vehicles") {
      return json([{
        id: R06_VEHICLE_ID,
        driver_id: DRIVER_ID,
        vehicle_type_code: "economy",
        is_active: true,
      }]);
    }
    if (url.pathname === "/rest/v1/driver_availability") {
      return json([{
        driver_id: DRIVER_ID,
        state: "available",
        vehicle_id: R06_VEHICLE_ID,
        reserved_booking_request_id: null,
        active_trip_id: null,
        version: 2,
      }]);
    }
    if (
      url.pathname === "/rest/v1/booking_requests" ||
      url.pathname === "/rest/v1/trips" ||
      url.pathname === "/rest/v1/payment_attempts"
    ) return json([]);
    throw new Error(
      `Unexpected request in read-only preflight: ${url.pathname}`,
    );
  };
  return { fetcher, calls };
}

Deno.test("read-only preflight issues only GETs and never invokes a financial RPC or Stripe", async () => {
  const transport = readOnlyTransport();
  const result = await runCardFixtureOperator(
    ["--fixture-id", FIXTURE_ID],
    environment(),
    {
      fetcher: transport.fetcher,
      now: () => NOW,
      stateExists: async () => false,
      reserveState: async () => {
        throw new Error("read-only mode wrote local execution state");
      },
    },
  );
  if (result.status !== "preflight_passed") {
    throw new Error("preflight status incorrect");
  }
  if (
    transport.calls.some((call) =>
      call.method !== "GET" || /\/rpc\/|stripe\.com/iu.test(call.url)
    )
  ) {
    throw new Error("read-only preflight performed or targeted a mutation");
  }
});

Deno.test("foreign Rider authentication blocks before any write", async () => {
  const transport = readOnlyTransport();
  const wrongRiderFetch: FetchLike = async (input, init) => {
    const url = new URL(String(input));
    if (
      url.pathname === "/auth/v1/user" &&
      new Headers(init?.headers).get("authorization")?.includes("rider-session")
    ) {
      transport.calls.push({
        url: `${url.origin}${url.pathname}`,
        method: init?.method ?? "GET",
      });
      return new Response(
        JSON.stringify({ id: RIDER_ID, email: "foreign@example.test" }),
        { status: 200 },
      );
    }
    return transport.fetcher(input, init);
  };
  await expectAsyncCode(
    () =>
      runCardFixtureOperator(["--fixture-id", FIXTURE_ID], environment(), {
        fetcher: wrongRiderFetch,
        stateExists: async () => false,
      }),
    "fixture_actor_not_eligible",
  );
  if (transport.calls.some((call) => call.method === "POST")) {
    throw new Error("foreign actor caused a write");
  }
});

Deno.test("existing fixture marker or persisted restart marker prevents duplicate execution", async () => {
  const transport = readOnlyTransport();
  const repeated = await runCardFixtureOperator(
    ["--fixture-id", FIXTURE_ID],
    environment(),
    {
      fetcher: transport.fetcher,
      stateExists: async () => true,
    },
  ).then(
    () => "unexpected",
    (error) => error instanceof CardFixtureError ? error.code : "other",
  );
  if (
    repeated !== "execution_state_exists_stop_and_reconcile" ||
    transport.calls.length !== 0
  ) {
    throw new Error("persisted execution marker did not block restart");
  }

  const duplicateTransport = readOnlyTransport();
  const duplicateFetch: FetchLike = async (input, init) => {
    const url = new URL(String(input));
    if (
      url.pathname === "/rest/v1/booking_requests" &&
      url.searchParams.has("pickup->>label")
    ) {
      duplicateTransport.calls.push({
        url: `${url.origin}${url.pathname}${url.search}`,
        method: init?.method ?? "GET",
      });
      return new Response(JSON.stringify([{ id: BOOKING_ID }]), {
        status: 200,
      });
    }
    return duplicateTransport.fetcher(input, init);
  };
  const duplicate = await runCardFixtureOperator(
    ["--fixture-id", FIXTURE_ID],
    environment(),
    {
      fetcher: duplicateFetch,
      stateExists: async () => false,
    },
  ).then(
    () => "unexpected",
    (error) => error instanceof CardFixtureError ? error.code : "other",
  );
  if (
    duplicate !== "duplicate_fixture_exists" ||
    duplicateTransport.calls.some((call) => call.method === "POST")
  ) {
    throw new Error("duplicate hosted fixture was not rejected safely");
  }
});

Deno.test("fixture isolation matches this run's unique label and retains older fixture rows", async () => {
  const transport = readOnlyTransport();
  await runCardFixtureOperator(
    ["--fixture-id", FIXTURE_ID],
    environment(),
    { fetcher: transport.fetcher, stateExists: async () => false },
  );
  const markerRequest = transport.calls.find((call) =>
    call.url.includes("pickup-%3E%3Elabel")
  );
  if (
    !markerRequest ||
    !markerRequest.url.includes(
      encodeURIComponent(`eq.${fixtureMarker(FIXTURE_ID)}_PICKUP`),
    )
  ) {
    throw new Error("fixture lookup did not isolate the fresh fixture UUID");
  }
});

Deno.test("execution approval is fixture-bound and local state cannot be reused", () => {
  const options = { fixtureId: FIXTURE_ID, execute: true };
  const wrong = environment({
    R06_EXECUTION_APPROVAL_REF:
      `${R06_EXECUTION_APPROVAL_PREFIX}00000000-0000-4000-8000-000000000000`,
  });
  if (
    errorCode(() => assertExecutionApproval(options, wrong)) !==
      "execution_approval_missing"
  ) {
    throw new Error("approval for another fixture was accepted");
  }
});

function canonicalExecutionTransport(): {
  fetcher: FetchLike;
  calls: { url: string; method: string }[];
  state: {
    booking: Record<string, unknown>;
    quote: Record<string, unknown>;
    payment: Record<string, unknown>;
    trip: Record<string, unknown>;
    attempt?: Record<string, unknown>;
  };
} {
  const calls: { url: string; method: string }[] = [];
  const state: {
    booking: Record<string, unknown>;
    quote: Record<string, unknown>;
    payment: Record<string, unknown>;
    trip: Record<string, unknown>;
    attempt?: Record<string, unknown>;
  } = {
    booking: booking("draft"),
    quote: quote("calculated"),
    payment: payment(),
    trip: trip(),
  };
  let driverOnTrip = false;
  const respond = (value: unknown, status = 200) =>
    new Response(JSON.stringify(value), { status });
  const fetcher: FetchLike = async (input, init) => {
    const url = new URL(String(input));
    const method = init?.method ?? "GET";
    calls.push({ url: `${url.origin}${url.pathname}${url.search}`, method });
    const body = typeof init?.body === "string"
      ? JSON.parse(init.body) as Record<string, unknown>
      : {};
    if (url.pathname === "/auth/v1/user") {
      const authorization = new Headers(init?.headers).get("authorization") ??
        "";
      return respond(
        authorization.includes("rider-session")
          ? { id: RIDER_ID, email: R06_RIDER_EMAIL }
          : { id: DRIVER_ID, email: R06_DRIVER_EMAIL },
      );
    }
    if (url.pathname === "/rest/v1/users") {
      const id = url.searchParams.get("id")?.slice(3);
      return respond([
        id === RIDER_ID
          ? {
            id: RIDER_ID,
            email: R06_RIDER_EMAIL,
            role: "rider",
            is_blocked: false,
          }
          : {
            id: DRIVER_ID,
            email: R06_DRIVER_EMAIL,
            role: "driver",
            is_blocked: false,
          },
      ]);
    }
    if (url.pathname === "/rest/v1/driver_profiles") {
      return respond([{ user_id: DRIVER_ID, approval_status: "approved" }]);
    }
    if (url.pathname === "/rest/v1/vehicles") {
      return respond([{
        id: R06_VEHICLE_ID,
        driver_id: DRIVER_ID,
        vehicle_type_code: "economy",
        is_active: true,
      }]);
    }
    if (url.pathname === "/rest/v1/driver_availability") {
      return respond([
        driverOnTrip
          ? {
            driver_id: DRIVER_ID,
            state: "onTrip",
            vehicle_id: R06_VEHICLE_ID,
            active_trip_id: TRIP_ID,
          }
          : {
            driver_id: DRIVER_ID,
            state: "available",
            vehicle_id: R06_VEHICLE_ID,
            reserved_booking_request_id: null,
            active_trip_id: null,
            version: 2,
          },
      ]);
    }
    if (url.pathname === "/rest/v1/booking_requests") {
      if (url.searchParams.has("pickup->>label")) return respond([]);
      if (url.searchParams.get("id") === `eq.${BOOKING_ID}`) {
        return respond([state.booking]);
      }
      return respond([]);
    }
    if (url.pathname === "/rest/v1/fare_quotes") return respond([state.quote]);
    if (url.pathname === "/rest/v1/trips") {
      return respond(
        url.searchParams.get("select") === "id" ? [] : [state.trip],
      );
    }
    if (url.pathname === "/rest/v1/payments") return respond([state.payment]);
    if (url.pathname === "/rest/v1/receipts") return respond([]);
    if (url.pathname === "/rest/v1/payment_attempts") {
      return respond(state.attempt ? [state.attempt] : []);
    }
    if (url.pathname === "/functions/v1/fare" && method === "POST") {
      return respond({
        data: {
          id: QUOTE_ID,
          booking_request_id: BOOKING_ID,
          quote_version: 1,
          fixed_fare_fils: 16000,
          currency: "JOD",
          status: "calculated",
        },
      });
    }
    if (!url.pathname.startsWith("/rest/v1/rpc/") || method !== "POST") {
      throw new Error(`Unexpected request ${method} ${url.pathname}`);
    }
    switch (url.pathname.slice("/rest/v1/rpc/".length)) {
      case "rider_create_booking_draft":
        state.booking = {
          ...booking("draft"),
          pickup: body.requested_pickup,
          destination: body.requested_destination,
        };
        return respond(state.booking);
      case "rider_lock_fare_quote":
        state.quote = quote("locked");
        state.booking = {
          ...state.booking,
          fare_quote_id: QUOTE_ID,
          version: 2,
        };
        return respond(state.quote);
      case "rider_confirm_booking":
        state.booking = { ...state.booking, status: "confirmed", version: 3 };
        return respond({ booking_request_id: BOOKING_ID, status: "confirmed" });
      case "backend_create_driver_match_offer":
        state.booking = { ...state.booking, status: "searching", version: 4 };
        return respond({
          id: OFFER_ID,
          booking_request_id: BOOKING_ID,
          driver_id: DRIVER_ID,
          vehicle_id: R06_VEHICLE_ID,
          fare_quote_id: QUOTE_ID,
          status: "offered",
          version: 1,
        });
      case "driver_transition_trip":
        driverOnTrip = true;
        state.trip = trip("accepted");
        state.booking = { ...state.booking, status: "matched", version: 5 };
        return respond({ trip_id: TRIP_ID, status: "accepted" });
      case "backend_record_payment_attempt":
        state.attempt = {
          ...attempt(new Date(NOW).toISOString()),
          idempotency_key: body.attempt_key,
          requested_amount_fils: body.amount_fils,
          payment_id: body.target_payment_id,
        };
        return respond(state.attempt);
      default:
        throw new Error(`Unexpected RPC ${url.pathname}`);
    }
  };
  return { fetcher, calls, state };
}

Deno.test("execute path uses canonical RPC allowlist, leaves Card pending, and never calls Stripe", async () => {
  const transport = canonicalExecutionTransport();
  const stateWrites: string[] = [];
  const environmentForExecution = environment({
    R06_EXECUTION_APPROVAL_REF: `${R06_EXECUTION_APPROVAL_PREFIX}${FIXTURE_ID}`,
  });
  const result = await runCardFixtureOperator(
    ["--fixture-id", FIXTURE_ID, "--execute"],
    environmentForExecution,
    {
      fetcher: transport.fetcher,
      now: () => NOW,
      stateExists: async () => false,
      reserveState: async (_path, payload) => {
        stateWrites.push(payload);
      },
    },
  );
  if (
    result.status !== "fixture_created" || result.tripId !== TRIP_ID ||
    result.paymentId !== PAYMENT_ID || result.attemptId !== ATTEMPT_ID
  ) {
    throw new Error("canonical fixture result did not reconcile");
  }
  const allowedPosts = new Set([
    "/functions/v1/fare",
    "/rest/v1/rpc/rider_create_booking_draft",
    "/rest/v1/rpc/rider_lock_fare_quote",
    "/rest/v1/rpc/rider_confirm_booking",
    "/rest/v1/rpc/backend_create_driver_match_offer",
    "/rest/v1/rpc/driver_transition_trip",
    "/rest/v1/rpc/backend_record_payment_attempt",
  ]);
  for (const call of transport.calls) {
    const path = new URL(call.url).pathname;
    if (call.method === "POST" && !allowedPosts.has(path)) {
      throw new Error(`Unexpected mutating path ${path}`);
    }
    if (/stripe\.com/iu.test(call.url)) {
      throw new Error("Stripe endpoint was called");
    }
  }
  if (stateWrites.length !== 1 || !stateWrites[0].includes(FIXTURE_ID)) {
    throw new Error("execution guard journal was not reserved before writes");
  }
  if (
    transport.state.payment.card_status !== "cardPaymentPending" ||
    transport.state.attempt?.status !== "pending"
  ) {
    throw new Error(
      "fixture changed financial state beyond pending preparation",
    );
  }
});
