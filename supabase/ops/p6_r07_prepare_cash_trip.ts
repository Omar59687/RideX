/**
 * Operator-only P6-R07 setup. Default mode is read-only preflight. Execution is
 * deliberately limited to the approved graduation test project and accounts.
 * Vehicle mode uses authenticated Driver RPCs; Trip mode creates an offer and
 * starts one canonical Cash Trip. Neither mode completes, settles, retries, or
 * cleans up, and neither issues a Receipt.
 */
import {
  assertApprovedActor,
  assertFixturePrerequisites,
  assertVehiclePrerequisites,
  parseFixtureArgs,
  R07_ACTORS,
  R07_ENDPOINT,
  R07_NAMESPACE,
} from "./p6_r07_fixture_contract.ts";
import { stageAcceptedFixtureTrip } from "./p6_r07_trip_lifecycle.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const safeFailure =
  "R07 fixture stopped safely; inspect the designated test project using authorized read-only tools.";

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error("configuration_missing");
  return value;
}

async function requestJson(
  path: string,
  options: {
    method?: string;
    token: string;
    apikey: string;
    body?: unknown;
  },
): Promise<unknown> {
  const key = options.apikey;
  let response: Response;
  try {
    response = await fetch(new URL(path, R07_ENDPOINT), {
      method: options.method ?? "GET",
      headers: {
        apikey: key,
        authorization: `Bearer ${options.token}`,
        accept: "application/json",
        ...(options.body === undefined
          ? {}
          : { "content-type": "application/json" }),
      },
      ...(options.body === undefined
        ? {}
        : { body: JSON.stringify(options.body) }),
      signal: AbortSignal.timeout(8000),
    });
  } catch {
    throw new Error("request_outcome_unknown");
  }
  if (!response.ok) throw new Error("backend_request_rejected");
  try {
    return await response.json();
  } catch {
    throw new Error("backend_response_invalid");
  }
}

function oneRow(payload: unknown): Record<string, unknown> {
  if (
    !Array.isArray(payload) || payload.length !== 1 ||
    typeof payload[0] !== "object" || payload[0] === null
  ) {
    throw new Error("fixture_prerequisites_not_met");
  }
  return payload[0] as Record<string, unknown>;
}

function noRows(payload: unknown): unknown[] {
  if (!Array.isArray(payload)) throw new Error("backend_response_invalid");
  return payload;
}

function rpcObject(payload: unknown): Record<string, unknown> {
  const row = Array.isArray(payload) && payload.length === 1
    ? payload[0]
    : payload;
  if (typeof row !== "object" || row === null || Array.isArray(row)) {
    throw new Error("backend_response_invalid");
  }
  return row as Record<string, unknown>;
}

async function actor(
  token: string,
  anonKey: string,
  serviceKey: string,
  role: "driver" | "rider",
) {
  const auth = rpcObject(
    await requestJson("/auth/v1/user", { token, apikey: anonKey }),
  );
  if (typeof auth.id !== "string" || !UUID.test(auth.id)) {
    throw new Error("fixture_actor_not_eligible");
  }
  const profile = oneRow(
    await requestJson(
      `/rest/v1/users?select=id,email,role,is_blocked&id=eq.${auth.id}&limit=2`,
      { token: serviceKey, apikey: serviceKey },
    ),
  );
  if (profile.id !== auth.id || profile.email !== auth.email) {
    throw new Error("fixture_actor_not_eligible");
  }
  let actorProfile = profile;
  if (role === "driver") {
    actorProfile = {
      ...profile,
      ...oneRow(
        await requestJson(
          `/rest/v1/driver_profiles?select=user_id,approval_status&user_id=eq.${auth.id}&limit=2`,
          { token: serviceKey, apikey: serviceKey },
        ),
      ),
    };
  }
  assertApprovedActor(actorProfile, role);
  return { id: auth.id, email: auth.email as string };
}

