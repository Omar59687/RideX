/**
 * Operator-only R06 Card fixture. Default is read-only preflight. Execute mode
 * uses only existing Rider, Driver, fare, matching, and payment RPC contracts.
 * It never calls Stripe or advances a Payment/Attempt state.
 */
import {
  assertActor,
  assertAttempt,
  assertBooking,
  assertCleanFixture,
  assertEnvironment,
  assertExecutionApproval,
  assertLockedQuote,
  assertNoRows,
  assertPayment,
  assertTrip,
  assertVehicle,
  type CardFixtureActor,
  type CardFixtureEnvironment,
  CardFixtureError,
  type CardFixtureOptions,
  fixtureMarker,
  fixtureOperationKeys,
  INITIAL_AUTHORIZATION_WINDOW_MS,
  parseCardFixtureArgs,
  R06_DRIVER_EMAIL,
  R06_FIXTURE_LABEL_PREFIX,
  R06_PROJECT_URL,
  R06_RIDER_EMAIL,
  R06_TEST_ROUTE,
  R06_VEHICLE_ID,
} from "./r06_card_fixture_contract.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const MAX_RESPONSE_BYTES = 32 * 1024;
const REQUEST_TIMEOUT_MS = 8_000;
const ACTIVE_TRIP_STATUSES =
  "(accepted,driverArriving,driverArrived,inProgress)";

export type FetchLike = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Response | Promise<Response>;

export interface CardFixtureRuntime {
  fetcher?: FetchLike;
  now?: () => number;
  stateExists?: (path: string) => Promise<boolean>;
  reserveState?: (path: string, payload: string) => Promise<void>;
}

export interface CardFixtureResult {
  status: "preflight_passed" | "fixture_created";
  bookingId?: string;
  tripId?: string;
  paymentId?: string;
  attemptId?: string;
  amountFils?: number;
  currency?: "JOD";
}

interface FixtureContext {
  rider: CardFixtureActor;
  driver: CardFixtureActor;
  bookingId: string;
  fareQuoteId: string;
  tripId: string;
  paymentId: string;
  paymentVersion: number;
  tripVersion: number;
  amountFils: number;
  operationKey: string;
}

function record(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new CardFixtureError("backend_response_invalid");
  }
  return value as Record<string, unknown>;
}

function rows(value: unknown): Record<string, unknown>[] {
  if (
    !Array.isArray(value) ||
    value.some((entry) =>
      typeof entry !== "object" || entry === null || Array.isArray(entry)
    )
  ) {
    throw new CardFixtureError("backend_response_invalid");
  }
  return value as Record<string, unknown>[];
}

function oneRow(value: unknown): Record<string, unknown> {
  const list = Array.isArray(value) ? rows(value) : [record(value)];
  if (list.length !== 1) {
    throw new CardFixtureError("canonical_row_unavailable");
  }
  return list[0];
}

function positiveVersion(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}

function quoteRoute(options: CardFixtureOptions): {
  pickup: Record<string, unknown>;
  destination: Record<string, unknown>;
} {
  const marker = fixtureMarker(options.fixtureId);
  return {
    pickup: {
      ...R06_TEST_ROUTE.pickup,
      label: `${marker}_PICKUP`,
    },
    destination: {
      ...R06_TEST_ROUTE.destination,
      label: `${marker}_DESTINATION`,
    },
  };
}

class SupabaseFixtureGateway {
  readonly #fetch: FetchLike;
  readonly #now: () => number;
  readonly #anonKey: string;
  readonly #serviceKey: string;

  constructor(
    private readonly environment: CardFixtureEnvironment,
    runtime: CardFixtureRuntime,
  ) {
    this.#fetch = runtime.fetcher ?? fetch;
    this.#now = runtime.now ?? Date.now;
    this.#anonKey = environment.SUPABASE_ANON_KEY!;
    this.#serviceKey = environment.SUPABASE_SERVICE_ROLE_KEY!;
  }

