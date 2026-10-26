import type { CanonicalIntentContext } from "./test_intent_provider.ts";
import type {
  TestIntentReservation,
  TestIntentReservationStore,
} from "./test_intent_reservation.ts";

/** Deterministic persistence fake for unit tests only; never production composition. */
export class ReservationFixture implements TestIntentReservationStore {
  readonly rows = new Map<string, TestIntentReservation>();
  records = 0;
  loseClaimAcknowledgement = false;
  loseRecordAcknowledgement = false;
  async claim(context: CanonicalIntentContext): Promise<TestIntentReservation> {
    const old = this.rows.get(context.attemptId);
    if (old) return { ...old, disposition: "existing", claimToken: undefined };
    if (
      [...this.rows.values()].some((r) =>
        r.context.paymentId === context.paymentId ||
        r.context.idempotencyKey === context.idempotencyKey
      )
    ) throw new Error("conflict");
    const row: TestIntentReservation = {
      disposition: "claimed",
      state: "reserved",
      context: Object.freeze({ ...context }),
      claimToken: "10000000-0000-4000-8000-000000000001",
      reference: null,
    };
    this.rows.set(context.attemptId, row);
    if (this.loseClaimAcknowledgement) throw new Error("lost claim acknowledgement");
    return row;
  }
  async record(id: string, token: string, reference: string | null): Promise<void> {
    this.records++;
    const row = this.rows.get(id)!;
    if (row.claimToken !== token) throw new Error("wrong claim");
    if (row.state !== "prepared") {
      this.rows.set(id, { ...row, state: reference ? "prepared" : "unknown", reference });
    }
    if (this.loseRecordAcknowledgement) throw new Error("lost record acknowledgement");
  }
  async read(context: CanonicalIntentContext): Promise<TestIntentReservation | null> {
    const row = this.rows.get(context.attemptId);
    return row ? { ...row, disposition: "existing", claimToken: undefined } : null;
  }
}
