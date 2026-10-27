"""Real two-session concurrency checks for the local R06 retirement guard.

Run only against a disposable Supabase local project, after `supabase db reset`:
  python supabase/tests/ops/r06_retirement_concurrency_test.py \
    --project ridex-r06-isolated --scenario claim-before-retirement

The project name is constrained to the R06 test prefix and all SQL is sent to
the named local Docker database container. The script never reads hosted env.
"""

from __future__ import annotations

import argparse
import subprocess
import time
from pathlib import Path


RIDER = "22000000-0000-0000-0000-000000000001"
TRIP = "ceff7eb6-2d1f-4744-9cbc-243d80d550ba"
PAYMENT = "44444444-4444-4444-8444-444444444438"
ATTEMPT_KEY = "r06-retirement-original-authorization"
OPERATION_KEY = "r06-retirement-original-authorization"


def psql(container: str, sql: str, *, expect_success: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        [
            "docker", "exec", "-i", container,
            "psql", "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1",
            "-U", "postgres", "-d", "postgres",
        ],
        input=sql,
        text=True,
        capture_output=True,
        timeout=20,
        check=False,
    )
    if expect_success != (result.returncode == 0):
        raise RuntimeError("local PostgreSQL concurrency operation had an unexpected result")
    return result


def setup_fixture(container: str) -> None:
    root = Path(__file__).resolve().parents[3]
    base_path = root / "supabase/tests/database/fixtures/r06_card_context.sql"
    target_path = root / "supabase/tests/database/fixtures/r06_retirement_target.sql"
    base = base_path.read_text(encoding="utf-8-sig")
    target_lines = target_path.read_text(encoding="utf-8-sig").splitlines()
    if not target_lines or target_lines[0].strip() != r"\ir r06_card_context.sql":
        raise RuntimeError("unexpected local test fixture include")
    sql = base + "\n" + "\n".join(target_lines[1:]) + "\ncommit;\n"
    psql(container, sql)


def outcome(container: str) -> str:
    result = psql(
        container,
        f"""
        select trips.status::text || '|' || payments.card_status::text || '|' || attempts.status::text || '|' ||
          (select count(*)::text from private.stripe_test_dispatch_reservations where trip_id = trips.id)
        from public.trips as trips
        join public.payments as payments on payments.trip_id = trips.id
        join public.payment_attempts as attempts on attempts.payment_id = payments.id
        where trips.id = '{TRIP}';
        """,
    )
    return result.stdout.strip()


def run_session(container: str, sql: str, *, expected_message: str) -> None:
    result = psql(container, sql, expect_success=False)
    if expected_message not in result.stderr:
        raise RuntimeError("local PostgreSQL session failed with an unexpected sanitized outcome")


