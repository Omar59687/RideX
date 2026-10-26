import {
  type CanonicalIntentContext,
  type PreparedTestIntent,
  TestIntentError,
  type TestIntentProvider,
  validIntentContext,
} from "./test_intent_provider.ts";

export interface TestIntentReservation {
  readonly disposition: "claimed" | "existing";
  readonly state: "reserved" | "unknown" | "prepared";
  readonly context: CanonicalIntentContext;
  readonly claimToken?: string;
  readonly reference: string | null;
}
export interface TestIntentReservationStore {
  claim(context: CanonicalIntentContext): Promise<TestIntentReservation>;
  record(attemptId: string, claimToken: string, reference: string | null): Promise<void>;
  read(context: CanonicalIntentContext): Promise<TestIntentReservation | null>;
}
const fields = [
  "paymentId",
  "attemptId",
  "riderId",
  "paymentVersion",
  "tripId",
  "tripVersion",
  "driverId",
  "tripStatus",
  "method",
  "paymentStatus",
  "amountFils",
  "currency",
  "idempotencyKey",
] as const;
export function sameIntentContext(a: CanonicalIntentContext, b: CanonicalIntentContext): boolean {
  return fields.every((key) => a[key] === b[key]);
}
function checked(value: unknown, expected: CanonicalIntentContext): TestIntentReservation {
  const row = value as TestIntentReservation | null;
  if (
    !row || !row.context || !validIntentContext(row.context) ||
    !sameIntentContext(row.context, expected) ||
    !["claimed", "existing"].includes(row.disposition) ||
    !["reserved", "unknown", "prepared"].includes(row.state) ||
    (row.disposition === "claimed" &&
      (row.state !== "reserved" || !/^[0-9a-f-]{36}$/i.test(row.claimToken ?? ""))) ||
    (row.state === "prepared" && !/^pi_[A-Za-z0-9]+$/.test(row.reference ?? "")) ||
    (row.state !== "prepared" && row.reference !== null)
  ) {
    throw new TestIntentError("unknown_result");
  }
  return row;
}

/** No leases/reclaim/TTL. Only the original positively acknowledged claim dispatches. */
export class DurableTestIntentProvider implements TestIntentProvider {
  constructor(
    readonly store: TestIntentReservationStore,
    readonly provider: TestIntentProvider,
    readonly assertReady: () => void,
  ) {}

  async prepare(context: CanonicalIntentContext): Promise<PreparedTestIntent> {
    if (!validIntentContext(context)) throw new TestIntentError("invalid_request");
    this.assertReady(); // missing account/key/JOD approval must not consume a claim.
    let reservation: TestIntentReservation;
    try {
      reservation = checked(await this.store.claim(context), context);
    } catch (error) {
      if (
        error instanceof TestIntentError &&
        (error.code === "stale_version" || error.code === "forbidden")
      ) throw error;
      throw new TestIntentError("unknown_result");
    }
    if (reservation.disposition === "existing") {
      // A reference permits read-only reconciliation, never a repeated POST.
      throw new TestIntentError("unknown_result");
    }
    const token = reservation.claimToken!;
    try {
      const result = await this.provider.prepare(Object.freeze({ ...reservation.context }));
      if (
        result.provider !== "stripe" || !/^pi_[A-Za-z0-9]+$/.test(result.reference) ||
        result.requiresCanonicalVerification !== true
      ) throw new Error("invalid_result");
      await this.store.record(context.attemptId, token, result.reference);
      return Object.freeze({
        provider: "stripe",
        reference: result.reference,
        requiresCanonicalVerification: true,
      });
    } catch {
      // All post-claim failures are uncertain, including lost persistence acknowledgement.
      // Best-effort unknown cannot downgrade an already persisted prepared reference.
      try {
        await this.store.record(context.attemptId, token, null);
      } catch { /* retain claim */ }
      throw new TestIntentError("unknown_result");
    }
  }
}

