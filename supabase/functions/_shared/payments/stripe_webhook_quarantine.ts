import {
  verifyStripeTestWebhookEnvelope,
  WebhookVerificationError,
} from "./stripe_webhook_verifier.ts";
export interface QuarantinedWebhook {
  eventId: string;
  eventType: string;
  bodySha256: string;
  providerRef: string;
  tripId: string;
  paymentId: string;
  attemptId: string;
  amountFils: number;
  currency: "JOD";
}
export interface WebhookQuarantineStore {
  quarantine(evidence: QuarantinedWebhook): Promise<"quarantined" | "duplicate">;
}
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new WebhookVerificationError();
  }
  return value as Record<string, unknown>;
}
/** Verifies then quarantines only. No endpoint, provider dispatch, success or financial mutation. */
export async function quarantineStripeTestWebhook(
  raw: Uint8Array,
  signature: string | null,
  secret: string,
  account: string,
  now: number,
  store: WebhookQuarantineStore,
): Promise<"quarantined" | "duplicate"> {
  const snapshot = new Uint8Array(raw);
  const envelope = await verifyStripeTestWebhookEnvelope(snapshot, signature, secret, account, now);
  if (
    ![
      "payment_intent.created",
      "payment_intent.amount_capturable_updated",
      "payment_intent.succeeded",
      "payment_intent.payment_failed",
      "payment_intent.canceled",
    ].includes(envelope.eventType)
  ) throw new WebhookVerificationError();
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(snapshot));
  } catch {
    throw new WebhookVerificationError();
  }
  const object = record(record(record(parsed).data).object);
  const metadata = record(object.metadata);
  if (
    object.object !== "payment_intent" || object.livemode !== false ||
    typeof object.id !== "string" || !/^pi_[A-Za-z0-9]{1,253}$/.test(object.id) ||
    object.currency !== "jod" ||
    typeof object.amount !== "number" || !Number.isSafeInteger(object.amount) ||
    object.amount <= 0 || object.amount > 214748364 ||
    typeof metadata.ridex_trip_id !== "string" || !uuid.test(metadata.ridex_trip_id) ||
    typeof metadata.ridex_payment_id !== "string" || !uuid.test(metadata.ridex_payment_id) ||
    typeof metadata.ridex_attempt_id !== "string" || !uuid.test(metadata.ridex_attempt_id)
  ) throw new WebhookVerificationError();
  const result = await store.quarantine({
    eventId: envelope.eventId,
    eventType: envelope.eventType,
    bodySha256: envelope.bodySha256,
    providerRef: object.id,
    tripId: metadata.ridex_trip_id,
    paymentId: metadata.ridex_payment_id,
    attemptId: metadata.ridex_attempt_id,
    amountFils: object.amount * 10,
    currency: "JOD",
  });
  if (result !== "quarantined" && result !== "duplicate") throw new WebhookVerificationError();
  return result;
}
export class WebhookQuarantineRejected extends Error {}
export class WebhookQuarantineUnavailable extends Error {}

/** Server-only store: one request, no retry; ambiguous writes stay unresolved. */
export class SupabaseWebhookQuarantineStore implements WebhookQuarantineStore {
  private readonly base: URL;
  constructor(
    url: string,
    private readonly secret: string,
    private readonly send: typeof fetch = fetch,
  ) {
    this.base = new URL(url);
    const local = this.base.protocol === "http:" &&
      ["localhost", "127.0.0.1", "[::1]", "::1"].includes(this.base.hostname);
    if (
      (!local && this.base.protocol !== "https:") || this.base.username || this.base.password ||
      this.base.pathname !== "/" || this.base.search || this.base.hash || !secret
    ) throw new WebhookVerificationError();
  }
  async quarantine(e: QuarantinedWebhook): Promise<"quarantined" | "duplicate"> {
    let response: Response;
    try {
      response = await this.send(
        new URL("/rest/v1/rpc/backend_quarantine_test_webhook", this.base),
        {
          method: "POST",
          redirect: "error",
          signal: AbortSignal.timeout(4000),
          headers: { apikey: this.secret, "content-type": "application/json" },
          body: JSON.stringify({
            event_id: e.eventId,
            event_kind: e.eventType,
            body_hash: e.bodySha256,
            provider_ref: e.providerRef,
            target_trip_id: e.tripId,
            target_payment_id: e.paymentId,
            target_attempt_id: e.attemptId,
            amount_fils: e.amountFils,
            currency: e.currency,
          }),
        },
      );
      const text = await response.text();
      if (text.length > 4096) throw new Error();
      if (!response.ok) {
        let code: unknown;
        try {
          code = JSON.parse(text)?.code;
        } catch { /* untrusted response */ }
        if (["22023", "23505", "23514", "42501"].includes(String(code))) {
          throw new WebhookQuarantineRejected();
        }
        throw new Error();
      }
      if (text.length > 128) throw new Error();
      const result: unknown = JSON.parse(text);
      if (result !== "quarantined" && result !== "duplicate") throw new Error();
      return result;
    } catch (error) {
      if (error instanceof WebhookQuarantineRejected) throw error;
      throw new WebhookQuarantineUnavailable();
    }
  }
}
