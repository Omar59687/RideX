import {
  CashMatchingError,
  type Row,
  SupabaseCashMatchingPort,
} from "../_shared/matching/cash_matching_adapter.ts";
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
/** Auth owner() must succeed before prepare; SQL checks this same session atomically. */
export class ServerAuthorizationPort extends SupabaseCashMatchingPort {
  constructor(
    url: string,
    publicKey: string,
    private readonly token: string,
    secret: string,
    send: typeof fetch = fetch,
  ) {
    super(url, publicKey, token, secret, send);
  }
  prepare(actor: string, input: Row): Promise<unknown> {
    let claims: Record<string, unknown>;
    try {
      const parts = this.token.split(".");
      if (parts.length !== 3 || parts[1].length > 8192) throw new Error();
      const base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
      claims = JSON.parse(atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, "=")));
    } catch {
      throw new CashMatchingError("unauthorized");
    }
    if (
      !claims || claims.sub !== actor || typeof claims.session_id !== "string" ||
      !uuid.test(claims.session_id) ||
      typeof claims.exp !== "number" || !Number.isSafeInteger(claims.exp) ||
      claims.exp <= Math.floor(Date.now() / 1000)
    ) throw new CashMatchingError("unauthorized");
    return this.call("/rest/v1/rpc/backend_prepare_card_authorization_for_session", true, {
      verified_actor_id: actor,
      verified_session_id: claims.session_id,
      token_expires_at: claims.exp,
      target_trip_id: input.trip_id,
      target_payment_id: input.payment_id,
      expected_trip_version: input.expected_trip_version,
      expected_payment_version: input.expected_payment_version,
      operation_key: input.idempotency_key,
    });
  }
}
