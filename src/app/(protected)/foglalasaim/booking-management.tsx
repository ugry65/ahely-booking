import Link from "next/link";
import { BookingTimeFields } from "../foglalasok/booking-time-fields";
import { cancelOwnBooking, updateOwnBooking } from "./actions";
import { budapestDateFromIso, budapestTimeFromIso } from "@/lib/my-bookings-calendar";

export type MyBooking = {
  booking_id: string;
  room_id: string;
  room_name: string;
  start_at: string;
  end_at: string;
  use_type: "individual" | "group";
  note: string | null;
  booking_title: string | null;
  series_id: string | null;
  updated_at: string;
};

export type BookableRoom = {
  room_id: string;
  room_name: string;
  is_training_room: boolean;
  display_order: number;
};

function dateLabel(iso: string) {
  return new Intl.DateTimeFormat("hu-HU", {
    timeZone: "Europe/Budapest",
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  }).format(new Date(iso));
}

export function timeOptions() {
  return Array.from({ length: 31 }, (_, index) => {
    const minute = 420 + index * 30;
    return `${String(Math.floor(minute / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`;
  });
}

export function BookingManagement({ booking, rooms, returnTo, closeHref }: { booking: MyBooking; rooms: BookableRoom[]; returnTo: string; closeHref?: string }) {
  const date = budapestDateFromIso(booking.start_at);
  const start = budapestTimeFromIso(booking.start_at);
  const end = budapestTimeFromIso(booking.end_at);
  const times = timeOptions();

  return <article className="card wide-card booking-management-card stack">
    <header className="booking-summary">
      <div>
        <p className="eyebrow">{booking.series_id ? "Ismétlődő sorozat alkalma" : "Egyedi foglalás"}</p>
        <h2>{booking.room_name}</h2>
        <p><strong>{dateLabel(booking.start_at)}, {start}–{end}</strong> · {booking.use_type === "group" ? "Csoportos" : "Egyéni"}</p>
        {booking.booking_title ? <p><strong>{booking.booking_title}</strong></p> : null}
        {booking.note ? <p className="muted">{booking.note}</p> : null}
      </div>
      {closeHref ? <Link className="button secondary" href={closeHref}>Bezárás</Link> : null}
    </header>

    {!booking.series_id ? <details>
      <summary>Módosítás</summary>
      <form action={updateOwnBooking} className="stack operation-form">
        <input type="hidden" name="bookingId" value={booking.booking_id} />
        <input type="hidden" name="expectedUpdatedAt" value={booking.updated_at} />
        <input type="hidden" name="idempotencyKey" value={crypto.randomUUID()} />
        <input type="hidden" name="returnTo" value={returnTo} />
        <label>Helyiség<select name="roomId" required defaultValue={booking.room_id}>{rooms.map((room) => <option key={room.room_id} value={room.room_id}>{room.room_name}</option>)}</select></label>
        <label>Dátum<input name="date" type="date" required defaultValue={date} /></label>
        <BookingTimeFields options={times} initialStartTime={start} initialEndTime={end} />
        <label>Használat<select name="useType" defaultValue={booking.use_type}><option value="individual">Egyéni</option><option value="group">Csoportos</option></select></label>
        <label>Foglalás címe<input name="bookingTitle" maxLength={100} defaultValue={booking.booking_title ?? ""} placeholder="Opcionális" /></label>
        <span className="muted form-help">A címet csak te és az adminisztrátorok láthatják.</span>
        <label>Megjegyzés<textarea name="note" maxLength={1000} rows={3} defaultValue={booking.note ?? ""} /></label>
        <button type="submit">Módosítás mentése</button>
      </form>
    </details> : <p className="muted form-help">A sorozat egyedi alkalma ezen a felületen nem módosítható, de lemondható.</p>}

    <details className="danger-zone">
      <summary>Foglalás lemondása</summary>
      <form action={cancelOwnBooking} className="stack operation-form">
        <input type="hidden" name="bookingId" value={booking.booking_id} />
        <input type="hidden" name="idempotencyKey" value={crypto.randomUUID()} />
        <input type="hidden" name="returnTo" value={returnTo} />
        <p className="muted form-help">Biztosan lemondod ezt az időpontot? Normál felhasználóként legalább 24 órával a kezdés előtt mondhatod le.</p>
        <label>Lemondás indoka<textarea name="reason" maxLength={500} rows={2} placeholder="Opcionális" /></label>
        <button className="danger-button" type="submit">Igen, lemondom</button>
      </form>
    </details>
  </article>;
}
