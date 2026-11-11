import {
  CashMatchingAdapter,
  CashMatchingError,
  SupabaseCashMatchingPort,
} from "./cash_matching_adapter.ts";

const rider = "a1230000-0000-4000-8000-000000000004";
const booking = "a1230000-0000-4000-8000-000000000001";
const quote = "a1230000-0000-4000-8000-000000000002";

for (const invalid of [null, [], "unexpected", { id: "invalid" }]) {
  Deno.test(
    "malformed authoritative Auth identity never reaches privileged matching: " +
      JSON.stringify(invalid),
    async () => {
      let privileged = 0;
      const port = new SupabaseCashMatchingPort(
        "https://example.invalid",
        "public-test",
        "rider-test",
        "service-test",
        (url, init) => {
          if (String(url).includes("/rpc/backend_")) privileged++;
          if (String(url).endsWith("/auth/v1/user")) {
            return Promise.resolve(Response.json(invalid));
          }
          throw new Error("unexpected request after malformed Auth response");
        },
      );
      let rejected = false;
      try {
        await new CashMatchingAdapter(port).request(booking, quote, 3);
      } catch (error) {
        rejected = error instanceof CashMatchingError;
      }
      if (!rejected || privileged) throw new Error("malformed Auth granted matching authority");
    },
  );
}

for (const failure of ["invalidJson", "authUnavailable", "profileMalformed", "sessionMalformed"]) {
  Deno.test("Auth boundary fails closed without mutations: " + failure, async () => {
    let privileged = 0;
    const port = new SupabaseCashMatchingPort(
      "https://example.invalid",
      "public-test",
      "rider-test",
      "service-test",
      (url) => {
        const path = String(url);
        if (path.includes("/rpc/backend_")) privileged++;
        if (path.endsWith("/auth/v1/user")) {
          if (failure === "invalidJson") {
            return Promise.resolve(new Response("<html>unavailable</html>"));
          }
          if (failure === "authUnavailable") {
            return Promise.resolve(Response.json({ error: "unavailable" }, { status: 503 }));
          }
          return Promise.resolve(Response.json({ id: rider }));
        }
        if (path.includes("/users?")) {
          return Promise.resolve(
            Response.json(
              failure === "profileMalformed"
                ? {}
                : [{ id: rider, role: "rider", is_blocked: false }],
            ),
          );
        }
        if (path.endsWith("/rpc/rider_matching_session_is_active")) {
          return Promise.resolve(Response.json("true"));
        }
        throw new Error("unexpected matching dispatch");
      },
    );
    let rejected = false;
    try {
      await new CashMatchingAdapter(port).request(booking, quote, 3);
    } catch (error) {
      rejected = error instanceof CashMatchingError;
    }
    if (!rejected || privileged) {
      throw new Error("unresolved Auth boundary granted matching authority");
    }
  });
}
