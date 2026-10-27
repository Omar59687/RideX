/** Fixed test scope and strict canonical-row guards for the R06 Card fixture. */
export const R06_PROJECT_URL = "https://ykasivejjchupswqyxpm.supabase.co";
export const R06_NAMESPACE = "ridex-grad-ykasivejjchupswqyxpm-v1";
export const R06_RIDER_EMAIL = "yousufrider@gmail.com";
export const R06_DRIVER_EMAIL = "yousufdriver@gmail.com";
export const R06_VEHICLE_ID = "48d007ab-c13c-4ff8-93f3-1dc7f1e6975d";
export const R06_TEST_ROUTE = {
  pickup: { latitude: 31.95, longitude: 35.91 },
  destination: { latitude: 31.96, longitude: 35.92 },
} as const;
export const R06_FIXTURE_LABEL_PREFIX = "RIDEX_R06_CARD_TEST_";
export const R06_EXECUTION_APPROVAL_PREFIX = "owner-approved-r06-card-fixture-";
export const INITIAL_AUTHORIZATION_WINDOW_MS = 120_000;

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const OPERATION_KEY = /^[A-Za-z0-9:_-]{8,128}$/u;

export class CardFixtureError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

export interface CardFixtureOptions {
  fixtureId: string;
  execute: boolean;
}

export interface CardFixtureEnvironment {
  SUPABASE_URL?: string;
  RIDEX_BACKEND_NAMESPACE?: string;
  SUPABASE_ANON_KEY?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
  R06_RIDER_ACCESS_TOKEN?: string;
  R06_DRIVER_ACCESS_TOKEN?: string;
  LOCALAPPDATA?: string;
  R06_FIXTURE_STATE_FILE?: string;
  R06_EXECUTION_APPROVAL_REF?: string;
}

export interface CardFixtureActor {
  id: string;
  email: string;
  role: "rider" | "driver";
  is_blocked: false;
  approval_status?: string;
}

export function parseCardFixtureArgs(args: string[]): CardFixtureOptions {
  let fixtureId = "";
  let execute = false;
  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    if (arg === "--execute") {
      if (execute) throw new CardFixtureError("invalid_arguments");
      execute = true;
      continue;
    }
    if (arg === "--fixture-id") {
      if (fixtureId || !args[index + 1]) {
        throw new CardFixtureError("invalid_arguments");
      }
      fixtureId = args[++index];
      continue;
    }
    throw new CardFixtureError("invalid_arguments");
  }
  if (!UUID.test(fixtureId)) throw new CardFixtureError("invalid_fixture_id");
  return { fixtureId: fixtureId.toLowerCase(), execute };
}

export function fixtureMarker(fixtureId: string): string {
  if (!UUID.test(fixtureId)) throw new CardFixtureError("invalid_fixture_id");
  return `${R06_FIXTURE_LABEL_PREFIX}${fixtureId.toLowerCase()}`;
}

export function fixtureOperationKeys(fixtureId: string): {
  confirmation: string;
  acceptance: string;
  authorization: string;
} {
  const marker = fixtureMarker(fixtureId).replace(
    "RIDEX_R06_CARD_TEST_",
    "r06-card-",
  );
  const keys = {
    confirmation: `${marker}-confirm`,
    acceptance: `${marker}-accept`,
    authorization: `${marker}-initial-auth`,
  };
  if (Object.values(keys).some((key) => !OPERATION_KEY.test(key))) {
    throw new CardFixtureError("invalid_fixture_id");
  }
  return keys;
}

export function assertEnvironment(
  environment: CardFixtureEnvironment,
  execute: boolean,
): void {
  if (
    environment.SUPABASE_URL !== R06_PROJECT_URL ||
    environment.RIDEX_BACKEND_NAMESPACE !== R06_NAMESPACE
  ) throw new CardFixtureError("project_or_namespace_mismatch");
  for (
    const name of [
      "SUPABASE_ANON_KEY",
      "SUPABASE_SERVICE_ROLE_KEY",
      "R06_RIDER_ACCESS_TOKEN",
      "R06_DRIVER_ACCESS_TOKEN",
    ] as const
  ) {
    if (!environment[name]?.trim()) {
      throw new CardFixtureError("configuration_missing");
    }
  }
  if (execute) {
    const statePath = environment.R06_FIXTURE_STATE_FILE?.trim();
    const localAppData = environment.LOCALAPPDATA?.trim().replace(
      /[\\/]+$/u,
      "",
    );
    const expectedStatePaths = localAppData
      ? [
        `${localAppData}\\RideX\\R06\\card-fixture-state.json`,
        `${localAppData}\\RideX\\R06\\concurrency-acceptance-state.json`,
      ]
      : [];
    if (
      !statePath || !isAbsolutePath(statePath) ||
      !expectedStatePaths.some((path) =>
        statePath.toLowerCase() === path.toLowerCase()
      )
    ) {
      throw new CardFixtureError("state_file_required");
    }
  }
}

