/** Operator entrypoint for R06 hosted reservation acceptance; Stripe stays off. */
import {
  type CardFixtureRuntime,
  type FetchLike,
  runCardFixtureOperator,
} from "./r06_prepare_card_fixture.ts";
import {
  CardFixtureError,
  R06_PROJECT_URL,
} from "./r06_card_fixture_contract.ts";

interface AttemptContext {
  riderId: string;
  driverId: string;
  tripId: string;
  paymentId: string;
  amountFils: number;
  attemptId?: string;
  tripVersion: number;
  paymentVersion: number;
  operationKey: string;
}

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const APPROVAL_PREFIX = "owner-approved-r06-card-concurrency-";

export interface ConcurrencyAcceptanceEvidence {
  winner: "claimA" | "claimB";
  replayTokens: 0;
  reservationCount: 1;
  reconnected: true;
}

function parseRecord(value: unknown): Record<string, unknown> {
  const candidate = Array.isArray(value) && value.length === 1
    ? value[0]
    : value;
  if (
    typeof candidate !== "object" || candidate === null ||
    Array.isArray(candidate)
  ) {
    throw new CardFixtureError("backend_response_invalid");
  }
  return candidate as Record<string, unknown>;
}

export function assertConcurrencyApproval(
  fixtureId: string,
  approval: string | undefined,
): void {
  if (
    !UUID.test(fixtureId) ||
    approval !== `${APPROVAL_PREFIX}${fixtureId.toLowerCase()}`
  ) {
    throw new CardFixtureError("concurrency_execution_approval_missing");
  }
}

