-- Isolated restore target only. Never run against a hosted project.
-- Supabase Auth upstream migration 20260831180000 (commit 05d9aec):
-- https://github.com/supabase/auth/commit/05d9aec
-- Preserve the complete COPY block, including non-null token expiry values.
do $$
begin
  if to_regclass('auth.one_time_tokens') is null then
    raise exception 'Isolated Auth bootstrap table is missing';
  end if;
  alter table auth.one_time_tokens add column if not exists expires_at timestamptz;
  if not exists (
    select 1 from pg_attribute a
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where a.attrelid = 'auth.one_time_tokens'::regclass
      and a.attname = 'expires_at' and not a.attisdropped
      and a.atttypid = 'timestamptz'::regtype
      and not a.attnotnull and d.oid is null
  ) then
    raise exception 'Isolated Auth expires_at definition differs from upstream';
  end if;
end
$$;
