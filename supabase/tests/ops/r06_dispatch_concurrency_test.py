"""Local Docker-only concurrency test. Requires an EMPTY isolated ridex_r06_safety_* DB.
Schema/migration setup is separate. Retains synthetic evidence; never resets/deletes data.
"""
import argparse
import json
import pathlib
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--database", required=True)
args = parser.parse_args()
if not re.fullmatch(r"ridex_r06_safety_[0-9]+", args.database):
    raise SystemExit("Only a dedicated local ridex_r06_safety_<digits> database is allowed.")
base = ["docker", "exec", "-i", "supabase_db_ridex", "psql", "-X", "-qAt",
        "-U", "postgres", "-d", args.database, "-v", "ON_ERROR_STOP=1"]

def sql(text):
    result = subprocess.run(base, input=text, text=True, capture_output=True, timeout=20)
    if result.returncode:
        raise RuntimeError("Local SQL check failed; inspect isolated test setup (no retry).")
    return result.stdout.strip()

if sql("select count(*) from public.users;") != "0":
    raise SystemExit("Isolated database is not empty. Do not reset or replay; use a new test database.")
fixture = pathlib.Path(__file__).resolve().parents[1] / "database/fixtures/r06_card_context.sql"
sql(fixture.read_text(encoding="utf-8-sig") + "\ncommit;\n")
attempt = sql("select id from public.payment_attempts where idempotency_key='r06-original-authorization';")
if not re.fullmatch(r"[0-9a-f-]{36}", attempt):
    raise RuntimeError("Local canonical attempt fixture unavailable.")
claim = (
    "set role service_role; set request.jwt.claims='{\"role\":\"service_role\"}';"
    "select public.backend_claim_stripe_test_preparation("
    "'22000000-0000-0000-0000-000000000001','22400000-0000-0000-0000-000000000001',"
    "'22500000-0000-0000-0000-000000000001','" + attempt + "',1,1,"
    "'r06-original-authorization')->>'disposition';"
)
first = subprocess.Popen(base, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True)
second = subprocess.Popen(base, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True)
first.stdin.write("begin;" + claim + "select pg_sleep(1);commit;")
first.stdin.close()
second.stdin.write(claim)
second.stdin.close()
first.wait(timeout=20)
second.wait(timeout=20)
if first.returncode or second.returncode:
    raise RuntimeError("Concurrent claim failed; evidence retained, no retry.")
outputs = first.stdout.read().split() + second.stdout.read().split()
assert outputs.count("claimed") == 1, outputs
assert outputs.count("existing") == 1, outputs
assert sql(claim) == "existing"  # independent new connection models restarted Edge owner
assert sql("select count(*) from private.stripe_test_dispatch_reservations;") == "1"
assert sql("select state from private.stripe_test_dispatch_reservations;") == "reserved"
assert sql("select status from public.payment_attempts where id='" + attempt + "';") == "pending"
assert sql("select card_status from public.payments where id='22500000-0000-0000-0000-000000000001';") == "cardPaymentPending"
assert sql("select count(*) from public.receipts;") == "0"
print(json.dumps({"status": "PASS", "concurrentClaimed": 1, "concurrentExisting": 1,
                  "restartedConnectionExisting": True, "reservationRetained": True,
                  "attemptPending": True, "paymentPending": True, "receipts": 0,
                  "providerInvocations": 0}))
