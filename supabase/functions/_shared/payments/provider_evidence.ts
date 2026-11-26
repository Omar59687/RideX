/** Provider-neutral read-only observation. This module has no database or
 * financial transition access. Its output is NOT payment authority. A fake
 * reader is only suitable for local tests; no reader is wired to reconciliation.
 */
export interface ProviderEvidenceReader {
  read(providerReference: string): Promise<unknown>;
}
export interface CanonicalEvidenceContext {
  provider: string;
  account: string;
  tripId: string;
  paymentId: string;
  attemptId: string;
  attemptKey: string;
  reservationAttemptId: string;
  reservationPaymentId: string;
  reservationTripId: string;
  reservationKey: string;
  reservationState: string;
  providerReference: string | null;
  amountFils: number;
  currency: string;
  operation: "authorize" | "capture";
}
export type EvidenceObservation =
  | { readonly disposition: "UNRESOLVED" }
  | {
    readonly disposition: "OBSERVED";
    readonly status: "requires_capture" | "succeeded";
    readonly authoritative: false;
  };
const unresolved: EvidenceObservation = Object.freeze({ disposition: "UNRESOLVED" });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function object(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}
/** Caller must load context from server-owned canonical rows. No request fields
 * are authority. Unknown/mismatched data never causes a retry or mutation.
 */
export async function observeProviderEvidence(
  context: CanonicalEvidenceContext,
  reader: ProviderEvidenceReader,
): Promise<EvidenceObservation> {
  if (
    !context || !uuid.test(context.tripId) || !uuid.test(context.paymentId) ||
    !uuid.test(context.attemptId) ||
    context.reservationTripId !== context.tripId ||
    context.reservationPaymentId !== context.paymentId ||
    context.reservationAttemptId !== context.attemptId || !context.attemptKey ||
    context.reservationKey !== context.attemptKey ||
    context.reservationState !== "prepared" || typeof context.providerReference !== "string" ||
    !context.providerReference ||
    !context.provider || !context.account || context.currency !== "JOD" ||
    !Number.isSafeInteger(context.amountFils) || context.amountFils <= 0 ||
    !["authorize", "capture"].includes(context.operation)
  ) return unresolved;
  let raw: unknown;
  try {
    raw = await reader.read(context.providerReference);
  } catch {
    return unresolved;
  }
  const e = object(raw);
  const meta = object(e?.metadata);
  if (
    !e || !meta || e.provider !== context.provider || e.account !== context.account ||
    e.environment !== "test" ||
    e.reference !== context.providerReference || e.currency !== "JOD" ||
    e.amountFils !== context.amountFils ||
    meta.tripId !== context.tripId || meta.paymentId !== context.paymentId ||
    meta.attemptId !== context.attemptId
  ) return unresolved;
  const status = context.operation === "authorize" ? "requires_capture" : "succeeded";
  if (e.status !== status) return unresolved;
  return Object.freeze({ disposition: "OBSERVED", status, authoritative: false });
}
