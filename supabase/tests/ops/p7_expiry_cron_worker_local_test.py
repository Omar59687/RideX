"""Exercise the EXACT deferred P7 expiry Cron job in a new network-free PostgreSQL.

Unlike pgTAP of the expiry RPC, this runs real pg_cron background workers and
checks cron.job_run_details. No remote database, user secrets, mounts, published
ports, or pre-existing Docker resources are accessed or modified. The new test
container is intentionally retained for inspection.

Requires the cached public.ecr.aws/supabase/postgres:17.11.0.006 Docker image
and its pg_cron extension, with Docker Desktop already running.
"""
from __future__ import annotations

import time
import uuid
from pathlib import Path

import r06_x2_local_test as h

ROOT = Path(__file__).resolve().parents[3]
ACTIVATE = (ROOT / 'supabase/deferred/p7_expiry_cron_owner_approved_activation.sql').read_text(encoding='utf-8')
DISABLE = (ROOT / 'supabase/deferred/p7_expiry_cron_owner_approved_disable.sql').read_text(encoding='utf-8')
ACTIVATION_APPROVAL = (
    "SET ridex.p7_target_ref = 'network-isolated-local-test';\n"
    "SET ridex.p7_cron_approval = 'RIDEX_P7_CRON_REVIEWED';\n"
)
DISABLE_APPROVAL = (
    "SET ridex.p7_target_ref = 'network-isolated-local-test';\n"
    "SET ridex.p7_cron_disable_approval = 'RIDEX_P7_CRON_DISABLE_REVIEWED';\n"
)
JOB_NAME = 'ridex-p7-matching-expiry'


def cluster() -> str:
    """Never restart/alter a container from any previous test run."""
    name = 'ridex-p7-cron-' + uuid.uuid4().hex[:12]
    command = (
        'initdb -D /tmp/ridex-p7-cron-data --auth=trust --no-locale '
        '> /tmp/ridex-p7-cron-init.log && '
        'exec postgres -D /tmp/ridex-p7-cron-data -k /tmp '
        '-c listen_addresses= -c log_statement=none '
        '-c shared_preload_libraries=pg_cron '
        '-c cron.database_name=postgres '
        '-c cron.use_background_workers=on '
        '-c max_worker_processes=16'
    )
    result = h.docker(
        'run', '-d', '--name', name,
        '--label', 'ridex.p7-cron.disposable=true',
        '--network', 'none', '--user', 'postgres', '--entrypoint', 'sh',
        h.IMAGE, '-c', command,
    )
    if result.returncode:
        raise RuntimeError('Cannot create fresh network-isolated pg_cron PostgreSQL container')
    print('new network-free disposable container: ' + name, flush=True)
    for _ in range(120):
        if h.docker('exec', name, 'pg_isready', '-h', '/tmp', '-U', 'postgres').returncode == 0:
            return name
        if h.docker('inspect', '-f', '{{.State.Running}}', name).stdout.strip() == 'false':
            raise RuntimeError('PostgreSQL failed to start with pg_cron preloaded; inspect only this new container')
        time.sleep(0.1)
    raise RuntimeError('New pg_cron PostgreSQL did not become ready')


def install_schema(container: str) -> None:
    """Run canonical migrations in pg_cron database, avoiding schedule_in_database."""
    h.sql(container, 'postgres', (ROOT / 'supabase/tests/ops/r06_x2_bootstrap.sql').read_text(encoding='utf-8'))
    h.sql(container, 'postgres', 'CREATE EXTENSION pg_cron WITH SCHEMA pg_catalog;')
    migrations = sorted((ROOT / 'supabase/migrations').glob('*.sql'))
    for migration in migrations:
        try:
            h.sql(container, 'postgres', migration.read_text(encoding='utf-8-sig'))
        except RuntimeError as e:
            raise RuntimeError(f'Migration failed: {migration.name}: {e}') from None
        version, name = migration.stem.split('_', 1)
        h.sql(container, 'postgres',
              f"INSERT INTO supabase_migrations.schema_migrations(version,name) VALUES ('{version}','{name}');")
    print(f'PASS: {len(migrations)} canonical migrations and pg_cron installed locally', flush=True)


def scalar(container: str, query: str) -> str:
    return h.sql(container, 'postgres', query).stdout.strip()


def reject(container: str, script: str, message: str) -> None:
    result = h.sql(container, 'postgres', script, must_succeed=False)
    if result.returncode == 0 or message.lower() not in result.stderr.lower():
        raise RuntimeError(f'Expected fail-closed guard was not observed: {message}')


def job_count(container: str) -> int:
    return int(scalar(container, "SELECT count(*) FROM cron.job WHERE jobname='ridex-p7-matching-expiry';"))


