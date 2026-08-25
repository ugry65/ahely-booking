begin;

select plan(3);

select ok(
  not has_function_privilege('authenticated', 'public.claim_booking_title_request(uuid,text,text)', 'EXECUTE'),
  'Az authenticated szerepkör nem hívhatja közvetlenül a booking title belső helpert'
);

select is(
  (select proconfig from pg_proc where oid = 'public.prevent_physical_delete()'::regprocedure) @> array['search_path=""'],
  true,
  'A fizikai törlést tiltó trigger helper fix üres search_pathot használ'
);

select is(
  (select proconfig from pg_proc where oid = 'public.prevent_audit_mutation()'::regprocedure) @> array['search_path=""'],
  true,
  'Az audit immutabilitási trigger helper fix üres search_pathot használ'
);

select * from finish();
rollback;
