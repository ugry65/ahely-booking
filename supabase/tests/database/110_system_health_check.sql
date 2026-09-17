begin;

select plan(5);

select has_function(
  'public',
  'system_health_check',
  array[]::text[],
  'A minimális adatbázis-health RPC létezik'
);

select is(
  public.system_health_check(),
  true,
  'A health RPC egészséges adatbázisban true értéket ad'
);

select is(
  (
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'system_health_check'
      and p.pronargs = 0
  ),
  false,
  'A health RPC nem SECURITY DEFINER'
);

select ok(
  has_function_privilege('anon', 'public.system_health_check()', 'EXECUTE'),
  'Az anon szerepkör explicit végrehajthatja a health RPC-t'
);

select ok(
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    where n.nspname = 'public'
      and p.proname = 'system_health_check'
      and p.pronargs = 0
      and acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  ),
  'A PUBLIC szerepkör nem kap végrehajtási jogot a health RPC-re'
);

select * from finish();
rollback;
