/** Server-only verification primitive. No endpoint, database write or financial transition.
 * A valid signature authenticates the envelope, not a Payment or provider effect.
 */
export class WebhookVerificationError extends Error {
  constructor() {
    super("invalid_webhook");
    this.name = "WebhookVerificationError";
  }
}

export interface VerifiedTestEventEnvelope {
  readonly provider: "stripe";
  readonly eventId: string;
  readonly eventType: string;
  readonly accountId: string;
  readonly eventCreated: number;
  readonly bodySha256: string;
}

const fail = (): never => {
  throw new WebhookVerificationError();
};
const bytes = new TextEncoder();
const maxBodyBytes = 1_048_576;
const maxHeaderBytes = 4096;
const toleranceSeconds = 300;

function signatureHeader(header: string): { timestamp: number; signatures: Uint8Array[] } {
  if (header.length > maxHeaderBytes) return fail();
  const parts = header.split(",").map((part) => part.trim());
  const timestamps = parts.filter((part) => part.startsWith("t="));
  const values = parts.filter((part) => part.startsWith("v1="));
  if (timestamps.length !== 1 || values.length < 1 || values.length > 8) return fail();
  const timestampText = timestamps[0].slice(2);
  if (!/^[0-9]{1,12}$/.test(timestampText)) return fail();
  const timestamp = Number(timestampText);
  if (!Number.isSafeInteger(timestamp)) return fail();
  const signatures = values.map((value) => {
    const hex = value.slice(3);
    if (!/^[a-fA-F0-9]{64}$/.test(hex)) return fail();
    return Uint8Array.from(hex.match(/../g)!, (pair) => parseInt(pair, 16));
  });
  return { timestamp, signatures };
}

/** Verify Stripe's timestamp.raw-body HMAC and a strictly test-mode envelope.
 * Caller must supply original bytes, the exact expected account, a server-only
 * secret and a trusted server clock. Account-less events are intentionally rejected.
 * The result deliberately omits raw payload and cannot authorize financial writes.
 */
export async function verifyStripeTestWebhookEnvelope(
  rawBody: Uint8Array,
  signature: string | null,
  secret: string,
  expectedAccount: string,
  nowSeconds: number,
): Promise<VerifiedTestEventEnvelope> {
  if (
    !(rawBody instanceof Uint8Array) || rawBody.length === 0 || rawBody.length > maxBodyBytes ||
    typeof signature !== "string" || !/^whsec_[A-Za-z0-9_]{8,}$/.test(secret) ||
    !/^acct_[A-Za-z0-9]+$/.test(expectedAccount) || !Number.isSafeInteger(nowSeconds)
  ) return fail();
  const snapshot = new Uint8Array(rawBody);
  const { timestamp, signatures } = signatureHeader(signature);
  if (Math.abs(nowSeconds - timestamp) > toleranceSeconds) return fail();
  const prefix = bytes.encode(`${timestamp}.`);
  const signed = new Uint8Array(prefix.length + snapshot.length);
  signed.set(prefix);
  signed.set(snapshot, prefix.length);
  const key = await crypto.subtle.importKey(
    "raw",
    bytes.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  let valid = false;
  for (const value of signatures) {
    valid = (await crypto.subtle.verify("HMAC", key, new Uint8Array(value), signed)) || valid;
  }
  if (!valid) return fail();
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(snapshot));
  } catch {
    return fail();
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return fail();
  const e = parsed as Record<string, unknown>;
  if (
    typeof e.id !== "string" || !/^evt_[A-Za-z0-9]+$/.test(e.id) || e.id.length > 256 ||
    typeof e.type !== "string" || !/^[a-z0-9_.]{1,128}$/.test(e.type) ||
    e.account !== expectedAccount || e.livemode !== false ||
    typeof e.created !== "number" || !Number.isSafeInteger(e.created) || e.created < 0
  ) return fail();
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", snapshot));
  const bodySha256 = Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("");
  return Object.freeze({
    provider: "stripe",
    eventId: e.id,
    eventType: e.type,
    accountId: expectedAccount,
    eventCreated: e.created,
    bodySha256,
  });
}
