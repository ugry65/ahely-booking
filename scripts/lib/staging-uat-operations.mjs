import { randomUUID } from 'node:crypto';

export const ROOM_IDS = {
  training: '11000000-0000-0000-0000-000000000001',
  room1: '11000000-0000-0000-0000-000000000002',
  room2: '11000000-0000-0000-0000-000000000003',
  room3: '11000000-0000-0000-0000-000000000004',
  forbidden: '11000000-0000-0000-0000-000000000005',
};

export function uatSpecs() {
  return [
    { key: 'admin', email: 'uat-admin@ahely.invalid', firstName: 'UAT', lastName: 'Admin', role: 'admin', active: true, namesVisible: true, canRepeat: false },
    { key: 'userA', email: 'uat-user-a@ahely.invalid', firstName: 'UAT', lastName: 'User A', role: 'user', active: true, namesVisible: true, canRepeat: true },
    { key: 'userB', email: 'uat-user-b@ahely.invalid', firstName: 'UAT', lastName: 'User B', role: 'user', active: true, namesVisible: true, canRepeat: true },
    { key: 'hidden', email: 'uat-hidden@ahely.invalid', firstName: 'UAT', lastName: 'Rejtett', role: 'user', active: true, namesVisible: true, canRepeat: false },
    { key: 'inactive', email: 'uat-inactive@ahely.invalid', firstName: 'UAT', lastName: 'Inaktív', role: 'user', active: false, namesVisible: true, canRepeat: false },
  ];
}

function assertSeparateResetIdentity(resetEmail, specs) {
  if (specs.some((spec) => spec.email === resetEmail.toLowerCase())) {
    throw new Error('Az UAT_RESET_EMAIL nem lehet azonos szintetikus UAT-identitással.');
  }
}

export async function listAllUsers(admin) {
  const users = [];
  for (let page = 1; ; page += 1) {
    const { data, error } = await admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    users.push(...data.users);
    if (data.users.length < 1000) return users;
  }
}

