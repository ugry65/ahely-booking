begin;

select plan(8);

select is(
  (select namespace.nspname
   from pg_extension extension
   join pg_namespace namespace on namespace.oid = extension.extnamespace
   where extension.extname = 'btree_gist'),
  'extensions',
  'btree_gist is outside the exposed public schema'
);

select ok(
  exists (
    select 1
    from pg_constraint constraint_row
    join pg_class relation on relation.oid = constraint_row.conrelid
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'bookings'
      and constraint_row.conname = 'bookings_no_room_overlap'
      and constraint_row.contype = 'x'
  ),
  'database-level double-booking exclusion constraint remains present'
);

select ok(
  not exists (
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.prosecdef
      and has_function_privilege('anon', procedure.oid, 'EXECUTE')
  ),
  'anon cannot execute SECURITY DEFINER functions'
);

select ok(
  not exists (
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.prosecdef
      and has_function_privilege('public', procedure.oid, 'EXECUTE')
  ),
  'PUBLIC cannot execute SECURITY DEFINER functions'
);

select ok(
  not exists (
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.prosecdef
      and not coalesce(procedure.proconfig @> array['search_path=""'], false)
  ),
  'every public SECURITY DEFINER function has an empty fixed search_path'
);

select ok(
  not exists (
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.prosecdef
      and left(procedure.proname, 6) = 'admin_'
      and has_function_privilege('authenticated', procedure.oid, 'EXECUTE')
      and position('public.require_active_admin()' in pg_get_functiondef(procedure.oid)) = 0
  ),
  'every authenticated admin SECURITY DEFINER API has the active-admin guard'
);

select ok(
  not has_schema_privilege('anon', 'public', 'CREATE')
  and not has_schema_privilege('authenticated', 'public', 'CREATE')
  and not has_schema_privilege('public', 'public', 'CREATE'),
  'untrusted API roles cannot create objects in public'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.create_booking_series(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.create_booking_series_base(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid)',
    'EXECUTE'
  ),
  'legacy recurring wrapper remains callable but its guarded base helper remains internal'
);

select * from finish();
rollback;
