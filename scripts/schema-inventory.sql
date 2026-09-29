-- Read-only, deterministic inventory of application-owned public schema objects.
-- One JSON object per line; no row data or secrets. Compare isolated rebuild to staging.
with objects(kind, object_key, definition) as (
  select 'relation', c.relname::text,
    concat_ws('|', c.relkind, c.relpersistence, c.relispartition,
      c.relrowsecurity, c.relforcerowsecurity,
      coalesce(array_to_string(c.reloptions, ','), ''),
      case when c.relkind in ('v', 'm') then pg_get_viewdef(c.oid, true) else '' end)
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
    and not exists (select 1 from pg_depend d
      where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')
  union all
  select 'column', c.relname || '.' || a.attname,
    concat_ws('|', format_type(a.atttypid, a.atttypmod), a.attnotnull,
      a.attidentity, a.attgenerated,
      coalesce(pg_get_expr(ad.adbin, ad.adrelid), ''),
      coalesce(coll.collname, ''))
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  left join pg_attrdef ad on ad.adrelid = c.oid and ad.adnum = a.attnum
  left join pg_collation coll on coll.oid = a.attcollation and coll.collname <> 'default'
  where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f')
    and not exists (select 1 from pg_depend d
      where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')
  union all
  select 'constraint', c.relname || '.' || con.conname, pg_get_constraintdef(con.oid, true)
  from pg_constraint con join pg_class c on c.oid = con.conrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
  union all
  select 'index', i.relname, pg_get_indexdef(i.oid)
  from pg_index ix join pg_class t on t.oid = ix.indrelid
  join pg_namespace n on n.oid = t.relnamespace
  join pg_class i on i.oid = ix.indexrelid
  where n.nspname = 'public'
  union all
  select 'policy', p.tablename || '.' || p.policyname,
    concat_ws('|', p.permissive, p.roles::text, p.cmd,
      coalesce(p.qual, ''), coalesce(p.with_check, ''))
  from pg_policies p where p.schemaname = 'public'
  union all
  select 'function', p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
    pg_get_functiondef(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind in ('f', 'p')
    and not exists (select 1 from pg_depend d
      where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
  union all
  select 'function_grant', p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
    concat_ws('|', pg_get_userbyid(p.proowner),
      has_function_privilege('anon', p.oid, 'EXECUTE'),
      has_function_privilege('authenticated', p.oid, 'EXECUTE'),
      has_function_privilege('service_role', p.oid, 'EXECUTE'),
      coalesce(p.proacl::text, 'DEFAULT'))
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind in ('f', 'p')
    and not exists (select 1 from pg_depend d
      where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
  union all
  select 'trigger', c.relname || '.' || t.tgname, pg_get_triggerdef(t.oid, true)
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and not t.tgisinternal
  union all
  select 'enum', typ.typname,
    (select string_agg(e.enumlabel, '|' order by e.enumsortorder)
     from pg_enum e where e.enumtypid = typ.oid)
  from pg_type typ join pg_namespace n on n.oid = typ.typnamespace
  where n.nspname = 'public' and typ.typtype = 'e'
  union all
  select 'relation_grant', c.relname,
    concat_ws('|', pg_get_userbyid(c.relowner),
      has_table_privilege('anon', c.oid, 'SELECT'),
      has_table_privilege('anon', c.oid, 'INSERT'),
      has_table_privilege('anon', c.oid, 'UPDATE'),
      has_table_privilege('anon', c.oid, 'DELETE'),
      has_table_privilege('authenticated', c.oid, 'SELECT'),
      has_table_privilege('authenticated', c.oid, 'INSERT'),
      has_table_privilege('authenticated', c.oid, 'UPDATE'),
      has_table_privilege('authenticated', c.oid, 'DELETE'),
      has_table_privilege('service_role', c.oid, 'SELECT'),
      has_table_privilege('service_role', c.oid, 'INSERT'),
      has_table_privilege('service_role', c.oid, 'UPDATE'),
      has_table_privilege('service_role', c.oid, 'DELETE'),
      coalesce(c.relacl::text, 'DEFAULT'))
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f')
    and not exists (select 1 from pg_depend d
      where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e')
)
select jsonb_build_object('kind', kind, 'key', object_key,
  'md5', md5(definition), 'definition', definition)
from objects
order by kind, object_key;
