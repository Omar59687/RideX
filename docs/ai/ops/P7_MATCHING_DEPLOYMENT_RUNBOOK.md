# P7 Matching Deployment Runbook

## Status and scope

This is a deployment preparation record for owner review. **READY FOR OWNER APPROVAL is not deployment approval.** No hosted command was run and no hosted or developer stack was changed. This document covers the Rider matching request guard and expiry scheduler only. Follow account/environment approvals and P6 restrictions in force for this project; this does not approve P6/payment work, production access, or any broader release. Authentication fixtures in the offline guard harness use a minimal `auth.sessions` table; they are not real GoTrue acceptance. Real GoTrue/session acceptance is handled separately and is a prerequisite before deployment approval.

## Final integrated local evidence

Final baseline `9aab49971d6d21358c61908f6574b3dc35243f2b`; final tree has 36 migrations. Sol reran A02: **1317 PASS / 0 FAIL / 0 SKIP**, A04: **19 races PASS**, guard: **27 assertions + 2 races PASS**, scheduler: **17 assertions + 2 scenarios PASS**, and real GoTrue/PostgREST HTTP: **26 assertions PASS**. These replace the initial mixed-checkpoint results. An initial exact backend-RPC inventory assertion failed when the new scheduler RPC was introduced; its authorized signature was added while retaining every privilege check, and the full 1317 assertions then passed. Scheduler fixture/actor/race mistakes were corrected without relaxing production invariants.

All DB runtimes are disposable: offline tests use network-none; real Auth uses a unique internal network, no host ports, and GoTrue-created users/sessions. The guard harness's final summary still says 35 as a legacy caption, but its two actual migration-chain headers report 36. Exact latest evidence is consolidated in P7_YOUSUF_FINAL_BACKEND_ACCEPTANCE.md. No hosted command was run.

## Migration sequence and compatibility

The guard migration is `20261111095410_rider_matching_request_guard.sql`; scheduler migration is `20261111103410_p7_matching_expiry_scheduler.sql`. Apply in lexical timestamp order after the existing chain. Confirm exact versions and no unexpected history entries in the intended Supabase project before applying. The local full-chain harnesses establish replay against their PostgreSQL 17.11 container only; they do not establish compatibility with the target project's Supabase/Postgres/GoTrue versions. Confirm target platform and `auth.sessions` columns/semantics against the actual hosted catalog using the read-only queries below before approval. The guard fails closed when the session relation/columns are unavailable. Do not infer hosted compatibility from synthetic local fixtures.

## Parameterized preflight commands

These are manual operator commands, intentionally not executed here. Use a separately approved account and explicit target reference. Keep credentials in the operator's secure environment; do not put tokens in shell history or this document.

```powershell
$ProjectRef = '<approved-project-ref>'
$DbUrl = '<approved-read-only-database-url>'
# Manual read-only catalog check using psql; ensure the supplied role is read-only.
psql "$DbUrl" -v ON_ERROR_STOP=1 -X -f supabase/ops/p7_matching_readonly_preflight.sql
# Supabase CLI status only; verify this CLI is linked to the intended project first.
npx --yes supabase@3.1.0 migration list --remote=$ProjectRef
```

Never run `db push`, `migration up`, SQL migrations, or any mutation during preflight. For hosted manual checks, obtain owner approval first, use the approved account/environment, and run only the read-only queries below. Do not paste secrets into logs.

### Duplicate nonterminal-trip preflight (read only)

Run with an authorized read-only database role. Review rows and resolve any duplicates through the separately approved operational process before deployment; this query does not alter data.

```sql
select driver_id, count(*) as nonterminal_trip_count,
       array_agg(id order by created_at, id) as trip_ids
from public.trips
where status not in ('completed','cancelledByRider','cancelledByDriver','cancelledByAdmin','failed')
group by driver_id
having count(*) > 1
order by driver_id;
```

## Actual catalog verification queries

Run read-only against the intended target. Inspect signatures, owners, security/search-path properties, ACLs including implicit PUBLIC execute, and private-table grants. Expected RPC signatures are `public.rider_matching_session_is_active()` and `public.rider_matching_request_guard()`. Authenticated should have execute; `anon`, `service_role`, and `PUBLIC` should not. The private budget table should have no grants to `PUBLIC`, `anon`, `authenticated`, or `service_role`.

