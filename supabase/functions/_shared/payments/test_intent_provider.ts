/** Server-only preparation seam. Not an HTTP endpoint or a payment authority.
 * No confirmation, authorization, capture, refund, webhook or client secret API.
 */
export type IntentFailure =
  | "invalid_request"
  | "forbidden"
  | "stale_version"
  | "not_configured"
  | "provider_rejected"
  | "unknown_result"
  | "invalid_response";

export class TestIntentError extends Error {
  readonly code: IntentFailure;
  constructor(code: IntentFailure) {
    super(code);
    this.code = code;
    this.name = "TestIntentError";
  }
}

export interface IntentCommand {
  readonly paymentId: string;
  readonly attemptId: string;
  readonly expectedPaymentVersion: number;
  readonly expectedTripVersion: number;
  readonly idempotencyKey: string;
}

/** Must be read by an authenticated trusted server owner from canonical rows,
 * including the original operation key. No caller-supplied fare or Trip truth.
 */
export interface CanonicalIntentContext {
  readonly paymentId: string;
  readonly attemptId: string;
  readonly riderId: string;
  readonly paymentVersion: number;
  readonly tripId: string;
  readonly tripVersion: number;
  readonly driverId: string;
  readonly tripStatus: string;
  readonly method: string;
  readonly paymentStatus: string;
  readonly amountFils: number;
  readonly currency: string;
  readonly idempotencyKey: string;
}

export interface PreparedTestIntent {
  readonly provider: "stripe";
  readonly reference: string;
  readonly requiresCanonicalVerification: true;
}

export interface TestIntentProvider {
  prepare(context: CanonicalIntentContext): Promise<PreparedTestIntent>;
}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function validIntentContext(context: CanonicalIntentContext): boolean {
  return uuid.test(context.paymentId) && uuid.test(context.attemptId) &&
    uuid.test(context.riderId) && uuid.test(context.tripId) &&
    uuid.test(context.driverId) && context.tripStatus === "accepted" &&
    context.method === "card" && context.paymentStatus === "cardPaymentPending" &&
    context.currency === "JOD" && Number.isSafeInteger(context.amountFils) &&
    context.amountFils > 0 && context.amountFils <= 99999999 &&
    // Conservative supported precision: reject instead of rounding canonical fare.
    context.amountFils % 10 === 0 &&
    Number.isSafeInteger(context.paymentVersion) && context.paymentVersion > 0 &&
    Number.isSafeInteger(context.tripVersion) && context.tripVersion > 0 &&
    /^[A-Za-z0-9:_-]{8,128}$/.test(context.idempotencyKey);
}

export async function prepareTestIntent(
  command: IntentCommand,
  readAuthorizedContext: (paymentId: string) => Promise<CanonicalIntentContext | null>,
  provider: TestIntentProvider,
): Promise<PreparedTestIntent> {
  if (
    !uuid.test(command.paymentId) || !uuid.test(command.attemptId) ||
    !Number.isSafeInteger(command.expectedPaymentVersion) ||
    command.expectedPaymentVersion < 1 ||
    !Number.isSafeInteger(command.expectedTripVersion) || command.expectedTripVersion < 1 ||
    !/^[A-Za-z0-9:_-]{8,128}$/.test(command.idempotencyKey)
  ) {
    throw new TestIntentError("invalid_request");
  }
  let context: CanonicalIntentContext | null;
  try {
    context = await readAuthorizedContext(command.paymentId);
  } catch {
    throw new TestIntentError("forbidden");
  }
  if (
    !context || !validIntentContext(context) || context.paymentId !== command.paymentId ||
    context.attemptId !== command.attemptId ||
    context.idempotencyKey !== command.idempotencyKey
  ) {
    throw new TestIntentError("forbidden");
  }
  if (
    context.paymentVersion !== command.expectedPaymentVersion ||
    context.tripVersion !== command.expectedTripVersion
  ) {
    throw new TestIntentError("stale_version");
  }
  // Copy and freeze the canonical snapshot before the asynchronous provider seam.
  return provider.prepare(Object.freeze({ ...context }));
}

export interface StripeTestConfiguration {
  /** Server secret manager only; never Flutter config or a request field. */
  readonly readSecret: () => string | undefined;
  /** Explicit account/currency approval, absent by default. */
  readonly jodTestModeApproved: boolean;
  readonly transport: typeof fetch;
}