export function createConcurrencyRuntime(
  serviceKey: string,
  fetcher: FetchLike = fetch,
):
  & Pick<
    CardFixtureRuntime,
    "beforeInitialAuthorization" | "afterInitialAuthorization"
  >
  & {
    acceptanceEvidence(): ConcurrencyAcceptanceEvidence | null;
  } {
  let evidence: ConcurrencyAcceptanceEvidence | null = null;
  const headers = {
    apikey: serviceKey,
    authorization: `Bearer ${serviceKey}`,
    accept: "application/json",
    "content-type": "application/json",
  };
  const request = async (path: string, body?: Record<string, unknown>) => {
    let response: Response;
    try {
      response = await fetcher(new URL(path, R06_PROJECT_URL), {
        method: body ? "POST" : "GET",
        redirect: "error",
        signal: AbortSignal.timeout(8_000),
        headers,
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
    } catch {
      throw new CardFixtureError("claim_outcome_unknown_stop_no_retry");
    }
    if (!response.ok) {
      throw new CardFixtureError("canonical_acceptance_check_failed");
    }
    try {
      return await response.json() as unknown;
    } catch {
      throw new CardFixtureError("backend_response_invalid");
    }
  };
  const rpc = async (name: string, body: Record<string, unknown>) =>
    parseRecord(await request(`/rest/v1/rpc/${name}`, body));
  const readRows = async (table: string, query: Record<string, string>) => {
    const url = new URL(`/rest/v1/${table}`, R06_PROJECT_URL);
    for (const [key, value] of Object.entries(query)) {
      url.searchParams.set(key, value);
    }
    const value = await request(url.pathname + url.search);
    if (!Array.isArray(value)) {
      throw new CardFixtureError("backend_response_invalid");
    }
    return value as Record<string, unknown>[];
  };
  const expectedContext = (context: AttemptContext) => ({
    paymentId: context.paymentId,
    attemptId: context.attemptId,
    riderId: context.riderId,
    paymentVersion: context.paymentVersion,
    tripId: context.tripId,
    tripVersion: context.tripVersion,
    driverId: context.driverId,
    tripStatus: "accepted",
    method: "card",
    paymentStatus: "cardPaymentPending",
    amountFils: context.amountFils,
    currency: "JOD",
    idempotencyKey: context.operationKey,
  });
  const claimBody = (context: AttemptContext) => ({
    actor_rider_id: context.riderId,
    target_trip_id: context.tripId,
    target_payment_id: context.paymentId,
    target_attempt_id: context.attemptId,
    expected_trip_version: context.tripVersion,
    expected_payment_version: context.paymentVersion,
    operation_key: context.operationKey,
  });

  return {
    acceptanceEvidence: () => evidence,
    beforeInitialAuthorization: async (context) => {
      const [tripRows, paymentRows, priorAttempts] = await Promise.all([
        readRows("trips", {
          select:
            "id,status,version,payment_method,rider_id,original_fare_fils,current_fare_fils,currency",
          id: `eq.${context.tripId}`,
          rider_id: `eq.${context.riderId}`,
          limit: "2",
        }),
        readRows("payments", {
          select:
            "id,trip_id,rider_id,method,card_status,authorized_amount_fils,final_amount_fils,currency,version",
          id: `eq.${context.paymentId}`,
          trip_id: `eq.${context.tripId}`,
          rider_id: `eq.${context.riderId}`,
          limit: "2",
        }),
        readRows("payment_attempts", {
          select: "id",
          payment_id: `eq.${context.paymentId}`,
          limit: "2",
        }),
      ]);
      if (
        tripRows.length !== 1 || paymentRows.length !== 1 ||
        priorAttempts.length !== 0 ||
        tripRows[0].status !== "accepted" ||
        tripRows[0].version !== context.tripVersion ||
        tripRows[0].payment_method !== "card" ||
        paymentRows[0].version !== context.paymentVersion ||
        paymentRows[0].method !== "card" ||
        paymentRows[0].card_status !== "cardPaymentPending" ||
        paymentRows[0].currency !== "JOD" ||
        paymentRows[0].authorized_amount_fils !==
          paymentRows[0].final_amount_fils ||
        paymentRows[0].authorized_amount_fils !==
          tripRows[0].original_fare_fils ||
        paymentRows[0].final_amount_fils !== tripRows[0].current_fare_fils ||
        tripRows[0].currency !== "JOD"
      ) throw new CardFixtureError("acceptance_preflight_failed");
    },
    afterInitialAuthorization: async (context) => {
      const withAttempt = { ...context, attemptId: context.attemptId! };
      // Both network requests start together; no read or await is performed first.
      const claimResults = await Promise.allSettled([
        rpc("backend_claim_stripe_test_preparation", claimBody(withAttempt)),
        rpc("backend_claim_stripe_test_preparation", claimBody(withAttempt)),
      ]);
      if (claimResults.some((result) => result.status === "rejected")) {
        await rpc("backend_read_stripe_test_preparation", {
          target_attempt_id: withAttempt.attemptId,
          actor_rider_id: withAttempt.riderId,
        }).catch(() => null);
        throw new CardFixtureError(
          "claim_outcome_unknown_reconciled_read_only",
        );
      }
      const replies = claimResults.map((result) =>
        (result as PromiseFulfilledResult<Record<string, unknown>>).value
      );
      const claimed = replies.filter((reply) =>
        reply.disposition === "claimed"
      );
      const existing = replies.filter((reply) =>
        reply.disposition === "existing"
      );
      const expected = expectedContext(withAttempt);
      for (const reply of replies) {
        const contextValue = reply.context as
          | Record<string, unknown>
          | undefined;
        if (
          reply.state !== "reserved" || reply.reference !== null ||
          !contextValue ||
          Object.entries(expected).some(([key, value]) =>
            contextValue[key] !== value
          )
        ) throw new CardFixtureError("claim_context_mismatch");
      }
      if (
        claimed.length !== 1 || existing.length !== 1 ||
        typeof claimed[0].claimToken !== "string" || !claimed[0].claimToken ||
        Object.hasOwn(existing[0], "claimToken")
      ) throw new CardFixtureError("claim_concurrency_invariant_failed");
      const recovered = await rpc("backend_read_stripe_test_preparation", {
        target_attempt_id: withAttempt.attemptId,
        actor_rider_id: withAttempt.riderId,
      });
      if (
        recovered.disposition !== "existing" ||
        recovered.state !== "reserved" ||
        recovered.reference !== null ||
        Object.hasOwn(recovered, "claimToken")
      ) throw new CardFixtureError("reservation_reconnect_unverified");
      const recoveredContext = recovered.context as
        | Record<string, unknown>
        | undefined;
      if (
        !recoveredContext ||
        Object.entries(expected).some(([key, value]) =>
          recoveredContext[key] !== value
        )
      ) throw new CardFixtureError("reservation_reconnect_unverified");
      evidence = {
        winner: replies[0].disposition === "claimed" ? "claimA" : "claimB",
        replayTokens: 0,
        reservationCount: 1,
        reconnected: true,
      };
    },
  };
}

if (import.meta.main) {
  const fixtureId = Deno.args.find((_, index) =>
    Deno.args[index - 1] === "--fixture-id"
  ) ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  assertConcurrencyApproval(
    fixtureId,
    Deno.env.get("R06_CONCURRENCY_APPROVAL_REF"),
  );
  if (!serviceKey) throw new CardFixtureError("configuration_missing");
  const runtime = createConcurrencyRuntime(serviceKey);
  const result = await runCardFixtureOperator(
    [...Deno.args, "--execute"],
    {
      SUPABASE_URL: Deno.env.get("SUPABASE_URL"),
      RIDEX_BACKEND_NAMESPACE: Deno.env.get("RIDEX_BACKEND_NAMESPACE"),
      SUPABASE_ANON_KEY: Deno.env.get("SUPABASE_ANON_KEY"),
      SUPABASE_SERVICE_ROLE_KEY: serviceKey,
      R06_RIDER_ACCESS_TOKEN: Deno.env.get("R06_RIDER_ACCESS_TOKEN"),
      R06_DRIVER_ACCESS_TOKEN: Deno.env.get("R06_DRIVER_ACCESS_TOKEN"),
      LOCALAPPDATA: Deno.env.get("LOCALAPPDATA"),
      R06_FIXTURE_STATE_FILE: Deno.env.get("R06_FIXTURE_STATE_FILE"),
      R06_EXECUTION_APPROVAL_REF:
        `owner-approved-r06-card-fixture-${fixtureId}`,
    },
    runtime,
  );
  const acceptance = runtime.acceptanceEvidence();
  if (!acceptance) {
    throw new CardFixtureError("acceptance_evidence_unavailable");
  }
  console.log(JSON.stringify({
    fixture: result,
    acceptance: { ...acceptance, financialStateUnchanged: true },
  }));
}