```sql
select n.nspname as schema_name, p.proname, pg_get_function_identity_arguments(p.oid) as identity_arguments,
       pg_get_function_result(p.oid) as result_type, p.prosecdef as security_definer,
       p.provolatile as volatility, p.proconfig as function_settings,
       pg_get_userbyid(p.proowner) as owner, p.proacl
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in
 ('rider_matching_session_is_active','rider_matching_request_guard')
order by p.proname;

select routine_schema, routine_name, grantee, privilege_type, is_grantable
from information_schema.routine_privileges
where routine_schema='public' and routine_name in
 ('rider_matching_session_is_active','rider_matching_request_guard')
order by routine_name, grantee, privilege_type;

select n.nspname as schema_name, c.relname as relation_name, c.relkind, c.relacl
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='private' and c.relname='rider_matching_request_budget';

select table_schema, table_name, grantee, privilege_type, is_grantable
from information_schema.role_table_grants
where table_schema='private' and table_name='rider_matching_request_budget'
order by grantee, privilege_type;

select to_regclass('auth.sessions') as auth_sessions_relation,
       (select string_agg(column_name, ', ' order by ordinal_position)
        from information_schema.columns where table_schema='auth' and table_name='sessions') as session_columns;
```

Check migration history separately with the approved CLI read-only status command and compare exact versions to the reviewed repository chain, including both P7 migrations. Catalog output must be reviewed by the owner/operator; this runbook does not interpret an unexpected ACL or schema as safe.

## Deployment handling and rollback

Before any deployment, take/confirm a recoverable database backup or provider-supported restore point and record its timestamp, target, and restore owner. Review migration SQL and target compatibility, migration history, duplicate-trip query, function signatures/grants, private relation permissions, GoTrue session schema, and scheduler prerequisites with the owner. Obtain explicit approval for the exact target and maintenance window. Apply migrations in lexical order using the approved deployment process, then repeat read-only catalog checks and the approved real-auth/scheduler acceptance. Record command output and exact pass/fail/skip/not-run counts without credentials.

If deployment fails, stop subsequent steps, preserve logs, and notify the owner. Use the provider restore/recovery procedure only under explicit incident/owner authorization. Do not run destructive or automatic rollback SQL: the migrations may not be safely reversible and request-budget state must be treated as data. No rollback statement is supplied here. Reconcile the deployed migration history and application compatibility before any retry.

## Approval gate

Current disposition: **READY FOR OWNER APPROVAL** for review of this runbook and its local evidence only. Hosted preflight, actual hosted catalog verification, target compatibility, real GoTrue acceptance, deployment, post-deployment checks, and any rollback remain **NOT RUN**. Do not describe this status as approved or deployed.

## Executable owner-approved deployment sequence (NOT EXECUTED)

These commands were prepared against Supabase CLI 3.1.0 help. They are not authorization. Review target, CLI version, credentials, P6 gates, backup and exact pending SQL before any mutation. Keep matching flags off throughout preflight.

```powershell
# Read-only preflight first. A role permitted to inspect Auth metadata is required.
psql "$DbUrl" -X -v ON_ERROR_STOP=1 -f supabase/ops/p7_matching_readonly_preflight.sql
npx --yes supabase@3.1.0 migration list --remote=$ProjectRef
# Owner-approved backup only; credentials supplied securely by operator.
pg_dump --dbname="$BackupDbUrl" --format=custom --file=ridex-before-p7-expiry.backup
pg_restore --list ridex-before-p7-expiry.backup
# After explicit target/migration approval. Skip unrelated Vault changes, even in dry run.
npx --yes supabase@3.1.0 db push --remote=$ProjectRef --skip-vault --dry-run
# STOP for review of exact pending migration list; do not include roles, seeds or deferred publication SQL.
npx --yes supabase@3.1.0 db push --remote=$ProjectRef --skip-vault
# Only if separately approved and current deployed function differs:
npx --yes supabase@3.1.0 functions deploy cash-matching --remote=$ProjectRef
psql "$DbUrl" -X -v ON_ERROR_STOP=1 -f supabase/ops/p7_matching_readonly_preflight.sql
```

Do not disable JWT verification, prune functions, or enable the integration flag from these commands. Record actual new deployment function version, schema history, role grants and target identifier. Repeat the HTTP cases in P7_REAL_AUTH_ACCEPTANCE.md using approved accounts and the real target, recording no tokens. Activate the single named expiry job only through the separately reviewed scheduler document after local/manual-target batch acceptance; check zero duplicates first. Hosted destructive rollback is not automatic: first disable only this job and keep app flags off; retain offer/audit/budget history and stop ingress, then use an owner-approved restore or reviewed forward fix. Do not drop historical data or automatically reverse the migration.
