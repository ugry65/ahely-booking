import { describe, expect, it } from 'vitest';
import { bootstrapUat, verifyUat, ROOM_IDS } from './staging-uat-operations.mjs';

function createFakeClient(resetEmail) {
  const state = {
    users: [{ id: 'reset-user', email: resetEmail.toLowerCase() }],
    profiles: [{
      id: 'reset-user',
      email: resetEmail.toLowerCase(),
      first_name: 'Existing',
      last_name: 'Reset User',
      role: 'user',
      is_active: true,
      other_booker_names_visible: false,
      can_repeat_bookings: false,
    }],
    rooms: [],
    permissions: [],
    accessGroups: [],
    groupMemberships: [],
    groupRoomPermissions: [],
    authUpdates: [],
  };
  let nextId = 1;

  const admin = {
    async listUsers() {
      return { data: { users: state.users }, error: null };
    },
    async createUser(input) {
      const user = { id: `user-${nextId++}`, email: input.email };
      state.users.push(user);
      state.profiles.push({
        id: user.id,
        email: input.email.toLowerCase(),
        role: 'user',
        is_active: true,
        other_booker_names_visible: true,
        can_repeat_bookings: false,
      });
      return { data: { user }, error: null };
    },
    async updateUserById(id, input) {
      state.authUpdates.push({ id, input });
      const user = state.users.find((item) => item.id === id);
      user.email = user.email ?? input.email;
      return { data: { user }, error: null };
    },
  };

  function from(table) {
    if (table === 'profiles') {
      return {
        update(values) {
          return {
            async eq(_column, id) {
              Object.assign(state.profiles.find((item) => item.id === id), values);
              return { error: null };
            },
          };
        },
        select() {
          return {
            async in(_column, emails) {
              return { data: state.profiles.filter((item) => emails.includes(item.email)), error: null };
            },
          };
        },
      };
    }

    if (table === 'rooms') {
      return {
        async upsert(rows) {
          state.rooms = rows.map((row) => ({ ...row }));
          return { error: null };
        },
        select() {
          return {
            async in(_column, ids) {
              return { data: state.rooms.filter((item) => ids.includes(item.id)), error: null };
            },
          };
        },
      };
    }

    throw new Error(`Unexpected table: ${table}`);
  }

  async function rpc(name, params = {}) {
    if (name === 'admin_room_access_overview') {
      return {
        data: {
          groups: state.accessGroups,
          group_members: state.groupMemberships,
          group_room_permissions: state.groupRoomPermissions,
          user_room_permissions: state.permissions,
        },
        error: null,
      };
    }

    if (name === 'admin_set_group_member') {
      if (params.p_is_member) {
        if (!state.groupMemberships.some((item) => item.user_id === params.p_user_id && item.group_id === params.p_group_id)) {
          state.groupMemberships.push({ user_id: params.p_user_id, group_id: params.p_group_id });
        }
      } else {
        state.groupMemberships = state.groupMemberships.filter(
          (item) => item.user_id !== params.p_user_id || item.group_id !== params.p_group_id,
        );
      }
      return { data: null, error: null };
    }

    if (name === 'admin_set_user_room_permission') {
      const row = {
        user_id: params.p_user_id,
        room_id: params.p_room_id,
        can_book: params.p_can_book,
        can_repeat: params.p_can_repeat,
      };
      const index = state.permissions.findIndex((item) => item.user_id === row.user_id && item.room_id === row.room_id);
      if (index === -1) state.permissions.push(row);
      else state.permissions[index] = row;
      return { data: null, error: null };
    }

    if (name === 'admin_set_profile_repeat_permission') {
      state.profiles.find((item) => item.id === params.p_user_id).can_repeat_bookings = params.p_can_repeat;
      return { data: null, error: null };
    }

    throw new Error(`Unexpected RPC: ${name}`);
  }

  const client = {
    auth: {
      admin,
      async signInWithPassword() {
        return { data: { session: { access_token: 'test-admin-token' } }, error: null };
      },
    },
    from,
    rpc,
  };
  return { client, state, resetEmail };
}

