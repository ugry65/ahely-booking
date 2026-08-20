"use client";

import { useMemo, useState } from "react";
import { createBooking } from "./actions";
import type { BookableRoom } from "./calendar-booking-grid";

const OPEN_MINUTE = 7 * 60;

function timeOptions() {
  return Array.from({ length: 31 }, (_, index) => {
    const minute = OPEN_MINUTE + index * 30;
    return `${String(Math.floor(minute / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`;
  });
}

export function QuickBookingDialog({ rooms, selectedDate, today }: { rooms: BookableRoom[]; selectedDate: string; today: string }) {
  const [open, setOpen] = useState(false);
  const idempotencyKey = useMemo(() => crypto.randomUUID(), [open]);

  return (
    <>
      <button
        type="button"
        aria-label="Új foglalás gyors megadása"
        title="Új foglalás"
        onClick={() => setOpen(true)}
        style={{
          width: "3rem",
          height: "3rem",
          borderRadius: "999px",
          fontSize: "1.8rem",
          lineHeight: 1,
          padding: 0,
          boxShadow: "0 .4rem 1rem rgb(31 42 36 / 18%)",
        }}
      >
        +
      </button>

      {open ? (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="quick-booking-title"
          style={{
            position: "fixed",
            inset: 0,
            zIndex: 50,
            display: "grid",
            placeItems: "center",
            padding: "1rem",
            background: "rgb(31 42 36 / 42%)",
          }}
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) setOpen(false);
          }}
        >
          <section className="card stack" style={{ width: "min(100%, 34rem)", maxHeight: "calc(100vh - 2rem)", overflow: "auto" }}>
            <div style={{ display: "flex", alignItems: "start", justifyContent: "space-between", gap: "1rem" }}>
              <div>
                <p className="eyebrow">Gyorsfoglalás</p>
                <h2 id="quick-booking-title" style={{ margin: ".15rem 0 .35rem" }}>Új foglalás</h2>
              </div>
              <button type="button" className="button secondary" onClick={() => setOpen(false)} aria-label="Bezárás">×</button>
            </div>

            <form action={createBooking} className="stack">
              <input type="hidden" name="idempotencyKey" value={idempotencyKey} />
              <label>Helyiség
                <select name="roomId" required defaultValue="">
                  <option value="" disabled>Válassz helyiséget</option>
                  {rooms.map((room) => <option key={room.room_id} value={room.room_id}>{room.room_name}</option>)}
                </select>
              </label>
              <label>Dátum<input name="date" type="date" required defaultValue={selectedDate} min={today} /></label>
              <div className="form-row">
                <label>Kezdés
                  <select name="startTime" required defaultValue="09:00">
                    {timeOptions().slice(0, -2).map((time) => <option key={time}>{time}</option>)}
                  </select>
                </label>
                <label>Befejezés
                  <select name="endTime" required defaultValue="10:00">
                    {timeOptions().slice(2).map((time) => <option key={time}>{time}</option>)}
                  </select>
                </label>
              </div>
              <label>Használat
                <select name="useType" defaultValue="individual">
                  <option value="individual">Egyéni</option>
                  <option value="group">Csoportos</option>
                </select>
              </label>
              <label>Megjegyzés<textarea name="note" maxLength={1000} rows={3} placeholder="Opcionális" /></label>
              <button type="submit">Foglalás mentése</button>
              <p className="muted form-help">A végleges jogosultság-, időrács-, előrefoglalási és ütközésellenőrzést a backend végzi.</p>
            </form>
          </section>
        </div>
      ) : null}
    </>
  );
}
