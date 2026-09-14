begin;

select plan(5);

select ok(
  not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='admin_import_papp_dalma_allbooked' and p.pronargs=5),
  'A történelmi Papp Dalma import RPC már nem létezik'
);
select ok(
  not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='admin_reconcile_papp_dalma_allbooked' and p.pronargs=2),
  'A történelmi Papp Dalma reconciliation RPC már nem létezik'
);
select ok(
  not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='admin_rollback_empty_papp_dalma_profile' and p.pronargs=2),
  'A történelmi Papp Dalma rollback RPC már nem létezik'
);
select ok(
  exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='admin_import_allbooked_customer' and p.pronargs=9),
  'Az általános ügyfélimport az egyetlen támogatott import RPC'
);
select ok(
  has_function_privilege('service_role', 'public.admin_import_allbooked_customer(uuid,uuid,text,text,text,text,text[],jsonb,uuid)', 'EXECUTE'),
  'Az általános ügyfélimport továbbra is service_role számára hívható'
);

select * from finish();
rollback;