export class StripeTestIntentProvider implements TestIntentProvider {
  #configuration: StripeTestConfiguration;
  constructor(configuration: StripeTestConfiguration) {
    this.#configuration = configuration;
  }

  #secret(): string {
    let secret: string | undefined;
    try {
      secret = this.#configuration.readSecret();
    } catch {
      throw new TestIntentError("not_configured");
    }
    if (
      !this.#configuration.jodTestModeApproved || !secret ||
      !/^(sk|rk)_test_[A-Za-z0-9_]+$/.test(secret)
    ) {
      throw new TestIntentError("not_configured");
    }
    return secret;
  }

  assertReady(): void {
    this.#secret();
  }

  async prepare(context: CanonicalIntentContext): Promise<PreparedTestIntent> {
    if (!validIntentContext(context)) throw new TestIntentError("invalid_request");
    const secret = this.#secret();
    const stripeAmount = context.amountFils / 10;
    const body = new URLSearchParams({
      amount: String(stripeAmount),
      currency: "jod",
      capture_method: "manual",
      confirmation_method: "manual",
      confirm: "false",
      "payment_method_types[]": "card",
      "metadata[ridex_payment_id]": context.paymentId,
      "metadata[ridex_attempt_id]": context.attemptId,
      "metadata[ridex_trip_id]": context.tripId,
    });
    let response: Response;
    try {
      response = await this.#configuration.transport(
        "https://api.stripe.com/v1/payment_intents",
        {
          method: "POST",
          redirect: "error",
          signal: AbortSignal.timeout(10000),
          headers: {
            Authorization: `Bearer ${secret}`,
            "Content-Type": "application/x-www-form-urlencoded",
            "Idempotency-Key": context.idempotencyKey,
          },
          body,
        },
      );
    } catch {
      throw new TestIntentError("unknown_result");
    }
    if (!response.ok) {
      throw new TestIntentError(response.status >= 500 ? "unknown_result" : "provider_rejected");
    }
    return await this.#parse(response, context);
  }

  /** Exact trusted reference from the durable reservation only. GET never replays creation. */
  async read(
    context: CanonicalIntentContext,
    reference: string,
  ): Promise<PreparedTestIntent | null> {
    if (!validIntentContext(context) || !/^pi_[A-Za-z0-9]+$/.test(reference)) {
      throw new TestIntentError("invalid_request");
    }
    const secret = this.#secret();
    let response: Response;
    try {
      response = await this.#configuration.transport(
        `https://api.stripe.com/v1/payment_intents/${reference}`,
        {
          method: "GET",
          redirect: "error",
          signal: AbortSignal.timeout(10000),
          headers: { Authorization: `Bearer ${secret}` },
        },
      );
    } catch {
      throw new TestIntentError("unknown_result");
    }
    if (response.status === 404) return null;
    if (!response.ok) throw new TestIntentError("unknown_result");
    const result = await this.#parse(response, context);
    if (result.reference !== reference) throw new TestIntentError("invalid_response");
    return result;
  }

  async #parse(response: Response, context: CanonicalIntentContext): Promise<PreparedTestIntent> {
    const stripeAmount = context.amountFils / 10;
    try {
      const text = await response.text();
      if (text.length > 16384) throw new Error();
      const result = JSON.parse(text);
      if (
        result.object !== "payment_intent" || result.livemode !== false ||
        !/^pi_[A-Za-z0-9]+$/.test(result.id) ||
        result.amount !== stripeAmount || result.currency !== "jod" ||
        result.capture_method !== "manual" || result.confirmation_method !== "manual" ||
        result.status !== "requires_payment_method" || result.payment_method !== null ||
        result.amount_received !== 0 || result.amount_capturable !== 0 ||
        result.latest_charge !== null ||
        result.metadata?.ridex_payment_id !== context.paymentId ||
        result.metadata?.ridex_attempt_id !== context.attemptId ||
        result.metadata?.ridex_trip_id !== context.tripId
      ) throw new Error();
      // Intentionally discard client_secret and every other provider field.
      return Object.freeze({
        provider: "stripe",
        reference: result.id,
        requiresCanonicalVerification: true,
      });
    } catch {
      throw new TestIntentError("invalid_response");
    }
  }
}