  async #request(path: string, options: {
    method?: string;
    token: string;
    apiKey: string;
    body?: unknown;
  }): Promise<unknown> {
    let response: Response;
    try {
      response = await this.#fetch(new URL(path, R06_PROJECT_URL), {
        method: options.method ?? "GET",
        redirect: "error",
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
        headers: {
          apikey: options.apiKey,
          authorization: `Bearer ${options.token}`,
          accept: "application/json",
          ...(options.body === undefined
            ? {}
            : { "content-type": "application/json" }),
        },
        ...(options.body === undefined
          ? {}
          : { body: JSON.stringify(options.body) }),
      });
    } catch {
      throw new CardFixtureError("request_outcome_unknown_stop_do_not_retry");
    }
    let text: string;
    try {
      text = await response.text();
    } catch {
      throw new CardFixtureError("request_outcome_unknown_stop_do_not_retry");
    }
    if (new TextEncoder().encode(text).byteLength > MAX_RESPONSE_BYTES) {
      throw new CardFixtureError("backend_response_invalid");
    }
    if (!response.ok) {
      // Never emit raw Postgres or Data API error text from an operator process.
      throw new CardFixtureError("canonical_operation_rejected_stop_no_retry");
    }
    try {
      return text ? JSON.parse(text) : null;
    } catch {
      throw new CardFixtureError("backend_response_invalid");
    }
  }

  async #select(
    table: string,
    params: Record<string, string>,
  ): Promise<Record<string, unknown>[]> {
    const url = new URL(`/rest/v1/${table}`, R06_PROJECT_URL);
    for (const [key, value] of Object.entries(params)) {
      url.searchParams.set(key, value);
    }
    return rows(
      await this.#request(url.pathname + url.search, {
        token: this.#serviceKey,
        apiKey: this.#serviceKey,
      }),
    );
  }

  async #rpc(
    name: string,
    body: Record<string, unknown>,
    identity: { token: string; apiKey: string },
  ): Promise<Record<string, unknown>> {
    return oneRow(
      await this.#request(`/rest/v1/rpc/${name}`, {
        method: "POST",
        token: identity.token,
        apiKey: identity.apiKey,
        body,
      }),
    );
  }

  async #authUser(token: string): Promise<Record<string, unknown>> {
    return record(
      await this.#request("/auth/v1/user", {
        token,
        apiKey: this.#anonKey,
      }),
    );
  }

  async authenticate(role: "rider" | "driver"): Promise<CardFixtureActor> {
    const token = role === "rider"
      ? this.environment.R06_RIDER_ACCESS_TOKEN!
      : this.environment.R06_DRIVER_ACCESS_TOKEN!;
    const authUser = await this.#authUser(token);
    if (
      typeof authUser.id !== "string" || !UUID.test(authUser.id) ||
      typeof authUser.email !== "string"
    ) {
      throw new CardFixtureError("fixture_actor_not_eligible");
    }
    const profileRows = await this.#select("users", {
      select: "id,email,role,is_blocked",
      id: `eq.${authUser.id}`,
      limit: "2",
    });
    const profile = profileRows.length === 1 ? profileRows[0] : null;
    if (
      !profile || profile.id !== authUser.id || profile.email !== authUser.email
    ) {
      throw new CardFixtureError("fixture_actor_not_eligible");
    }
    let approvalStatus: "approved" | undefined;
    if (role === "driver") {
      const driverProfiles = await this.#select("driver_profiles", {
        select: "user_id,approval_status",
        user_id: `eq.${authUser.id}`,
        limit: "2",
      });
      if (
        driverProfiles.length !== 1 || driverProfiles[0].user_id !== authUser.id
      ) {
        throw new CardFixtureError("fixture_actor_not_eligible");
      }
      approvalStatus = driverProfiles[0].approval_status === "approved"
        ? "approved"
        : undefined;
    }
    const actor = {
      id: authUser.id,
      email: authUser.email,
      role: profile.role,
      is_blocked: profile.is_blocked,
      ...(approvalStatus === undefined
        ? {}
        : { approval_status: approvalStatus }),
    } as CardFixtureActor;
    assertActor(actor, role);
    return actor;
  }

  async #riderRpc(
    name: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const rider = await this.authenticate("rider");
    if (rider.email !== R06_RIDER_EMAIL) {
      throw new CardFixtureError("fixture_actor_not_eligible");
    }
    return this.#rpc(name, body, {
      token: this.environment.R06_RIDER_ACCESS_TOKEN!,
      apiKey: this.#anonKey,
    });
  }

  async #driverRpc(
    name: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const driver = await this.authenticate("driver");
    if (driver.email !== R06_DRIVER_EMAIL) {
      throw new CardFixtureError("fixture_actor_not_eligible");
    }
    return this.#rpc(name, body, {
      token: this.environment.R06_DRIVER_ACCESS_TOKEN!,
      apiKey: this.#anonKey,
    });
  }

  async #backendRpc(
    name: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    return this.#rpc(name, body, {
      token: this.#serviceKey,
      apiKey: this.#serviceKey,
    });
  }

  async #fareQuote(
    bookingId: string,
    version: number,
  ): Promise<Record<string, unknown>> {
    const rider = await this.authenticate("rider");
    if (rider.email !== R06_RIDER_EMAIL) {
      throw new CardFixtureError("fixture_actor_not_eligible");
    }
    const result = record(
      await this.#request("/functions/v1/fare", {
        method: "POST",
        token: this.environment.R06_RIDER_ACCESS_TOKEN!,
        apiKey: this.#anonKey,
        body: {
          operation: "quote",
          booking_request_id: bookingId,
          expected_booking_version: version,
        },
      }),
    );
    return record(result.data);
  }

  async #readOne(
    table: string,
    params: Record<string, string>,
  ): Promise<Record<string, unknown>> {
    const found = await this.#select(table, { ...params, limit: "2" });
    if (found.length !== 1) {
      throw new CardFixtureError("canonical_row_unavailable");
    }
    return found[0];
  }

  async #readBooking(bookingId: string): Promise<Record<string, unknown>> {
    return this.#readOne("booking_requests", {
      select:
        "id,rider_id,status,version,payment_method,vehicle_type_code,fare_quote_id,pickup,destination",
      id: `eq.${bookingId}`,
    });
  }

  async #readQuote(quoteId: string): Promise<Record<string, unknown>> {
    return this.#readOne("fare_quotes", {
      select:
        "id,booking_request_id,rider_id,status,vehicle_type_code,quote_version,fixed_fare_fils,currency,expires_at",
      id: `eq.${quoteId}`,
    });
  }

  async #readTrip(tripId: string): Promise<Record<string, unknown>> {
    return this.#readOne("trips", {
      select:
        "id,booking_request_id,rider_id,driver_id,vehicle_id,fare_quote_id,payment_method,status,version,currency,original_fare_fils,current_fare_fils",
      id: `eq.${tripId}`,
    });
  }

  async preflight(options: CardFixtureOptions): Promise<{
    rider: CardFixtureActor;
    driver: CardFixtureActor;
  }> {
    const [rider, driver] = await Promise.all([
      this.authenticate("rider"),
      this.authenticate("driver"),
    ]);
    const [
      vehicleRows,
      availabilityRows,
      fixtureRows,
      driverTrips,
      riderTrips,
    ] = await Promise.all([
      this.#select("vehicles", {
        select: "id,driver_id,vehicle_type_code,is_active",
        id: `eq.${R06_VEHICLE_ID}`,
        limit: "2",
      }),
      this.#select("driver_availability", {
        select:
          "driver_id,state,vehicle_id,reserved_booking_request_id,active_trip_id,version",
        driver_id: `eq.${driver.id}`,
        limit: "2",
      }),
      this.#select("booking_requests", {
        select: "id",
        rider_id: `eq.${rider.id}`,
        "pickup->>label": `like.${R06_FIXTURE_LABEL_PREFIX}*_PICKUP`,
        limit: "2",
      }),
      this.#select("trips", {
        select: "id",
        driver_id: `eq.${driver.id}`,
        status: `in.${ACTIVE_TRIP_STATUSES}`,
        limit: "2",
      }),
      this.#select("trips", {
        select: "id",
        rider_id: `eq.${rider.id}`,
        status: `in.${ACTIVE_TRIP_STATUSES}`,
        limit: "2",
      }),
    ]);
    if (vehicleRows.length !== 1 || availabilityRows.length !== 1) {
      throw new CardFixtureError("driver_vehicle_not_available");
    }
    assertVehicle(vehicleRows[0], availabilityRows[0], driver.id);
    assertCleanFixture(fixtureRows);
    assertNoRows(driverTrips, "driver_has_conflicting_trip");
    assertNoRows(riderTrips, "rider_has_conflicting_trip");

    const operationKey = fixtureOperationKeys(options.fixtureId).authorization;
    const priorAttempts = await this.#select("payment_attempts", {
      select: "id",
      idempotency_key: `eq.${operationKey}`,
      limit: "2",
    });
    assertNoRows(priorAttempts, "duplicate_fixture_operation_key");
    return { rider, driver };
  }

  async create(options: CardFixtureOptions, actors: {
    rider: CardFixtureActor;
    driver: CardFixtureActor;
  }, now: () => number): Promise<CardFixtureResult> {
    const keys = fixtureOperationKeys(options.fixtureId);
    const route = quoteRoute(options);

    // This authenticated Rider RPC has no idempotency parameter. The fixture
    // marker plus a durable local create-new state file make repeats fail closed.
    const draftResult = await this.#riderRpc("rider_create_booking_draft", {
      requested_pickup: route.pickup,
      requested_destination: route.destination,
      requested_vehicle_type: "economy",
      requested_payment_method: "card",
      requested_stops: [],
    });
    const bookingId = draftResult.id;
    if (typeof bookingId !== "string" || !UUID.test(bookingId)) {
      throw new CardFixtureError("booking_create_result_unverified_stop");
    }
    const draft = await this.#readBooking(bookingId);
    assertBooking(draft, {
      id: bookingId,
      riderId: actors.rider.id,
      fixtureId: options.fixtureId,
      status: "draft",
    });

    const calculated = await this.#fareQuote(
      bookingId,
      draft.version as number,
    );
    if (
      calculated.booking_request_id !== bookingId ||
      !UUID.test(String(calculated.id)) ||
      calculated.status !== "calculated" || calculated.currency !== "JOD" ||
      typeof calculated.quote_version !== "number" ||
      !positiveVersion(calculated.quote_version)
    ) throw new CardFixtureError("fare_calculation_unverified_stop");
    const quote = await this.#readQuote(calculated.id as string);
    assertLockedQuote(quote, {
      bookingId,
      riderId: actors.rider.id,
      vehicleTypeCode: "economy",
      status: "calculated",
    });

    const lockedResult = await this.#riderRpc("rider_lock_fare_quote", {
      target_booking_request_id: bookingId,
      target_fare_quote_id: quote.id,
      expected_booking_version: draft.version,
      expected_quote_version: quote.quote_version,
    });
    if (lockedResult.id !== quote.id || lockedResult.status !== "locked") {
      throw new CardFixtureError("fare_lock_unverified_stop");
    }
    const lockedQuote = await this.#readQuote(quote.id as string);
    assertLockedQuote(lockedQuote, {
      bookingId,
      riderId: actors.rider.id,
      vehicleTypeCode: "economy",
    });
    if (lockedQuote.fixed_fare_fils !== quote.fixed_fare_fils) {
      throw new CardFixtureError("fare_lock_unverified_stop");
    }
    const lockedBooking = await this.#readBooking(bookingId);
    assertBooking(lockedBooking, {
      id: bookingId,
      riderId: actors.rider.id,
      fixtureId: options.fixtureId,
      status: "draft",
      expectQuote: true,
    });
    if (lockedBooking.fare_quote_id !== quote.id) {
      throw new CardFixtureError("fare_lock_unverified_stop");
    }

    await this.#riderRpc("rider_confirm_booking", {
      target_booking_request_id: bookingId,
      expected_version: lockedBooking.version,
      idempotency_key: keys.confirmation,
    });
    const confirmed = await this.#readBooking(bookingId);
    assertBooking(confirmed, {
      id: bookingId,
      riderId: actors.rider.id,
      fixtureId: options.fixtureId,
      status: "confirmed",
      expectQuote: true,
    });
    if (confirmed.fare_quote_id !== quote.id) {
      throw new CardFixtureError("booking_confirmation_unverified_stop");
    }

    const offerResult = await this.#backendRpc(
      "backend_create_driver_match_offer",
      {
        target_booking_request_id: bookingId,
        target_driver_id: actors.driver.id,
        target_vehicle_id: R06_VEHICLE_ID,
        requested_radius_meters: 3000,
        expected_booking_version: confirmed.version,
      },
    );
    const offerId = offerResult.id;
    if (
      typeof offerId !== "string" || !UUID.test(offerId) ||
      offerResult.booking_request_id !== bookingId ||
      offerResult.driver_id !== actors.driver.id ||
      offerResult.vehicle_id !== R06_VEHICLE_ID ||
      offerResult.fare_quote_id !== quote.id ||
      offerResult.status !== "offered" ||
      !positiveVersion(offerResult.version)
    ) throw new CardFixtureError("match_offer_unverified_stop");

    const acceptResult = await this.#driverRpc("driver_transition_trip", {
      target_id: offerId,
      requested_status: "accepted",
      expected_version: offerResult.version,
      idempotency_key: keys.acceptance,
    });
    const tripId = acceptResult.trip_id;
    if (
      typeof tripId !== "string" || !UUID.test(tripId) ||
      acceptResult.status !== "accepted"
    ) throw new CardFixtureError("trip_acceptance_unverified_stop");

    const trip = await this.#readTrip(tripId);
    assertTrip(trip, {
      tripId,
      bookingId,
      riderId: actors.rider.id,
      driverId: actors.driver.id,
      vehicleId: R06_VEHICLE_ID,
      fareQuoteId: quote.id as string,
      fareFils: quote.fixed_fare_fils as number,
      status: "accepted",
    });

    const [paymentRows, receipts, currentAvailability] = await Promise.all([
      this.#select("payments", {
        select:
          "id,booking_request_id,trip_id,rider_id,method,authorized_amount_fils,final_amount_fils,currency,cash_status,card_status,provider_name,card_brand,card_last_four,authorized_at,paid_at,cancelled_at,refunded_at,sanitized_failure_code,version",
        booking_request_id: `eq.${bookingId}`,
        limit: "2",
      }),
      this.#select("receipts", {
        select: "id",
        trip_id: `eq.${tripId}`,
        limit: "2",
      }),
      this.#readOne("driver_availability", {
        select: "driver_id,state,active_trip_id,vehicle_id",
        driver_id: `eq.${actors.driver.id}`,
      }),
    ]);
    assertNoRows(receipts, "unexpected_receipt_exists");
    if (
      paymentRows.length !== 1 ||
      currentAvailability.driver_id !== actors.driver.id ||
      currentAvailability.state !== "onTrip" ||
      currentAvailability.active_trip_id !== tripId ||
      currentAvailability.vehicle_id !== R06_VEHICLE_ID
    ) {
      throw new CardFixtureError("canonical_payment_or_driver_state_mismatch");
    }
    const payment = paymentRows[0];
    assertPayment(payment, {
      tripId,
      riderId: actors.rider.id,
      amountFils: quote.fixed_fare_fils as number,
    });

    // This existing backend RPC creates exactly one canonical pending Attempt;
    // it cannot call Stripe and its response is reconciled before returning.
    const createdAtBeforeAttempt = now();
    const attemptResult = await this.#backendRpc(
      "backend_record_payment_attempt",
      {
        target_payment_id: payment.id,
        attempt_type: "initialAuthorization",
        amount_fils: payment.authorized_amount_fils,
        attempt_key: keys.authorization,
        provider: "stripe",
      },
    );
    const attemptId = attemptResult.id;
    if (typeof attemptId !== "string" || !UUID.test(attemptId)) {
      throw new CardFixtureError("attempt_create_result_unverified_stop");
    }
    const attemptRows = await this.#select("payment_attempts", {
      select:
        "id,payment_id,type,status,authorization_cycle,attempt_sequence,provider_name,idempotency_key,requested_amount_fils,currency,provider_transaction_reference,sanitized_failure_code,sanitized_failure_message,completed_at,verified_at,refund_id,created_at",
      id: `eq.${attemptId}`,
      payment_id: `eq.${payment.id}`,
      limit: "2",
    });
    if (
      attemptRows.length !== 1 ||
      now() - createdAtBeforeAttempt >= INITIAL_AUTHORIZATION_WINDOW_MS
    ) {
      throw new CardFixtureError("attempt_verification_unavailable_stop");
    }
    assertAttempt(attemptRows[0], {
      paymentId: payment.id as string,
      amountFils: payment.authorized_amount_fils as number,
      operationKey: keys.authorization,
      now: now(),
    });

    // Re-read financial state after appending the Attempt. The operator must
    // leave Payment/Trip pending and must never issue a receipt.
    const [finalPaymentRows, finalTrip, finalReceipts] = await Promise.all([
      this.#select("payments", {
        select:
          "id,booking_request_id,trip_id,rider_id,method,authorized_amount_fils,final_amount_fils,currency,cash_status,card_status,provider_name,card_brand,card_last_four,authorized_at,paid_at,cancelled_at,refunded_at,sanitized_failure_code,version",
        id: `eq.${payment.id}`,
        limit: "2",
      }),
      this.#readTrip(tripId),
      this.#select("receipts", {
        select: "id",
        trip_id: `eq.${tripId}`,
        limit: "2",
      }),
    ]);
    if (finalPaymentRows.length !== 1) {
      throw new CardFixtureError("canonical_payment_mismatch");
    }
    assertPayment(finalPaymentRows[0], {
      tripId,
      riderId: actors.rider.id,
      amountFils: quote.fixed_fare_fils as number,
    });
    assertTrip(finalTrip, {
      tripId,
      bookingId,
      riderId: actors.rider.id,
      driverId: actors.driver.id,
      vehicleId: R06_VEHICLE_ID,
      fareQuoteId: quote.id as string,
      fareFils: quote.fixed_fare_fils as number,
      status: "accepted",
    });
    assertNoRows(finalReceipts, "unexpected_receipt_exists");

    return {
      status: "fixture_created",
      bookingId,
      tripId,
      paymentId: payment.id as string,
      attemptId,
      amountFils: quote.fixed_fare_fils as number,
      currency: "JOD",
    };
  }
}

