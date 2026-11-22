/** LOCAL TEST FIXTURE ONLY. This has no Stripe identity or payment authority. */
export type FakeIdentity = Readonly<
  { provider: "local_fake"; account: string; environment: "local_test" }
>;
export function verifyLocalFakeIdentity(
  enabled: boolean,
  account: string,
): FakeIdentity {
  if (!enabled || !/^local_fake_[a-z0-9]{1,32}$/.test(account)) {
    throw new Error("local_fake_unavailable");
  }
  return Object.freeze({
    provider: "local_fake",
    account,
    environment: "local_test",
  });
}

import type { ProviderEvidenceReader } from "../../functions/_shared/payments/provider_evidence.ts";
/** Implements the existing read-only seam only in tests; never produces authority. */
export class LocalFakeEvidenceReader implements ProviderEvidenceReader {
  constructor(
    private readonly identity: FakeIdentity,
    private readonly evidence: Readonly<Record<string, unknown>>,
  ) {}
  read(reference: string): Promise<unknown> {
    if (
      !/^local_fake_[a-z0-9]{1,32}$/.test(reference) ||
      this.evidence.reference !== reference
    ) return Promise.reject(new Error("unknown"));
    return Promise.resolve({
      ...this.evidence,
      provider: this.identity.provider,
      account: this.identity.account,
      environment: "test",
    });
  }
}
