create or replace function public.system_health_check()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists(select 1 from public.app_settings);
$$;

revoke all on function public.system_health_check() from public;
grant execute on function public.system_health_check() to anon, authenticated;
