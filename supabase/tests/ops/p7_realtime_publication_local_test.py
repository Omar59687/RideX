"""Check owner-guarded P7 Realtime SQL against a fresh, network-isolated PostgreSQL.

Uses the existing R06 local harness: a NEW Docker container with --network none,
no mounts or project credentials, and a full migration replay. Never connects to
hosted Supabase or alters pre-existing containers. The disposable container is
intentionally left for inspection (same behavior as the existing expiry harness).

This verifies PostgreSQL publication state and the SQL approval/rollback fences;
it does NOT constitute a Supabase Realtime WebSocket acceptance test.
"""
from __future__ import annotations

from pathlib import Path

import r06_x2_local_test as h

ROOT = Path(__file__).resolve().parents[3]
ACTIVATE = (ROOT / 'supabase/deferred/p7_realtime_owner_approved_activation.sql').read_text(encoding='utf-8')
ROLLBACK = (ROOT / 'supabase/deferred/p7_realtime_owner_approved_rollback.sql').read_text(encoding='utf-8')

CREATE_PUBLICATION = (
    "CREATE PUBLICATION supabase_realtime "
    "WITH (publish = 'insert, update, delete, truncate');"
)
APPROVE_ACTIVATION = (
    "SET ridex.p7_target_ref = 'isolated-docker-test';\n"
    "SET ridex.p7_realtime_approval = 'RIDEX_P7_REALTIME_REVIEWED';\n"
)
APPROVE_ROLLBACK = (
    "SET ridex.p7_target_ref = 'isolated-docker-test';\n"
    "SET ridex.p7_realtime_rollback_approval = 'RIDEX_P7_REALTIME_ROLLBACK_REVIEWED';\n"
)
EXPECTED_MEMBERS = 'public.driver_locations,public.trip_status_events,public.trips'


def state(container: str, database: str) -> tuple[str, str]:
    """Read normalized publication flags and exact membership."""
    flags = h.sql(container, database, """
        SELECT concat_ws(',', pubinsert, pubupdate, pubdelete, pubtruncate,
                         puballtables)
        FROM pg_catalog.pg_publication
        WHERE pubname = 'supabase_realtime';
    """).stdout.strip()
    members = h.sql(container, database, """
        SELECT coalesce(string_agg(schemaname || '.' || tablename,
                                  ',' ORDER BY schemaname, tablename), '')
        FROM pg_catalog.pg_publication_tables
        WHERE pubname = 'supabase_realtime';
    """).stdout.strip()
    return flags, members


def require_state(container: str, database: str, flags: str, members: str) -> None:
    actual = state(container, database)
    if actual != (flags, members):
        raise RuntimeError(f'Publication state mismatch: expected {(flags, members)}, got {actual}')


def must_reject(container: str, database: str, script: str, expected_message: str) -> None:
    result = h.sql(container, database, script, must_succeed=False)
    if result.returncode == 0 or expected_message.lower() not in result.stderr.lower():
        # Intentionally do not print full SQL or session variables.
        raise RuntimeError(f'Guard did not reject safely: {expected_message}')


def check() -> None:
    container = h.create_cluster()
    print(f'network-isolated disposable container: {container}', flush=True)
    base = h.build_database(container)
    db = h.clone(container, base)
    h.sql(container, db, CREATE_PUBLICATION)
    original = 't,t,t,t,f'
    safe = 't,t,f,f,f'
    require_state(container, db, original, '')
    print('PASS initial publication empty; INSERT/UPDATE/DELETE/TRUNCATE enabled', flush=True)

    # Missing approval must not change the publication.
    must_reject(container, db, ACTIVATE, 'Explicit owner approval')
    require_state(container, db, original, '')
    print('PASS activation rejected without owner approval; publication unchanged', flush=True)

    # Separate clone: an otherwise-approved activation must reject absent RLS.
    bad = h.clone(container, base)
    h.sql(container, bad, CREATE_PUBLICATION)
    h.sql(container, bad, 'ALTER TABLE public.driver_locations DISABLE ROW LEVEL SECURITY;')
    must_reject(container, bad, APPROVE_ACTIVATION + ACTIVATE,
                'Required RLS/SELECT contract missing')
    require_state(container, bad, original, '')
    print('PASS activation rejected missing RLS; publication unchanged', flush=True)

    # Activation is atomic; it MUST publish only the three approved tables.
    h.sql(container, db, APPROVE_ACTIVATION + ACTIVATE)
    require_state(container, db, safe, EXPECTED_MEMBERS)
    print('PASS approved local activation: exact three tables and INSERT/UPDATE only', flush=True)

    # Even an approved second activation fails closed (no accidental replay).
    must_reject(container, db, APPROVE_ACTIVATION + ACTIVATE,
                'Publication already has')
    require_state(container, db, safe, EXPECTED_MEMBERS)
    print('PASS duplicate activation rejected; publication unchanged', flush=True)

    # Rollback needs its own separate explicit owner approval.
    must_reject(container, db, ROLLBACK, 'Explicit rollback approval')
    require_state(container, db, safe, EXPECTED_MEMBERS)
    print('PASS rollback rejected without approval', flush=True)

    # Extra membership must never be silently removed by rollback.
    h.sql(container, db, 'ALTER PUBLICATION supabase_realtime ADD TABLE public.users;')
    unexpected = EXPECTED_MEMBERS + ',public.users'
    require_state(container, db, safe, unexpected)
    must_reject(container, db, APPROVE_ROLLBACK + ROLLBACK,
                'Publication does not match sole RideX membership')
    require_state(container, db, safe, unexpected)
    h.sql(container, db, 'ALTER PUBLICATION supabase_realtime DROP TABLE public.users;')
    require_state(container, db, safe, EXPECTED_MEMBERS)
    print('PASS rollback refuses an unrelated table; no destructive changes', flush=True)

    # Approved local rollback restores precisely the initial publication.
    h.sql(container, db, APPROVE_ROLLBACK + ROLLBACK)
    require_state(container, db, original, '')
    print('PASS approved local rollback: empty membership and original operations', flush=True)
    print('PASS: all isolated PostgreSQL Realtime publication guard scenarios', flush=True)


if __name__ == '__main__':
    check()
