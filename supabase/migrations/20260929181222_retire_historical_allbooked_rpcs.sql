-- Forward-only reconciliation of the historical AllBooked import lineage.
-- Keep the source migrations intact; never replay the one-time UAT SQL.
begin;

alter type public.booking_status add value if not exists 'voided';

drop function if exists public.admin_void_papp_dalma_test_import(uuid,text,uuid);
drop function if exists public.admin_rollback_empty_allbooked_profile(uuid,uuid,text);
drop function if exists public.admin_import_papp_dalma_allbooked(uuid,uuid,text,jsonb,uuid);
drop function if exists public.admin_reconcile_papp_dalma_allbooked(uuid,text[]);
drop function if exists public.admin_rollback_empty_papp_dalma_profile(uuid,uuid);

commit;
