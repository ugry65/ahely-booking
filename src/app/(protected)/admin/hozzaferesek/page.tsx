import Link from "next/link";
import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { saveRoom, saveUserRoomPermission } from "./actions";

type Room = { id: string; name: string; display_order: number; is_training_room: boolean; is_active: boolean };
type User = { id: string; name: string; email: string; is_active: boolean };
type UserPermission = { user_id: string; room_id: string; can_book: boolean; can_repeat: boolean };
type Overview = { rooms: Room[]; users: User[]; user_room_permissions: UserPermission[] };

const empty: Overview = { rooms: [], users: [], user_room_permissions: [] };
function pairKey(firstId: string, secondId: string) { return `${firstId}:${secondId}`; }

export default async function RoomAccessAdminPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams; const supabase = await createClient();
  const response = await supabase.rpc("admin_room_access_overview");
  const raw = response.error ? null : response.data as unknown as { rooms?: Room[]; users?: User[]; user_room_permissions?: UserPermission[] };
  const overview: Overview = raw ? { rooms: raw.rooms ?? [], users: raw.users ?? [], user_room_permissions: raw.user_room_permissions ?? [] } : empty;
  const userPermissions = new Map(overview.user_room_permissions.map((item) => [pairKey(item.user_id, item.room_id), item]));

  return <section className="stack">
    <header className="page-heading"><div><p className="eyebrow">Adminisztráció</p><h1>Közvetlen user-jogok</h1><p className="muted">Átmeneti kompatibilitási felület az egyedi user–helyiség kivételekhez. Az ismétlődő foglalási jog már user-szinten, a Felhasználók oldalon kezelendő.</p></div><Link className="button secondary" href="/admin/felhasznalok">Felhasználók</Link></header>
    {params.hiba ? <p className="message error" role="alert">{params.hiba}</p> : null}
    {params.uzenet ? <p className="message success" role="status">{params.uzenet}</p> : null}
    {response.error ? <p className="message error" role="alert">Az adminisztrációs adatok betöltése nem sikerült.</p> : null}

    <section className="card wide-card stack"><h2>Helyiségek</h2><p className="muted">Ez a blokk kompatibilitási okból marad meg ezen az oldalon is. A helyiségek elsődleges adminfelülete a Helyiségek menü.</p>
      <form action={saveRoom} className="admin-editor-row"><input type="hidden" name="isActive" value="false" /><label>Név<input name="name" required maxLength={120} /></label><label>Sorrend<input name="displayOrder" type="number" min="0" required /></label><label className="inline-check"><input type="checkbox" name="isActive" value="true" defaultChecked /> Aktív</label><button>Új helyiség</button></form>
      <div className="admin-record-list">{overview.rooms.map((room) => <form action={saveRoom} className="admin-editor-row" key={room.id}><input type="hidden" name="roomId" value={room.id} /><input type="hidden" name="isActive" value="false" /><label>Név<input name="name" defaultValue={room.name} required maxLength={120} /></label><label>Sorrend<input name="displayOrder" type="number" min="0" defaultValue={room.display_order} required /></label><label className="inline-check"><input type="checkbox" name="isActive" value="true" defaultChecked={room.is_active} /> Aktív</label><button>Mentés</button></form>)}</div>
    </section>

    <section className="card wide-card stack"><h2>Felhasználók közvetlen helyiségjogai</h2><p className="muted">Itt kizárólag az egyedi közvetlen foglalási kivételek kezelendők. A csoportból kapott foglalási jog ettől függetlenül érvényesül; az ismétlődő foglalás jogosultsága user-szintű.</p><div className="admin-permission-list">{overview.users.map((user) => <details key={user.id}><summary>{user.name} · {user.email}{user.is_active ? "" : " · Inaktív"}</summary><div className="admin-record-list">{overview.rooms.map((room) => { const permission = userPermissions.get(pairKey(user.id, room.id)); return <form action={saveUserRoomPermission} className="permission-matrix-row" key={room.id}><input type="hidden" name="userId" value={user.id} /><input type="hidden" name="roomId" value={room.id} /><input type="hidden" name="canBook" value="false" /><input type="hidden" name="canRepeat" value="false" /><strong>{room.name}{room.is_active ? "" : " · Inaktív"}</strong><label className="inline-check"><input type="checkbox" name="canBook" value="true" defaultChecked={permission?.can_book ?? false} /> Közvetlen foglalási jog</label><button>Mentés</button></form>; })}</div></details>)}</div></section>
  </section>;
}
