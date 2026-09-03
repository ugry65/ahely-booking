begin;

select plan(5);

select ok(
  to_regprocedure('public.system_health_check()') is not null,
  'system_health_check RPC létezik'
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.system_health_check()'::regprocedure
  ),
  true,
  'system_health_check SECURITY DEFINER függvény'
);

select ok(
  coalesce(
    (
      select array_to_string(proconfig, ',') like '%search_path=public, pg_temp%'
      from pg_proc
      where oid = 'public.system_health_check()'::regprocedure
    ),
    false
  ),
  'system_health_check fix search_path beállítással fut'
);

select ok(
  has_function_privilege('anon', 'public.system_health_check()', 'EXECUTE'),
  'anon szerepkör végrehajthatja a minimális health RPC-t'
);

set local role anon;
select is(
  public.system_health_check(),
  true,
  'anon health check valós read-only DB ellenőrzést végez és sikeres'
);
reset role;

select * from finish();
rollback;