describe('staging UAT mutating and verification operations', () => {
  it('rejects a reset email that collides with a synthetic identity', async () => {
    const resetEmail = 'uat-user-a@ahely.invalid';
    const { client } = createFakeClient(resetEmail);

    await expect(bootstrapUat(client, client, resetEmail, 'very-long-test-password'))
      .rejects.toThrow(/nem lehet azonos szintetikus UAT-identitással/);
  });

  it('bootstraps five synthetic identities plus a separate reset identity', async () => {
    const resetEmail = 'uat-reset@example.test';
    const { client, state } = createFakeClient(resetEmail);

    const result = await bootstrapUat(client, client, resetEmail, 'very-long-test-password');

    expect(state.users).toHaveLength(6);
    expect(state.profiles.find((item) => item.email === 'uat-admin@ahely.invalid')).toMatchObject({ role: 'admin', is_active: true });
    expect(state.profiles.find((item) => item.email === 'uat-user-a@ahely.invalid')).toMatchObject({ role: 'user', is_active: true, other_booker_names_visible: true });
    expect(state.profiles.find((item) => item.email === 'uat-user-a@ahely.invalid')).toMatchObject({ can_repeat_bookings: true });
    expect(state.profiles.find((item) => item.email === resetEmail)).toMatchObject({
      first_name: 'Existing',
      last_name: 'Reset User',
      other_booker_names_visible: false,
    });
    expect(state.authUpdates.some((item) => item.id === 'reset-user')).toBe(false);
    expect(state.profiles.find((item) => item.email === 'uat-inactive@ahely.invalid')).toMatchObject({ is_active: false });
    expect(state.rooms).toHaveLength(5);
    expect(state.permissions.some((item) => item.user_id === result.ids.userA && item.room_id === ROOM_IDS.forbidden && item.can_book)).toBe(false);
    expect(state.permissions.some((item) => item.user_id === result.ids.userA && item.room_id === ROOM_IDS.room1 && item.can_book)).toBe(true);

    await expect(verifyUat(client, client, resetEmail, 'very-long-test-password')).resolves.toBe(true);
  });

  it('bootstrap removes stale synthetic rights but preserves the reset identity rights', async () => {
    const resetEmail = 'uat-reset@example.test';
    const { client, state } = createFakeClient(resetEmail);
    const result = await bootstrapUat(client, client, resetEmail, 'very-long-test-password');
    state.permissions.push({ user_id: result.ids.userA, room_id: ROOM_IDS.forbidden, can_book: true, can_repeat: false });
    state.groupMemberships.push({ user_id: result.ids.userA, group_id: 'stale-group' });
    state.permissions.push({ user_id: 'reset-user', room_id: ROOM_IDS.forbidden, can_book: true, can_repeat: false });
    state.groupMemberships.push({ user_id: 'reset-user', group_id: 'real-group' });

    await bootstrapUat(client, client, resetEmail, 'very-long-test-password');

    expect(state.permissions.some((item) => item.user_id === result.ids.userA && item.room_id === ROOM_IDS.forbidden && item.can_book)).toBe(false);
    expect(state.groupMemberships.some((item) => item.user_id === result.ids.userA)).toBe(false);
    expect(state.permissions.some((item) => item.user_id === 'reset-user' && item.room_id === ROOM_IDS.forbidden)).toBe(true);
    expect(state.groupMemberships.some((item) => item.user_id === 'reset-user' && item.group_id === 'real-group')).toBe(true);
  });

  it('verify fails when a group makes the forbidden control room effectively bookable for USER-A', async () => {
    const resetEmail = 'uat-reset@example.test';
    const { client, state } = createFakeClient(resetEmail);
    const result = await bootstrapUat(client, client, resetEmail, 'very-long-test-password');
    state.accessGroups.push({ id: 'unexpected-group', name: 'Unexpected', is_active: true });
    state.groupMemberships.push({ user_id: result.ids.userA, group_id: 'unexpected-group' });
    state.groupRoomPermissions.push({ group_id: 'unexpected-group', room_id: ROOM_IDS.forbidden, can_book: true });

    await expect(verifyUat(client, client, resetEmail, 'very-long-test-password')).rejects.toThrow(/effektív foglalási jogai eltérnek/);
  });
});