async function main(): Promise<void> {
  const options = parseFixtureArgs(Deno.args);
  const namespace = requiredEnv("RIDEX_BACKEND_NAMESPACE");
  const anonKey = requiredEnv("SUPABASE_ANON_KEY");
  const serviceKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  const driverToken = requiredEnv("R07_DRIVER_ACCESS_TOKEN");
  if (namespace !== R07_NAMESPACE) {
    throw new Error("backend_namespace_mismatch");
  }
  if (options.execute) {
    const approvalRef = requiredEnv("R07_EXECUTION_APPROVAL_REF");
    if (approvalRef.length < 8 || approvalRef.length > 128) {
      throw new Error("execution_approval_missing");
    }
  }

  const driver = await actor(driverToken, anonKey, serviceKey, "driver");
  if (driver.email !== R07_ACTORS.driver) {
    throw new Error("fixture_actor_not_eligible");
  }

  if (options.prepareVehicle) {
    const [vehiclesPayload, availabilityPayload] = await Promise.all([
      requestJson(
        `/rest/v1/vehicles?select=id&driver_id=eq.${driver.id}&limit=2`,
        { token: serviceKey, apikey: serviceKey },
      ),
      requestJson(
        `/rest/v1/driver_availability?select=driver_id,state,vehicle_id,reserved_booking_request_id,active_trip_id,version&driver_id=eq.${driver.id}&limit=2`,
        { token: serviceKey, apikey: serviceKey },
      ),
    ]);
    const vehicles = noRows(vehiclesPayload);
    const availability = oneRow(availabilityPayload);
    assertVehiclePrerequisites(vehicles, availability, driver.id);
    if (!options.execute) {
      console.log(
        "R07 Driver vehicle read-only preflight passed; no records were changed.",
      );
      return;
    }
    const created = rpcObject(
      await requestJson("/rest/v1/rpc/driver_create_vehicle", {
        method: "POST",
        token: driverToken,
        apikey: anonKey,
        body: {
          vehicle_type: "economy",
          vehicle_make: "RideX Test Fixture",
          vehicle_model: "QA Economy",
          vehicle_color: "Blue (Test)",
          vehicle_registration_plate: "RIDEX-TEST-ONLY",
          vehicle_seat_capacity: 4,
          vehicle_model_year: null,
          vehicle_photo_url: null,
        },
      }),
    );
    if (
      typeof created.id !== "string" || !UUID.test(created.id) ||
      created.driver_id !== driver.id || created.is_active !== false ||
      created.version !== 1
    ) throw new Error("vehicle_create_result_unverified_do_not_retry");

    const active = rpcObject(
      await requestJson("/rest/v1/rpc/driver_set_vehicle_active", {
        method: "POST",
        token: driverToken,
        apikey: anonKey,
        body: {
          target_vehicle_id: created.id,
          expected_version: created.version,
          active: true,
        },
      }),
    );
    if (
      active.id !== created.id || active.driver_id !== driver.id ||
      active.is_active !== true || !Number.isSafeInteger(active.version)
    ) throw new Error("vehicle_activation_unverified_no_further_command");

    const available = rpcObject(
      await requestJson("/rest/v1/rpc/driver_set_availability", {
        method: "POST",
        token: driverToken,
        apikey: anonKey,
        body: {
          requested_state: "available",
          requested_vehicle_id: created.id,
          expected_version: availability.version,
        },
      }),
    );
    if (
      available.driver_id !== driver.id || available.state !== "available" ||
      available.vehicle_id !== created.id
    ) throw new Error("vehicle_availability_unverified_no_further_command");
    console.log(
      "R07 synthetic Driver vehicle created and activated through authenticated Driver RPCs; no booking or Trip was changed.",
    );
    console.log(
      `Restricted fixture vehicle identifier: ${created.id}`,
    );
    console.log("No cleanup is performed.");
    return;
  }

  const riderToken = requiredEnv("R07_RIDER_ACCESS_TOKEN");
  const rider = await actor(riderToken, anonKey, serviceKey, "rider");
  if (rider.email !== R07_ACTORS.rider) {
    throw new Error("fixture_actor_not_eligible");
  }

  const [
    bookingPayload,
    vehiclePayload,
    availabilityPayload,
    tripsPayload,
    offersPayload,
  ] = await Promise.all([
    requestJson(
      `/rest/v1/booking_requests?select=id,rider_id,status,version,payment_method,vehicle_type_code,fare_quote_id&id=eq.${options.bookingId}&limit=2`,
      { token: serviceKey, apikey: serviceKey },
    ),
    requestJson(
      `/rest/v1/vehicles?select=id,driver_id,vehicle_type_code,is_active&id=eq.${options.vehicleId}&limit=2`,
      { token: serviceKey, apikey: serviceKey },
    ),
    requestJson(
      `/rest/v1/driver_availability?select=driver_id,state,vehicle_id&driver_id=eq.${driver.id}&limit=2`,
      { token: serviceKey, apikey: serviceKey },
    ),
    requestJson(
      `/rest/v1/trips?select=id&booking_request_id=eq.${options.bookingId}&limit=2`,
      { token: serviceKey, apikey: serviceKey },
    ),
    requestJson(
      `/rest/v1/driver_match_offers?select=id,status,driver_id&booking_request_id=eq.${options.bookingId}&limit=2`,
      { token: serviceKey, apikey: serviceKey },
    ),
  ]);
  const booking = oneRow(bookingPayload);
  const quote = oneRow(
    await requestJson(
      `/rest/v1/fare_quotes?select=id,booking_request_id,rider_id,status,vehicle_type_code&id=eq.${
        String(booking.fare_quote_id)
      }&limit=2`,
      { token: serviceKey, apikey: serviceKey },
    ),
  );
  assertFixturePrerequisites({
    booking,
    quote,
    vehicle: oneRow(vehiclePayload),
    availability: oneRow(availabilityPayload),
    trips: noRows(tripsPayload),
    offers: noRows(offersPayload),
    driverId: driver.id,
    riderId: rider.id,
    bookingId: options.bookingId,
    vehicleId: options.vehicleId,
  });

  if (!options.execute) {
    console.log(
      "R07 read-only preflight passed for the approved test scope; no records were changed.",
    );
    return;
  }

  const offer = rpcObject(
    await requestJson("/rest/v1/rpc/backend_create_driver_match_offer", {
      method: "POST",
      token: serviceKey,
      apikey: serviceKey,
      body: {
        target_booking_request_id: options.bookingId,
        target_driver_id: driver.id,
        target_vehicle_id: options.vehicleId,
        requested_radius_meters: 3000,
        expected_booking_version: booking.version,
      },
    }),
  );
  if (
    typeof offer.id !== "string" || !UUID.test(offer.id) ||
    offer.driver_id !== driver.id || offer.version !== 1
  ) {
    throw new Error("offer_result_unverified_do_not_retry");
  }

  const accepted = rpcObject(
    await requestJson("/rest/v1/rpc/driver_transition_trip", {
      method: "POST",
      token: driverToken,
      apikey: anonKey,
      body: {
        target_id: offer.id,
        requested_status: "accepted",
        expected_version: offer.version,
        idempotency_key: `p6-r07-accept-${crypto.randomUUID()}`,
      },
    }),
  );
  if (
    typeof accepted.trip_id !== "string" || !UUID.test(accepted.trip_id) ||
    accepted.status !== "accepted"
  ) {
    throw new Error("accept_result_unverified_do_not_retry");
  }

  const tripId = accepted.trip_id;
  const trip = await stageAcceptedFixtureTrip({
    tripId,
    bookingId: options.bookingId,
    driverId: driver.id,
    riderId: rider.id,
    vehicleId: options.vehicleId,
  }, {
    readTrip: async () =>
      oneRow(
        await requestJson(
          `/rest/v1/trips?select=id,booking_request_id,driver_id,rider_id,vehicle_id,status,version,payment_method&id=eq.${tripId}&driver_id=eq.${driver.id}&limit=2`,
          { token: driverToken, apikey: anonKey },
        ),
      ),
    transition: async (status, version, key) =>
      rpcObject(
        await requestJson(
          "/rest/v1/rpc/driver_transition_trip",
          {
            method: "POST",
            token: driverToken,
            apikey: anonKey,
            body: {
              target_id: tripId,
              requested_status: status,
              expected_version: version,
              idempotency_key: key,
            },
          },
        ),
      ),
    commandKey: (status) => `p6-r07-${status}-${crypto.randomUUID()}`,
  });
  console.log(
    "R07 canonical Cash Trip prepared and in progress. No completion, settlement, receipt, retry, or cleanup was performed.",
  );
  console.log(
    `Restricted fixture Trip identifier: ${trip.id}`,
  );
  console.log(
    "Record exact identifiers only in the restricted acceptance ledger; reconcile any uncertain result with authorized reads.",
  );
}

try {
  await main();
} catch {
  console.error(safeFailure);
  Deno.exitCode = 1;
}