export async function runCardFixtureOperator(
  rawArgs: string[],
  environment: CardFixtureEnvironment,
  runtime: CardFixtureRuntime = {},
): Promise<CardFixtureResult> {
  const options = parseCardFixtureArgs(rawArgs);
  assertEnvironment(environment, options.execute);
  const statePath = environment.R06_FIXTURE_STATE_FILE;
  if (
    statePath && await (runtime.stateExists ?? defaultStateExists)(statePath)
  ) {
    throw new CardFixtureError("execution_state_exists_stop_and_reconcile");
  }
  const gateway = new SupabaseFixtureGateway(environment, runtime);
  const actors = await gateway.preflight(options);
  if (!options.execute) return { status: "preflight_passed" };

  assertExecutionApproval(options, environment);
  const executionStatePath = environment.R06_FIXTURE_STATE_FILE!;
  const exists = runtime.stateExists ?? defaultStateExists;
  if (await exists(executionStatePath)) {
    throw new CardFixtureError("execution_state_exists_stop_and_reconcile");
  }
  const reserveState = runtime.reserveState ?? defaultReserveState;
  await reserveState(
    executionStatePath,
    JSON.stringify({
      project: "ykasivejjchupswqyxpm",
      fixtureId: options.fixtureId,
      startedAt: new Date((runtime.now ?? Date.now)()).toISOString(),
      status: "started_do_not_retry",
    }),
  );
  return gateway.create(options, actors, runtime.now ?? Date.now);
}

