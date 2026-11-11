"""Real GoTrue/PostgREST in new internal-network containers; no shared stacks.

Only assertion labels print. Ephemeral local secrets/tokens stay in memory.
Resources created by this run are removed on completion, never existing ones.
"""
import base64
import hashlib
import hmac
import json
import ipaddress
import secrets
import subprocess
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
IMAGES = {'db': 'public.ecr.aws/supabase/postgres:17.11.0.006',
          'auth': 'public.ecr.aws/supabase/gotrue:v2.197.0',
          'rest': 'public.ecr.aws/supabase/postgrest:v16.5'}


def docker(*args, content=None):
    result = subprocess.run(['docker', *args], input=content, text=True,
                            capture_output=True, timeout=90)
    if result.returncode:
        raise RuntimeError('isolated Docker operation failed: ' + args[0])
    return result.stdout.strip()


def main():
    prefix = 'ridex-p7-auth-' + uuid.uuid4().hex[:10]
    names = {kind: prefix + '-' + kind for kind in IMAGES}
    secret = secrets.token_urlsafe(48)
    count = 0
    stage = 'initialization'

    def sql(statement):
        return docker('exec', '-i', names['db'], 'psql', '-h', '/tmp', '-U', 'postgres',
                      '-d', 'postgres', '-XAtq', '-v', 'ON_ERROR_STOP=1', content=statement)

    def request(service, path, token=None, body=None):
        host = 'auth:9999' if service == 'auth' else 'rest:3000'
        args = ['exec', '-i', names['db'], 'curl', '-sS', '--max-time', '10',
                '-X', 'POST' if body is not None else 'GET', '-H',
                'Content-Type: application/json', '-w', '\n%{http_code}']
        if token:
            args += ['-H', 'Authorization: Bearer ' + token]
        if body is not None:
            args += ['--data-binary', '@-']
        raw = docker(*args, 'http://' + host + path,
                     content=json.dumps(body) if body is not None else None)
        text, separator, status = raw.rpartition('\n')
        if not separator:
            text, status = '', raw
        return int(status), json.loads(text) if text else None

    def check(condition, label):
        nonlocal count
        if not condition:
            raise RuntimeError('assertion failed: ' + label)
        count += 1
        print('PASS ' + label, flush=True)

    def ready(kind, path):
        for _ in range(60):
            try:
                if request(kind, path)[0] == 200:
                    return
            except (RuntimeError, ValueError):
                pass
            time.sleep(.5)
        raise RuntimeError('isolated service readiness timeout: ' + kind)

    try:
        for image in IMAGES.values():
            docker('image', 'inspect', image)
        # Default Docker pools can be exhausted by retained developer networks.
        ids = docker('network', 'ls', '-q').splitlines()
        used = [ipaddress.ip_network(c['Subnet']) for n in json.loads(docker('network', 'inspect', *ids)) for c in (n.get('IPAM', {}).get('Config') or []) if c.get('Subnet')]
        subnet = next(str(ipaddress.ip_network(f'10.254.{n}.0/24')) for n in range(1,255) if not any(ipaddress.ip_network(f'10.254.{n}.0/24').overlaps(x) for x in used if x.version==4))
        docker('network', 'create', '--internal', '--subnet', subnet, '--label', 'ridex.p7.auth-test=true', prefix)
        stage = 'PostgreSQL startup'
        docker('run', '-d', '--name', names['db'], '--network', prefix,
               '--network-alias', 'db', '--label', 'ridex.p7.auth-test=true',
               '--user', 'postgres', '--entrypoint', 'sh', IMAGES['db'], '-c',
               'initdb -D /tmp/p7-auth --auth=trust --no-locale >/tmp/init.log && '
               f"printf 'host all all {subnet} trust\\n' >> /tmp/p7-auth/pg_hba.conf && "
               'exec postgres -D /tmp/p7-auth -k /tmp -c listen_addresses=*')
        for _ in range(100):
            probe = subprocess.run(['docker', 'exec', names['db'], 'pg_isready', '-h', '/tmp'], capture_output=True)
            if probe.returncode == 0:
                break
            time.sleep(.2)
        else:
            raise RuntimeError('database readiness timeout')
        # Bootstrap roles/helpers only; real GoTrue creates all Auth tables.
        bootstrap = (ROOT / 'supabase/tests/ops/r06_x2_bootstrap.sql').read_text()
        start, end = bootstrap.index('create table auth.users'), bootstrap.index('create function auth.uid()')
        sql(bootstrap[:start] + bootstrap[end:])
        sql('alter role authenticator login;')
        stage = 'real GoTrue startup'
        env = dict(GOTRUE_API_HOST='0.0.0.0', GOTRUE_API_PORT='9999', API_EXTERNAL_URL='http://auth:9999',
                   GOTRUE_DB_DRIVER='postgres', GOTRUE_DB_DATABASE_URL='postgres://postgres@db:5432/postgres?sslmode=disable&search_path=auth',
                   GOTRUE_JWT_SECRET=secret, GOTRUE_JWT_DEFAULT_GROUP_NAME='authenticated', GOTRUE_JWT_AUD='authenticated', GOTRUE_JWT_EXP='3600',
                   GOTRUE_SITE_URL='http://localhost', GOTRUE_DISABLE_SIGNUP='false',
                   GOTRUE_EXTERNAL_EMAIL_ENABLED='true', GOTRUE_MAILER_AUTOCONFIRM='true')
        args = ['run', '-d', '--name', names['auth'], '--network', prefix, '--network-alias', 'auth',
                '--label', 'ridex.p7.auth-test=true']
        for key, value in env.items():
            args += ['-e', key + '=' + value]
        docker(*args, IMAGES['auth'])
        ready('auth', '/health')
        stage = 'app migration replay over real Auth schema'
        migrations = sorted((ROOT / 'supabase/migrations').glob('*.sql'))
        for migration in migrations:
            sql(migration.read_text(encoding='utf-8-sig'))
            version, name = migration.stem.split('_', 1)
            sql(f"insert into supabase_migrations.schema_migrations(version,name) values ('{version}','{name}');")
        print('REPLAY ' + str(len(migrations)) + ' app migrations over real GoTrue schema', flush=True)
        stage = 'PostgREST startup'
        docker('run', '-d', '--name', names['rest'], '--network', prefix, '--network-alias', 'rest',
               '--label', 'ridex.p7.auth-test=true', '-e',
               'PGRST_DB_URI=postgres://authenticator@db:5432/postgres?sslmode=disable', '-e',
               'PGRST_DB_SCHEMAS=public', '-e', 'PGRST_DB_ANON_ROLE=anon', '-e',
               'PGRST_JWT_SECRET=' + secret, IMAGES['rest'])
        ready('rest', '/')
        stage = 'real HTTP assertions'
        check(sql("select to_regclass('auth.sessions') is not null;") == 't', 'GoTrue created session table')
        tokens = []
        for index in range(2):
            email, password = f'rider{index}@example.test', secrets.token_urlsafe(20)
            status, data = request('auth', '/signup', body=dict(email=email, password=password,
                                                              data=dict(role='rider', display_name='Local Rider')))
            check(status == 200 and bool(data.get('access_token')), 'real Rider signup ' + str(index) + ' status=' + str(status) + ' code=' + str(data.get('error_code', data.get('code','none'))))
            status, data = request('auth', '/token?grant_type=password', body=dict(email=email, password=password))
            check(status == 200 and bool(data.get('access_token')), 'real sign-in ' + str(index))
            tokens.append((data['access_token'], data['user']['id']))
        token, rider = tokens[0]
        check(request('auth', '/user', token)[1]['id'] == rider, 'authoritative Auth identity')
        association = request('rest', '/rpc/rider_matching_session_is_active', token, {})
        check(association == (200, True), 'real session association ' + str(association))
        check(request('rest', '/rpc/rider_matching_request_guard', token, {}) == (200, True), 'real request admission')
        check(request('rest', '/rpc/rider_matching_request_guard', body={})[0] in (401, 403), 'missing JWT rejected')
        check(request('rest', '/rpc/rider_matching_request_guard', 'invalid-token', {})[0] == 401, 'invalid JWT rejected')
        enc = lambda b: base64.urlsafe_b64encode(b).rstrip(b'=').decode()
        message = enc(b'{"alg":"HS256","typ":"JWT"}') + '.' + enc(json.dumps(dict(
            sub=rider, role='authenticated', aud='authenticated', exp=int(time.time()) - 600)).encode())
        expired = message + '.' + enc(hmac.new(secret.encode(), message.encode(), hashlib.sha256).digest())
        check(request('rest', '/rpc/rider_matching_request_guard', expired, {})[0] == 401, 'expired JWT rejected')
        claims = json.loads(base64.urlsafe_b64decode(token.split('.')[1] + '=='))
        check(sql(f"select exists(select 1 from auth.sessions where id='{claims['session_id']}' and user_id='{rider}');") == 't', 'real JWT session_id ownership')
        check(request('rest', '/users?id=eq.' + rider, tokens[1][0])[1] == [], 'foreign Rider profile isolation')
        booking = str(uuid.uuid4())
        sql(f"insert into public.booking_requests(id,rider_id,pickup,destination,vehicle_type_code,payment_method) values ('{booking}','{rider}','{{\"latitude\":31.95,\"longitude\":35.93}}','{{\"latitude\":31.96,\"longitude\":35.94}}','economy','cash');")
        check(request('rest','/booking_requests?select=id&id=eq.'+booking,token)[1] == [{'id':booking}], 'Rider can read own canonical Booking')
        check(request('rest','/booking_requests?select=id&id=eq.'+booking,tokens[1][0])[1] == [], 'foreign Rider Booking hidden by real PostgREST RLS')
        sql((ROOT/'supabase/ops/p7_matching_readonly_preflight.sql').read_text())
        check(True, 'read-only deployment preflight executes on real Auth schema')
        sql(f"update public.users set is_blocked=true where id='{rider}';")
        check(request('rest', '/rpc/rider_matching_session_is_active', token, {}) == (200, False), 'blocked Rider denied')
        check(request('rest', '/rpc/rider_matching_request_guard', token, {})[0] == 403, 'blocked admission denied')
        sql(f"update public.users set is_blocked=false where id='{rider}';")
        sql(f"update private.rider_matching_request_budget set window_started_at=clock_timestamp()+interval '2 minutes',request_count=1 where rider_id='{rider}';")
        check(all(request('rest','/rpc/rider_matching_request_guard',token,{}) == (200, True) for _ in range(29)), 'real HTTP requests two through thirty admitted')
        check(request('rest', '/rpc/rider_matching_request_guard', token, {}) == (200, False), 'exhausted durable budget denied')
        check(request('rest', '/rpc/backend_expire_due_booking_matches', token, {})[0] in (401, 403, 404), 'Rider scheduler access denied')
        check(request('rest', '/rpc/backend_expire_booking_match_offers', token,
                      dict(target_booking_request_id=str(uuid.uuid4()), expected_booking_version=1))[0] in (401, 403, 404), 'Rider privileged expiry denied')
        check(request('auth', '/logout?scope=global', token, {})[0] == 204, 'real GoTrue logout')
        check(sql(f"select count(*) from auth.sessions where id='{claims['session_id']}';") == '0', 'GoTrue deleted logged-out session')
        check(request('rest', '/rpc/rider_matching_session_is_active', token, {}) == (200, False), 'unexpired JWT denied after logout')
        check(request('rest', '/rpc/rider_matching_request_guard', token, {})[0] == 403, 'logged-out JWT cannot enter matching')
        print(f'TOTAL PASS={count} FAIL=0 SKIP=0; local real Auth/PostgREST only', flush=True)
    except Exception:
        print('FAIL stage: ' + stage, flush=True)
        # Report only structured server error fields; never request headers or tokens.
        logs = subprocess.run(['docker','logs','--tail','8',names['auth']], capture_output=True, text=True)
        for line in (logs.stdout + logs.stderr).splitlines():
            try:
                error = json.loads(line).get('error')
                if error:
                    import re
                    error = re.sub(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+', '<redacted-address>', str(error))
                    print('Auth diagnostic: ' + error[:500], flush=True)
            except ValueError:
                pass
        raise
    finally:
        for name in names.values():
            info = subprocess.run(['docker','inspect',name], capture_output=True, text=True)
            if info.returncode == 0 and json.loads(info.stdout)[0].get('Config',{}).get('Labels',{}).get('ridex.p7.auth-test') == 'true':
                subprocess.run(['docker', 'rm', '-f', name], capture_output=True)
        info = subprocess.run(['docker','network','inspect',prefix], capture_output=True, text=True)
        if info.returncode == 0 and json.loads(info.stdout)[0].get('Labels',{}).get('ridex.p7.auth-test') == 'true':
            subprocess.run(['docker', 'network', 'rm', prefix], capture_output=True)


if __name__ == '__main__':
    main()
