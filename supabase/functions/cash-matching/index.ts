import {
  CashMatchingAdapter,
  CashMatchingError,
  SupabaseCashMatchingPort,
} from "../_shared/matching/cash_matching_adapter.ts";
import { authorizeCaller } from "../fare/core.ts";
import { createCashMatchingHandler } from "./core.ts";
import { resolveDefaultApiKey } from "../_shared/api_keys.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const publishableKey = resolveDefaultApiKey(
  Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"),
  Deno.env.get("SUPABASE_PUBLISHABLE_KEY"),
);
const secretKey = resolveDefaultApiKey(
  Deno.env.get("SUPABASE_SECRET_KEYS"),
  Deno.env.get("SUPABASE_SECRET_KEY"),
);

Deno.serve(createCashMatchingHandler({
  authorize: (request) =>
    authorizeCaller(request, {
      supabaseUrl,
      publishableKey,
    }),
  match: async (input, request) => {
    const authorization = request.headers.get("authorization") ?? "";
    const riderBearer = /^Bearer\s+([^\s]+)$/iu.exec(authorization)?.[1] ?? "";
    if (!supabaseUrl || !publishableKey || !secretKey || !riderBearer) {
      throw new CashMatchingError("unknown");
    }
    const port = new SupabaseCashMatchingPort(
      supabaseUrl,
      publishableKey,
      riderBearer,
      secretKey,
    );
    await port.admitRequest();
    return await new CashMatchingAdapter(port).request(
      input.bookingId,
      input.quoteId,
      input.expectedBookingVersion,
    );
  },
}));
