/** Server-only A05 composition. The dedicated cash-matching Edge Function
 * supplies trusted environment values and an authenticated Rider bearer.
 * The Rider credential reads canonical RLS state; only the trusted backend port
 * may discover/create offers. Driver acceptance remains driver_transition_trip.
 */
export type Row = Record<string, unknown>;
export type Owner = { id: string; session: object };
export interface CashMatchingPort {
  owner(): Promise<Owner>;
  read(bookingId: string): Promise<Row | null>;
  candidates(bookingId: string, version: number): Promise<unknown>;
  offer(bookingId: string, driverId: string, vehicleId: string, version: number): Promise<unknown>;
}
export class CashMatchingError extends Error {
  constructor(
    readonly code: "unauthorized" | "invalid_request" | "invalid_state" | "conflict" | "unknown",
  ) {
    super(code);
  }
}
export type MatchingResult = {
  bookingId: string;
  fareQuoteId: string;
  state: "awaitingDriver" | "noCandidates" | "assigned";
  tripId?: string;
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function row(value: unknown): Row {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new CashMatchingError("invalid_state");
  }
  return value as Row;
}
export function rows(value: unknown): Row[] {
  if (value === null) return [];
  if (Array.isArray(value)) return value.map(row);
  return [row(value)];
}
const integer = (v: unknown) => typeof v === "number" && Number.isSafeInteger(v) && v >= 0;
function canonical(value: unknown): string {
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  if (value && typeof value === "object") {
    return "{" + Object.entries(value).filter(([, v]) => v !== null)
      .sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) =>
        JSON.stringify(k) + ":" + canonical(v)
      ).join(",") +
      "}";
  }
  return JSON.stringify(value);
}
function stops(value: unknown): unknown[] {
  if (!Array.isArray(value)) throw new CashMatchingError("invalid_state");
  return value.map(row).sort((a, b) => Number(a.sequence) - Number(b.sequence)).map((v, i) => {
    if (v.sequence !== i + 1 || !v.location) throw new CashMatchingError("invalid_state");
    return { location: v.location, label: v.label ?? null, rider_note: v.rider_note ?? null };
  });
}
/** A locator is never authority. Read all linkage from one owned DB projection. */
export function checkedBooking(b: Row, ownerId: string, bookingId: string, quoteId: string): Row {
  if (b.id !== bookingId || b.rider_id !== ownerId) throw new CashMatchingError("unauthorized");
  if (
    b.payment_method !== "cash" ||
    !["confirmed", "searching", "matched"].includes(String(b.status)) ||
    !integer(b.version) || Number(b.version) < 1 || b.fare_quote_id !== quoteId
  ) throw new CashMatchingError("invalid_state");
  const matches = rows(b.fare_quotes).filter((q) => q.id === quoteId);
  if (matches.length !== 1) throw new CashMatchingError("invalid_state");
  const q = matches[0];
  if (
    q.booking_request_id !== bookingId || q.rider_id !== ownerId || q.status !== "locked" ||
    q.currency !== "JOD" || !integer(q.fixed_fare_fils) || !integer(q.route_distance_meters) ||
    !integer(q.route_duration_seconds) || typeof q.locked_at !== "string" ||
    !Number.isFinite(Date.parse(q.locked_at)) ||
    canonical(q.pickup) !== canonical(b.pickup) ||
    canonical(q.destination) !== canonical(b.destination) ||
    q.vehicle_type_code !== b.vehicle_type_code || !Array.isArray(q.ordered_stops) ||
    canonical(q.ordered_stops) !== canonical(stops(b.booking_stops))
  ) throw new CashMatchingError("invalid_state");
  return q;
}
export function assignedTrip(b: Row, q: Row, ownerId: string): string | undefined {
  const trips = rows(b.trips);
  if (b.status !== "matched") {
    if (trips.length) throw new CashMatchingError("invalid_state");
    return undefined;
  }
  if (trips.length !== 1) throw new CashMatchingError("invalid_state");
  const t = trips[0];
  const accepted = rows(b.driver_match_offers).filter((o) => o.status === "accepted");
  if (
    accepted.length !== 1 || !uuid.test(String(accepted[0].id)) ||
    accepted[0].booking_request_id !== b.id ||
    !integer(t.version) || Number(t.version) < 1 ||
    ![
      "accepted",
      "driverArriving",
      "driverArrived",
      "inProgress",
      "completed",
      "cancelledByRider",
      "cancelledByDriver",
      "cancelledByAdmin",
      "failed",
    ].includes(String(t.status)) ||
    !uuid.test(String(t.id)) || t.booking_request_id !== b.id ||
    t.fare_quote_id !== q.id || t.rider_id !== ownerId || t.driver_id !== b.matched_driver_id ||
    t.vehicle_id !== b.matched_vehicle_id || !uuid.test(String(t.driver_id)) ||
    !uuid.test(String(t.vehicle_id)) ||
    t.payment_method !== "cash" || t.currency !== q.currency ||
    t.original_fare_fils !== q.fixed_fare_fils ||
    t.pickup == null || t.destination == null || canonical(t.pickup) !== canonical(q.pickup) ||
    canonical(t.destination) !== canonical(q.destination) ||
    t.route_distance_meters !== q.route_distance_meters ||
    t.route_duration_seconds !== q.route_duration_seconds ||
    t.route_geometry_reference !== q.route_geometry_reference ||
    canonical(stops(t.trip_stops)) !== canonical(q.ordered_stops) ||
    accepted[0].driver_id !== t.driver_id || accepted[0].vehicle_id !== t.vehicle_id ||
    accepted[0].fare_quote_id !== q.id
  ) {
    throw new CashMatchingError("invalid_state");
  }
  return String(t.id);
}
export class CashMatchingAdapter {
  constructor(private readonly port: CashMatchingPort) {}
  async request(
    bookingId: string,
    quoteId: string,
    expectedVersion: number,
  ): Promise<MatchingResult> {
    if (
      !uuid.test(bookingId) || !uuid.test(quoteId) || !Number.isSafeInteger(expectedVersion) ||
      expectedVersion < 1
    ) {
      throw new CashMatchingError("invalid_request");
    }
    const readOwner = async (): Promise<Owner> => {
      try {
        return await this.port.owner();
      } catch (error) {
        if (error instanceof CashMatchingError) throw error;
        throw new CashMatchingError("unknown");
      }
    };
    const owner = await readOwner();
    if (!uuid.test(owner.id)) throw new CashMatchingError("unauthorized");
    const guard = async () => {
      const current = await readOwner();
      if (current.id !== owner.id || current.session !== owner.session) {
        throw new CashMatchingError("unauthorized");
      }
    };
    const read = async () => {
      await guard();
      const value = await this.port.read(bookingId);
      await guard();
      if (!value) throw new CashMatchingError("unauthorized");
      const q = checkedBooking(value, owner.id, bookingId, quoteId);
      return { b: value, q };
    };
    const result = (state: MatchingResult["state"], tripId?: string): MatchingResult => ({
      bookingId,
      fareQuoteId: quoteId,
      state,
      ...(tripId ? { tripId } : {}),
    });
    try {
      let { b, q } = await read();
      const trip = assignedTrip(b, q, owner.id);
      if (trip) return result("assigned", trip);
      // Recover prior effects BEFORE enforcing the caller's original version.
      // Read-only recovery never creates another offer or extends a deadline.
      if (rows(b.driver_match_offers).some((o) => o.status === "offered")) {
        return result("awaitingDriver");
      }
      if (b.version !== expectedVersion) throw new CashMatchingError("conflict");
      await guard();
      const raw = await this.port.candidates(bookingId, Number(b.version));
      await guard();
      if (!Array.isArray(raw) || raw.length > 3) throw new CashMatchingError("invalid_state");
      const candidates = raw.map(row);
      const seen = new Set<string>();
      for (const c of candidates) {
        if (
          !uuid.test(String(c.driver_id)) || !uuid.test(String(c.vehicle_id)) ||
          seen.has(String(c.driver_id))
        ) {
          throw new CashMatchingError("invalid_state");
        }
        seen.add(String(c.driver_id));
      }
      if (!candidates.length) return result("noCandidates");
      for (const c of candidates) {
        ({ b, q } = await read());
        const assigned = assignedTrip(b, q, owner.id);
        if (assigned) return result("assigned", assigned);
        await guard();
        const offered = row(
          await this.port.offer(
            bookingId,
            String(c.driver_id),
            String(c.vehicle_id),
            Number(b.version),
          ),
        );
        await guard();
        if (
          offered.booking_request_id !== bookingId || offered.fare_quote_id !== quoteId ||
          offered.driver_id !== c.driver_id || offered.vehicle_id !== c.vehicle_id ||
          !uuid.test(String(offered.id))
        ) {
          throw new CashMatchingError("invalid_state");
        }
      }
      ({ b, q } = await read());
      const assigned = assignedTrip(b, q, owner.id);
      if (assigned) return result("assigned", assigned);
      if (rows(b.driver_match_offers).some((o) => o.status === "offered")) {
        return result("awaitingDriver");
      }
      throw new CashMatchingError("conflict");
    } catch (error) {
      await guard();
      if (error instanceof CashMatchingError) throw error;
      // Unknown mutation response: only reread; never replay or advance to a
      // different Driver within this request. The next request recovers state.
      try {
        const { b, q } = await read();
        const trip = assignedTrip(b, q, owner.id);
        if (trip) return result("assigned", trip);
        if (rows(b.driver_match_offers).some((o) => o.status === "offered")) {
          return result("awaitingDriver");
        }
      } catch (readError) {
        if (readError instanceof CashMatchingError) throw readError;
      }
      throw new CashMatchingError("unknown");
    }
  }
}

