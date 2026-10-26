/** Fixed scope and pure guards for the operator-run P6-R07 fixture tool. */
export const R07_ENDPOINT = "https://ykasivejjchupswqyxpm.supabase.co";
export const R07_NAMESPACE = "ridex-grad-ykasivejjchupswqyxpm-v1";
export const R07_ACTORS = {
  driver: "yousufdriver@gmail.com",
  rider: "yousufrider@gmail.com",
} as const;

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

export interface FixtureOptions {
  execute: boolean;
  prepareVehicle: boolean;
  bookingId: string;
  vehicleId: string;
}

export function parseFixtureArgs(args: string[]): FixtureOptions {
  const values = new Map<string, string>();
  let execute = false;
  let prepareVehicle = false;
  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    if (arg === "--execute") {
      if (execute) throw new Error("invalid_arguments");
      execute = true;
      continue;
    }
    if (arg === "--prepare-vehicle") {
      if (prepareVehicle) throw new Error("invalid_arguments");
      prepareVehicle = true;
      continue;
    }
    if (arg !== "--booking-id" && arg !== "--vehicle-id") {
      throw new Error("invalid_arguments");
    }
    const value = args[++index];
    if (!value || values.has(arg)) throw new Error("invalid_arguments");
    values.set(arg, value);
  }
  const bookingId = values.get("--booking-id") ?? "";
  const vehicleId = values.get("--vehicle-id") ?? "";
  if (prepareVehicle) {
    if (bookingId || vehicleId) throw new Error("invalid_arguments");
    return { execute, prepareVehicle, bookingId, vehicleId };
  }
  if (
    !UUID.test(bookingId) || !UUID.test(vehicleId) || bookingId === vehicleId
  ) {
    throw new Error("invalid_arguments");
  }
  return { execute, prepareVehicle, bookingId, vehicleId };
}

export function assertVehiclePrerequisites(
  vehicles: unknown[],
  availability: Record<string, unknown>,
  driverId: string,
): void {
  if (
    vehicles.length !== 0 || availability.driver_id !== driverId ||
    availability.state !== "offline" || availability.vehicle_id !== null ||
    availability.reserved_booking_request_id !== null ||
    availability.active_trip_id !== null ||
    !Number.isSafeInteger(availability.version) ||
    (availability.version as number) < 1
  ) throw new Error("vehicle_fixture_prerequisites_not_met");
}

export function assertApprovedActor(
  actual: {
    email?: unknown;
    role?: unknown;
    is_blocked?: unknown;
    approval_status?: unknown;
  },
  expectedRole: "driver" | "rider",
): void {
  const email = expectedRole === "driver"
    ? R07_ACTORS.driver
    : R07_ACTORS.rider;
  if (
    actual.email !== email || actual.role !== expectedRole ||
    actual.is_blocked !== false ||
    (expectedRole === "driver" && actual.approval_status !== "approved")
  ) throw new Error("fixture_actor_not_eligible");
}

export function assertFixturePrerequisites(input: {
  booking: Record<string, unknown>;
  quote: Record<string, unknown>;
  vehicle: Record<string, unknown>;
  availability: Record<string, unknown>;
  trips: unknown[];
  offers: unknown[];
  driverId: string;
  riderId: string;
  bookingId: string;
  vehicleId: string;
}): void {
  const { booking, quote, vehicle, availability } = input;
  if (
    booking.id !== input.bookingId || booking.rider_id !== input.riderId ||
    booking.status !== "confirmed" || booking.payment_method !== "cash" ||
    !Number.isSafeInteger(booking.version) || (booking.version as number) < 1 ||
    booking.fare_quote_id !== quote.id ||
    quote.booking_request_id !== booking.id ||
    quote.rider_id !== input.riderId || quote.status !== "locked" ||
    quote.vehicle_type_code !== booking.vehicle_type_code ||
    booking.vehicle_type_code !== vehicle.vehicle_type_code ||
    vehicle.id !== input.vehicleId || vehicle.driver_id !== input.driverId ||
    vehicle.is_active !== true || availability.driver_id !== input.driverId ||
    availability.state !== "available" ||
    availability.vehicle_id !== vehicle.id ||
    input.trips.length !== 0 || input.offers.length !== 0
  ) throw new Error("fixture_prerequisites_not_met");
}
