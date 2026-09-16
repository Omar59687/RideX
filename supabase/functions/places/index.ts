import { authorizeCaller, createPlacesHandler } from "./core.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const googleMapsApiKey = Deno.env.get("GOOGLE_MAPS_WEB_SERVICES_API_KEY") ?? "";
const googleRoutesApiKey = Deno.env.get("GOOGLE_ROUTES_API_KEY") ?? "";

Deno.serve(createPlacesHandler({
  apiKey: googleMapsApiKey,
  googleRoutesApiKey,
  authorize: (request) =>
    authorizeCaller(request, {
      supabaseUrl,
      supabaseAnonKey,
    }),
}));
