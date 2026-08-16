begin;

select plan(14);

insert into auth.users (id, email, raw_user_meta_data) values
  (
    '00000000-0000-0000-0000-000000000011',
    'admin-rls@example.invalid',
    '{"first_name":"RLS","last_name":"Admin","role":"admin"}'
  ),
  (
    '00000000-0000-0000-0000-000000000012',
    'user-rls@example.invalid',
    '{"first_name":"RLS","last_name":"User"}'
  ),
  (
    '00000000-0000-0000-0000-000000000013',
    'inactive-rls@example.invalid',
    '{"first_name":"RLS","last_name":"Inactive"}'
  );

select is(
  (select role::text from public.profiles where id = '00000000-0000-0000-0000-000000000011'),
  'user',
  'A kliensmetadata nem emelheti adminná az új usert'
);

update public.profiles
set role = 'admin'
where id = '00000000-0000-0000-0000-000000000011';

update public.profiles
set is_active = false
where id = '00000000-0000-0000-0000-000000000013';

set local role anon;
select throws_ok(
  $$select id from public.profiles$$,
  '42501',
  null,
  'Anonim kliens nem olvashat profilt'
);
select throws_ok(
  $$select id from public.rooms$$,
  '42501',
  null,
  'Anonim kliens nem olvashat helyiséget'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000012', true);

select ok(public.is_active_user(), 'Az aktív normál user aktívnak minősül');
select is((select count(*) from public.profiles), 1::bigint, 'Normál user csak a saját profilját látja');
select is(
  (select count(*) from public.profiles where id = '00000000-0000-0000-0000-000000000011'),
  0::bigint,
  'Normál user más profilját közvetlen API-val sem látja'
);
select throws_ok(
  $$select admin_note from public.profiles$$,
  '42501',
  null,
  'Normál user az admin_note oszlopot sem kérheti le'
);
select is((select count(*) from public.rooms), 11::bigint, 'Aktív user olvashatja az aktív törzsadat-RLS mögötti helyiségeket');
select throws_ok(
  $$update public.profiles set phone = '+3610000000' where id = auth.uid()$$,
  '42501',
  null,
  'A közvetlen profilírás deny-by-default'
);
select throws_ok(
  $$select * from public.monthly_settlements$$,
  '42501',
  null,
  'Normál user pénzügyi táblát közvetlenül nem olvashat'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000013', true);
select is((select count(*) from public.profiles), 0::bigint, 'Inaktív user a saját profilját sem olvashatja');
select is((select count(*) from public.rooms), 0::bigint, 'Inaktív user törzsadatot sem olvashat');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000011', true);
select ok(public.is_admin(), 'Az adminszerepet a profiles tábla igazolja');
select is((select count(*) from public.profiles), 3::bigint, 'Aktív admin minden profilt láthat a biztonságos oszlopokon');

select * from finish();
rollback;
