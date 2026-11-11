-- Phase 7 Realtime publication membership for canonical Trip and Driver
-- location state.
--
-- This migration only adds the three required tables to the existing
-- supabase_realtime publication. It does not create the publication, change
-- RLS, grants, replica identity, publication-wide publish settings, or add
-- unrelated tables.
--
-- SECURITY: adding a table to the publication does not bypass RLS for
-- INSERT/UPDATE, but Supabase/Postgres Changes does not apply RLS to DELETE
-- payloads. Publication operations are publication-wide; this migration never
-- changes them and aborts unless DELETE and TRUNCATE are already disabled.
-- The gate is intentional until owners inventory subscribers and approve the
-- publication-wide operation set. See the D06 handoff for read-only checks.
begin;

do $migration$
declare
  required_publication constant text := 'supabase_realtime';
  required_schema constant text := 'public';
  required_tables constant text[] := array[
    'trips',
    'trip_status_events',
    'driver_locations'
  ];
  required_table text;
begin
  if not exists (
    select 1
    from pg_catalog.pg_publication
    where pubname = required_publication
  ) then
    raise exception
      'Required publication "%" does not exist. Create it before applying this migration.',
      required_publication
      using errcode = '42704';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_publication
    where pubname = required_publication
      and puballtables
  ) then
    raise exception
      'Publication "%" is FOR ALL TABLES; refusing to treat scoped membership as verified.',
      required_publication
      using errcode = '55000';
  end if;

  -- Postgres Changes does not apply RLS to DELETE payloads. The publication
  -- operation set is publication-wide, so changing it here could affect
  -- unrelated subscribers. Fail closed until an owner has separately audited
  -- subscribers and configured an approved INSERT/UPDATE-only publication.
  if exists (
    select 1
    from pg_catalog.pg_publication
    where pubname = required_publication
      and (pubdelete or pubtruncate)
  ) then
    raise exception
      'Publication "%" currently publishes DELETE or TRUNCATE. Review all subscribers and configure an approved operation set before adding Trip/location tables.',
      required_publication
      using errcode = '55000';
  end if;

  foreach required_table in array required_tables loop
    if pg_catalog.to_regclass(
      pg_catalog.format('%I.%I', required_schema, required_table)
    ) is null then
      raise exception
        'Required table "%.%" does not exist. Apply the canonical schema before this migration.',
        required_schema, required_table
        using errcode = '42P01';
    end if;

    if not exists (
      select 1
      from pg_catalog.pg_publication_tables
      where pubname = required_publication
        and schemaname = required_schema
        and tablename = required_table
    ) then
      execute pg_catalog.format(
        'alter publication %I add table %I.%I',
        required_publication, required_schema, required_table
      );
    end if;
  end loop;
end
$migration$;

commit;
