begin;

select plan(5);

select ok(
  not has_function('public', 'admin_import_papp_dalma_allbooked', array['uuid','uuid','text','jsonb','uuid']),
  'A történelmi Papp Dalma import RPC már nem létezik'
);
select ok(
  not has_function('public', 'admin_reconcile_papp_dalma_allbooked', array['uuid','text[]']),
  'A történelmi Papp Dalma reconciliation RPC már nem létezik'
);
select ok(
  not has_function('public', 'admin_rollback_empty_papp_dalma_profile', array['uuid','uuid']),
  'A történelmi Papp Dalma rollback RPC már nem létezik'
);
select ok(
  has_function('public', 'admin_import_allbooked_customer', array['uuid','uuid','text','text','text','text','text[]','jsonb','uuid']),
  'Az általános ügyfélimport az egyetlen támogatott import RPC'
);
select ok(
  has_function_privilege('service_role', 'public.admin_import_allbooked_customer(uuid,uuid,text,text,text,text,text[],jsonb,uuid)', 'EXECUTE'),
  'Az általános ügyfélimport továbbra is service_role számára hívható'
);

select * from finish();
rollback;
