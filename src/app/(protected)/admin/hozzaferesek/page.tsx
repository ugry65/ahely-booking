import Link from "next/link";
import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { saveGroup, saveGroupMember, saveGroupRoomPermission, saveRoom, saveUserRoomPermission } from "./actions";

type Room = { id: string; name: string; display_order: number; is_training_room: boolean; is_active: boolean };
type User = { id: string; name: string; email: string; is_active: boolean };
type Group = { id: string; name: string; is_active: boolean };
type UserPermission = { user_id: string; room_id: string; can_book: boolean; can_repeat: boolean };
type GroupMember = { group_id: string; user_id: string };
type GroupPermission = { group_id: string; room_id: string; can_book: boolean; can_repeat: boolean };
type Overview = { rooms: Room[]; users: User[]; groups: Group[]; user_room_permissions: UserPermission[]; group_members: GroupMember[]; group_room_permissions: GroupPermission[] };

const empty: Overview = { rooms: [], users: [], groups: [], user_room_permissions: [], group_members: [], group_room_permissions: [] };
function pairKey(firstId: string, secondId: string) { return `${firstId}:${secondId}`; }

export default async function RoomAccessAdminPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams; const supabase = await createClient();
  const response = await supabase.rpc("admin_room_access_overview");
  const overview = response.error ? empty : response.data as unknown as Overview;
  const userPermissions = new Map(overview.user_room_permissions.map((item) => [pairKey(item.user_id, item.room_id), item]));
  const groupMembers = new Set(overview.group_members.map((item) => pairKey(item.group_id, item.user_id)));
  const groupPermissions = new Map(overview.group_room_permissions.map((item) => [pairKey(item.group_id, item.room_id), item]));

  return <section className="stack">
    <header className="page-heading"><div><p className="eyebrow">Adminisztráció</p><h1>Helyiségek és hozzáférések</h1><p className="muted">Minden változtatás auditált adatbázis-műveleten keresztül történik.</p></div><Link className="button secondary" href="/admin/felhasznalok">Felhasználók</Link></header>
    {params.hiba ? <p className="message error" role="alert">{params.hiba}</p> : null}
    {params.uzenet ? <p className="message success" role="status">{params.uzenet}</p> : null}
    {response.error ? <p className="message error" role="alert">Az adminisztrációs adatok betöltése nem sikerült.</p> : null}

    <section className="card wide-card stack"><h2>Helyiségek</h2><form action={saveRoom} className="admin-editor-row"><input type="hidden" name="isActive" value="false" /><label>Név<input name="name" required maxLength={120} /></label><label>Sorrend<input name="displayOrder" type="number" min="0" required /></label><label className="inline-check"><input type="hidden" name="isTrainingRoom" value="false" /><input type="checkbox" name="isTrainingRoom" value="true" /> Tréningterem</label><label className="inline-check"><input type="checkbox" name="isActive" value="true" defaultChecked /> Aktív</label><button>Új helyiség</button></form>
      <div className="admin-record-list">{overview.rooms.map((room) => <form action={saveRoom} className="admin-editor-row" key={room.id}><input type="hidden" name="roomId" value={room.id} /><input type="hidden" name="isTrainingRoom" value="false" /><input type="hidden" name="isActive" value="false" /><label>Név<input name="name" defaultValue={room.name} required maxLength={120} /></label><label>Sorrend<input name="displayOrder" type="number" min="0" defaultValue={room.display_order} required /></label><label className="inline-check"><input type="checkbox" name="isTrainingRoom" value="true" defaultChecked={room.is_training_room} /> Tréningterem</label><label className="inline-check"><input type="checkbox" name="isActive" value="true" defaultChecked={room.is_active} /> Aktív</label><button>Mentés</button></form>)}</div>
    </section>

    <section className="card wide-card stack"><h2>Hozzáférési csoportok</h2><form action={saveGroup} className="admin-editor-row compact"><input type="hidden" name="isActive" value="false" /><label>Név<input name="name" required maxLength={120} /></label><label className="inline-check"><input type="checkbox" name="isActive" value="true" defaultChecked /> Aktív</label><button>Új csoport</button></form>
      <div className="admin-record-list">{overview.groups.map((group) => <form action={saveGroup} className="admin-editor-row compact" key={group.id}><input type="hidden" name="groupId" value={group.id} /><input type="hidden" name="isActive" value="false" /><label>Név<input name="name" defaultValue={group.name} required maxLength={120} /></label><label className="inline-check"><input type="checkbox" name="isActive" value="true" defaultChecked={group.is_active} /> Aktív</label><button>Mentés</button></form>)}</div>
    </section>

    <div className="admin-access-grid">
      <section className="card wide-card stack"><h2>Közvetlen userjog</h2><p className="muted">Nyisd le a felhasználót; minden helyiség aktuális joga előre be van állítva.</p><div className="admin-permission-list">{overview.users.map((user) => <details key={user.id}><summary>{user.name} · {user.email}{user.is_active ? "" : " · Inaktív"}</summary><div className="admin-record-list">{overview.rooms.map((room) => { const permission = userPermissions.get(pairKey(user.id, room.id)); return <form action={saveUserRoomPermission} className="permission-matrix-row" key={room.id}><input type="hidden" name="userId" value={user.id} /><input type="hidden" name="roomId" value={room.id} /><input type="hidden" name="canBook" value="false" /><input type="hidden" name="canRepeat" value="false" /><strong>{room.name}{room.is_active ? "" : " · Inaktív"}</strong><label className="inline-check"><input type="checkbox" name="canBook" value="true" defaultChecked={permission?.can_book ?? false} /> Foglalhat</label><label className="inline-check"><input type="checkbox" name="canRepeat" value="true" defaultChecked={permission?.can_repeat ?? false} /> Ismételhet</label><button>Mentés</button></form>; })}</div></details>)}</div></section>
      <section className="card wide-card stack"><h2>Csoporttagság</h2><p className="muted">Minden user jelenlegi tagsági állapota előre be van állítva.</p><div className="admin-permission-list">{overview.groups.map((group) => <details key={group.id}><summary>{group.name}{group.is_active ? "" : " · Inaktív"}</summary><div className="admin-record-list">{overview.users.map((user) => <form action={saveGroupMember} className="permission-matrix-row member-row" key={user.id}><input type="hidden" name="groupId" value={group.id} /><input type="hidden" name="userId" value={user.id} /><input type="hidden" name="isMember" value="false" /><span><strong>{user.name}</strong><small>{user.email}{user.is_active ? "" : " · Inaktív"}</small></span><label className="inline-check"><input type="checkbox" name="isMember" value="true" defaultChecked={groupMembers.has(pairKey(group.id, user.id))} /> Tag</label><button>Mentés</button></form>)}</div></details>)}</div></section>
      <section className="card wide-card stack"><h2>Csoport helyiségjoga</h2><p className="muted">Nyisd le a csoportot; minden helyiség aktuális joga előre be van állítva.</p><div className="admin-permission-list">{overview.groups.map((group) => <details key={group.id}><summary>{group.name}{group.is_active ? "" : " · Inaktív"}</summary><div className="admin-record-list">{overview.rooms.map((room) => { const permission = groupPermissions.get(pairKey(group.id, room.id)); return <form action={saveGroupRoomPermission} className="permission-matrix-row" key={room.id}><input type="hidden" name="groupId" value={group.id} /><input type="hidden" name="roomId" value={room.id} /><input type="hidden" name="canBook" value="false" /><input type="hidden" name="canRepeat" value="false" /><strong>{room.name}{room.is_active ? "" : " · Inaktív"}</strong><label className="inline-check"><input type="checkbox" name="canBook" value="true" defaultChecked={permission?.can_book ?? false} /> Foglalhat</label><label className="inline-check"><input type="checkbox" name="canRepeat" value="true" defaultChecked={permission?.can_repeat ?? false} /> Ismételhet</label><button>Mentés</button></form>; })}</div></details>)}</div></section>
    </div>
  </section>;
}
