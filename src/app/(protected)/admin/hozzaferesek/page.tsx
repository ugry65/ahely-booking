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
function flags(canBook: boolean, canRepeat: boolean) { return `${canBook ? "Foglalhat" : "Nem foglalhat"}${canRepeat ? " · Ismételhet" : ""}`; }

export default async function RoomAccessAdminPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams; const supabase = await createClient();
  const response = await supabase.rpc("admin_room_access_overview");
  const overview = response.error ? empty : response.data as unknown as Overview;
  const roomName = new Map(overview.rooms.map((item) => [item.id, item.name]));
  const userName = new Map(overview.users.map((item) => [item.id, item.name]));
  const groupName = new Map(overview.groups.map((item) => [item.id, item.name]));

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
      <section className="card wide-card stack"><h2>Közvetlen userjog</h2><form action={saveUserRoomPermission} className="stack"><label>Felhasználó<select name="userId" required>{overview.users.map((user) => <option key={user.id} value={user.id}>{user.name}{user.is_active ? "" : " · Inaktív"}</option>)}</select></label><label>Helyiség<select name="roomId" required>{overview.rooms.map((room) => <option key={room.id} value={room.id}>{room.name}{room.is_active ? "" : " · Inaktív"}</option>)}</select></label><input type="hidden" name="canBook" value="false" /><input type="hidden" name="canRepeat" value="false" /><label className="inline-check"><input type="checkbox" name="canBook" value="true" /> Foglalhat</label><label className="inline-check"><input type="checkbox" name="canRepeat" value="true" /> Ismételhet</label><button>Jog mentése</button></form><ul className="admin-summary-list">{overview.user_room_permissions.map((item) => <li key={`${item.user_id}:${item.room_id}`}><strong>{userName.get(item.user_id)}</strong> — {roomName.get(item.room_id)} · {flags(item.can_book, item.can_repeat)}</li>)}</ul></section>
      <section className="card wide-card stack"><h2>Csoporttagság</h2><form action={saveGroupMember} className="stack"><label>Csoport<select name="groupId" required>{overview.groups.map((group) => <option key={group.id} value={group.id}>{group.name}{group.is_active ? "" : " · Inaktív"}</option>)}</select></label><label>Felhasználó<select name="userId" required>{overview.users.map((user) => <option key={user.id} value={user.id}>{user.name}{user.is_active ? "" : " · Inaktív"}</option>)}</select></label><input type="hidden" name="isMember" value="false" /><label className="inline-check"><input type="checkbox" name="isMember" value="true" defaultChecked /> Tag</label><button>Tagság mentése</button></form><ul className="admin-summary-list">{overview.group_members.map((item) => <li key={`${item.group_id}:${item.user_id}`}><strong>{groupName.get(item.group_id)}</strong> — {userName.get(item.user_id)}</li>)}</ul></section>
      <section className="card wide-card stack"><h2>Csoport helyiségjoga</h2><form action={saveGroupRoomPermission} className="stack"><label>Csoport<select name="groupId" required>{overview.groups.map((group) => <option key={group.id} value={group.id}>{group.name}{group.is_active ? "" : " · Inaktív"}</option>)}</select></label><label>Helyiség<select name="roomId" required>{overview.rooms.map((room) => <option key={room.id} value={room.id}>{room.name}{room.is_active ? "" : " · Inaktív"}</option>)}</select></label><input type="hidden" name="canBook" value="false" /><input type="hidden" name="canRepeat" value="false" /><label className="inline-check"><input type="checkbox" name="canBook" value="true" /> Foglalhat</label><label className="inline-check"><input type="checkbox" name="canRepeat" value="true" /> Ismételhet</label><button>Jog mentése</button></form><ul className="admin-summary-list">{overview.group_room_permissions.map((item) => <li key={`${item.group_id}:${item.room_id}`}><strong>{groupName.get(item.group_id)}</strong> — {roomName.get(item.room_id)} · {flags(item.can_book, item.can_repeat)}</li>)}</ul></section>
    </div>
  </section>;
}