export async function ensureAuthUser(admin, users, spec, password) {
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

export async function ensureResetIdentity(admin, users, resetEmail, password) {
  const normalizedEmail = resetEmail.toLowerCase();
  const existing = users.find((candidate) => candidate.email?.toLowerCase() === normalizedEmail);
  if (existing) return existing;

  const { data, error } = await admin.createUser({
    email: normalizedEmail,
    password,
    email_confirm: true,
    user_metadata: { first_name: 'UAT', last_name: 'Password Reset' },
  });
  if (error) throw error;
  users.push(data.user);
  return data.user;
}

function must(error, context) {
  if (error) throw new Error(`${context}: ${error.message}`);
}

async function signInUatAdmin(adminClient, password) {
  const { error } = await adminClient.auth.signInWithPassword({
    email: 'uat-admin@ahely.invalid',
    password,
  });
  must(error, 'Szintetikus UAT admin beléptetése');
}

async function resetSyntheticAccess(adminClient, syntheticUserIds) {
  const { data: overview, error: overviewError } = await adminClient.rpc('admin_room_access_overview');
  must(overviewError, 'UAT hozzáférési áttekintés betöltése');

  for (const membership of overview.group_members.filter((item) => syntheticUserIds.includes(item.user_id))) {
    const { error } = await adminClient.rpc('admin_set_group_member', {
      p_group_id: membership.group_id,
      p_user_id: membership.user_id,
      p_is_member: false,
      p_correlation_id: randomUUID(),
    });
    must(error, 'Korábbi UAT csoporttagság törlése');
  }

  for (const permission of overview.user_room_permissions.filter((item) => syntheticUserIds.includes(item.user_id))) {
    const { error } = await adminClient.rpc('admin_set_user_room_permission', {
      p_user_id: permission.user_id,
      p_room_id: permission.room_id,
      p_can_book: false,
      p_can_repeat: false,
      p_correlation_id: randomUUID(),
    });
    must(error, 'Korábbi UAT helyiségjog visszavonása');
  }
}

async function setSyntheticAccess(adminClient, specs, ids, permissions) {
  for (const spec of specs) {
    const { error } = await adminClient.rpc('admin_set_profile_repeat_permission', {
      p_user_id: ids[spec.key],
      p_can_repeat: spec.canRepeat,
      p_correlation_id: randomUUID(),
    });
    must(error, 'UAT ismétlődő foglalási jog beállítása');
  }

  for (const permission of permissions) {
    const { error } = await adminClient.rpc('admin_set_user_room_permission', {
      ...permission,
      p_correlation_id: randomUUID(),
    });
    must(error, 'UAT helyiségjog beállítása');
  }
}

export async function bootstrapUat(client, adminClient, resetEmail, password) {
  const specs = uatSpecs();
  assertSeparateResetIdentity(resetEmail, specs);
  const existingUsers = await listAllUsers(client.auth.admin);
  const ids = {};

  await ensureResetIdentity(client.auth.admin, existingUsers, resetEmail, password);

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

  await signInUatAdmin(adminClient, password);
  const syntheticUserIds = Object.values(ids);
  await resetSyntheticAccess(adminClient, syntheticUserIds);

  const permissions = [
    { p_user_id: ids.userA, p_room_id: ROOM_IDS.training, p_can_book: true, p_can_repeat: false },
    { p_user_id: ids.userA, p_room_id: ROOM_IDS.room1, p_can_book: true, p_can_repeat: false },
    { p_user_id: ids.userA, p_room_id: ROOM_IDS.room2, p_can_book: true, p_can_repeat: false },
    { p_user_id: ids.userB, p_room_id: ROOM_IDS.room1, p_can_book: true, p_can_repeat: false },
    { p_user_id: ids.userB, p_room_id: ROOM_IDS.room3, p_can_book: true, p_can_repeat: false },
    { p_user_id: ids.hidden, p_room_id: ROOM_IDS.room1, p_can_book: true, p_can_repeat: false },
    { p_user_id: ids.inactive, p_room_id: ROOM_IDS.room1, p_can_book: true, p_can_repeat: false },
  ];
  await setSyntheticAccess(adminClient, specs, ids, permissions);

  return { ids };
}

export async function verifyUat(client, adminClient, resetEmail, password) {
  const specs = uatSpecs();
  assertSeparateResetIdentity(resetEmail, specs);
  const expectedEmails = specs.map((spec) => spec.email);
  const users = await listAllUsers(client.auth.admin);
  for (const email of [...expectedEmails, resetEmail.toLowerCase()]) {
    if (!users.some((user) => user.email?.toLowerCase() === email)) {
      throw new Error(`Hiányzó UAT Auth user: ${email}`);
    }
  }

  const { data: profiles, error: profileError } = await client.from('profiles')
    .select('email,role,is_active,other_booker_names_visible,can_repeat_bookings')
    .in('email', expectedEmails);
  must(profileError, 'UAT profilok ellenőrzése');
  if (profiles.length !== 5) throw new Error(`5 UAT profil helyett ${profiles.length} található.`);
  const admin = profiles.find((p) => p.email === 'uat-admin@ahely.invalid');
  const inactive = profiles.find((p) => p.email === 'uat-inactive@ahely.invalid');
  const userA = profiles.find((p) => p.email === 'uat-user-a@ahely.invalid');
  if (admin?.role !== 'admin' || !admin.is_active) throw new Error('ADMIN-1 profil hibás.');
  if (inactive?.is_active !== false) throw new Error('USER-INACTIVE profilnak inaktívnak kell lennie.');
  if (userA?.other_booker_names_visible !== true) throw new Error('USER-A névláthatósági UAT beállítása hibás.');
  if (userA?.can_repeat_bookings !== true) throw new Error('USER-A ismétlődő foglalási UAT beállítása hibás.');

  const { data: rooms, error: roomError } = await client.from('rooms')
    .select('id,name,is_training_room,is_active')
    .in('id', Object.values(ROOM_IDS));
  must(roomError, 'UAT helyiségek ellenőrzése');
  if (rooms.length !== 5) throw new Error(`5 UAT helyiség helyett ${rooms.length} található.`);
  if (!rooms.some((room) => room.id === ROOM_IDS.training && room.is_training_room && room.is_active)) {
    throw new Error('A Tréningterem UAT konfigurációja hiányzik.');
  }

  const userAId = users.find((user) => user.email?.toLowerCase() === 'uat-user-a@ahely.invalid')?.id;
  await signInUatAdmin(adminClient, password);
  const { data: overview, error: overviewError } = await adminClient.rpc('admin_room_access_overview');
  must(overviewError, 'USER-A effektív helyiségjogainak ellenőrzése');

  const actualBookableRoomIds = new Set(
    overview.user_room_permissions
      .filter((permission) => permission.user_id === userAId && permission.can_book)
      .map((permission) => permission.room_id),
  );
  const activeGroupIds = new Set(overview.groups.filter((group) => group.is_active).map((group) => group.id));
  const userAGroupIds = new Set(
    overview.group_members
      .filter((membership) => membership.user_id === userAId && activeGroupIds.has(membership.group_id))
      .map((membership) => membership.group_id),
  );
  for (const permission of overview.group_room_permissions) {
    if (permission.can_book && userAGroupIds.has(permission.group_id)) actualBookableRoomIds.add(permission.room_id);
  }

  const expectedBookableRoomIds = [ROOM_IDS.training, ROOM_IDS.room1, ROOM_IDS.room2].sort();
  if (JSON.stringify([...actualBookableRoomIds].sort()) !== JSON.stringify(expectedBookableRoomIds)) {
    throw new Error('USER-A effektív foglalási jogai eltérnek a determinisztikus UAT-beállítástól.');
  }


  return true;
}
