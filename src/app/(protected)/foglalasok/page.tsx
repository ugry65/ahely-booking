import Link from "next/link";
import { requireActiveProfile } from "@/lib/auth";
import { budapestLocalToIso, isValidDate } from "@/lib/booking-form";
import { createClient } from "@/lib/supabase/server";
import { CalendarBookingGrid, type BookableRoom, type CalendarBooking } from "./calendar-booking-grid";
import { QuickBookingDialog } from "./quick-booking-dialog";

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
    <section
      className="booking-page stack"
      style={{ width: "min(calc(100vw - 2rem), 100rem)", marginLeft: "50%", transform: "translateX(-50%)" }}
    >
      <header className="page-heading" style={{ alignItems: "flex-end" }}>
        <div>
          <p className="eyebrow">Foglalási naptár</p>
          <h1>{dateTitle(selectedDate)}</h1>
          <p className="muted">Üdv, {profile.first_name}! A foglaltságok budapesti idő szerint jelennek meg.</p>
          <Link href="/foglalasok/ismetlod">Ismétlődő foglalás létrehozása →</Link>
        </div>

        <div style={{ display: "flex", alignItems: "end", gap: "1rem" }}>
          <div style={{ display: "grid", gap: ".7rem", justifyItems: "end" }}>
            <nav className="date-nav" aria-label="Naptári nap választása">
              <Link className="button secondary" href={`/foglalasok?datum=${shiftDate(selectedDate, -1)}`}>← Előző</Link>
              <Link className="button secondary" href={`/foglalasok?datum=${today}`}>Ma</Link>
              <Link className="button secondary" href={`/foglalasok?datum=${shiftDate(selectedDate, 1)}`}>Következő →</Link>
            </nav>
            <form method="get" style={{ display: "flex", alignItems: "end", gap: ".5rem" }}>
              <label style={{ fontSize: ".82rem" }}>Ugrás dátumra
                <input type="date" name="datum" defaultValue={selectedDate} />
              </label>
              <button type="submit" className="button secondary">Mutasd</button>
            </form>
          </div>
          {rooms.length ? <QuickBookingDialog rooms={rooms} selectedDate={selectedDate} today={today} /> : null}
        </div>
      </header>

      {params.hiba || params.uzenet ? <p className={`message ${params.hiba ? "error" : "success"}`} role="status">{params.hiba ?? params.uzenet}</p> : null}
      {roomsResult.error || bookingsResult.error ? <p className="message error" role="alert">A naptár betöltése nem sikerült. Kérlek, frissítsd az oldalt.</p> : null}

      {rooms.length ? (
        <CalendarBookingGrid rooms={rooms} bookings={bookings} selectedDate={selectedDate} />
      ) : (
        <div className="calendar-card empty-state"><h2>Nincs foglalható helyiséged</h2><p className="muted">Kérj jogosultságot az A-Hely adminisztrátorától.</p></div>
      )}
    </section>
  );
}
