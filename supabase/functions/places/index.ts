import { authorizeCaller, createPlacesHandler } from "./core.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const googlePlacesApiKey = Deno.env.get("GOOGLE_PLACES_API_KEY") ?? "";
const googleRoutesApiKey = Deno.env.get("GOOGLE_ROUTES_API_KEY") ?? "";

Deno.serve(createPlacesHandler({
  apiKey: googlePlacesApiKey,
  googleRoutesApiKey,
  authorize: (request) =>
    authorizeCaller(request, {
      supabaseUrl,
      supabaseAnonKey,
    }),
}));
