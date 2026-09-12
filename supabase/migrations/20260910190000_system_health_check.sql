begin;

create or replace function public.system_health_check()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select true;
$$;

revoke all on function public.system_health_check() from public;
grant execute on function public.system_health_check() to anon;

comment on function public.system_health_check() is
  'Minimális, read-only production health RPC. Nem olvas üzleti vagy személyes adatot; kizárólag a PostgREST -> PostgreSQL útvonal működését igazolja.';

commit;
