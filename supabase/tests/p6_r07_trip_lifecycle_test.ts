import {
  FixtureStagingStatus,
  FixtureTripIdentity,
  stageAcceptedFixtureTrip,
} from "../ops/p6_r07_trip_lifecycle.ts";

function equal(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error("assertion_failed");
  }
}

async function rejects(action: () => Promise<unknown>): Promise<void> {
  try {
    await action();
  } catch {
    return;
  }
  throw new Error("expected_rejection");
}

const identity: FixtureTripIdentity = {
  tripId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  bookingId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  driverId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
  riderId: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
  vehicleId: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
};

function backend() {
  let row: Record<string, unknown> = {
    id: identity.tripId,
    booking_request_id: identity.bookingId,
    driver_id: identity.driverId,
    rider_id: identity.riderId,
    vehicle_id: identity.vehicleId,
    payment_method: "cash",
    status: "accepted",
    version: 1,
  };
  const calls: { status: string; version: number; key: string }[] = [];
  let reads = 0;
  return {
    calls,
    get reads() {
      return reads;
    },
    get row() {
      return { ...row };
    },
    set row(value: Record<string, unknown>) {
      row = value;
    },
    readTrip: () => {
      reads++;
      return Promise.resolve({ ...row });
    },
    transition: (
      status: FixtureStagingStatus,
      version: number,
      key: string,
    ) => {
      calls.push({ status, version, key });
      // The server's existing trigger rejects skipped lifecycle statuses.
      const next: Record<string, string> = {
        accepted: "driverArriving",
        driverArriving: "driverArrived",
        driverArrived: "inProgress",
      };
      if (next[String(row.status)] !== status || version !== row.version) {
        return Promise.reject(
          new Error("Invalid Trip status transition or stale version"),
        );
      }
      row = { ...row, status, version: version + 1 };
      return Promise.resolve({ trip_id: identity.tripId, status });
    },
    commandKey: (status: FixtureStagingStatus) => `original-${status}`,
  };
}

Deno.test("R07 obeys the server lifecycle and rereads each new canonical version", async () => {
  const db = backend();
  const final = await stageAcceptedFixtureTrip(identity, db);
  equal(db.calls, [
    { status: "driverArriving", version: 1, key: "original-driverArriving" },
    { status: "driverArrived", version: 2, key: "original-driverArrived" },
    { status: "inProgress", version: 3, key: "original-inProgress" },
  ]);
  equal(db.reads, 4);
  equal(final.status, "inProgress");
  equal(final.version, 4);
});

Deno.test("unknown transition outcome stops without replay or a later command", async () => {
  const db = backend();
  await rejects(() =>
    stageAcceptedFixtureTrip(identity, {
      ...db,
      transition: async (status, version, key) => {
        const response = await db.transition(status, version, key);
        if (status === "driverArrived") throw new Error("response_lost");
        return response;
      },
    })
  );
  equal(db.calls.map((call) => call.status), [
    "driverArriving",
    "driverArrived",
  ]);
  equal(db.row.status, "driverArrived");
  equal(db.reads, 2);
});

Deno.test("stale canonical reread prevents dispatch of the next stage", async () => {
  const db = backend();
  await rejects(() =>
    stageAcceptedFixtureTrip(identity, {
      ...db,
      readTrip: async () => {
        const row = await db.readTrip();
        return db.reads === 2 ? { ...row, version: 1 } : row;
      },
    })
  );
  equal(db.calls.length, 1);
});

Deno.test("foreign identity, non-Cash or invalid initial state dispatches nothing", async () => {
  for (
    const change of [
      { id: identity.bookingId },
      { booking_request_id: identity.tripId },
      { driver_id: identity.riderId },
      { rider_id: identity.driverId },
      { vehicle_id: identity.tripId },
      { payment_method: "card" },
      { status: "inProgress" },
      { version: 0 },
      { version: 1.5 },
    ]
  ) {
    const db = backend();
    db.row = { ...db.row, ...change };
    await rejects(() => stageAcceptedFixtureTrip(identity, db));
    equal(db.calls.length, 0);
  }
});

Deno.test("authorization rejection stops the sequence without retry", async () => {
  const db = backend();
  const attempted: string[] = [];
  await rejects(() =>
    stageAcceptedFixtureTrip(identity, {
      ...db,
      transition: (status, version, key) => {
        attempted.push(status);
        if (status === "driverArrived") {
          return Promise.reject(new Error("authorization_revoked"));
        }
        return db.transition(status, version, key);
      },
    })
  );
  equal(attempted, ["driverArriving", "driverArrived"]);
  equal(db.calls.length, 1);
});

Deno.test("conflicting RPC response stops before another read or command", async () => {
  const db = backend();
  await rejects(() =>
    stageAcceptedFixtureTrip(identity, {
      ...db,
      transition: async (status, version, key) => {
        await db.transition(status, version, key);
        return { trip_id: identity.bookingId, status };
      },
    })
  );
  equal(db.calls.length, 1);
  equal(db.reads, 1);
});