export interface ReadOnlyTestIntentProvider {
  read(context: CanonicalIntentContext, reference: string): Promise<PreparedTestIntent | null>;
}
export interface TestIntentReconciliation {
  readonly state: "preparation_verified" | "unresolved";
  readonly requiresCanonicalVerification: true;
}
/** No writes, claim creation, provider POST, retry, retirement or financial state transition. */
export async function reconcileReservedTestIntent(
  context: CanonicalIntentContext,
  store: TestIntentReservationStore,
  provider: ReadOnlyTestIntentProvider,
): Promise<TestIntentReconciliation> {
  const unresolved = Object.freeze({
    state: "unresolved" as const,
    requiresCanonicalVerification: true as const,
  });
  try {
    const existing = await store.read(context);
    if (!existing) return unresolved;
    const reservation = checked(existing, context);
    if (reservation.disposition !== "existing" || !reservation.reference) return unresolved;
    const observed = await provider.read(reservation.context, reservation.reference);
    if (
      !observed || observed.provider !== "stripe" ||
      observed.reference !== reservation.reference ||
      observed.requiresCanonicalVerification !== true
    ) return unresolved;
    // This proves only an unconfirmed test preparation, never authorization/capture/receipt.
    return Object.freeze({ state: "preparation_verified", requiresCanonicalVerification: true });
  } catch {
    return unresolved;
  }
}

export class SupabaseTestIntentReservationStore implements TestIntentReservationStore {
  readonly #base: URL;
  readonly #serviceKey: string;
  readonly #transport: typeof fetch;
  constructor(
    url: string,
    serviceKey: string,
    transport: typeof fetch = fetch,
  ) {
    this.#base = new URL(url);
    this.#serviceKey = serviceKey;
    this.#transport = transport;
    if (
      this.#base.protocol !== "https:" || this.#base.username || this.#base.password ||
      this.#base.pathname !== "/" || this.#base.search || this.#base.hash || !serviceKey
    ) {
      throw new TestIntentError("not_configured");
    }
  }
  async #rpc(name: string, body: Record<string, unknown>): Promise<unknown> {
    let response: Response;
    try {
      response = await this.#transport(new URL("/rest/v1/rpc/" + name, this.#base), {
        method: "POST",
        redirect: "error",
        signal: AbortSignal.timeout(4000),
        headers: {
          apikey: this.#serviceKey,
          authorization: "Bearer " + this.#serviceKey,
          "content-type": "application/json",
        },
        body: JSON.stringify(body),
      });
    } catch {
      throw new TestIntentError("unknown_result");
    }
    if (!response.ok) {
      // Never expose raw database messages or provider material.
      let code: unknown;
      try {
        const text = await response.text();
        if (text.length <= 16384) code = JSON.parse(text)?.code;
      } catch { /* untrusted/malformed errors stay unknown */ }
      if (code === "40001") throw new TestIntentError("stale_version");
      if (code === "42501" || code === "23505") throw new TestIntentError("forbidden");
      throw new TestIntentError("unknown_result");
    }
    try {
      const text = await response.text();
      if (text.length > 16384) throw new Error();
      return text ? JSON.parse(text) : null;
    } catch {
      throw new TestIntentError("unknown_result");
    }
  }
  async claim(context: CanonicalIntentContext): Promise<TestIntentReservation> {
    return checked(
      await this.#rpc("backend_claim_stripe_test_preparation", {
        actor_rider_id: context.riderId,
        target_trip_id: context.tripId,
        target_payment_id: context.paymentId,
        target_attempt_id: context.attemptId,
        expected_trip_version: context.tripVersion,
        expected_payment_version: context.paymentVersion,
        operation_key: context.idempotencyKey,
      }),
      context,
    );
  }
  async record(attemptId: string, claimToken: string, reference: string | null): Promise<void> {
    await this.#rpc("backend_record_stripe_test_preparation", {
      target_attempt_id: attemptId,
      original_claim_token: claimToken,
      prepared_reference: reference,
    });
  }
  async read(context: CanonicalIntentContext): Promise<TestIntentReservation | null> {
    const result = await this.#rpc("backend_read_stripe_test_preparation", {
      target_attempt_id: context.attemptId,
      actor_rider_id: context.riderId,
    });
    return result === null ? null : checked(result, context);
  }
}
