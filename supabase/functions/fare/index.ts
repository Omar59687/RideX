import { authorizeCaller, createBackendQuoteCaller, createFareHandler } from "./core.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

Deno.serve(createFareHandler({
  authorize: (request) =>
    authorizeCaller(request, {
      supabaseUrl,
      supabaseAnonKey,
    }),
  calculateFare: createBackendQuoteCaller({
    supabaseUrl,
    serviceRoleKey,
  }),
}));
