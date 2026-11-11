"""Offline, disposable-cluster regression checks for the P7 request guard."""
from __future__ import annotations

import importlib.util
import uuid
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("r06", ROOT / "supabase/tests/ops/r06_x2_local_test.py")
r06 = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(r06)


RIDER = "11111111-1111-4111-8111-111111111111"
SESSION = "22222222-2222-4222-8222-222222222222"
AUTH = "select set_config('request.jwt.claims','" + json.dumps(dict(sub=RIDER, role="authenticated", session_id=SESSION)) + "',false); set role authenticated;"

def budget_race(container: str, base: str, rollback: bool) -> None:
    db = r06.clone(container, base)
    r06.sql(container, db, "create table auth.sessions(id uuid primary key,user_id uuid not null,not_after timestamptz);")
    r06.sql(container, db, f"insert into auth.users(id,email,raw_user_meta_data) values ('{RIDER}','race@example.test','{{}}'); insert into auth.sessions values ('{SESSION}','{RIDER}',null); insert into private.rider_matching_request_budget values ('{RIDER}',clock_timestamp()+interval '2 minutes',29);")
    tag = 'matching_guard_' + uuid.uuid4().hex[:8]
    one = r06.session(container, db, tag+'_one'); two = None
    try:
        one.stdin.write("begin;"+AUTH+"do $$ begin if not public.rider_matching_request_guard() then raise exception 'winner not admitted'; end if; end $$;"+f"set application_name='{tag}_ready';\n")
        one.stdin.flush()
        r06.await_activity(container,tag+'_ready',"state='idle in transaction'",one)
        two = r06.session(container,db,tag+'_two')
        condition = 'not public.rider_matching_request_guard()' if rollback else 'public.rider_matching_request_guard()'
        two.stdin.write("begin;"+AUTH+"do $$ begin if "+condition+" then raise exception 'wrong contender admission'; end if; end $$;\n")
        two.stdin.flush()
        r06.await_activity(container,tag+'_two',"wait_event_type='Lock' and cardinality(pg_blocking_pids(pid))>0",two)
        for proc,tail in [(one,'rollback;' if rollback else 'commit;'),(two,'commit;')]:
            code,error=r06.finish(proc,tail)
            if code: raise RuntimeError('guard race failed: '+error)
        if r06.sql(container,db,'select request_count from private.rider_matching_request_budget;').stdout.strip()!='30': raise RuntimeError('budget escaped cap')
        print('PASS guard real lock waiter '+('rollback frees admission' if rollback else '30th wins / 31st denied'),flush=True)
    finally:
        for proc in (one,two):
            if proc is not None and proc.poll() is None: r06.finish(proc,'rollback;')

def main() -> None:
    container = r06.create_cluster()
    print("disposable network-none cluster: " + container, flush=True)
    base = r06.build_database(container)
    r06.build_database(container)  # independent full lexical replay
    # GoTrue owns auth.sessions; the migration replay intentionally does not create it.
    db = r06.clone(container, base)
    r06.sql(container, db, "create table auth.sessions(id uuid primary key,user_id uuid not null,not_after timestamptz);")
    r06.tap(container, db, ROOT / "supabase/tests/database/20261111095411_rider_matching_request_guard.test.sql")
    budget_race(container, base, False)
    budget_race(container, base, True)
    print("PASS: 27 matching guard TAP assertions, 2 independent-session races and two full 35-migration replays", flush=True)


if __name__ == "__main__":
    main()