def wait_for_first_session(container: str) -> None:
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        result = psql(
            container,
            "select count(*) from pg_catalog.pg_stat_activity "
            "where application_name = 'r06_concurrency_first' "
            "and wait_event = 'PgSleep';",
        )
        if result.stdout.strip() == "1":
            return
        time.sleep(0.05)
    raise RuntimeError("first local PostgreSQL session did not reach the synchronization barrier")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument(
        "--scenario",
        required=True,
        choices=(
            "claim-before-retirement",
            "retirement-before-claim",
            "completion-before-retirement",
            "retirement-before-completion",
        ),
    )
    args = parser.parse_args()
    if not args.project.startswith("ridex-r06-") or "/" in args.project or "\\" in args.project:
        parser.error("--project must name an isolated ridex-r06-* local Docker project")
    container = f"supabase_db_{args.project}"
    setup_fixture(container)

    claim = f"""
      begin;
      select set_config('request.jwt.claims', '{{"role":"service_role"}}', true);
      select public.backend_claim_stripe_test_preparation(
        '{RIDER}', '{TRIP}', '{PAYMENT}',
        (select id from public.payment_attempts where idempotency_key='{ATTEMPT_KEY}'),
        1, 1, '{OPERATION_KEY}');
    """
    retire = f"""
      begin;
      select set_config('request.jwt.claims', '{{"sub":"{RIDER}","role":"authenticated"}}', true);
      select public.rider_retire_r06_card_fixture(
        '{TRIP}', 1, '{PAYMENT}', 1,
        (select id from public.payment_attempts where idempotency_key='{ATTEMPT_KEY}'));
    """
    completion = f"""
      begin;
      select set_config('request.jwt.claims', '{{"role":"service_role"}}', true);
      select public.backend_complete_payment_attempt(
        (select id from public.payment_attempts where idempotency_key='{ATTEMPT_KEY}'),
        'failed', 'pi_r06_concurrent_failure');
    """

    if args.scenario == "claim-before-retirement":
        first_sql = "select set_config('application_name','r06_concurrency_first',false);\n" + claim + "select pg_catalog.pg_sleep(5); commit;\n"
        first = subprocess.Popen(
            ["docker", "exec", "-i", container, "psql", "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        assert first.stdin is not None
        first.stdin.write(first_sql)
        first.stdin.close()
        wait_for_first_session(container)
        run_session(container, retire, expected_message="R06 dispatch reservation exists; retirement is refused.")
        first_stdout, first_stderr = first.communicate(timeout=15)
        if first.returncode != 0 or "claimed" not in first_stdout:
            raise RuntimeError("reservation claimant did not commit the expected winner")
        if outcome(container) != "accepted|cardPaymentPending|pending|1":
            raise RuntimeError("claim-first race changed financial or Trip state")

    elif args.scenario == "retirement-before-claim":
        first_sql = "select set_config('application_name','r06_concurrency_first',false);\n" + retire + "select pg_catalog.pg_sleep(5); commit;\n"
        first = subprocess.Popen(
            ["docker", "exec", "-i", container, "psql", "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        assert first.stdin is not None
        first.stdin.write(first_sql)
        first.stdin.close()
        wait_for_first_session(container)
        run_session(container, claim, expected_message="Canonical preparation context unavailable.")
        first_stdout, first_stderr = first.communicate(timeout=15)
        if first.returncode != 0 or "cancelledByRider" not in first_stdout:
            raise RuntimeError("retirement did not commit before the blocked claim")
        if outcome(container) != "cancelledByRider|paymentCancelled|pending|0":
            raise RuntimeError("retirement-first race changed Attempt or reservation state")

    elif args.scenario == "completion-before-retirement":
        first_sql = "select set_config('application_name','r06_concurrency_first',false);\n" + completion + "select pg_catalog.pg_sleep(5); commit;\n"
        first = subprocess.Popen(
            ["docker", "exec", "-i", container, "psql", "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        assert first.stdin is not None
        first.stdin.write(first_sql)
        first.stdin.close()
        wait_for_first_session(container)
        run_session(container, retire, expected_message="R06 authorization evidence is not eligible for retirement.")
        first_stdout, first_stderr = first.communicate(timeout=15)
        if first.returncode != 0:
            raise RuntimeError("provider completion did not commit before guarded cancellation")
        if outcome(container) != "accepted|cardPaymentPending|failed|0":
            raise RuntimeError("completion-first race allowed unsafe cancellation")

    else:
        first_sql = "select set_config('application_name','r06_concurrency_first',false);\n" + retire + "select pg_catalog.pg_sleep(5); commit;\n"
        first = subprocess.Popen(
            ["docker", "exec", "-i", container, "psql", "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        assert first.stdin is not None
        first.stdin.write(first_sql)
        first.stdin.close()
        wait_for_first_session(container)
        run_session(container, completion, expected_message="The retired R06 authorization evidence is immutable.")
        first_stdout, first_stderr = first.communicate(timeout=15)
        if first.returncode != 0 or "cancelledByRider" not in first_stdout:
            raise RuntimeError("retirement did not commit before the blocked Attempt completion")
        if outcome(container) != "cancelledByRider|paymentCancelled|pending|0":
            raise RuntimeError("late completion changed the retired Attempt")

    print(f"{args.scenario}: PASS (two independent local PostgreSQL sessions)")


if __name__ == "__main__":
    main()
