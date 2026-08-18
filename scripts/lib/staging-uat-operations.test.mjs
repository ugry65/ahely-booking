import { describe, expect, it } from 'vitest';
import { bootstrapUat, verifyUat, ROOM_IDS } from './staging-uat-operations.mjs';

function createFakeClient(resetEmail) {
  const state = {
    users: [],
    profiles: [],
    rooms: [],
    permissions: [],
    exceptions: [],
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
      });
      return { data: { user }, error: null };
    },
    async updateUserById(id, input) {
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

    if (table === 'user_room_permissions') {
      return {
        async upsert(rows) {
          state.permissions = rows.map((row) => ({ ...row }));
          return { error: null };
        },
        select() {
          const filters = {};
          const chain = {
            eq(column, value) {
              filters[column] = value;
              return chain;
            },
            async maybeSingle() {
              const data = state.permissions.find((item) =>
                Object.entries(filters).every(([key, value]) => item[key] === value),
              ) ?? null;
              return { data, error: null };
            },
          };
          return chain;
        },
      };
    }

    if (table === 'calendar_exceptions') {
      return {
        async upsert(row) {
          state.exceptions = [row];
          return { error: null };
        },
        select() {
          const filters = {};
          const chain = {
            eq(column, value) {
              filters[column] = value;
              return chain;
            },
            async limit() {
              const data = state.exceptions.filter((item) =>
                Object.entries(filters).every(([key, value]) => item[key] === value),
              );
              return { data, error: null };
            },
          };
          return chain;
        },
      };
    }

    throw new Error(`Unexpected table: ${table}`);
  }

  return { client: { auth: { admin }, from }, state, resetEmail };
}

describe('staging UAT mutating and verification operations', () => {
  it('bootstraps the five identities, permissions and closed exception idempotently enough for verify', async () => {
    const resetEmail = 'uat-reset@example.test';
    const { client, state } = createFakeClient(resetEmail);

    const result = await bootstrapUat(client, resetEmail, 'very-long-test-password', new Date('2026-08-18T12:00:00Z'));

    expect(state.users).toHaveLength(5);
    expect(state.profiles.find((item) => item.email === 'uat-admin@ahely.invalid')).toMatchObject({ role: 'admin', is_active: true });
    expect(state.profiles.find((item) => item.email === resetEmail)).toMatchObject({ role: 'user', is_active: true, other_booker_names_visible: false });
    expect(state.profiles.find((item) => item.email === 'uat-inactive@ahely.invalid')).toMatchObject({ is_active: false });
    expect(state.rooms).toHaveLength(5);
    expect(state.permissions.some((item) => item.user_id === result.ids.userA && item.room_id === ROOM_IDS.forbidden && item.can_book)).toBe(false);
    expect(state.permissions.some((item) => item.user_id === result.ids.userA && item.room_id === ROOM_IDS.room1 && item.can_repeat)).toBe(true);
    expect(state.exceptions).toEqual([expect.objectContaining({ is_closed: true, reason: 'UAT zárt kivételdátum', created_by: result.ids.admin })]);

    await expect(verifyUat(client, resetEmail)).resolves.toBe(true);
  });

  it('verify fails when the forbidden control room becomes bookable for USER-A', async () => {
    const resetEmail = 'uat-reset@example.test';
    const { client, state } = createFakeClient(resetEmail);
    const result = await bootstrapUat(client, resetEmail, 'very-long-test-password');
    state.permissions.push({ user_id: result.ids.userA, room_id: ROOM_IDS.forbidden, can_book: true, can_repeat: false });

    await expect(verifyUat(client, resetEmail)).rejects.toThrow(/nem kaphat foglalási jogot/);
  });
});
