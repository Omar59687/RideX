import {
  assertApprovedActor,
  assertFixturePrerequisites,
  assertVehiclePrerequisites,
  parseFixtureArgs,
  R07_ENDPOINT,
  R07_NAMESPACE,
} from "../ops/p6_r07_fixture_contract.ts";
function assertEqual(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error("assertion_failed");
  }
}

function assertThrows(operation: () => unknown): void {
  try {
    operation();
  } catch {
    return;
  }
  throw new Error("expected_operation_to_throw");
}

const bookingId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const vehicleId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const driverId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const riderId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";

Deno.test("R07 fixture scope is pinned to the approved test backend", () => {
  assertEqual(R07_ENDPOINT, "https://ykasivejjchupswqyxpm.supabase.co");
  assertEqual(R07_NAMESPACE, "ridex-grad-ykasivejjchupswqyxpm-v1");
});

Deno.test("fixture parser defaults to read-only and requires two UUID identities", () => {
  assertEqual(
    parseFixtureArgs(["--booking-id", bookingId, "--vehicle-id", vehicleId]),
    {
      execute: false,
      prepareVehicle: false,
      bookingId,
      vehicleId,
    },
  );
  assertThrows(() =>
    parseFixtureArgs([
      "--execute",
      "--booking-id",
      "caller-id",
      "--vehicle-id",
      vehicleId,
    ])
  );
  assertEqual(parseFixtureArgs(["--prepare-vehicle"]), {
    execute: false,
    prepareVehicle: true,
    bookingId: "",
    vehicleId: "",
  });
  assertThrows(() =>
    parseFixtureArgs([
      "--prepare-vehicle",
      "--booking-id",
      bookingId,
      "--vehicle-id",
      vehicleId,
    ])
  );
  assertThrows(() =>
    parseFixtureArgs([
      "--execute",
      "--booking-id",
      bookingId,
      "--vehicle-id",
      vehicleId,
      "--endpoint",
      "https://prod.example",
    ])
  );
});

Deno.test("dedicated actor identity and Driver approval are exact", () => {
  assertApprovedActor({
    email: "yousufdriver@gmail.com",
    role: "driver",
    is_blocked: false,
    approval_status: "approved",
  }, "driver");
  assertApprovedActor({
    email: "yousufrider@gmail.com",
    role: "rider",
    is_blocked: false,
  }, "rider");
  assertThrows(() =>
    assertApprovedActor({
      email: "other@example.com",
      role: "driver",
      is_blocked: false,
      approval_status: "approved",
    }, "driver")
  );
  assertThrows(() =>
    assertApprovedActor({
      email: "yousufdriver@gmail.com",
      role: "driver",
      is_blocked: true,
      approval_status: "approved",
    }, "driver")
  );
  assertThrows(() =>
    assertApprovedActor({
      email: "yousufdriver@gmail.com",
      role: "driver",
      is_blocked: false,
      approval_status: "pending",
    }, "driver")
  );
});

function prerequisite(overrides: Record<string, unknown> = {}) {
  const input = {
    booking: {
      id: bookingId,
      rider_id: riderId,
      status: "confirmed",
      version: 4,
      payment_method: "cash",
      vehicle_type_code: "economy",
      fare_quote_id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
    },
    quote: {
      id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
      booking_request_id: bookingId,
      rider_id: riderId,
      status: "locked",
      vehicle_type_code: "economy",
    },
    vehicle: {
      id: vehicleId,
      driver_id: driverId,
      vehicle_type_code: "economy",
      is_active: true,
    },
    availability: {
      driver_id: driverId,
      state: "available",
      vehicle_id: vehicleId,
    },
    trips: [],
    offers: [],
    driverId,
    riderId,
    bookingId,
    vehicleId,
    ...overrides,
  };
  assertFixturePrerequisites(input);
}

Deno.test("canonical booking, quote, vehicle and availability are all required", () => {
  prerequisite();
  assertThrows(() =>
    prerequisite({
      booking: {
        id: bookingId,
        rider_id: riderId,
        status: "confirmed",
        version: 4,
        payment_method: "card",
        vehicle_type_code: "economy",
        fare_quote_id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
      },
    })
  );
  assertThrows(() =>
    prerequisite({
      vehicle: {
        id: vehicleId,
        driver_id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
        vehicle_type_code: "economy",
        is_active: true,
      },
    })
  );
  assertThrows(() =>
    prerequisite({
      availability: { driver_id: driverId, state: "offline", vehicle_id: null },
    })
  );
  assertThrows(() =>
    prerequisite({
      quote: {
        id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
        booking_request_id: bookingId,
        rider_id: riderId,
        status: "calculated",
        vehicle_type_code: "economy",
      },
    })
  );
  assertThrows(() => prerequisite({ trips: [{ id: "exists" }] }));
  assertThrows(() => prerequisite({ offers: [{ id: "exists" }] }));
});

Deno.test("vehicle setup requires empty owned inventory and offline availability", () => {
  assertVehiclePrerequisites([], {
    driver_id: driverId,
    state: "offline",
    vehicle_id: null,
    reserved_booking_request_id: null,
    active_trip_id: null,
    version: 1,
  }, driverId);
  assertThrows(() =>
    assertVehiclePrerequisites([{}], {
      driver_id: driverId,
      state: "offline",
      vehicle_id: null,
      reserved_booking_request_id: null,
      active_trip_id: null,
      version: 1,
    }, driverId)
  );
  assertThrows(() =>
    assertVehiclePrerequisites([], {
      driver_id: driverId,
      state: "available",
      vehicle_id: vehicleId,
      reserved_booking_request_id: null,
      active_trip_id: null,
      version: 2,
    }, driverId)
  );
});
