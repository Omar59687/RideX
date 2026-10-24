import { type CanonicalIntentContext, type PreparedTestIntent,
  type TestIntentProvider, TestIntentError } from "./test_intent_provider.ts";

/** Explicit test-only fake. Never a production fallback or financial result. */
export class FakeTestIntentProvider implements TestIntentProvider {
  readonly calls: CanonicalIntentContext[] = [];
  readonly #originals = new Map<string, string>();
  async prepare(context: CanonicalIntentContext): Promise<PreparedTestIntent> {
    const snapshot = JSON.stringify(context);
    const original = this.#originals.get(context.idempotencyKey);
    if (original !== undefined && original !== snapshot) {
      throw new TestIntentError("provider_rejected");
    }
    this.#originals.set(context.idempotencyKey, snapshot);
    this.calls.push(Object.freeze({ ...context }));
    return Object.freeze({ provider: "stripe", reference: "pi_TestFixture",
      requiresCanonicalVerification: true });
  }
}
