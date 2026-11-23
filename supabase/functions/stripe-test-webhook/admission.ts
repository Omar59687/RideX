/** Shared database-backed admission, service-only; no IP headers are trusted. */
export interface WebhookAdmission {
  acquire(): Promise<string | null>;
  release(token: string): Promise<void>;
}
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export class SupabaseWebhookAdmission implements WebhookAdmission {
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
    ) throw new Error("admission_unavailable");
  }
  private async call(name: string, body: object): Promise<unknown> {
    const response = await this.send(new URL(`/rest/v1/rpc/${name}`, this.base), {
      method: "POST",
      redirect: "error",
      signal: AbortSignal.timeout(4000),
      headers: { apikey: this.secret, "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!response.ok) throw new Error("admission_unavailable");
    const text = await response.text();
    if (text.length > 128) throw new Error("admission_unavailable");
    return JSON.parse(text);
  }
  async acquire(): Promise<string | null> {
    const value = await this.call("backend_acquire_test_webhook_admission", {});
    if (value === null) return null;
    if (typeof value !== "string" || !uuid.test(value)) throw new Error("admission_unavailable");
    return value;
  }
  async release(token: string): Promise<void> {
    if (
      !uuid.test(token) ||
      await this.call("backend_release_test_webhook_admission", { target_lease: token }) !== true
    ) throw new Error("admission_unavailable");
  }
}
