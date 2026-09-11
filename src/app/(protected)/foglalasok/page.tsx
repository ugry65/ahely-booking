import { requireActiveProfile } from "@/lib/auth";
import { budapestLocalToIso, isValidDate } from "@/lib/booking-form";
import { createClient } from "@/lib/supabase/server";
import { CalendarBookingGrid, type BookableRoom, type CalendarBooking } from "./calendar-booking-grid";
import { CalendarDateNavigation } from "./calendar-date-navigation";
import { MobileDateStrip } from "./mobile-date-strip";
import { QuickBookingDialog, type BookingUser } from "./quick-booking-dialog";
import "./calendar-booking-actions.css";
import "./calendar-header.css";

type BaseCalendarBooking = Omit<CalendarBooking, "note" | "series_id" | "updated_at" | "can_manage">;
type CalendarBookingManagement = Pick<CalendarBooking, "booking_id" | "note" | "booking_title" | "series_id" | "updated_at" | "can_manage">;

function budapestToday() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
}
function shiftDate(date: string, days: number) { const [year, month, day] = date.split("-").map(Number); return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10); }
function dateTitle(date: string) { return new Intl.DateTimeFormat("hu-HU", { timeZone: "UTC", weekday: "long", year: "numeric", month: "long", day: "numeric" }).format(new Date(`${date}T12:00:00Z`)); }

export default async function BookingsPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const profile = await requireActiveProfile();
  const params = await searchParams;
  const today = budapestToday();
  const selectedDate = params.datum && isValidDate(params.datum) ? params.datum : today;
  const dayStart = budapestLocalToIso(selectedDate, "00:00");
  const dayEnd = budapestLocalToIso(shiftDate(selectedDate, 1), "00:00");
  const supabase = await createClient();
  const [roomsResult, bookingsResult, managementResult, repeatableRoomsResult, usersResult] = await Promise.all([
    supabase.rpc("list_bookable_rooms").returns<BookableRoom[]>(),
    supabase.rpc("list_calendar_bookings", { p_start_at: dayStart, p_end_at: dayEnd }).returns<BaseCalendarBooking[]>(),
    supabase.rpc("list_calendar_booking_management", { p_start_at: dayStart, p_end_at: dayEnd }).returns<CalendarBookingManagement[]>(),
    supabase.rpc("list_repeatable_rooms").returns<BookableRoom[]>(),
    profile.role === "admin"
      ? supabase.from("profiles").select("id,first_name,last_name,email").eq("is_active", true).order("last_name").order("first_name")
      : Promise.resolve({ data: [], error: null }),
  ]);
  const rooms = (roomsResult.data ?? []) as unknown as BookableRoom[];
  const baseBookings = (bookingsResult.data ?? []) as unknown as BaseCalendarBooking[];
  const management = (managementResult.data ?? []) as unknown as CalendarBookingManagement[];
  const managementByBookingId = new Map(management.map((item) => [item.booking_id, item]));
  const bookings: CalendarBooking[] = baseBookings.map((booking) => {
    const manageable = managementByBookingId.get(booking.booking_id);
    return {
      ...booking,
      booking_title: manageable?.booking_title ?? booking.booking_title ?? null,
      note: manageable?.note ?? null,
      series_id: manageable?.series_id ?? null,
      updated_at: manageable?.updated_at ?? null,
      can_manage: manageable?.can_manage ?? false,
    };
  });
  const repeatableRoomIds = ((repeatableRoomsResult.data ?? []) as unknown as BookableRoom[]).map((room) => room.room_id);
  const bookingUsers: BookingUser[] = ((usersResult.data ?? []) as Array<{ id: string; first_name: string; last_name: string; email: string }>).map((user) => ({ id: user.id, name: `${user.last_name} ${user.first_name}`.trim(), email: user.email }));

  return (
    <section className="booking-page stack">
      <MobileDateStrip selectedDate={selectedDate} />
      <header className="desktop-calendar-header" aria-label="Naptár vezérlők">
        <div className="calendar-header-main">
          <CalendarDateNavigation
            previousDate={shiftDate(selectedDate, -1)}
            today={today}
            nextDate={shiftDate(selectedDate, 1)}
            selectedDate={selectedDate}
          />
          <h1 className="calendar-date-title">{dateTitle(selectedDate)}</h1>
          <div id="calendar-selection-actions-slot" className="calendar-selection-actions-slot" />
        </div>
        <form method="get" className="calendar-date-jump">
          <input type="date" name="datum" defaultValue={selectedDate} aria-label="Ugrás dátumra" />
          <button type="submit" className="button secondary">Mutasd</button>
        </form>
      </header>

      {rooms.length ? <QuickBookingDialog rooms={rooms} repeatableRoomIds={repeatableRoomIds} selectedDate={selectedDate} bookingUsers={bookingUsers} currentUserId={profile.id} isAdmin={profile.role === "admin"} /> : null}
      {params.hiba || params.uzenet ? <p className={`message ${params.hiba ? "error" : "success"}`} role="status">{params.hiba ?? params.uzenet}</p> : null}
      {roomsResult.error || bookingsResult.error || managementResult.error || repeatableRoomsResult.error || usersResult.error ? <p className="message error" role="alert">A naptár betöltése nem sikerült. Kérlek, frissítsd az oldalt.</p> : null}
      {rooms.length ? <CalendarBookingGrid rooms={rooms} bookings={bookings} selectedDate={selectedDate} repeatableRoomIds={repeatableRoomIds} bookingUsers={bookingUsers} currentUserId={profile.id} isAdmin={profile.role === "admin"} /> : <div className="calendar-card empty-state"><h2>Nincs foglalható helyiséged</h2><p className="muted">Kérj jogosultságot az A-Hely adminisztrátorától.</p></div>}
    </section>
  );
}
