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
  candidatesValue: unknown = [{ driver_id: dId, vehicle_id: vId }];
  onRead?: () => void;
  onOffer?: () => void;
  owner() {
    return Promise.resolve({ id: this.ownerId, session: this.session });
  }
  read() {
    this.onRead?.();
    return Promise.resolve(structuredClone(this.b));
  }
  candidates() {
    this.discoveries++;
    return Promise.resolve(this.candidatesValue);
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
  for (const c of calls) {
    const h = c.init.headers as Record<string, string>;
    eq(h.Authorization, "Bearer " + (c.url.includes("/rpc/") ? "server-test" : "rider-test"));
  }
  eq(calls.filter((c) => c.init.method === "POST").map((c) => new URL(c.url).pathname), [
    "/rest/v1/rpc/backend_find_nearby_driver_candidates",
    "/rest/v1/rpc/backend_create_driver_match_offer",
  ]);
  eq(JSON.parse(String(calls.at(-1)!.init.body)), {
    target_booking_request_id: bId,
    target_driver_id: dId,
    target_vehicle_id: vId,
    requested_radius_meters: 3000,
    expected_booking_version: 3,
  });
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
          : [{ id: rId, role: "rider", is_blocked: true }],
      )),
  );
  await rejected(() => p.owner(), "unauthorized");
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