function isAbsolutePath(value: string): boolean {
  return /^[A-Za-z]:[\\/]/u.test(value) || value.startsWith("\\\\") ||
    value.startsWith("/");
}

export function assertExecutionApproval(
  options: CardFixtureOptions,
  environment: CardFixtureEnvironment,
): void {
  if (!options.execute) throw new CardFixtureError("execution_flag_required");
  const expected = `${R06_EXECUTION_APPROVAL_PREFIX}${options.fixtureId}`;
  if (environment.R06_EXECUTION_APPROVAL_REF !== expected) {
    throw new CardFixtureError("execution_approval_missing");
  }
}

export function assertActor(
  actor: CardFixtureActor,
  expectedRole: "rider" | "driver",
): void {
  const expectedEmail = expectedRole === "rider"
    ? R06_RIDER_EMAIL
    : R06_DRIVER_EMAIL;
  if (
    !UUID.test(actor.id) || actor.email.toLowerCase() !== expectedEmail ||
    actor.role !== expectedRole || actor.is_blocked !== false ||
    (expectedRole === "driver" && actor.approval_status !== "approved")
  ) throw new CardFixtureError("fixture_actor_not_eligible");
}

export function assertCleanFixture(rows: unknown[]): void {
  if (rows.length !== 0) throw new CardFixtureError("duplicate_fixture_exists");
}

export function assertVehicle(
  vehicle: Record<string, unknown>,
  availability: Record<string, unknown>,
  driverId: string,
): void {
  if (
    vehicle.id !== R06_VEHICLE_ID || vehicle.driver_id !== driverId ||
    vehicle.vehicle_type_code !== "economy" || vehicle.is_active !== true ||
    availability.driver_id !== driverId || availability.state !== "available" ||
    availability.vehicle_id !== vehicle.id ||
    availability.reserved_booking_request_id !== null ||
    availability.active_trip_id !== null ||
    !positiveVersion(availability.version)
  ) throw new CardFixtureError("driver_vehicle_not_available");
}

export function assertBooking(
  row: Record<string, unknown>,
  expected: {
    id?: string;
    riderId: string;
    fixtureId: string;
    status: string;
    version?: number;
    expectQuote?: boolean;
  },
): void {
  const marker = fixtureMarker(expected.fixtureId);
  const pickupLabel = asRecord(row.pickup)?.label;
  const destinationLabel = asRecord(row.destination)?.label;
  if (
    (expected.id !== undefined && row.id !== expected.id) ||
    row.rider_id !== expected.riderId || row.payment_method !== "card" ||
    row.vehicle_type_code !== "economy" || row.status !== expected.status ||
    pickupLabel !== `${marker}_PICKUP` ||
    destinationLabel !== `${marker}_DESTINATION` ||
    !positiveVersion(row.version) ||
    (expected.version !== undefined && row.version !== expected.version) ||
    (expected.expectQuote === true &&
      (typeof row.fare_quote_id !== "string" ||
        !UUID.test(row.fare_quote_id))) ||
    (expected.expectQuote !== true && row.fare_quote_id !== null)
  ) throw new CardFixtureError("canonical_booking_mismatch");
}

