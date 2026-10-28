"""Network-free R06-X2 PostgreSQL tests in a NEW disposable Docker cluster.

Creates no hosted connections, calls no providers, reads no environment keys,
does not alter the original RideX state files, and never resets/drops/stops any
pre-existing container/database. Resources are intentionally left for review.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
IMAGE = "public.ecr.aws/supabase/postgres:17.11.0.006"
RIDER = "d3c3dc11-a840-4712-a6a4-599b4ae27329"
TRIP = "dda56345-4123-4a0c-9771-5287899d2344"
PAYMENT = "cbbb4b94-ac92-49b9-8b43-1f370c783e5b"
ATTEMPT = "45ae3584-fa38-4fa5-b8c8-10efd79f8416"
APPROVAL = "8168236a-6a53-4a08-8dfa-f79e68fe8921"
REQUEST = "8168236a-6a53-4a08-8dfa-f79e68fe8923"
FIXTURE = "8168236a-6a53-4a08-8dfa-f79e68fe8925"
RECOVER = f"select public.rider_recover_r06_x2_reserved_fixture('{FIXTURE}','{TRIP}','{PAYMENT}','{ATTEMPT}',1,1,12,'{APPROVAL}','{REQUEST}');"
RIDER_AUTH = f"select set_config('request.jwt.claims','{{\"sub\":\"{RIDER}\",\"role\":\"authenticated\"}}',false); set role authenticated;"
BACKEND_AUTH = "select set_config('request.jwt.claims','{\"role\":\"service_role\"}',false); set role service_role;"


def docker(*args: str, input: str | None = None, timeout: int = 60) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["docker", *args], input=input, text=True, capture_output=True, timeout=timeout, check=False)


def sql(container: str, db: str, statement: str, *, must_succeed: bool = True) -> subprocess.CompletedProcess[str]:
    result = docker("exec", "-i", container, "psql", "-h", "/tmp", "-U", "postgres", "-d", db,
                    "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", input=statement)
    if must_succeed and result.returncode:
        # SQL is test-owned. Never echo result rows or parameter values/tokens.
        message = next((line for line in result.stderr.splitlines() if "ERROR:" in line), "PostgreSQL failure")
        raise RuntimeError(message)
    return result


def expand(path: Path) -> str:
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    return "\n".join(expand(path.parent / line[4:].strip()) if line.startswith("\\ir ") else line for line in lines)


def create_cluster() -> str:
    name = "ridex-r06-x2-" + uuid.uuid4().hex[:12]
    result = docker("run", "-d", "--name", name, "--label", "ridex.r06-x2.disposable=true",
                    "--network", "none", "--user", "postgres", "--entrypoint", "sh", IMAGE, "-c",
                    "initdb -D /tmp/r06-x2-data --auth=trust --no-locale > /tmp/r06-x2-init.log && "
                    "exec postgres -D /tmp/r06-x2-data -k /tmp -c listen_addresses= -c log_statement=none")
    if result.returncode:
        raise RuntimeError("Could not create a new isolated PostgreSQL container")
    for _ in range(100):
        if docker("exec", name, "pg_isready", "-h", "/tmp", "-U", "postgres").returncode == 0:
            return name
        time.sleep(0.1)
    raise RuntimeError("New disposable PostgreSQL cluster failed to start")


def build_database(container: str) -> str:
    db = "r06_x2_base_" + uuid.uuid4().hex[:10]
    sql(container, "postgres", f'create database "{db}";')
    sql(container, db, (ROOT / "supabase/tests/ops/r06_x2_bootstrap.sql").read_text())
    migrations = sorted((ROOT / "supabase/migrations").glob("*.sql"))
    for migration in migrations:
        content = migration.read_text(encoding="utf-8-sig")
        try:
            sql(container, db, content)
        except RuntimeError as error:
            raise RuntimeError(f"Migration {migration.name}: {error}") from None
        version, name = migration.stem.split("_", 1)
        sql(container, db, f"insert into supabase_migrations.schema_migrations(version,name) values ('{version}','{name}');")
    actual = sql(container, db, "select string_agg(version,',' order by version) from supabase_migrations.schema_migrations;").stdout.strip()
    if actual != ",".join(m.name.split("_", 1)[0] for m in migrations):
        raise RuntimeError("Migration history does not match the complete lexical chain")
    approvals = sql(container, db, "select count(*) from private.r06_x2_owner_approvals;").stdout.strip()
    if approvals != "0":
        raise RuntimeError("Migration must not provision recovery approval evidence")
    print(f"migration chain: {len(migrations)} applied, exact history, zero approvals ({db})", flush=True)
    return db


def clone(container: str, base: str) -> str:
    db = "r06_x2_test_" + uuid.uuid4().hex[:10]
    sql(container, "postgres", f'create database "{db}" template "{base}";')
    return db


def load_fixture(container: str, db: str) -> None:
    sql(container, db, expand(ROOT / "supabase/tests/database/fixtures/r06_x2_reserved_target.sql"))
    sql(container, db, expand(ROOT / "supabase/tests/database/fixtures/r06_x2_synthetic_approval.sql"))


def tap(container: str, db: str, path: Path) -> int:
    content = expand(path)
    if path.name == "20261028150001_cash_only_booking_confirmation_concurrency.test.sql":
        # Keep the existing regression file untouched. Its Supabase-network
        # hostname is adapted in memory to this container's Unix socket.
        original = "host=db port=5432 dbname=%s user=%s password=%s"
        if content.count(original) != 1:
            raise RuntimeError("Unexpected dblink transport in existing Cash regression")
        content = content.replace(original, "host=/tmp port=5432 dbname=%s user=%s application_name=%s")
    result = sql(container, db, "set search_path=public,extensions;\n" + content)
    lines = result.stdout.splitlines()
    failed = [line for line in lines if re.match(r"^(not ok|Bail out!)", line)]
    plans = [line for line in lines if re.match(r"^1\.\.[0-9]+$", line)]
    if failed or not plans:
        raise RuntimeError(path.name + ": " + "; ".join(failed or ["missing pgTAP plan"]))
    count = int(plans[-1].split("..")[1])
    if len([line for line in lines if re.match(r"^ok [0-9]+", line)]) != count:
        raise RuntimeError(path.name + ": pgTAP count mismatch")
    print(f"pgTAP {path.name}: {count} passed", flush=True)
    return count


def activity(container: str, app: str, predicate: str) -> bool:
    return sql(container, "postgres", f"select exists(select 1 from pg_stat_activity where application_name='{app}' and {predicate});").stdout.strip() == "t"


def await_activity(container: str, app: str, predicate: str, process: subprocess.Popen[str] | None = None) -> None:
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if process is not None and process.poll() is not None:
            error = process.stderr.read() if process.stderr is not None else ""
            message = next((line for line in error.splitlines() if "ERROR:" in line), "session exited")
            raise RuntimeError("PostgreSQL session ended before its barrier: " + message)
        if activity(container, app, predicate):
            return
        time.sleep(0.03)
    raise RuntimeError("Deterministic PostgreSQL barrier not reached")


def session(container: str, db: str, app: str) -> subprocess.Popen[str]:
    process = subprocess.Popen(["docker", "exec", "-i", container, "psql", "-h", "/tmp", "-U", "postgres", "-d", db,
                                "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1"],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert process.stdin is not None
    process.stdin.write(f"set application_name='{app}'; set statement_timeout='15s';\n")
    process.stdin.flush()
    return process


def finish(process: subprocess.Popen[str], tail: str = "") -> tuple[int, str]:
    assert process.stdin is not None
    try:
        process.stdin.write(tail + "\n")
        process.stdin.close()
    except (BrokenPipeError, OSError):
        # ON_ERROR_STOP may already have closed the expected losing session.
        pass
    process.stdin = None
    _, error = process.communicate(timeout=25)
    return process.returncode, error


def races(container: str, base: str) -> int:
    # Winner remains idle in an open transaction holding real row locks. The
    # controller observes pg_stat_activity and pg_blocking_pids before COMMIT;
    # no timing-based pg_sleep synchronization is used.
    claim = f"do $$ begin perform public.backend_claim_stripe_test_preparation('{RIDER}','{TRIP}','{PAYMENT}','{ATTEMPT}',1,1,'r06-x2-synthetic-operation'); end $$;"
    # Private token stays inside the database, selected as owner before SET ROLE.
    record = f"do $$ declare token uuid; begin select claim_token into token from private.stripe_test_dispatch_reservations where attempt_id='{ATTEMPT}'; perform set_config('request.jwt.claims','{{\"role\":\"service_role\"}}',true); perform public.backend_record_stripe_test_preparation('{ATTEMPT}',token,'pi_LocalLateEvidence'); end $$;"
    complete = f"select (public.backend_complete_payment_attempt('{ATTEMPT}','failed','pi_LocalCompletion')).status;"
    insert = f"insert into public.payment_attempts(payment_id,type,requested_amount_fils,currency,idempotency_key) values ('{PAYMENT}','providerStatusVerification',2550,'JOD','local-concurrent-insert');"
    webhook_update = f"update public.processed_webhook_events set payment_id='{PAYMENT}' where id='8168236a-6a53-4a08-8dfa-f79e68fe8902';"
    refund_update = f"update public.refunds set payment_id='{PAYMENT}' where id='8168236a-6a53-4a08-8dfa-f79e68fe8901';"
    change_insert = f"insert into public.trip_change_requests(trip_id,rider_id,requested_destination) values ('{TRIP}','{RIDER}','{{\"latitude\":32.0,\"longitude\":36.0}}');"
    operations = {"claim": BACKEND_AUTH + claim, "record": record,
                  "completion": BACKEND_AUTH + complete, "direct-insert": BACKEND_AUTH + insert,
                  "webhook-reassignment": BACKEND_AUTH + webhook_update,
                  "refund-reassignment": BACKEND_AUTH + refund_update,
                  # Baseline service_role lacks EXECUTE on the route-validator
                  # CHECK function. Owner DML exercises this additional fence
                  # without weakening any application-role grant in the test.
                  "trip-change-owner-insert": change_insert}
    count = 0
    for operation, command in operations.items():
        for recovery_first in (False, True):
            db = clone(container, base)
            load_fixture(container, db)
            if operation in ("webhook-reassignment", "refund-reassignment"):
                sql(container, db, expand(ROOT / "supabase/tests/database/fixtures/r06_x2_unrelated_financial_evidence.sql"))
            # The exact historical claim is expired. For the successful
            # claim-first ordering only, make its LOCAL synthetic creation time
            # fresh; recovery must then refuse the changed approved snapshot.
            if operation == "claim" and not recovery_first:
                sql(container, db, "alter table public.payment_attempts disable trigger user; "
                    "update public.payment_attempts set created_at=now(); "
                    "alter table public.payment_attempts enable trigger user;")
            first_command = RIDER_AUTH + RECOVER if recovery_first else command
            second_command = command if recovery_first else RIDER_AUTH + RECOVER
            first_app = "r06_x2_first_" + uuid.uuid4().hex[:8]
            second_app = "r06_x2_second_" + uuid.uuid4().hex[:8]
            first = session(container, db, first_app)
            assert first.stdin is not None
            first.stdin.write("begin;\n" + first_command + f"\nset application_name='{first_app}_ready';\n")
            first.stdin.flush()
            await_activity(container, first_app + "_ready", "state='idle in transaction'", first)
            second = session(container, db, second_app)
            assert second.stdin is not None
            second.stdin.write("begin;\n" + second_command + "\n")
            second.stdin.flush()
            await_activity(container, second_app, "wait_event_type='Lock' and cardinality(pg_blocking_pids(pid))>0", second)
            first_code, _ = finish(first, "commit;")
            second_code, second_error = finish(second, "commit;")
            if first_code:
                raise RuntimeError(f"{operation} race winner failed")
            expected_failure = True
            if bool(second_code) != expected_failure or (second_code and "R06-X2" not in second_error):
                raise RuntimeError(f"{operation} race loser had unexpected sanitized result")
            recovered = sql(container, db, "select count(*) from private.r06_x2_recoveries;").stdout.strip()
            expected_recovered = recovery_first
            if recovered != ("1" if expected_recovered else "0"):
                raise RuntimeError(f"{operation} race broke atomic recovery")
            outcome = sql(container, db, "select t.status::text||'|'||p.card_status::text||'|'||a.status::text||'|'||r.state||'|'||d.state::text "
                "from public.trips t join public.payments p on p.trip_id=t.id "
                f"join public.payment_attempts a on a.id='{ATTEMPT}' "
                "join private.stripe_test_dispatch_reservations r on r.attempt_id=a.id "
                "join public.driver_availability d on d.driver_id=t.driver_id;").stdout.strip()
            expected = ("cancelledByRider|paymentCancelled|pending|reserved|offline" if recovery_first else
                        "accepted|cardPaymentPending|" + ("failed" if operation == "completion" else "pending") +
                        "|" + ("prepared" if operation == "record" else "reserved") + "|onTrip")
            if outcome != expected:
                raise RuntimeError(f"{operation} race left an incorrect canonical outcome")
            if operation in ("webhook-reassignment", "refund-reassignment", "trip-change-owner-insert"):
                table = {"webhook-reassignment": "processed_webhook_events", "refund-reassignment": "refunds",
                         "trip-change-owner-insert": "trip_change_requests"}[operation]
                predicate = f"trip_id='{TRIP}'" if operation == "trip-change-owner-insert" else f"payment_id='{PAYMENT}'"
                evidence_count = sql(container, db, f"select count(*) from public.{table} where {predicate};").stdout.strip()
                if evidence_count != ("0" if recovery_first else "1"):
                    raise RuntimeError(f"{operation} race lost evidence or crossed the recovery fence")
            count += 1
            print(f"race {operation}/recovery ({'recovery' if recovery_first else operation} first): passed", flush=True)
    for conflict in (False, True):
        db = clone(container, base)
        load_fixture(container, db)
        first_app = "r06_x2_first_" + uuid.uuid4().hex[:8]
        second_app = "r06_x2_second_" + uuid.uuid4().hex[:8]
        first = session(container, db, first_app)
        assert first.stdin is not None
        first.stdin.write("begin;\n" + RIDER_AUTH + RECOVER + f"\nset application_name='{first_app}_ready';\n")
        first.stdin.flush()
        await_activity(container, first_app + "_ready", "state='idle in transaction'", first)
        second = session(container, db, second_app)
        assert second.stdin is not None
        second_command = RECOVER.replace(REQUEST, "8168236a-6a53-4a08-8dfa-f79e68fe8924") if conflict else RECOVER
        second.stdin.write("begin;\n" + RIDER_AUTH + second_command + "\n")
        second.stdin.flush()
        await_activity(container, second_app, "wait_event_type='Lock' and cardinality(pg_blocking_pids(pid))>0", second)
        first_code, _ = finish(first, "commit;")
        second_code, second_error = finish(second, "commit;")
        if first_code or not second_code or ("conflicts" if conflict else "reconcile read-only") not in second_error:
            raise RuntimeError("Concurrent duplicate/conflict had unexpected outcome")
        if sql(container, db, "select count(*) from private.r06_x2_recoveries;").stdout.strip() != "1":
            raise RuntimeError("Concurrent duplicate/conflict created multiple recoveries")
        count += 1
        print(f"race {'conflicting' if conflict else 'duplicate'} recovery requests: passed", flush=True)
    return count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--existing-new-container", help="Only a freshly created network-none ridex-r06-x2-* cluster")
    args = parser.parse_args()
    if args.existing_new_container:
        container = args.existing_new_container
        if not re.fullmatch(r"ridex-r06-x2-[a-z0-9-]+", container):
            parser.error("Container must have the disposable R06-X2 prefix")
        details = json.loads(docker("inspect", container).stdout)[0]
        if details["HostConfig"]["NetworkMode"] != "none" or details["Mounts"]:
            parser.error("Existing test container must have no network or mounts")
    else:
        container = create_cluster()
    print("disposable cluster: " + container, flush=True)
    base = build_database(container)
    # A second complete from-scratch replay validates repeat reset/history,
    # without mutating/resetting any existing database or migration files.
    build_database(container)
    tests = sorted((ROOT / "supabase/tests/database").glob("2026102814022*.test.sql"))
    tests += sorted((ROOT / "supabase/tests/database").glob("2026102719234*.test.sql"))
    tests += sorted((ROOT / "supabase/tests/database").glob("2026102719235*.test.sql"))
    tests += [ROOT / "supabase/tests/database/20261026163720_stripe_test_reservation.test.sql",
              ROOT / "supabase/tests/database/20261028150000_cash_only_rider_booking_confirmation.test.sql",
              ROOT / "supabase/tests/database/20261028150001_cash_only_booking_confirmation_concurrency.test.sql"]
    assertions = sum(tap(container, clone(container, base), test) for test in tests)
    race_count = races(container, base)
    print(f"PASS: {assertions} pgTAP assertions; {race_count} real independent-connection races; 2 full migration replays", flush=True)


if __name__ == "__main__":
    main()
