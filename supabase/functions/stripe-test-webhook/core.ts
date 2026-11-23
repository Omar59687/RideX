import type { WebhookAdmission } from "./admission.ts";
import {
  quarantineStripeTestWebhook,
  WebhookQuarantineRejected,
  type WebhookQuarantineStore,
} from "../_shared/payments/stripe_webhook_quarantine.ts";
import { WebhookVerificationError } from "../_shared/payments/stripe_webhook_verifier.ts";
const limit = 1_048_576;
export interface WebhookDependencies {
  enabled: boolean;
  secret: string;
  account: string;
  now: () => number;
  store: WebhookQuarantineStore;
  admission?: WebhookAdmission;
}
function reply(status: number, error?: string): Response {
  return new Response(JSON.stringify(error ? { error } : { received: true }), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      ...(status === 429 ? { "retry-after": "60" } : {}),
    },
  });
}
async function readRaw(request: Request): Promise<Uint8Array> {
  const length = request.headers.get("content-length");
  if (length !== null && (!/^\d+$/.test(length) || Number(length) > limit)) {
    throw new WebhookVerificationError();
  }
  const reader = request.body?.getReader();
  if (!reader) throw new WebhookVerificationError();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const part = await reader.read();
      if (part.done) break;
      size += part.value.byteLength;
      if (size > limit) {
        await reader.cancel();
        throw new WebhookVerificationError();
      }
      chunks.push(part.value);
    }
  } finally {
    reader.releaseLock();
  }
  const result = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  return result;
}
/** Test-mode webhook intake only; durable quarantine never executes financial transitions. */
export function createStripeTestWebhookHandler(
  deps: WebhookDependencies,
): (request: Request) => Promise<Response> {
  let active = 0;
  let windowStart = 0;
  let windowCount = 0;
  return async (request) => {
    if (!deps.enabled) return reply(503, "unavailable");
    if (request.method !== "POST") return reply(405, "method_not_allowed");
    if (
      request.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase() !==
        "application/json"
    ) return reply(400, "invalid_request");
    const now = deps.now();
    if (!Number.isSafeInteger(now) || now < 0) return reply(503, "unavailable");
    if (now < windowStart || now - windowStart >= 60) {
      windowStart = now;
      windowCount = 0;
    }
    if (active >= 8 || windowCount >= 60) return reply(429, "rate_limited");
    active++;
    windowCount++;
    let token: string | null = null;
    let result: Response = reply(503, "unavailable");
    try {
      if (!deps.admission) throw new Error("admission_unavailable");
      token = await deps.admission.acquire();
      if (token === null) {
        result = reply(429, "rate_limited");
      } else {
        const raw = await readRaw(request);
        await quarantineStripeTestWebhook(
          raw,
          request.headers.get("stripe-signature"),
          deps.secret,
          deps.account,
          now,
          deps.store,
        );
        result = reply(200);
      }
    } catch (error) {
      if (error instanceof WebhookVerificationError) result = reply(400, "invalid_webhook");
      else if (error instanceof WebhookQuarantineRejected) result = reply(422, "rejected");
      else result = reply(503, "unavailable");
    } finally {
      if (token !== null) {
        try {
          await deps.admission!.release(token);
        } catch {
          result = reply(503, "unavailable");
        }
      }
      active--;
    }
    return result;
  };
}
