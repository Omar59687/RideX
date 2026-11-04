"""P7-A02: fresh network-isolated PostgreSQL; never touches existing stacks.
Run: python supabase/tests/ops/p7_a02_local_test.py
Each pgTAP file gets a fresh clone of the fully migrated empty database.
The minimal auth bootstrap verifies PostgreSQL contracts, not GoTrue integration.
Resources remain for review. No hosted connections or provider calls.
"""
from pathlib import Path
import json
import re
import r06_x2_local_test as harness


def main():
    container = harness.create_cluster()
    print('ISOLATED_CONTAINER=' + container, flush=True)
    inspection = harness.docker('inspect', container)
    if inspection.returncode:
        raise RuntimeError('Container isolation inspection failed')
    details = json.loads(inspection.stdout)[0]
    if (details['HostConfig']['NetworkMode'] != 'none' or details['Mounts']
            or details['HostConfig']['PortBindings']):
        raise RuntimeError('Container must have no network, mounts or port bindings')
    print('ISOLATION=network:none ports:none mounts:none', flush=True)
    print(harness.sql(container, 'postgres', 'select version();').stdout.strip(), flush=True)
    base = harness.build_database(container)
    root = harness.ROOT
    files = sorted((root / 'supabase/tests/database').glob('0*.test.sql'))
    files += sorted((root / 'supabase/tests/database').glob('2026102815000*.test.sql'))
    files += sorted((root / 'supabase/tests/database').glob('20261104*.test.sql'))
    report = []
    for path in files:
        db = harness.clone(container, base)
        content = harness.expand(path)
        # Existing Supabase-network transport adapted only in memory. The new
        # container has no network; dblink connects to its private Unix socket.
        content = content.replace('host=db port=5432 dbname=%s user=%s password=%s',
                                  'host=/tmp port=5432 dbname=%s user=%s application_name=%s')
        result = harness.sql(container, db, 'set search_path=public,extensions;\n' + content, must_succeed=False)
        lines = result.stdout.splitlines()
        passed = sum(bool(re.match(r'^ok [0-9]+', line)) and '# SKIP' not in line for line in lines)
        failed = sum(bool(re.match(r'^not ok [0-9]+', line)) for line in lines)
        skipped = sum('# SKIP' in line for line in lines)
        plans = [int(line[3:]) for line in lines if re.match(r'^1\.\.[0-9]+$', line)]
        good = result.returncode == 0 and not failed and plans and plans[-1] == passed + skipped
        row = dict(file=path.name, database=db, passed=passed, failed=failed, skipped=skipped, complete=bool(good))
        report.append(row)
        print(json.dumps(row), flush=True)
        if not good:
            print(result.stdout, flush=True)
            print(result.stderr, flush=True)
    print('TOTAL=' + json.dumps(dict(passed=sum(r['passed'] for r in report), failed=sum(r['failed'] for r in report), skipped=sum(r['skipped'] for r in report), incomplete=sum(not r['complete'] for r in report))), flush=True)
    if not all(r['complete'] for r in report):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
