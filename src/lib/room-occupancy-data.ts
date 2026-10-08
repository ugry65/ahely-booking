import "server-only";
import { requireAdmin } from "./auth";
import { createClient } from "./supabase/server";
import { readAllPages, reportMonths, timeMinutes, visibleWeek, type OccupancyBooking, type OccupancyFilter, type ReportRoom } from "./room-occupancy";

type User = { id: string; first_name: string; last_name: string };
export async function loadRoomOccupancy(filter: OccupancyFilter, forceList = false) {
  await requireAdmin();
  const db = await createClient();
  const [roomsResponse, usersResponse, settingsResponse] = await Promise.all([
    db.from("rooms").select("id,name,is_active").order("display_order").order("id"),
    db.from("profiles").select("id,first_name,last_name").order("last_name").order("first_name"),
    db.from("app_settings").select("key,value").in("key", ["opening_time", "closing_time"]),
  ]);
  if (roomsResponse.error || usersResponse.error || settingsResponse.error) throw new Error("A szobák vagy beállítások betöltése nem sikerült. Próbáld újra.");
  const rooms = (roomsResponse.data ?? []) as ReportRoom[];
  const users = (usersResponse.data ?? []) as User[];
  if (filter.roomIds.some(id => !rooms.some(r => r.id === id))) throw new Error("A kiválasztott szoba nem található.");
  if (filter.userId && !users.some(u => u.id === filter.userId)) throw new Error("A kiválasztott foglaló nem található.");
  const selectedRooms = rooms.filter(r => filter.roomIds.length ? filter.roomIds.includes(r.id) : r.is_active);
  const openingTime = settingsResponse.data?.find(s => s.key === "opening_time")?.value;
  const closingTime = settingsResponse.data?.find(s => s.key === "closing_time")?.value;
  if (typeof openingTime !== "string" || typeof closingTime !== "string" || !/^\d\d:\d\d/.test(openingTime) || !/^\d\d:\d\d/.test(closingTime)) throw new Error("A nyitvatartási beállítások nem érvényesek.");
  const opening = { start: timeMinutes(openingTime), end: timeMinutes(closingTime) };
  if (!Number.isFinite(opening.start) || !Number.isFinite(opening.end) || opening.end <= opening.start) throw new Error("A nyitvatartási beállítások nem érvényesek.");
  const weekly = filter.view === "week" && !forceList;
  const days = visibleWeek(filter);
  const from = weekly && days[0] > filter.from ? days[0] : filter.from;
  const to = weekly && days[6] < filter.to ? days[6] : filter.to;
  const bookings: OccupancyBooking[] = [];
  if (selectedRooms.length) {
    for (const month of reportMonths(from, to)) {
      const common = { p_user_id: weekly ? null : filter.userId };
      const active = await readAllPages<OccupancyBooking>((offset, last) => db.rpc("admin_monthly_active_booking_details", { p_month: month, ...common }, { count: "exact" })
        .gte("booking_date", from).lte("booking_date", to).in("room_name", selectedRooms.map(r => r.name))
        .order("booking_date").order("start_time").order("booking_id").range(offset, last).abortSignal(AbortSignal.timeout(20000)));
      bookings.push(...active.map(b => ({ ...b, status: "active" as const })));
      if (filter.cancelled && !weekly) {
        const cancelled = await readAllPages<OccupancyBooking>((offset, last) => db.rpc("admin_cancellation_details", { p_end_month: month, p_months: 1, ...common }, { count: "exact" })
          .gte("booking_date", from).lte("booking_date", to).in("room_name", selectedRooms.map(r => r.name))
          .order("booking_date").order("start_time").order("booking_id").range(offset, last).abortSignal(AbortSignal.timeout(20000)));
        bookings.push(...cancelled.map(b => ({ ...b, booking_title: null, status: "cancelled" as const })));
      }
      if (bookings.length > 20000) throw new Error("Túl sok találat. Szűkítsd az időszakot vagy a szobakijelölést.");
    }
  }
  const ids = new Set(bookings.map(b => b.booking_id));
  if (ids.size !== bookings.length) throw new Error("A foglalások közben változtak. Futtasd újra a lekérdezést.");
  bookings.sort((a,b) => a.booking_date.localeCompare(b.booking_date) || a.start_time.localeCompare(b.start_time) || a.room_name.localeCompare(b.room_name, "hu") || a.booking_id.localeCompare(b.booking_id));
  return { rooms, users, selectedRooms, opening, bookings };
}
