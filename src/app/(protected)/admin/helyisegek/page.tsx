import Link from "next/link";

import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

import { saveAccessGroup, saveGroupRoomPermission, saveRoom } from "./actions";

type Room = { id: string; name: string; display_order: number; is_training_room: boolean; is_active: boolean };
type Group = { id: string; name: string; is_active: boolean };
type GroupRoomPermission = { group_id: string; room_id: string; can_book: boolean; can_repeat: boolean };
type Overview = { rooms: Room[]; groups: Group[]; group_room_permissions: GroupRoomPermission[] };

const empty: Overview = { rooms: [], groups: [], group_room_permissions: [] };
function pairKey(firstId: string, secondId: string) { return `${firstId}:${secondId}`; }

export default async function RoomsAdminPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireAdmin();
  const params = await searchParams;
  const supabase = await createClient();
  const response = await supabase.rpc("admin_room_access_overview");
  const raw = response.error ? null : response.data as unknown as {
    rooms?: Room[];
    groups?: Group[];
    group_room_permissions?: GroupRoomPermission[];
  };
  const overview: Overview = raw ? {
    rooms: raw.rooms ?? [],
    groups: raw.groups ?? [],
    group_room_permissions: raw.group_room_permissions ?? [],
  } : empty;
  const groupPermissions = new Map(
    overview.group_room_permissions.map((item) => [pairKey(item.group_id, item.room_id), item]),
  );

  return (
    <section className="stack">
      <header className="page-heading">
        <div>
          <p className="eyebrow">Adminisztráció</p>
          <h1>Helyiségek</h1>
          <p className="muted">Helyiségek és helyiségcsoportok kezelése. A csoportok foglalási jogot adnak; ismétlődő foglalási jog továbbra is közvetlenül a felhasználónál kezelendő.</p>
        </div>
        <Link className="button secondary" href="/admin/hozzaferesek">Közvetlen user-jogok</Link>
      </header>

      {params.hiba ? <p className="message error" role="alert">{params.hiba}</p> : null}
      {params.uzenet ? <p className="message success" role="status">{params.uzenet}</p> : null}
      {response.error ? <p className="message error" role="alert">A helyiségadatok betöltése nem sikerült.</p> : null}

      <section className="card wide-card stack">
        <h2>Helyiségek</h2>
        <p className="muted">A meglévő helyiségek megmaradnak; itt új helyiség hozható létre, illetve a név, sorrend és aktív állapot módosítható.</p>
        <form action={saveRoom} className="admin-editor-row">
          <input type="hidden" name="isActive" value="false" />
          <label>Név<input name="name" required maxLength={120} /></label>
          <label>Sorrend<input name="displayOrder" type="number" min="0" required /></label>
          <label className="inline-check"><input type="checkbox" name="isActive" value="true" defaultChecked /> Aktív</label>
          <button type="submit">Új helyiség</button>
        </form>
        <div className="admin-record-list">
          {overview.rooms.map((room) => (
            <form action={saveRoom} className="admin-editor-row" key={room.id}>
              <input type="hidden" name="roomId" value={room.id} />
              <input type="hidden" name="isActive" value="false" />
              <label>Név<input name="name" defaultValue={room.name} required maxLength={120} /></label>
              <label>Sorrend<input name="displayOrder" type="number" min="0" defaultValue={room.display_order} required /></label>
              <label className="inline-check"><input type="checkbox" name="isActive" value="true" defaultChecked={room.is_active} /> Aktív</label>
              <button type="submit">Mentés</button>
            </form>
          ))}
        </div>
      </section>

      <section className="card wide-card stack">
        <h2>Helyiségcsoportok</h2>
        <p className="muted">Egy csoport több helyiséget fog össze. A későbbi Felhasználók felületen egy userhez egy vagy több csoport lesz rendelhető. A közvetlen helyiségjogok ettől függetlenül megmaradnak.</p>
        <form action={saveAccessGroup} className="admin-editor-row">
          <input type="hidden" name="isActive" value="false" />
          <label>Név<input name="name" required maxLength={120} /></label>
          <label className="inline-check"><input type="checkbox" name="isActive" value="true" defaultChecked /> Aktív</label>
          <button type="submit">Új csoport</button>
        </form>

        <div className="admin-permission-list">
          {overview.groups.map((group) => (
            <details key={group.id} open={group.name === "A-Hely" || group.name === "Másik Hely"}>
              <summary>{group.name}{group.is_active ? "" : " · Inaktív"}</summary>
              <div className="stack" style={{ paddingTop: ".8rem" }}>
                <form action={saveAccessGroup} className="admin-editor-row">
                  <input type="hidden" name="groupId" value={group.id} />
                  <input type="hidden" name="isActive" value="false" />
                  <label>Név<input name="name" defaultValue={group.name} required maxLength={120} /></label>
                  <label className="inline-check"><input type="checkbox" name="isActive" value="true" defaultChecked={group.is_active} /> Aktív</label>
                  <button type="submit">Csoport mentése</button>
                </form>

                <div className="admin-record-list">
                  {overview.rooms.map((room) => {
                    const permission = groupPermissions.get(pairKey(group.id, room.id));
                    return (
                      <form action={saveGroupRoomPermission} className="permission-matrix-row" key={room.id}>
                        <input type="hidden" name="groupId" value={group.id} />
                        <input type="hidden" name="roomId" value={room.id} />
                        <input type="hidden" name="canBook" value="false" />
                        <strong>{room.name}{room.is_active ? "" : " · Inaktív"}</strong>
                        <label className="inline-check">
                          <input type="checkbox" name="canBook" value="true" defaultChecked={permission?.can_book ?? false} /> Csoportból foglalható
                        </label>
                        <span className="muted">Ismétlés: user-szintű</span>
                        <button type="submit">Mentés</button>
                      </form>
                    );
                  })}
                </div>
              </div>
            </details>
          ))}
        </div>
      </section>
    </section>
  );
}
