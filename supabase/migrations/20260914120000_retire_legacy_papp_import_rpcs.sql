begin;

-- The generic customer importer replaced the staging-only Papp Dalma writer.
-- Remove the historical RPCs instead of leaving service_role-callable write
-- paths in any environment, including production.
drop function if exists public.admin_import_papp_dalma_allbooked(uuid, uuid, text, jsonb, uuid);
drop function if exists public.admin_reconcile_papp_dalma_allbooked(uuid, text[]);
drop function if exists public.admin_rollback_empty_papp_dalma_profile(uuid, uuid);

commit;
