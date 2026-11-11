import {
  CashMatchingAdapter,
  CashMatchingError,
  CashMatchingPort,
  Row,
  SupabaseCashMatchingPort,
} from "./cash_matching_adapter.ts";
const id = (n: number) => `a7050000-0000-0000-0000-${String(n).padStart(12, "0")}`;
const [bId, qId, rId, dId, vId, oId, tId] = [1, 2, 3, 4, 5, 6, 7].map(id);
const point = { latitude: 31.95, longitude: 35.93 };
function booking(): Row {
  const q = {
    id: qId,
    booking_request_id: bId,
    rider_id: rId,
    status: "locked",
    currency: "JOD",
    fixed_fare_fils: 2000,
    route_distance_meters: 5400,
    route_duration_seconds: 720,
    locked_at: "2026-11-04T10:00:00Z",
    pickup: point,
    destination: point,
    vehicle_type_code: "economy",
    ordered_stops: [{ location: point, label: "one" }],
    route_geometry_reference: "route-a",
  };
  return {
    id: bId,
    rider_id: rId,
    payment_method: "cash",
    status: "confirmed",
    version: 3,
    fare_quote_id: qId,
    pickup: point,
    destination: point,
    vehicle_type_code: "economy",
    fare_quotes: [q],
    booking_stops: [{ sequence: 1, location: point, label: "one" }],
    trips: [],
    driver_match_offers: [],
  };
}
function assigned(b: Row) {
  const q = (b.fare_quotes as Row[])[0];
  b.status = "matched";
  b.version = 5;
  b.matched_driver_id = dId;
  b.matched_vehicle_id = vId;
  b.driver_match_offers = [{
    id: oId,
    booking_request_id: bId,
    fare_quote_id: qId,
    driver_id: dId,
    vehicle_id: vId,
    status: "accepted",
  }];
  b.trips = [{
    ...q,
    id: tId,
    version: 1,
    status: "accepted",
    fare_quote_id: qId,
    payment_method: "cash",
    original_fare_fils: 2000,
    driver_id: dId,
    vehicle_id: vId,
    trip_stops: b.booking_stops,
  }];
}
class Fake implements CashMatchingPort {
  b = booking();
  session = {};
  ownerId = rId;
  calls = 0;
  offerVersions: number[] = [];
  discoveries = 0;
  expirations = 0;
  expireFailure?: Error;
  candidatesValue: unknown = [{ driver_id: dId, vehicle_id: vId }];
  onRead?: () => void;
  onOffer?: () => void;
  owner() {
    return Promise.resolve({ id: this.ownerId, session: this.session });
  }
  admitRequest() {
    return Promise.resolve();
  }
  read() {
    this.onRead?.();
    return Promise.resolve(structuredClone(this.b));
  }
  candidates() {
    this.discoveries++;
    return Promise.resolve(this.candidatesValue);
  }
  expireOffers(_bookingId: string, version: number) {
    this.expirations++;
    if (version !== this.b.version) throw new CashMatchingError("conflict");
    if (this.expireFailure) throw this.expireFailure;
    const offers = this.b.driver_match_offers as Row[];
    const expired = offers.filter((offer) =>
      offer.status === "offered" &&
      Date.parse(String(offer.expires_at)) <= Date.now()
    );
    // A04 retains terminal rows and does not change Booking version for offer expiry.
    for (const offer of expired) offer.status = "expired";
    return Promise.resolve(true);
  }
  offer(_b: string, _d: string, _v: string, version: number) {
    this.calls++;
    this.offerVersions.push(version);
    if (version !== this.b.version) throw new CashMatchingError("conflict");
    if (this.b.status === "confirmed") this.b.version = version + 1;
    this.b.status = "searching";
    const o = {
      id: oId,
      booking_request_id: bId,
      fare_quote_id: qId,
      driver_id: _d,
      vehicle_id: _v,
      status: "offered",
    };
    (this.b.driver_match_offers as Row[]).push(o);
    this.onOffer?.();
    return Promise.resolve(o);
  }
}
function eq(a: unknown, b: unknown) {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw new Error(`Mismatch ${JSON.stringify(a)} != ${JSON.stringify(b)}`);
  }
}
async function rejected(f: () => Promise<unknown>, code: string) {
  try {
    await f();
  } catch (e) {
    if (e instanceof CashMatchingError) {
      eq(e.code, code);
      return;
    }
    throw e;
  }
  throw new Error("Expected rejection");
}
const run = (p: Fake, v = 3) => new CashMatchingAdapter(p).request(bId, qId, v);
Deno.test("compose candidate and offer; never create/accept Trip or payment", async () => {
  const p = new Fake();
  eq((await run(p)).state, "awaitingDriver");
  eq(p.calls, 1);
  eq(p.b.trips, []);
});
Deno.test("recover offer with original stale version without second dispatch", async () => {
  const p = new Fake();
  await run(p);
  eq((await run(p)).state, "awaitingDriver");
  eq(p.calls, 1);
  eq(p.discoveries, 1);
});
Deno.test("fresh pending offer stays pending and is not redispatched", async () => {
  const p = new Fake();
  await run(p);
  const priorVersion = p.b.version;
  eq((await run(p, 3)).state, "awaitingDriver");
  eq(p.calls, 1);
  eq(p.expirations, 1);
  eq(p.b.version, priorVersion);
});
Deno.test("expired offers retain history and retry another candidate at canonical version", async () => {
  const p = new Fake();
  p.b.status = "searching";
  p.b.version = 4;
  p.b.driver_match_offers = [{
    id: oId,
    booking_request_id: bId,
    fare_quote_id: qId,
    driver_id: dId,
    vehicle_id: vId,
    status: "offered",
    expires_at: "2000-01-01T00:00:00Z",
  }];
  p.candidatesValue = [{ driver_id: id(8), vehicle_id: id(9) }];
  eq((await run(p, 4)).state, "awaitingDriver");
  eq((p.b.driver_match_offers as Row[]).map((o) => o.status), ["expired", "offered"]);
  eq(p.b.version, 4);
  eq(p.offerVersions, [4]);
  eq(p.expirations, 1);
});
Deno.test("expired all-offers state does not dispatch after an invalid canonical transition", async () => {
  const p = new Fake();
  p.b.status = "searching";
  p.b.driver_match_offers = [{
    id: oId,
    booking_request_id: bId,
    fare_quote_id: qId,
    driver_id: dId,
    vehicle_id: vId,
    status: "offered",
    expires_at: "2000-01-01T00:00:00Z",
  }];
  p.expireOffers = async function (_bookingId, version) {
    this.expirations++;
    this.b.driver_match_offers = [];
    this.b.status = "cancelled";
    this.b.version = version + 1;
    return true;
  };
  await rejected(() => run(p), "invalid_state");
  eq(p.calls, 0);
});
Deno.test("expiry version conflict stops before candidate discovery", async () => {
  const p = new Fake();
  p.b.driver_match_offers = [{
    id: oId,
    booking_request_id: bId,
    fare_quote_id: qId,
    driver_id: dId,
    vehicle_id: vId,
    status: "offered",
    expires_at: "2099-01-01T00:00:00Z",
  }];
  p.expireOffers = async () => {
    throw new CashMatchingError("conflict");
  };
  await rejected(() => run(p), "conflict");
  eq(p.discoveries, 0);
  eq(p.calls, 0);
});
Deno.test("lost expiry response rereads pending canonical offer without redispatch", async () => {
  const p = new Fake();
  await run(p);
  p.expireFailure = new Error("lost response");
  eq((await run(p, 3)).state, "awaitingDriver");
  eq(p.calls, 1);
  eq(p.expirations, 1);
});
Deno.test("recover actual assigned Trip through canonical linkage", async () => {
  const p = new Fake();
  assigned(p.b);
  eq((await run(p)).tripId, tId);
  eq(p.calls, 0);
});
Deno.test("empty candidate search", async () => {
  const p = new Fake();
  p.candidatesValue = [];
  eq((await run(p)).state, "noCandidates");
  eq(p.calls, 0);
});
Deno.test("stale version never dispatches", async () => {
  const p = new Fake();
  await rejected(() => run(p, 2), "conflict");
  eq(p.discoveries, 0);
  eq(p.calls, 0);
});
const invalid: Record<string, (b: Row) => void> = {
  Card: (b) => {
    b.payment_method = "card";
  },
  cancelled: (b) => {
    b.status = "cancelled";
  },
  quoteLink: (b) => {
    b.fare_quote_id = id(99);
  },
  quoteOwner: (b) => {
    (b.fare_quotes as Row[])[0].rider_id = id(99);
  },
  unlocked: (b) => {
    (b.fare_quotes as Row[])[0].status = "calculated";
  },
  currency: (b) => {
    (b.fare_quotes as Row[])[0].currency = "USD";
  },
  stops: (b) => {
    b.booking_stops = [];
  },
  pickup: (b) => {
    b.pickup = { latitude: 0, longitude: 0 };
  },
  duplicateTrip: (b) => {
    assigned(b);
    (b.trips as Row[]).push((b.trips as Row[])[0]);
  },
  wrongTripQuote: (b) => {
    assigned(b);
    (b.trips as Row[])[0].fare_quote_id = id(99);
  },
  wrongOfferBooking: (b) => {
    assigned(b);
    (b.driver_match_offers as Row[])[0].booking_request_id = id(99);
  },
  changedTripFare: (b) => {
    assigned(b);
    (b.trips as Row[])[0].original_fare_fils = 1;
  },
  changedRoute: (b) => {
    assigned(b);
    (b.trips as Row[])[0].route_geometry_reference = "different";
  },
};
for (const [name, mutate] of Object.entries(invalid)) {
  Deno.test(`fail closed: ${name}`, async () => {
    const p = new Fake();
    mutate(p.b);
    await rejected(() => run(p), "invalid_state");
    eq(p.calls, 0);
  });
}
Deno.test("foreign Rider never dispatches", async () => {
  const p = new Fake();
  p.ownerId = id(99);
  await rejected(() => run(p), "unauthorized");
  eq(p.calls, 0);
});
Deno.test("session A-B-A replacement after read rejects", async () => {
  const p = new Fake();
  p.onRead = () => {
    p.session = {};
  };
  await rejected(() => run(p), "unauthorized");
  eq(p.calls, 0);
});
Deno.test("invalid locator rejected before any dispatch", async () => {
  const p = new Fake();
  await rejected(
    () => new CashMatchingAdapter(p).request("trip-as-booking", qId, 3),
    "invalid_request",
  );
  eq(p.calls, 0);
});
Deno.test("candidate limit fails closed", async () => {
  const p = new Fake();
  p.candidatesValue = Array(4).fill({ driver_id: dId, vehicle_id: vId });
  await rejected(() => run(p), "invalid_state");
  eq(p.calls, 0);
});
Deno.test("duplicate candidates fail before writes", async () => {
  const p = new Fake();
  p.candidatesValue = Array(2).fill({ driver_id: dId, vehicle_id: vId });
  await rejected(() => run(p), "invalid_state");
  eq(p.calls, 0);
});
Deno.test("lost mutation response rereads, never replays", async () => {
  const p = new Fake();
  p.onOffer = () => {
    throw new Error("network");
  };
  eq((await run(p)).state, "awaitingDriver");
  eq(p.calls, 1);
});
Deno.test("unknown mutation with no canonical effect remains unknown", async () => {
  const p = new Fake();
  p.onOffer = () => {
    p.b.driver_match_offers = [];
    throw new Error("network");
  };
  await rejected(() => run(p), "unknown");
  eq(p.calls, 1);
});
Deno.test("transport keeps privileged credentials only on allowlisted backend RPCs", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const send: typeof fetch = (input, init) => {
    const url = String(input);
    calls.push({ url, init: init! });
    return Promise.resolve(
      Response.json(
        url.includes("/auth/")
          ? { id: rId }
          : url.includes("/users?")
          ? [{ id: rId, role: "rider", is_blocked: false }]
          : url.includes("session_is_active") || url.includes("request_guard")
          ? true
          : [],
      ),
    );
  };
  const p = new SupabaseCashMatchingPort(
    "https://example.invalid",
    "public-test",
    "rider-test",
    "server-test",
    send,
  );
  await p.owner();
  await p.read(bId);
  await p.candidates(bId, 3);
  await p.offer(bId, dId, vId, 3);
  await p.expireOffers(bId, 3);
  for (const c of calls) {
    const h = c.init.headers as Record<string, string>;
    const privileged = c.url.includes("backend_find_nearby_driver_candidates") ||
      c.url.includes("backend_create_driver_match_offer") ||
      c.url.includes("backend_expire_booking_match_offers");
    eq(h.Authorization, "Bearer " + (privileged ? "server-test" : "rider-test"));
    if (c.url.includes("rider_matching_")) eq(h.apikey, "public-test");
  }
  eq(calls.filter((c) => c.init.method === "POST").map((c) => new URL(c.url).pathname), [
    "/rest/v1/rpc/rider_matching_session_is_active",
    "/rest/v1/rpc/backend_find_nearby_driver_candidates",
    "/rest/v1/rpc/backend_create_driver_match_offer",
    "/rest/v1/rpc/backend_expire_booking_match_offers",
  ]);
  eq(JSON.parse(String(calls.at(-2)!.init.body)), {
    target_booking_request_id: bId,
    target_driver_id: dId,
    target_vehicle_id: vId,
    requested_radius_meters: 3000,
    expected_booking_version: 3,
  });
  eq(JSON.parse(String(calls.at(-1)!.init.body)), {
    target_booking_request_id: bId,
    expected_booking_version: 3,
  });
});
Deno.test("session and admission RPCs require strict true/false and Rider credentials", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  let rpcResponse: unknown = true;
  const port = new SupabaseCashMatchingPort(
    "https://example.invalid",
    "public",
    "rider",
    "service",
    (input, init) => {
      const url = String(input);
      calls.push({ url, init: init! });
      return Promise.resolve(Response.json(
        url.includes("/auth/")
          ? { id: rId }
          : url.includes("/users?")
          ? [{ id: rId, role: "rider", is_blocked: false }]
          : rpcResponse,
      ));
    },
  );
  await port.owner();
  await port.admitRequest();
  for (const c of calls.filter((c) => c.url.includes("rider_matching_"))) {
    const h = c.init.headers as Record<string, string>;
    eq(h.Authorization, "Bearer rider");
    eq(h.apikey, "public");
    eq(c.init.body, "{}");
  }
  rpcResponse = false;
  await rejected(() => port.owner(), "unauthorized");
  await rejected(() => port.admitRequest(), "rate_limited");
  for (const malformed of [null, "true", 1, []]) {
    rpcResponse = malformed;
    await rejected(() => port.admitRequest(), "unknown");
  }
});
Deno.test("transport denies blocked authenticated Rider", async () => {
  const p = new SupabaseCashMatchingPort(
    "https://example.invalid",
    "public-test",
    "rider-test",
    "server-test",
    (_i) =>
      Promise.resolve(Response.json(
        String(_i).includes("/auth/")
          ? { id: rId }
          : String(_i).includes("/users?")
          ? [{ id: rId, role: "rider", is_blocked: true }]
          : [{ id: rId, role: "rider", is_blocked: true }],
      )),
  );
  await rejected(() => p.owner(), "unauthorized");
});
Deno.test("transport permits HTTP only for local loopback Supabase", () => {
  for (
    const url of [
      "http://127.0.0.1:55421",
      "http://localhost:55421",
      "http://[::1]:55421",
    ]
  ) {
    new SupabaseCashMatchingPort(url, "public-test", "rider-test", "server-test");
  }
  for (const url of ["http://example.invalid", "ftp://localhost:55421"]) {
    try {
      new SupabaseCashMatchingPort(url, "public-test", "rider-test", "server-test");
    } catch (error) {
      if (error instanceof CashMatchingError && error.code === "invalid_request") continue;
      throw error;
    }
    throw new Error(`unsafe endpoint accepted: ${url}`);
  }
});
Deno.test("HTTP 503 is ambiguous, not a safe-to-replay conflict", async () => {
  const p = new SupabaseCashMatchingPort(
    "https://example.invalid",
    "p",
    "r",
    "s",
    () => Promise.resolve(new Response("", { status: 503 })),
  );
  try {
    await p.offer(bId, dId, vId, 3);
  } catch (e) {
    if (e instanceof CashMatchingError) throw new Error("503 classified as known rejection");
    return;
  }
  throw new Error("Expected failure");
});
Deno.test("initial Auth transport failure is sanitized", async () => {
  const p = new Fake();
  p.owner = () => Promise.reject(new Error("private transport detail"));
  await rejected(() => run(p), "unknown");
  eq(p.calls, 0);
});
Deno.test("three bounded offers reread canonical booking version after first transition", async () => {
  const p = new Fake();
  p.candidatesValue = [{ driver_id: dId, vehicle_id: vId }, {
    driver_id: id(14),
    vehicle_id: id(15),
  }, { driver_id: id(24), vehicle_id: id(25) }];
  eq((await run(p)).state, "awaitingDriver");
  eq(p.calls, 3);
  eq(p.offerVersions, [3, 4, 4]);
});
Deno.test("cancellation after discovery prevents dispatch", async () => {
  const p = new Fake();
  let reads = 0;
  p.onRead = () => {
    if (++reads === 2) p.b.status = "cancelled";
  };
  await rejected(() => run(p), "invalid_state");
  eq(p.calls, 0);
});
Deno.test("Driver acceptance during dispatch returns actual canonical Trip", async () => {
  const p = new Fake();
  p.onOffer = () => assigned(p.b);
  eq((await run(p)).tripId, tId);
  eq(p.calls, 1);
});

for (const status of [403, 404, 500]) {
  Deno.test(
    "guard transport failure " + status + " cannot admit or publish ownership",
    async () => {
      const port = new SupabaseCashMatchingPort(
        "https://example.invalid",
        "public",
        "rider",
        "service",
        (input) => {
          const url = String(input);
          if (url.includes("/auth/")) return Promise.resolve(Response.json({ id: rId }));
          if (url.includes("/users?")) {
            return Promise.resolve(Response.json([{ id: rId, role: "rider", is_blocked: false }]));
          }
          if (!url.includes("rider_matching_")) throw new Error("unexpected dispatch");
          return Promise.resolve(new Response("sanitized", { status }));
        },
      );
      const expected = status === 403 ? "unauthorized" : "unknown";
      await rejected(() => port.admitRequest(), expected);
      await rejected(() => port.owner(), expected);
    },
  );
}
