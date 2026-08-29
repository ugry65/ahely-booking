"use client";

import { useMemo, useState } from "react";
import { createBooking } from "./actions";
import { createRecurringBooking } from "./ismetlod/actions";
import { RecurringExceptionCalendar } from "./ismetlod/recurring-exception-calendar";
import type { BookableRoom } from "./calendar-booking-grid";
import { BookingTimeFields } from "./booking-time-fields";
import { RecurringEndFields } from "./recurring-end-fields";

const OPEN_MINUTE = 7 * 60;
type RepeatFrequency = "none" | "daily" | "weekly" | "biweekly" | "monthly";
export type BookingUser = { id: string; name: string; email: string };

function timeOptions() {
  return Array.from({ length: 31 }, (_, index) => {
    const minute = OPEN_MINUTE + index * 30;
    return `${String(Math.floor(minute / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`;
  });
}

export function QuickBookingDialog({ rooms, repeatableRoomIds, selectedDate, today, bookingUsers = [], currentUserId, isAdmin = false }: { rooms: BookableRoom[]; repeatableRoomIds: string[]; selectedDate: string; today: string; bookingUsers?: BookingUser[]; currentUserId?: string; isAdmin?: boolean }) {
  const [open, setOpen] = useState(false);
  const [selectedRoomId, setSelectedRoomId] = useState("");
  const [repeatFrequency, setRepeatFrequency] = useState<RepeatFrequency>("none");
  const [useType, setUseType] = useState<"individual" | "group">("individual");
  const idempotencyKey = useMemo(() => crypto.randomUUID(), [open, repeatFrequency]);
  const selectedRoom = rooms.find((room) => room.room_id === selectedRoomId);
  const canRepeat = selectedRoomId ? repeatableRoomIds.includes(selectedRoomId) : false;
  const formAction = repeatFrequency === "none" ? createBooking : createRecurringBooking;
  const showGroupRate = isAdmin && selectedRoom?.is_training_room && useType === "group";

  function closeDialog() {
    setOpen(false);
    setSelectedRoomId("");
    setRepeatFrequency("none");
    setUseType("individual");
  }

  return (
    <>
      <button type="button" aria-label="Új foglalás gyors megadása" title="Új foglalás" onClick={() => setOpen(true)} style={{ position: "fixed", right: "2rem", bottom: "2rem", zIndex: 40, width: "3.5rem", height: "3.5rem", borderRadius: "999px", fontSize: "2rem", lineHeight: 1, padding: 0, boxShadow: "0 .5rem 1.25rem rgb(31 42 36 / 24%)" }}>+</button>

      {open ? (
        <div role="dialog" aria-modal="true" aria-labelledby="quick-booking-title" className="booking-modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) closeDialog(); }}>
          <section className="card stack booking-modal-card">
            <div className="booking-modal-heading">
              <div><p className="eyebrow">Új időpont</p><h2 id="quick-booking-title">Foglalás</h2></div>
              <button type="button" className="button secondary" onClick={closeDialog} aria-label="Bezárás">×</button>
            </div>

            <form action={formAction} className="stack">
              <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
              {bookingUsers.length ? (
                <label>Felhasználó
                  <select name="targetUserId" defaultValue={currentUserId ?? bookingUsers[0]?.id} required>
                    {bookingUsers.map((user) => <option key={user.id} value={user.id}>{user.name} · {user.email}</option>)}
                  </select>
                  <span className="muted form-help">Adminisztrátorként kiválaszthatod, kinek a nevében jön létre a foglalás.</span>
                </label>
              ) : null}
              <label>Helyiség
                <select name="roomId" required value={selectedRoomId} onChange={(event) => { setSelectedRoomId(event.target.value); setRepeatFrequency("none"); setUseType("individual"); }}>
                  <option value="" disabled>Válassz helyiséget</option>
                  {rooms.map((room) => <option key={room.room_id} value={room.room_id}>{room.room_name}</option>)}
                </select>
              </label>
              <label>Dátum<input name="date" type="date" required defaultValue={selectedDate} min={today} /></label>
              <BookingTimeFields options={timeOptions()} initialStartTime="09:00" initialEndTime="10:00" />

              <label>Ismétlődés
                <select name="frequency" value={repeatFrequency} onChange={(event) => setRepeatFrequency(event.target.value as RepeatFrequency)} disabled={!canRepeat}>
                  <option value="none">Nincs</option>
                  <option value="daily">Naponta</option>
                  <option value="weekly">Hetente</option>
                  <option value="biweekly">Kéthetente</option>
                  <option value="monthly">Havonta</option>
                </select>
                {selectedRoomId && !canRepeat ? <span className="muted form-help">Ehhez a helyiséghez nincs ismétlődő foglalási jogosultságod.</span> : null}
              </label>

              {repeatFrequency !== "none" ? (
                <fieldset className="repeat-options">
                  <legend>Ismétlődés beállításai</legend>
                  <RecurringEndFields initialDate={selectedDate} />
                  <RecurringExceptionCalendar />
                  <label>Ütközés kezelése<select name="conflictPolicy" defaultValue="abort_all"><option value="abort_all">Teljes sorozat megszakítása</option><option value="create_available">Csak a szabad alkalmak létrehozása</option></select></label>
                </fieldset>
              ) : null}

              {selectedRoom?.is_training_room ? (
                <label>Használat<select name="useType" value={useType} onChange={(event) => setUseType(event.target.value as "individual" | "group")}><option value="individual">Egyéni</option><option value="group">Csoportos</option></select></label>
              ) : <input type="hidden" name="useType" value="individual" />}

              {showGroupRate ? (
                <label>Csoportos óradíj
                  <input name="groupHourlyRateHuf" type="number" min="0" step="1" defaultValue="5000" required />
                  <span className="muted form-help">A Tréningterem csoportos használatának alapdíja 5 000 Ft/óra. Adminisztrátorként ennél a foglalásnál vagy sorozatnál felülírhatod.</span>
                </label>
              ) : null}

              <label>Foglalás címe<input name="bookingTitle" maxLength={100} placeholder="Opcionális" /></label>
              <span className="muted form-help">A címet csak te és az adminisztrátorok láthatják.</span>
              <label>Megjegyzés<textarea name="note" maxLength={1000} rows={3} placeholder="Opcionális" /></label>
              <div className="booking-modal-actions">
                <button type="submit">{repeatFrequency === "none" ? "Foglalás mentése" : "Sorozat létrehozása"}</button>
                <button type="button" className="button secondary" onClick={closeDialog}>Mégse</button>
              </div>
              <p className="muted form-help">A végleges jogosultság-, időrács-, előrefoglalási és ütközésellenőrzést a backend végzi.</p>
            </form>
          </section>
        </div>
      ) : null}
    </>
  );
}
