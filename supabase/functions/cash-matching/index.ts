import {
  CashMatchingAdapter,
  CashMatchingError,
  SupabaseCashMatchingPort,
} from "../_shared/matching/cash_matching_adapter.ts";
import { authorizeCaller } from "../fare/core.ts";
import { createCashMatchingHandler } from "./core.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

Deno.serve(createCashMatchingHandler({
  authorize: (request) => authorizeCaller(request, {
    supabaseUrl,
    supabaseAnonKey,
  }),
  match: async (input, request) => {
    const authorization = request.headers.get("authorization") ?? "";
    const riderBearer = /^Bearer\s+([^\s]+)$/iu.exec(authorization)?.[1] ?? "";
    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey || !riderBearer) {
      throw new CashMatchingError("unknown");
    }
    const port = new SupabaseCashMatchingPort(
      supabaseUrl,
      supabaseAnonKey,
      riderBearer,
      serviceRoleKey,
    );
    return await new CashMatchingAdapter(port).request(
      input.bookingId,
      input.quoteId,
      input.expectedBookingVersion,
    );
  },
}));