/** Explicit server-only REST port; never imported by Flutter and not wired to
 * Deno.serve. Host, keys and Rider bearer must come from trusted server config /
 * verified request composition, not JSON body fields. No credentials in results.
 */
export class SupabaseCashMatchingPort implements CashMatchingPort {
  private readonly session = {};
  constructor(
    private readonly url: string,
    private readonly publicKey: string,
    private readonly riderBearer: string,
    private readonly serviceKey: string,
    private readonly send: typeof fetch = fetch,
  ) {
    let parsed: URL | null = null;
    try {
      parsed = new URL(url);
    } catch {
      parsed = null;
    }
    const loopbackHttp = parsed?.protocol === "http:" &&
      ["localhost", "127.0.0.1", "::1", "[::1]"].includes(parsed.hostname);
    if ((!parsed || (parsed.protocol !== "https:" && !loopbackHttp)) ||
      !publicKey || !riderBearer || !serviceKey) {
      throw new CashMatchingError("invalid_request");
    }
  }
  private async call(path: string, privileged = false, body?: Row): Promise<unknown> {
    const key = privileged ? this.serviceKey : this.publicKey;
    const response = await this.send(this.url + path, {
      method: body ? "POST" : "GET",
      signal: AbortSignal.timeout(15_000),
      headers: {
        apikey: key,
        Authorization: "Bearer " + (privileged ? this.serviceKey : this.riderBearer),
        "Content-Type": "application/json",
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    if (response.status >= 500) throw new Error("ambiguous_backend_response");
    if (!response.ok) {
      throw new CashMatchingError(
        response.status === 401 || response.status === 403 ? "unauthorized" : "conflict",
      );
    }
    return await response.json();
  }
  async owner(): Promise<Owner> {
    const user = row(await this.call("/auth/v1/user"));
    if (!uuid.test(String(user.id))) throw new CashMatchingError("unauthorized");
    const profile = await this.call("/rest/v1/users?select=id,role,is_blocked&id=eq." + user.id);
    if (
      !Array.isArray(profile) || profile.length !== 1 || profile[0].id !== user.id ||
      profile[0].role !== "rider" || profile[0].is_blocked !== false
    ) throw new CashMatchingError("unauthorized");
    return { id: String(user.id), session: this.session };
  }
  async read(id: string): Promise<Row | null> {
    const projection =
      "*,booking_stops(*),fare_quotes!fare_quotes_booking_rider_fk(*),trips!trips_booking_request_id_fkey(*,trip_stops(*)),driver_match_offers!driver_match_offers_booking_request_id_fkey(*)";
    const value = await this.call(
      "/rest/v1/booking_requests?select=" + encodeURIComponent(projection) + "&id=eq." + id,
    );
    if (!Array.isArray(value) || value.length > 1) throw new CashMatchingError("invalid_state");
    return value.length ? row(value[0]) : null;
  }
  candidates(id: string, version: number): Promise<unknown> {
    return this.call("/rest/v1/rpc/backend_find_nearby_driver_candidates", true, {
      target_booking_request_id: id,
      expected_booking_version: version,
      requested_radius_meters: 3000,
      requested_limit: 3,
    });
  }
  offer(id: string, driver: string, vehicle: string, version: number): Promise<unknown> {
    return this.call("/rest/v1/rpc/backend_create_driver_match_offer", true, {
      target_booking_request_id: id,
      target_driver_id: driver,
      target_vehicle_id: vehicle,
      requested_radius_meters: 3000,
      expected_booking_version: version,
    });
  }
}
