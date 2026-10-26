/** Canonical test-Trip staging only; no completion, settlement, or replay. */
export interface FixtureTripIdentity {
  tripId: string;
  bookingId: string;
  driverId: string;
  riderId: string;
  vehicleId: string;
}

export type FixtureStagingStatus =
  | "driverArriving"
  | "driverArrived"
  | "inProgress";

export interface FixtureTripLifecycle {
  readTrip(): Promise<Record<string, unknown>>;
  transition(
    status: FixtureStagingStatus,
    expectedVersion: number,
    idempotencyKey: string,
  ): Promise<Record<string, unknown>>;
  commandKey(status: FixtureStagingStatus): string;
}

function requireCanonicalTrip(
  row: Record<string, unknown>,
  identity: FixtureTripIdentity,
  status: "accepted" | FixtureStagingStatus,
  expectedVersion?: number,
): number {
  const version = row.version;
  if (
    row.id !== identity.tripId ||
    row.booking_request_id !== identity.bookingId ||
    row.driver_id !== identity.driverId || row.rider_id !== identity.riderId ||
    row.vehicle_id !== identity.vehicleId || row.payment_method !== "cash" ||
    row.status !== status || typeof version !== "number" ||
    !Number.isSafeInteger(version) || version < 1 ||
    (expectedVersion !== undefined && version !== expectedVersion)
  ) throw new Error("trip_state_unverified_no_further_command");
  return version;
}

/**
 * Matches private.enforce_trip_transition: accepted -> driverArriving ->
 * driverArrived -> inProgress. Each command is dispatched once, followed by a
 * canonical reread. A rejected/unknown result ends the sequence without retry.
 * The operator's execution authorization must cover all three staging statuses.
 */
export async function stageAcceptedFixtureTrip(
  identity: FixtureTripIdentity,
  lifecycle: FixtureTripLifecycle,
): Promise<Record<string, unknown>> {
  let trip = await lifecycle.readTrip();
  let version = requireCanonicalTrip(trip, identity, "accepted");
  const statuses: readonly FixtureStagingStatus[] = [
    "driverArriving",
    "driverArrived",
    "inProgress",
  ];
  for (const status of statuses) {
    const key = lifecycle.commandKey(status);
    if (key.trim() !== key || key.length < 1 || key.length > 128) {
      throw new Error("invalid_fixture_command_key");
    }
    const result = await lifecycle.transition(status, version, key);
    if (result.trip_id !== identity.tripId || result.status !== status) {
      throw new Error("trip_transition_result_unverified_do_not_retry");
    }
    trip = await lifecycle.readTrip();
    version = requireCanonicalTrip(trip, identity, status, version + 1);
  }
  return trip;
}