export function assertLockedQuote(
  quote: Record<string, unknown>,
  expected: {
    bookingId: string;
    riderId: string;
    vehicleTypeCode?: string;
    status?: "calculated" | "locked";
  },
): void {
  if (
    !UUID.test(String(quote.id)) ||
    quote.booking_request_id !== expected.bookingId ||
    quote.rider_id !== expected.riderId ||
    (expected.vehicleTypeCode !== undefined &&
      quote.vehicle_type_code !== expected.vehicleTypeCode) ||
    quote.status !== (expected.status ?? "locked") ||
    quote.currency !== "JOD" || !positiveMoney(quote.fixed_fare_fils) ||
    (quote.fixed_fare_fils as number) % 10 !== 0 ||
    !positiveVersion(quote.quote_version) ||
    typeof quote.expires_at !== "string" ||
    Date.parse(quote.expires_at) <= Date.now()
  ) throw new CardFixtureError("locked_fare_unavailable");
}

export function assertTrip(
  trip: Record<string, unknown>,
  expected: {
    tripId?: string;
    bookingId: string;
    riderId: string;
    driverId: string;
    vehicleId: string;
    fareQuoteId: string;
    fareFils: number;
    status: "accepted";
  },
): void {
  if (
    !UUID.test(String(trip.id)) ||
    (expected.tripId !== undefined && trip.id !== expected.tripId) ||
    trip.booking_request_id !== expected.bookingId ||
    trip.rider_id !== expected.riderId ||
    trip.driver_id !== expected.driverId ||
    trip.vehicle_id !== expected.vehicleId ||
    trip.fare_quote_id !== expected.fareQuoteId ||
    trip.payment_method !== "card" ||
    trip.status !== expected.status || trip.currency !== "JOD" ||
    !positiveVersion(trip.version) || !positiveMoney(trip.original_fare_fils) ||
    trip.original_fare_fils !== trip.current_fare_fils ||
    trip.original_fare_fils !== expected.fareFils
  ) throw new CardFixtureError("canonical_trip_mismatch");
}

export function assertPayment(
  payment: Record<string, unknown>,
  expected: {
    tripId: string;
    riderId: string;
    amountFils: number;
    status?: string;
  },
): void {
  if (
    !UUID.test(String(payment.id)) || payment.trip_id !== expected.tripId ||
    payment.rider_id !== expected.riderId || payment.method !== "card" ||
    payment.card_status !== (expected.status ?? "cardPaymentPending") ||
    payment.currency !== "JOD" ||
    payment.authorized_amount_fils !== expected.amountFils ||
    payment.final_amount_fils !== expected.amountFils ||
    !positiveVersion(payment.version) ||
    payment.cash_status !== null || payment.provider_name !== null ||
    payment.card_brand !== null || payment.card_last_four !== null ||
    payment.authorized_at !== null || payment.paid_at !== null ||
    payment.cancelled_at !== null || payment.refunded_at !== null ||
    payment.sanitized_failure_code !== null
  ) throw new CardFixtureError("canonical_payment_mismatch");
}

export function assertAttempt(
  attempt: Record<string, unknown>,
  expected: {
    paymentId: string;
    amountFils: number;
    operationKey: string;
    now?: number;
  },
): void {
  const createdAt = typeof attempt.created_at === "string"
    ? Date.parse(attempt.created_at)
    : NaN;
  const now = expected.now ?? Date.now();
  if (
    !UUID.test(String(attempt.id)) ||
    attempt.payment_id !== expected.paymentId ||
    attempt.type !== "initialAuthorization" || attempt.status !== "pending" ||
    attempt.authorization_cycle !== 1 || attempt.provider_name !== "stripe" ||
    attempt.attempt_sequence !== 1 || attempt.refund_id !== null ||
    attempt.idempotency_key !== expected.operationKey ||
    attempt.requested_amount_fils !== expected.amountFils ||
    attempt.currency !== "JOD" ||
    attempt.provider_transaction_reference !== null ||
    attempt.sanitized_failure_code !== null ||
    attempt.sanitized_failure_message !== null ||
    attempt.completed_at !== null || attempt.verified_at !== null ||
    !Number.isFinite(createdAt) ||
    createdAt > now || now - createdAt >= INITIAL_AUTHORIZATION_WINDOW_MS
  ) throw new CardFixtureError("canonical_attempt_mismatch_or_expired");
}

export function assertNoRows(rows: unknown[], code: string): void {
  if (rows.length !== 0) throw new CardFixtureError(code);
}

function positiveVersion(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}

function positiveMoney(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) &&
    value > 0 && value <= 99_999_999;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}
