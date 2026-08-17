import Link from "next/link";
import { requireActiveProfile } from "@/lib/auth";
import { budapestLocalToIso, isValidDate } from "@/lib/booking-form";
import { createClient } from "@/lib/supabase/server";
import { createBooking } from "./actions";

type BookableRoom = { room_id: string; room_name: string; is_training_room: boolean; display_order: number };
type CalendarBooking = { booking_id: string; room_id: string; room_name: string; start_at: string; end_at: string; use_type: "individual" | "group"; is_own: boolean; booker_display_name: string | null };
const OPEN_MINUTE = 420;
const CLOSE_MINUTE = 1320;

function budapestToday() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
}
function shiftDate(date: string, days: number) {
  const [year, month, day] = date.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}
function dateTitle(date: string) {
  return new Intl.DateTimeFormat("hu-HU", { timeZone: "UTC", weekday: "long", year: "numeric", month: "long", day: "numeric" }).format(new Date(`${date}T12:00:00Z`));
}
function localMinute(iso: string) {
  const parts = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Budapest", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(new Date(iso));
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return Number(values.hour) * 60 + Number(values.minute);
}
function timeLabel(iso: string) {
  return new Intl.DateTimeFormat("hu-HU", { timeZone: "Europe/Budapest", hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
}
function timeOptions() {
  return Array.from({ length: 31 }, (_, index) => {
    const minute = OPEN_MINUTE + index * 30;
    return `${String(Math.floor(minute / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`;
  });
}

export default async function BookingsPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const profile = await requireActiveProfile();
  const params = await searchParams;
  const today = budapestToday();
  const selectedDate = params.datum && isValidDate(params.datum) ? params.datum : today;
  const dayStart = budapestLocalToIso(selectedDate, "00:00");
  const dayEnd = budapestLocalToIso(shiftDate(selectedDate, 1), "00:00");
  const supabase = await createClient();
  const [roomsResult, bookingsResult] = await Promise.all([
    supabase.rpc("list_bookable_rooms").returns<BookableRoom[]>(),
    supabase.rpc("list_calendar_bookings", { p_start_at: dayStart, p_end_at: dayEnd }).returns<CalendarBooking[]>(),
  ]);
  const rooms = (roomsResult.data ?? []) as unknown as BookableRoom[];
  const bookings = (bookingsResult.data ?? []) as unknown as CalendarBooking[];

  return (
    <section className="booking-page stack">
      <header className="page-heading">
        <div><p className="eyebrow">Foglalási naptár</p><h1>{dateTitle(selectedDate)}</h1><p className="muted">Üdv, {profile.first_name}! A foglaltságok budapesti idő szerint jelennek meg.</p></div>
        <nav className="date-nav" aria-label="Naptári nap választása">
          <Link className="button secondary" href={`/foglalasok?datum=${shiftDate(selectedDate, -1)}`}>← Előző</Link>
          <Link className="button secondary" href={`/foglalasok?datum=${today}`}>Ma</Link>
          <Link className="button secondary" href={`/foglalasok?datum=${shiftDate(selectedDate, 1)}`}>Következő →</Link>
        </nav>
      </header>
      {params.hiba || params.uzenet ? <p className={`message ${params.hiba ? "error" : "success"}`} role="status">{params.hiba ?? params.uzenet}</p> : null}
      {roomsResult.error || bookingsResult.error ? <p className="message error" role="alert">A naptár betöltése nem sikerült. Kérlek, frissítsd az oldalt.</p> : null}

      <div className="booking-layout">
        <div className="calendar-card" aria-label={`${dateTitle(selectedDate)} foglalásai`}>
          {rooms.length ? <div className="calendar-scroll"><div className="calendar-grid" style={{ gridTemplateColumns: `4.5rem repeat(${rooms.length}, minmax(10rem, 1fr))` }}>
            <div className="calendar-corner" />
            {rooms.map((room) => <div className="room-heading" key={room.room_id}>{room.room_name}{room.is_training_room ? <small>Tréningterem</small> : null}</div>)}
            <div className="time-axis">{Array.from({ length: 16 }, (_, index) => <span key={index} style={{ top: `${index * 60}px` }}>{String(index + 7).padStart(2, "0")}:00</span>)}</div>
            {rooms.map((room) => <div className="room-timeline" key={room.room_id}>
              {bookings.filter((booking) => booking.room_id === room.room_id).map((booking) => {
                const start = Math.max(localMinute(booking.start_at), OPEN_MINUTE);
                const end = Math.min(localMinute(booking.end_at), CLOSE_MINUTE);
                return <article className={`booking-block ${booking.is_own ? "own" : ""}`} key={booking.booking_id} style={{ top: `${start - OPEN_MINUTE}px`, height: `${Math.max(end - start, 30)}px` }}>
                  <strong>{timeLabel(booking.start_at)}–{timeLabel(booking.end_at)}</strong><span>{booking.is_own ? "Saját foglalás" : booking.booker_display_name ?? "Foglalt"}</span>{booking.use_type === "group" ? <small>Csoportos</small> : null}
                </article>;
              })}
            </div>)}
          </div></div> : <div className="empty-state"><h2>Nincs foglalható helyiséged</h2><p className="muted">Kérj jogosultságot az A-Hely adminisztrátorától.</p></div>}
        </div>

        <aside className="card booking-form-card stack">
          <div><p className="eyebrow">Új időpont</p><h2>Foglalás létrehozása</h2></div>
          {rooms.length ? <form action={createBooking} className="stack">
            <label>Helyiség<select name="roomId" required defaultValue=""><option value="" disabled>Válassz helyiséget</option>{rooms.map((room) => <option key={room.room_id} value={room.room_id}>{room.room_name}</option>)}</select></label>
            <label>Dátum<input name="date" type="date" required defaultValue={selectedDate} min={today} /></label>
            <div className="form-row"><label>Kezdés<select name="startTime" required defaultValue="09:00">{timeOptions().slice(0, -2).map((time) => <option key={time}>{time}</option>)}</select></label><label>Befejezés<select name="endTime" required defaultValue="10:00">{timeOptions().slice(2).map((time) => <option key={time}>{time}</option>)}</select></label></div>
            <label>Használat<select name="useType" defaultValue="individual"><option value="individual">Egyéni</option><option value="group">Csoportos</option></select></label>
            <label>Megjegyzés<textarea name="note" maxLength={1000} rows={3} placeholder="Opcionális" /></label>
            <button type="submit">Foglalás mentése</button>
            <p className="muted form-help">Minimum 60 perc, 30 perces időegységekben. A végleges jogosultság- és ütközésellenőrzést az adatbázis végzi.</p>
          </form> : <p className="muted">Foglaláshoz előbb helyiségjogosultság szükséges.</p>}
        </aside>
      </div>
    </section>
  );
}
