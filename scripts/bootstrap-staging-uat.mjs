import { createClient } from '@supabase/supabase-js';
import { assertStagingUrl, budapestDatePlusDays } from './lib/staging-uat-bootstrap.mjs';

const ROOM_IDS = {
  training: '11000000-0000-0000-0000-000000000001',
  room1: '11000000-0000-0000-0000-000000000002',
  room2: '11000000-0000-0000-0000-000000000003',
  room3: '11000000-0000-0000-0000-000000000004',
  forbidden: '11000000-0000-0000-0000-000000000005',
};

function requiredEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Hiányzó környezeti változó: ${name}`);
  return value;
}

async function listAllUsers(admin) {
  const users = [];
  for (let page = 1; ; page += 1) {
    const { data, error } = await admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    users.push(...data.users);
    if (data.users.length < 1000) return users;
  }
}

async function ensureAuthUser(admin, users, spec, password) {
  let user = users.find((candidate) => candidate.email?.toLowerCase() === spec.email.toLowerCase());
  if (!user) {
    const { data, error } = await admin.createUser({
      email: spec.email,
      password,
      email_confirm: true,
      user_metadata: { first_name: spec.firstName, last_name: spec.lastName },
    });
    if (error) throw error;
    user = data.user;
    users.push(user);
  } else {
    const { data, error } = await admin.updateUserById(user.id, {
      password,
      user_metadata: { first_name: spec.firstName, last_name: spec.lastName },
    });
    if (error) throw error;
    user = data.user;
  }
  return user;
}

function must(error, context) {
  if (error) throw new Error(`${context}: ${error.message}`);
}

async function bootstrap(client, resetEmail, password) {
  const specs = [
    { key: 'admin', email: 'uat-admin@ahely.invalid', firstName: 'UAT', lastName: 'Admin', role: 'admin', active: true, namesVisible: true },
    { key: 'userA', email: resetEmail, firstName: 'UAT', lastName: 'User A', role: 'user', active: true, namesVisible: false },
    { key: 'userB', email: 'uat-user-b@ahely.invalid', firstName: 'UAT', lastName: 'User B', role: 'user', active: true, namesVisible: true },
    { key: 'hidden', email: 'uat-hidden@ahely.invalid', firstName: 'UAT', lastName: 'Rejtett', role: 'user', active: true, namesVisible: true },
    { key: 'inactive', email: 'uat-inactive@ahely.invalid', firstName: 'UAT', lastName: 'Inaktív', role: 'user', active: false, namesVisible: true },
  ];

  const existingUsers = await listAllUsers(client.auth.admin);
  const ids = {};
  for (const spec of specs) {
    const user = await ensureAuthUser(client.auth.admin, existingUsers, spec, password);
    ids[spec.key] = user.id;
    const { error } = await client.from('profiles').update({
      first_name: spec.firstName,
      last_name: spec.lastName,
      role: spec.role,
      is_active: spec.active,
      other_booker_names_visible: spec.namesVisible,
    }).eq('id', user.id);
    must(error, `Profil beállítása: ${spec.key}`);
  }

  const rooms = [
    { id: ROOM_IDS.training, name: 'Tréningterem', display_order: 1, is_training_room: true, is_active: true },
    { id: ROOM_IDS.room1, name: '1.Szoba-családi', display_order: 2, is_training_room: false, is_active: true },
    { id: ROOM_IDS.room2, name: '2.Szoba', display_order: 3, is_training_room: false, is_active: true },
    { id: ROOM_IDS.room3, name: '3.Szoba', display_order: 4, is_training_room: false, is_active: true },
    { id: ROOM_IDS.forbidden, name: '4.Szoba', display_order: 5, is_training_room: false, is_active: true },
  ];
  const { error: roomError } = await client.from('rooms').upsert(rooms, { onConflict: 'id' });
  must(roomError, 'UAT helyiségek létrehozása');

  const permissions = [
    { user_id: ids.userA, room_id: ROOM_IDS.training, can_book: true, can_repeat: false },
    { user_id: ids.userA, room_id: ROOM_IDS.room1, can_book: true, can_repeat: true },
    { user_id: ids.userA, room_id: ROOM_IDS.room2, can_book: true, can_repeat: false },
    { user_id: ids.userB, room_id: ROOM_IDS.room1, can_book: true, can_repeat: false },
    { user_id: ids.userB, room_id: ROOM_IDS.room3, can_book: true, can_repeat: true },
    { user_id: ids.hidden, room_id: ROOM_IDS.room1, can_book: true, can_repeat: false },
    { user_id: ids.inactive, room_id: ROOM_IDS.room1, can_book: true, can_repeat: false },
  ];
  const { error: permissionError } = await client.from('user_room_permissions').upsert(permissions, { onConflict: 'user_id,room_id' });
  must(permissionError, 'UAT helyiségjogok létrehozása');

  const exceptionDate = budapestDatePlusDays(20);
  const { error: exceptionError } = await client.from('calendar_exceptions').upsert({
    service_date: exceptionDate,
    opens_at: null,
    closes_at: null,
    is_closed: true,
    reason: 'UAT zárt kivételdátum',
    created_by: ids.admin,
  }, { onConflict: 'service_date' });
  must(exceptionError, 'UAT kivételdátum létrehozása');

  console.log(`UAT bootstrap kész. Kivételdátum: ${exceptionDate}.`);
}

async function verify(client, resetEmail) {
  const expectedEmails = [
    'uat-admin@ahely.invalid', resetEmail.toLowerCase(), 'uat-user-b@ahely.invalid',
    'uat-hidden@ahely.invalid', 'uat-inactive@ahely.invalid',
  ];
  const users = await listAllUsers(client.auth.admin);
  for (const email of expectedEmails) {
    if (!users.some((user) => user.email?.toLowerCase() === email)) {
      throw new Error(`Hiányzó UAT Auth user: ${email}`);
    }
  }

  const { data: profiles, error: profileError } = await client.from('profiles')
    .select('email,role,is_active,other_booker_names_visible')
    .in('email', expectedEmails);
  must(profileError, 'UAT profilok ellenőrzése');
  if (profiles.length !== 5) throw new Error(`5 UAT profil helyett ${profiles.length} található.`);
  const admin = profiles.find((p) => p.email === 'uat-admin@ahely.invalid');
  const inactive = profiles.find((p) => p.email === 'uat-inactive@ahely.invalid');
  const userA = profiles.find((p) => p.email === resetEmail.toLowerCase());
  if (admin?.role !== 'admin' || !admin.is_active) throw new Error('ADMIN-1 profil hibás.');
  if (inactive?.is_active !== false) throw new Error('USER-INACTIVE profilnak inaktívnak kell lennie.');
  if (userA?.other_booker_names_visible !== false) throw new Error('USER-A névláthatósági UAT beállítása hibás.');

  const { data: rooms, error: roomError } = await client.from('rooms')
    .select('id,name,is_training_room,is_active')
    .in('id', Object.values(ROOM_IDS));
  must(roomError, 'UAT helyiségek ellenőrzése');
  if (rooms.length !== 5) throw new Error(`5 UAT helyiség helyett ${rooms.length} található.`);
  if (!rooms.some((room) => room.id === ROOM_IDS.training && room.is_training_room && room.is_active)) {
    throw new Error('A Tréningterem UAT konfigurációja hiányzik.');
  }

  const userAId = users.find((u) => u.email?.toLowerCase() === resetEmail.toLowerCase())?.id;
  const { data: forbiddenPermission, error: forbiddenError } = await client.from('user_room_permissions')
    .select('can_book')
    .eq('user_id', userAId)
    .eq('room_id', ROOM_IDS.forbidden)
    .maybeSingle();
  must(forbiddenError, 'Tiltott helyiségjog ellenőrzése');
  if (forbiddenPermission?.can_book) throw new Error('USER-A nem kaphat foglalási jogot a tiltott UAT helyiségre.');

  const { data: exceptions, error: exceptionError } = await client.from('calendar_exceptions')
    .select('service_date,is_closed,reason')
    .eq('reason', 'UAT zárt kivételdátum')
    .eq('is_closed', true)
    .limit(1);
  must(exceptionError, 'UAT kivételdátum ellenőrzése');
  if (!exceptions.length) throw new Error('Hiányzik az UAT zárt kivételdátum.');

  console.log('UAT staging konfiguráció ellenőrzése sikeres.');
}

const mode = process.argv[2] ?? 'verify';
if (!['bootstrap', 'verify'].includes(mode)) throw new Error('Használat: node scripts/bootstrap-staging-uat.mjs [bootstrap|verify]');

const url = assertStagingUrl(requiredEnv('NEXT_PUBLIC_SUPABASE_URL'));
const serviceRoleKey = requiredEnv('SUPABASE_STAGING_SERVICE_ROLE_KEY');
const resetEmail = requiredEnv('UAT_RESET_EMAIL').toLowerCase();
const password = requiredEnv('UAT_SHARED_PASSWORD');
if (password.length < 12) throw new Error('Az UAT_SHARED_PASSWORD legalább 12 karakter legyen.');

const client = createClient(url, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
});

if (mode === 'bootstrap') await bootstrap(client, resetEmail, password);
await verify(client, resetEmail);
