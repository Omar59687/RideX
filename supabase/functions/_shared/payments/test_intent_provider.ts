/** Server-only preparation seam. Not an HTTP endpoint or a payment authority.
 * No confirmation, authorization, capture, refund, webhook or client secret API.
 */
export type IntentFailure = "invalid_request" | "forbidden" | "stale_version" |
  "not_configured" | "provider_rejected" | "unknown_result" | "invalid_response";

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
  readonly expectedPaymentVersion: number;
  readonly idempotencyKey: string;
}

/** Must be read by an authenticated trusted server owner from canonical rows,
 * including the original operation key. No caller-supplied fare or Trip truth.
 */
export interface CanonicalIntentContext {
  readonly paymentId: string;
  readonly paymentVersion: number;
  readonly tripId: string;
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
function valid(context: CanonicalIntentContext): boolean {
  return uuid.test(context.paymentId) && uuid.test(context.tripId) &&
    uuid.test(context.driverId) && context.tripStatus === "accepted" &&
    context.method === "card" && context.paymentStatus === "cardPaymentPending" &&
    context.currency === "JOD" && Number.isSafeInteger(context.amountFils) &&
    context.amountFils > 0 && context.amountFils <= 99999999 &&
    // Conservative supported precision: reject instead of rounding canonical fare.
    context.amountFils % 10 === 0 &&
    Number.isSafeInteger(context.paymentVersion) && context.paymentVersion > 0 &&
    /^[A-Za-z0-9:_-]{8,128}$/.test(context.idempotencyKey);
}

export async function prepareTestIntent(
  command: IntentCommand,
  readAuthorizedContext: (paymentId: string) => Promise<CanonicalIntentContext | null>,
  provider: TestIntentProvider,
): Promise<PreparedTestIntent> {
  if (!uuid.test(command.paymentId) ||
    !Number.isSafeInteger(command.expectedPaymentVersion) ||
    command.expectedPaymentVersion < 1 ||
    !/^[A-Za-z0-9:_-]{8,128}$/.test(command.idempotencyKey)) {
    throw new TestIntentError("invalid_request");
  }
  let context: CanonicalIntentContext | null;
  try { context = await readAuthorizedContext(command.paymentId); }
  catch { throw new TestIntentError("forbidden"); }
  if (!context || !valid(context) || context.paymentId !== command.paymentId ||
    context.idempotencyKey !== command.idempotencyKey) {
    throw new TestIntentError("forbidden");
  }
  if (context.paymentVersion !== command.expectedPaymentVersion) {
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

  async prepare(context: CanonicalIntentContext): Promise<PreparedTestIntent> {
    if (!valid(context)) throw new TestIntentError("invalid_request");
    let secret: string | undefined;
    try { secret = this.#configuration.readSecret(); }
    catch { throw new TestIntentError("not_configured"); }
    if (!this.#configuration.jodTestModeApproved || !secret ||
      !/^(sk|rk)_test_[A-Za-z0-9_]+$/.test(secret)) {
      throw new TestIntentError("not_configured");
    }
    const body = new URLSearchParams({
      amount: String(context.amountFils), currency: "jod",
      capture_method: "manual", confirmation_method: "manual", confirm: "false",
      "payment_method_types[]": "card",
    });
    let response: Response;
    try {
      response = await this.#configuration.transport(
        "https://api.stripe.com/v1/payment_intents", {
          method: "POST", redirect: "error", signal: AbortSignal.timeout(10000),
          headers: { Authorization: `Bearer ${secret}`,
            "Content-Type": "application/x-www-form-urlencoded",
            "Idempotency-Key": context.idempotencyKey },
          body,
        });
    } catch { throw new TestIntentError("unknown_result"); }
    if (!response.ok) throw new TestIntentError("provider_rejected");
    try {
      const text = await response.text();
      if (text.length > 16384) throw new Error();
      const result = JSON.parse(text);
      if (result.object !== "payment_intent" || result.livemode !== false ||
        !/^pi_[A-Za-z0-9]+$/.test(result.id) ||
        result.amount !== context.amountFils || result.currency !== "jod" ||
        result.capture_method !== "manual" || result.confirmation_method !== "manual" ||
        result.status !== "requires_payment_method" || result.payment_method !== null ||
        result.amount_received !== 0 || result.amount_capturable !== 0 ||
        result.latest_charge !== null) throw new Error();
      // Intentionally discard client_secret and every other provider field.
      return Object.freeze({ provider: "stripe", reference: result.id,
        requiresCanonicalVerification: true });
    } catch { throw new TestIntentError("invalid_response"); }
  }
}