async function defaultStateExists(path: string): Promise<boolean> {
  try {
    await Deno.stat(path);
    return true;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw new CardFixtureError("state_file_unavailable");
  }
}

async function defaultReserveState(
  path: string,
  payload: string,
): Promise<void> {
  try {
    await Deno.writeTextFile(path, `${payload}\n`, { createNew: true });
  } catch {
    throw new CardFixtureError("execution_state_exists_or_unavailable_stop");
  }
}

function readEnvironment(): CardFixtureEnvironment {
  return {
    SUPABASE_URL: Deno.env.get("SUPABASE_URL"),
    RIDEX_BACKEND_NAMESPACE: Deno.env.get("RIDEX_BACKEND_NAMESPACE"),
    SUPABASE_ANON_KEY: Deno.env.get("SUPABASE_ANON_KEY"),
    SUPABASE_SERVICE_ROLE_KEY: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    R06_RIDER_ACCESS_TOKEN: Deno.env.get("R06_RIDER_ACCESS_TOKEN"),
    R06_DRIVER_ACCESS_TOKEN: Deno.env.get("R06_DRIVER_ACCESS_TOKEN"),
    LOCALAPPDATA: Deno.env.get("LOCALAPPDATA"),
    R06_FIXTURE_STATE_FILE: Deno.env.get("R06_FIXTURE_STATE_FILE"),
    R06_EXECUTION_APPROVAL_REF: Deno.env.get("R06_EXECUTION_APPROVAL_REF"),
  };
}

if (import.meta.main) {
  try {
    const result = await runCardFixtureOperator(Deno.args, readEnvironment());
    console.log(JSON.stringify(result));
  } catch (error) {
    const code = error instanceof CardFixtureError
      ? error.code
      : "fixture_stopped_safely";
    console.error(JSON.stringify({ status: "BLOCKED", reason: code }));
    Deno.exitCode = 1;
  }
}
