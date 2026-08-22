import Link from "next/link";
import { requireActiveProfile } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { BookingTimeFields } from "../foglalasok/booking-time-fields";
import { cancelOwnBooking, updateOwnBooking } from "./actions";

type MyBooking = { booking_id: string; room_id: string; room_name: string; start_at: string; end_at: string; use_type: "individual" | "group"; note: string | null; series_id: string | null; updated_at: string };
type BookableRoom = { room_id: string; room_name: string; is_training_room: boolean; display_order: number };

function localParts(iso: string) {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(new Date(iso));
  return Object.fromEntries(parts.map((part) => [part.type, part.value]));
}
function localDate(iso: string) { const p = localParts(iso); return `${p.year}-${p.month}-${p.day}`; }
function localTime(iso: string) { const p = localParts(iso); return `${p.hour}:${p.minute}`; }
function dateLabel(iso: string) { return new Intl.DateTimeFormat("hu-HU", { timeZone: "Europe/Budapest", weekday: "long", year: "numeric", month: "long", day: "numeric" }).format(new Date(iso)); }
function timeOptions() { return Array.from({ length: 31 }, (_, index) => { const minute = 420 + index * 30; return `${String(Math.floor(minute / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`; }); }

export default async function MyBookingsPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireActiveProfile();
  const params = await searchParams;
  const supabase = await createClient();
  const [bookingsResult, roomsResult] = await Promise.all([
    supabase.rpc("list_my_bookings").returns<MyBooking[]>(),
    supabase.rpc("list_bookable_rooms").returns<BookableRoom[]>(),
  ]);
  const bookings = (bookingsResult.data ?? []) as unknown as MyBooking[];
  const rooms = (roomsResult.data ?? []) as unknown as BookableRoom[];
  const times = timeOptions();

  return <section className="stack">
    <header className="page-heading"><div><p className="eyebrow">Saját időpontok</p><h1>Foglalásaim</h1><p className="muted">A jövőbeli aktív foglalásaid budapesti idő szerint.</p></div><Link className="button secondary" href="/foglalasok">Naptár és új foglalás</Link></header>
    {params.hiba || params.uzenet ? <p className={`message ${params.hiba ? "error" : "success"}`} role="status">{params.hiba ?? params.uzenet}</p> : null}
    {bookingsResult.error || roomsResult.error ? <p className="message error" role="alert">A foglalások betöltése nem sikerült. Kérlek, frissítsd az oldalt.</p> : null}
    {!bookings.length && !bookingsResult.error ? <div className="card wide-card empty-state"><h2>Nincs közelgő foglalásod</h2><p className="muted">A naptárban hozhatsz létre új időpontot.</p></div> : null}
    <div className="my-bookings-list">
      {bookings.map((booking) => {
        const date = localDate(booking.start_at); const start = localTime(booking.start_at); const end = localTime(booking.end_at);
        return <article className="card wide-card booking-management-card stack" key={booking.booking_id}>
          <header className="booking-summary"><div><p className="eyebrow">{booking.series_id ? "Ismétlődő sorozat alkalma" : "Egyedi foglalás"}</p><h2>{booking.room_name}</h2><p><strong>{dateLabel(booking.start_at)}, {start}–{end}</strong> · {booking.use_type === "group" ? "Csoportos" : "Egyéni"}</p>{booking.note ? <p className="muted">{booking.note}</p> : null}</div></header>
          {!booking.series_id ? <details><summary>Módosítás</summary><form action={updateOwnBooking} className="stack operation-form">
            <input type="hidden" name="bookingId" value={booking.booking_id} /><input type="hidden" name="expectedUpdatedAt" value={booking.updated_at} /><input type="hidden" name="idempotencyKey" value={crypto.randomUUID()} />
            <label>Helyiség<select name="roomId" required defaultValue={booking.room_id}>{rooms.map((room) => <option key={room.room_id} value={room.room_id}>{room.room_name}</option>)}</select></label>
            <label>Dátum<input name="date" type="date" required defaultValue={date} /></label>
            <BookingTimeFields options={times} initialStartTime={start} initialEndTime={end} />
            <label>Használat<select name="useType" defaultValue={booking.use_type}><option value="individual">Egyéni</option><option value="group">Csoportos</option></select></label>
            <label>Megjegyzés<textarea name="note" maxLength={1000} rows={3} defaultValue={booking.note ?? ""} /></label>
            <button type="submit">Módosítás mentése</button>
          </form></details> : <p className="muted form-help">A sorozat egyedi alkalma ezen a felületen nem módosítható, de lemondható.</p>}
          <details className="danger-zone"><summary>Foglalás lemondása</summary><form action={cancelOwnBooking} className="stack operation-form">
            <input type="hidden" name="bookingId" value={booking.booking_id} /><input type="hidden" name="idempotencyKey" value={crypto.randomUUID()} />
            <p className="muted form-help">Biztosan lemondod ezt az időpontot? Normál felhasználóként legalább 24 órával a kezdés előtt mondhatod le.</p>
            <label>Lemondás indoka<textarea name="reason" maxLength={500} rows={2} placeholder="Opcionális" /></label>
            <button className="danger-button" type="submit">Igen, lemondom</button>
          </form></details>
        </article>;
      })}
    </div>
  </section>;
}
