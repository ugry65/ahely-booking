begin;

-- Supabase exposes the public schema through PostgREST. Keep extension-owned
-- objects out of that API schema while preserving the GiST operator classes
-- used by bookings_no_room_overlap.
create schema if not exists extensions;

do $$
declare
  v_schema text;
  v_relocatable boolean;
begin
  select namespace.nspname, extension.extrelocatable
    into v_schema, v_relocatable
  from pg_extension extension
  join pg_namespace namespace on namespace.oid = extension.extnamespace
  where extension.extname = 'btree_gist';

  if v_schema is null then
    create extension btree_gist with schema extensions;
  elsif v_schema = 'public' then
    if not v_relocatable then
      raise exception 'btree_gist is in public but is not relocatable';
    end if;
    alter extension btree_gist set schema extensions;
  elsif v_schema <> 'extensions' then
    raise exception 'btree_gist is installed in unexpected schema: %', v_schema;
  end if;
end
$$;

commit;
