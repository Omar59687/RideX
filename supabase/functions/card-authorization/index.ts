import { CashMatchingError } from "../_shared/matching/cash_matching_adapter.ts";
import { resolveDefaultApiKey } from "../_shared/api_keys.ts";
import { createCardAuthorizationHandler } from "./core.ts";
import { ServerAuthorizationPort } from "./port.ts";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const publishableKey = resolveDefaultApiKey(
  Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"),
  Deno.env.get("SUPABASE_PUBLISHABLE_KEY"),
);
const secretKey = resolveDefaultApiKey(
  Deno.env.get("SUPABASE_SECRET_KEYS"),
  Deno.env.get("SUPABASE_SECRET_KEY"),
);
Deno.serve(createCardAuthorizationHandler((request) => {
  const token = /^Bearer\s+([^\s]+)$/iu.exec(request.headers.get("authorization") ?? "")?.[1] ?? "";
  if (!url || !publishableKey || !secretKey || !token) throw new CashMatchingError("unauthorized");
  return new ServerAuthorizationPort(url, publishableKey, token, secretKey);
}));
