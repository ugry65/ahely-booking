begin;

select plan(16);

select ok(has_table_privilege('service_role', 'public.profiles', 'SELECT'), 'service_role olvashatja a profiles táblát');
select ok(has_table_privilege('service_role', 'public.profiles', 'UPDATE'), 'service_role frissítheti a profiles táblát');
select ok(not has_table_privilege('service_role', 'public.profiles', 'INSERT'), 'service_role nem szúrhat be közvetlenül profiles rekordot');
select ok(not has_table_privilege('service_role', 'public.profiles', 'DELETE'), 'service_role nem törölhet profiles rekordot');

select ok(has_table_privilege('service_role', 'public.rooms', 'SELECT'), 'service_role olvashatja a rooms táblát');
select ok(has_table_privilege('service_role', 'public.rooms', 'INSERT'), 'service_role létrehozhat UAT helyiséget');
select ok(has_table_privilege('service_role', 'public.rooms', 'UPDATE'), 'service_role frissíthet UAT helyiséget');
select ok(not has_table_privilege('service_role', 'public.rooms', 'DELETE'), 'service_role nem törölhet helyiséget');

select ok(has_table_privilege('service_role', 'public.user_room_permissions', 'SELECT'), 'service_role olvashatja a közvetlen helyiségjogokat');
select ok(has_table_privilege('service_role', 'public.user_room_permissions', 'INSERT'), 'service_role létrehozhat UAT helyiségjogot');
select ok(has_table_privilege('service_role', 'public.user_room_permissions', 'UPDATE'), 'service_role frissíthet UAT helyiségjogot');
select ok(not has_table_privilege('service_role', 'public.user_room_permissions', 'DELETE'), 'service_role nem törölhet helyiségjogot');


select ok(not has_table_privilege('service_role', 'public.bookings', 'INSERT'), 'service_role nem kerülheti meg közvetlen INSERT-tel a foglalási RPC-t');
select ok(not has_table_privilege('service_role', 'public.payments', 'INSERT'), 'service_role nem írhat közvetlenül befizetést');
select ok(not has_table_privilege('service_role', 'public.audit_logs', 'INSERT'), 'service_role nem írhat közvetlenül auditrekordot');
select ok(not has_table_privilege('authenticated', 'public.profiles', 'UPDATE'), 'authenticated user továbbra sem frissítheti közvetlenül a profiles táblát');

select * from finish();
rollback;
