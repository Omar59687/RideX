import {
  assertConcurrencyApproval,
  createConcurrencyRuntime,
} from "./r06_accept_card_concurrency.ts";
import { CardFixtureError } from "./r06_card_fixture_contract.ts";
import type { FetchLike } from "./r06_prepare_card_fixture.ts";

const context = {
  riderId: "22000000-0000-4000-8000-000000000001",
  driverId: "22000000-0000-4000-8000-000000000002",
  tripId: "22400000-0000-4000-8000-000000000004",
  paymentId: "22400000-0000-4000-8000-000000000005",
  attemptId: "22400000-0000-4000-8000-000000000006",
  amountFils: 2_150,
  tripVersion: 1,
  paymentVersion: 1,
  operationKey: "r06-card-test-initial-auth",
};
const reservationContext = {
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
};

function json(value: unknown): Response {
  return new Response(JSON.stringify(value), { status: 200 });
}

Deno.test("concurrency approval is bound to one fresh fixture UUID", () => {
  assertConcurrencyApproval(
    context.attemptId,
    `owner-approved-r06-card-concurrency-${context.attemptId}`,
  );
  try {
    assertConcurrencyApproval(
      context.attemptId,
      "owner-approved-r06-card-concurrency-other",
    );
  } catch (error) {
    if (
      error instanceof CardFixtureError &&
      error.code === "concurrency_execution_approval_missing"
    ) return;
    throw error;
  }
  throw new Error("approval for a different fixture was accepted");
});

Deno.test("operator starts two independent claims together and reconnects without token replay", async () => {
  let claimCalls = 0;
  let activeClaims = 0;
  let maximumConcurrentClaims = 0;
  let reconnectCalls = 0;
  const fetcher: FetchLike = async (input) => {
    const url = new URL(String(input));
    if (url.pathname.endsWith("backend_claim_stripe_test_preparation")) {
      const ordinal = ++claimCalls;
      activeClaims++;
      maximumConcurrentClaims = Math.max(maximumConcurrentClaims, activeClaims);
      await new Promise((resolve) => setTimeout(resolve, 5));
      activeClaims--;
      return json(
        ordinal === 1
          ? {
            disposition: "claimed",
            state: "reserved",
            context: reservationContext,
            claimToken: "one-time",
            reference: null,
          }
          : {
            disposition: "existing",
            state: "reserved",
            context: reservationContext,
            reference: null,
          },
      );
    }
    if (url.pathname.endsWith("backend_read_stripe_test_preparation")) {
      reconnectCalls++;
      return json({
        disposition: "existing",
        state: "reserved",
        context: reservationContext,
        reference: null,
      });
    }
    throw new Error(`Unexpected request ${url.pathname}`);
  };
  const runtime = createConcurrencyRuntime("service-test-key", fetcher);
  if (!runtime.afterInitialAuthorization) throw new Error("Missing race hook");
  await runtime.afterInitialAuthorization(context);
  if (
    claimCalls !== 2 || maximumConcurrentClaims !== 2 || reconnectCalls !== 1
  ) {
    throw new Error("Claims did not run concurrently or reconnect was omitted");
  }
  const evidence = runtime.acceptanceEvidence();
  if (
    !evidence || evidence.replayTokens !== 0 ||
    evidence.reservationCount !== 1 ||
    evidence.reconnected !== true
  ) {
    throw new Error(
      "Acceptance evidence did not report the required invariants",
    );
  }
});

Deno.test("unknown claim acknowledgements reconcile read-only and never replay", async () => {
  let claimCalls = 0;
  let reconnectCalls = 0;
  const fetcher: FetchLike = async (input) => {
    const url = new URL(String(input));
    if (url.pathname.endsWith("backend_claim_stripe_test_preparation")) {
      claimCalls++;
      if (claimCalls === 1) throw new Error("lost acknowledgement");
      return json({
        disposition: "existing",
        state: "reserved",
        context: reservationContext,
        reference: null,
      });
    }
    if (url.pathname.endsWith("backend_read_stripe_test_preparation")) {
      reconnectCalls++;
      return json({
        disposition: "existing",
        state: "reserved",
        context: reservationContext,
        reference: null,
      });
    }
    throw new Error(`Unexpected request ${url.pathname}`);
  };
  const runtime = createConcurrencyRuntime("service-test-key", fetcher);
  if (!runtime.afterInitialAuthorization) throw new Error("Missing race hook");
  try {
    await runtime.afterInitialAuthorization(context);
  } catch (error) {
    if (
      !(error instanceof CardFixtureError) ||
      error.code !== "claim_outcome_unknown_reconciled_read_only"
    ) throw error;
    if (claimCalls !== 2 || reconnectCalls !== 1) {
      throw new Error("Unknown outcome was retried");
    }
    return;
  }
  throw new Error("Unknown claim outcome was accepted");
});
