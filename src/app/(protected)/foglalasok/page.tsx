import Link from "next/link";
import { requireActiveProfile } from "@/lib/auth";
import { budapestLocalToIso, isValidDate } from "@/lib/booking-form";
import { createClient } from "@/lib/supabase/server";
import { createBooking } from "./actions";
import { CalendarBookingGrid, type BookableRoom, type CalendarBooking } from "./calendar-booking-grid";

const OPEN_MINUTE = 420;

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
      <header className="page-heading calendar-page-heading">
        <div>
          <p className="eyebrow">Foglalási naptár</p>
          <h1>{dateTitle(selectedDate)}</h1>
          <p className="muted">Üdv, {profile.first_name}! A foglaltságok budapesti idő szerint jelennek meg.</p>
          <Link href="/foglalasok/ismetlod">Ismétlődő foglalás létrehozása →</Link>
        </div>
        <div className="calendar-navigation-stack">
          <nav className="date-nav" aria-label="Naptári nap választása">
            <Link className="button secondary" href={`/foglalasok?datum=${shiftDate(selectedDate, -1)}`}>← Előző</Link>
            <Link className="button secondary" href={`/foglalasok?datum=${today}`}>Ma</Link>
            <Link className="button secondary" href={`/foglalasok?datum=${shiftDate(selectedDate, 1)}`}>Következő →</Link>
          </nav>
          <form method="get" className="date-jump-form">
            <label>Ugrás dátumra
              <input type="date" name="datum" defaultValue={selectedDate} />
            </label>
            <button type="submit" className="button secondary">Mutasd</button>
          </form>
        </div>
      </header>

      {params.hiba || params.uzenet ? <p className={`message ${params.hiba ? "error" : "success"}`} role="status">{params.hiba ?? params.uzenet}</p> : null}
      {roomsResult.error || bookingsResult.error ? <p className="message error" role="alert">A naptár betöltése nem sikerült. Kérlek, frissítsd az oldalt.</p> : null}

      {rooms.length ? (
        <CalendarBookingGrid rooms={rooms} bookings={bookings} selectedDate={selectedDate} />
      ) : (
        <div className="calendar-card empty-state"><h2>Nincs foglalható helyiséged</h2><p className="muted">Kérj jogosultságot az A-Hely adminisztrátorától.</p></div>
      )}

      {rooms.length ? (
        <details className="manual-booking card wide-card">
          <summary>Foglalás megadása kézzel</summary>
          <p className="muted">Mobilon vagy billentyűzetes használatnál a foglalás a hagyományos mezőkkel is megadható.</p>
          <form action={createBooking} className="stack manual-booking-form">
            <input type="hidden" name="idempotencyKey" value={crypto.randomUUID()} />
            <label>Helyiség<select name="roomId" required defaultValue=""><option value="" disabled>Válassz helyiséget</option>{rooms.map((room) => <option key={room.room_id} value={room.room_id}>{room.room_name}</option>)}</select></label>
            <label>Dátum<input name="date" type="date" required defaultValue={selectedDate} min={today} /></label>
            <div className="form-row"><label>Kezdés<select name="startTime" required defaultValue="09:00">{timeOptions().slice(0, -2).map((time) => <option key={time}>{time}</option>)}</select></label><label>Befejezés<select name="endTime" required defaultValue="10:00">{timeOptions().slice(2).map((time) => <option key={time}>{time}</option>)}</select></label></div>
            <label>Használat<select name="useType" defaultValue="individual"><option value="individual">Egyéni</option><option value="group">Csoportos</option></select></label>
            <label>Megjegyzés<textarea name="note" maxLength={1000} rows={3} placeholder="Opcionális" /></label>
            <button type="submit">Foglalás mentése</button>
            <p className="muted form-help">Minimum 60 perc, 30 perces időegységekben. A végleges jogosultság- és ütközésellenőrzést az adatbázis végzi.</p>
          </form>
        </details>
      ) : null}
    </section>
  );
}