def exercise(container: str) -> None:
    install_schema(container)
    assert job_count(container) == 0, 'Unexpected pre-existing Cron job'
    print('PASS: no job created implicitly by canonical migrations', flush=True)

    reject(container, ACTIVATE, 'Explicit owner approval')
    assert job_count(container) == 0, 'Unapproved activation created a job'
    print('PASS: activation without approval rejected', flush=True)

    # No fixture or live Booking is used; the real job must safely return zero.
    before = scalar(container,
        "SELECT concat_ws('|',(SELECT count(*) FROM public.booking_requests),"
        "(SELECT count(*) FROM public.driver_match_offers),"
        "(SELECT count(*) FROM public.trips),(SELECT count(*) FROM public.payments));")
    h.sql(container, 'postgres', ACTIVATION_APPROVAL + ACTIVATE)
    assert job_count(container) == 1, 'Expected one named Cron job'
    properties = scalar(container,
        "SELECT schedule || '|' || active::text || '|' || database || '|' || username "
        "FROM cron.job WHERE jobname='ridex-p7-matching-expiry';")
    assert properties == '5 seconds|true|postgres|postgres', ('Unexpected local Cron properties', properties)
    print('PASS: exactly one active five-second local Cron job', flush=True)

    reject(container, ACTIVATION_APPROVAL + ACTIVATE, 'An expiry job already exists')
    assert job_count(container) == 1, 'Duplicate activation changed job count'
    print('PASS: repeated activation rejected without replacing the job', flush=True)

    # Observe TWO independently scheduled executions. The actual job command
    # must succeed with SET LOCAL ROLE, JWT-role GUC, and a real database RPC.
    deadline = time.monotonic() + 25
    successes = 0
    while time.monotonic() < deadline:
        statuses = scalar(container,
            "SELECT coalesce(string_agg(status, ',' ORDER BY runid), '') "
            "FROM cron.job_run_details "
            "WHERE jobid=(SELECT jobid FROM cron.job WHERE jobname='ridex-p7-matching-expiry');")
        observations = [status for status in statuses.split(',') if status]
        unexpected = [status for status in observations if status not in ('succeeded', 'running', 'starting', 'connecting', 'sending')]
        if unexpected:
            raise RuntimeError('Local Cron worker failed: ' + ','.join(unexpected))
        successes = observations.count('succeeded')
        if successes >= 2:
            break
        time.sleep(0.5)
    if successes < 2:
        raise RuntimeError(f'Expected two successful actual five-second Cron executions, observed {successes}')
    after = scalar(container,
        "SELECT concat_ws('|',(SELECT count(*) FROM public.booking_requests),"
        "(SELECT count(*) FROM public.driver_match_offers),"
        "(SELECT count(*) FROM public.trips),(SELECT count(*) FROM public.payments));")
    assert before == after, 'Scheduler modified canonical records with no due work'
    print(f'PASS: {successes} actual pg_cron worker executions succeeded; no Trip/Payment/Booking changes', flush=True)

    reject(container, DISABLE, 'Explicit disable approval')
    assert scalar(container,
        "SELECT active::text FROM cron.job WHERE jobname='ridex-p7-matching-expiry';") == 'true'
    print('PASS: disable without approval rejected', flush=True)

    h.sql(container, 'postgres', DISABLE_APPROVAL + DISABLE)
    assert scalar(container,
        "SELECT active::text FROM cron.job WHERE jobname='ridex-p7-matching-expiry';") == 'false'
    assert job_count(container) == 1, 'Disable deleted the job'
    recorded = int(scalar(container,
        "SELECT count(*) FROM cron.job_run_details "
        "WHERE jobid=(SELECT jobid FROM cron.job WHERE jobname='ridex-p7-matching-expiry');"))
    assert recorded >= 2, 'Job history disappeared after disable'
    print('PASS: approved disable preserves named job and its run history', flush=True)
    print('PASS: actual local expiry Cron scheduling, execution, and disable lifecycle', flush=True)


def main() -> None:
    container = cluster()
    try:
        exercise(container)
    except BaseException:
        # This newly created network-free container belongs only to this test.
        # If assertions fail, do not leave the five-second job hammering the
        # local database until a developer manually investigates the failure.
        try:
            h.sql(container, 'postgres', """
                DO $cleanup$
                DECLARE target_job bigint;
                BEGIN
                  IF to_regclass('cron.job') IS NOT NULL THEN
                    SELECT jobid INTO target_job FROM cron.job
                    WHERE jobname='ridex-p7-matching-expiry';
                    IF target_job IS NOT NULL THEN
                      PERFORM cron.alter_job(target_job, active := false);
                    END IF;
                  END IF;
                END $cleanup$;
            """)
            print('SAFETY: local Cron job disabled after test failure', flush=True)
        except Exception as cleanup_error:
            print('WARNING: could not disable local test Cron job; inspect only ' +
                  container + ': ' + type(cleanup_error).__name__, flush=True)
        raise


if __name__ == '__main__':
    main()
