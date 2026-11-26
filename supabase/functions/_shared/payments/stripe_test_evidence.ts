import {
  type CanonicalEvidenceContext,
  type EvidenceObservation,
  observeProviderEvidence,
} from "./provider_evidence.ts";

/** Server-only, test-mode GETs. No dispatch, persistence, or transition authority. */
export async function readStripeTestEvidence(
  context: CanonicalEvidenceContext,
  readSecret: () => string | undefined,
  transport: typeof fetch = fetch,
): Promise<EvidenceObservation> {
  const unresolved: EvidenceObservation = { disposition: "UNRESOLVED" };
  if (context.provider !== "stripe" || !/^acct_[A-Za-z0-9]+$/.test(context.account)) {
    return unresolved;
  }
  return await observeProviderEvidence(context, {
    async read(reference) {
      if (!/^pi_[A-Za-z0-9]+$/.test(reference)) throw new Error("invalid reference");
      const secret = readSecret();
      if (!secret || !/^(sk|rk)_test_[A-Za-z0-9_]+$/.test(secret)) throw new Error("unavailable");
      async function get(path: string): Promise<Record<string, unknown>> {
        const response = await transport(`https://api.stripe.com/v1/${path}`, {
          method: "GET",
          redirect: "error",
          signal: AbortSignal.timeout(10000),
          headers: { Authorization: `Bearer ${secret}` },
        });
        if (!response.ok) throw new Error("unavailable");
        const raw = await response.text();
        if (raw.length > 16384) throw new Error("invalid response");
        const value: unknown = JSON.parse(raw);
        if (!value || typeof value !== "object" || Array.isArray(value)) {
          throw new Error("invalid response");
        }
        return value as Record<string, unknown>;
      }
      const account = await get("account");
      if (account.object !== "account" || account.id !== context.account) {
        throw new Error("account mismatch");
      }
      const intent = await get(`payment_intents/${reference}`);
      const metadata = intent.metadata;
      if (!metadata || typeof metadata !== "object" || Array.isArray(metadata)) {
        throw new Error("missing metadata");
      }
      const m = metadata as Record<string, unknown>;
      const amount = context.amountFils / 10;
      if (
        !Number.isSafeInteger(amount) || amount <= 0 || intent.object !== "payment_intent" ||
        intent.id !== reference || intent.livemode !== false || intent.amount !== amount ||
        intent.currency !== "jod" || intent.capture_method !== "manual" ||
        (context.operation === "authorize" &&
          (intent.status !== "requires_capture" || intent.amount_capturable !== amount ||
            intent.amount_received !== 0)) ||
        (context.operation === "capture" &&
          (intent.status !== "succeeded" || intent.amount_received !== amount ||
            intent.amount_capturable !== 0))
      ) throw new Error("invalid intent");
      return {
        provider: "stripe",
        account: account.id,
        environment: "test",
        reference: intent.id,
        amountFils: context.amountFils,
        currency: "JOD",
        status: intent.status,
        metadata: {
          tripId: m.ridex_trip_id,
          paymentId: m.ridex_payment_id,
          attemptId: m.ridex_attempt_id,
        },
      };
    },
  });
}
