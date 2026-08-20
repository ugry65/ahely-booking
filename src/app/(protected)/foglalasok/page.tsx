import Link from "next/link";
import { requireActiveProfile } from "@/lib/auth";
import { budapestLocalToIso, isValidDate } from "@/lib/booking-form";
import { createClient } from "@/lib/supabase/server";
import { CalendarBookingGrid, type BookableRoom, type CalendarBooking } from "./calendar-booking-grid";
import { MobileDateStrip } from "./mobile-date-strip";
import { QuickBookingDialog } from "./quick-booking-dialog";

function budapestToday() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
}
function shiftDate(date: string, days: number) { const [year, month, day] = date.split("-").map(Number); return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10); }
function dateTitle(date: string) { return new Intl.DateTimeFormat("hu-HU", { timeZone: "UTC", weekday: "long", year: "numeric", month: "long", day: "numeric" }).format(new Date(`${date}T12:00:00Z`)); }

export default async function BookingsPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  await requireActiveProfile();
  const params = await searchParams;
  const today = budapestToday();
  const selectedDate = params.datum && isValidDate(params.datum) ? params.datum : today;
  const dayStart = budapestLocalToIso(selectedDate, "00:00");
  const dayEnd = budapestLocalToIso(shiftDate(selectedDate, 1), "00:00");
  const supabase = await createClient();
  const [roomsResult, bookingsResult, repeatableRoomsResult] = await Promise.all([
    supabase.rpc("list_bookable_rooms").returns<BookableRoom[]>(),
    supabase.rpc("list_calendar_bookings", { p_start_at: dayStart, p_end_at: dayEnd }).returns<CalendarBooking[]>(),
    supabase.rpc("list_repeatable_rooms").returns<BookableRoom[]>(),
  ]);
  const rooms = (roomsResult.data ?? []) as unknown as BookableRoom[];
  const bookings = (bookingsResult.data ?? []) as unknown as CalendarBooking[];
  const repeatableRoomIds = ((repeatableRoomsResult.data ?? []) as unknown as BookableRoom[]).map((room) => room.room_id);

  return (
    <section className="booking-page stack" style={{ width: "min(calc(100vw - 2rem), 100rem)", marginLeft: "50%", transform: "translateX(-50%)", gap: ".65rem" }}>
      <MobileDateStrip selectedDate={selectedDate} />
      <header className="desktop-calendar-header" aria-label="Naptár vezérlők">
        <div style={{ display: "flex", alignItems: "center", gap: ".65rem", flexWrap: "wrap" }}>
          <nav className="date-nav" aria-label="Naptári nap választása" style={{ gap: ".3rem" }}>
            <Link className="button secondary" href={`/foglalasok?datum=${shiftDate(selectedDate, -1)}`} aria-label="Előző nap">←</Link>
            <Link className="button secondary" href={`/foglalasok?datum=${today}`}>Ma</Link>
            <Link className="button secondary" href={`/foglalasok?datum=${shiftDate(selectedDate, 1)}`} aria-label="Következő nap">→</Link>
          </nav>
          <h1 style={{ margin: 0, fontSize: "clamp(1.05rem, 1.6vw, 1.35rem)", lineHeight: 1.15, whiteSpace: "nowrap" }}>{dateTitle(selectedDate)}</h1>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: ".45rem", flexWrap: "wrap", justifyContent: "flex-end" }}>
          <form method="get" style={{ display: "flex", alignItems: "center", gap: ".35rem" }}>
            <input type="date" name="datum" defaultValue={selectedDate} aria-label="Ugrás dátumra" style={{ width: "9.7rem", minHeight: "2.25rem", padding: ".35rem .5rem" }} />
            <button type="submit" className="button secondary" style={{ minHeight: "2.25rem", padding: ".35rem .65rem" }}>Mutasd</button>
          </form>
          {rooms.length ? <QuickBookingDialog rooms={rooms} repeatableRoomIds={repeatableRoomIds} selectedDate={selectedDate} today={today} /> : null}
        </div>
      </header>
      {params.hiba || params.uzenet ? <p className={`message ${params.hiba ? "error" : "success"}`} role="status">{params.hiba ?? params.uzenet}</p> : null}
      {roomsResult.error || bookingsResult.error || repeatableRoomsResult.error ? <p className="message error" role="alert">A naptár betöltése nem sikerült. Kérlek, frissítsd az oldalt.</p> : null}
      {rooms.length ? <CalendarBookingGrid rooms={rooms} bookings={bookings} selectedDate={selectedDate} repeatableRoomIds={repeatableRoomIds} /> : <div className="calendar-card empty-state"><h2>Nincs foglalható helyiséged</h2><p className="muted">Kérj jogosultságot az A-Hely adminisztrátorától.</p></div>}
    </section>
  );
}
