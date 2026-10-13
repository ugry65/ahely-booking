import "server-only";
import { requireActiveProfile } from "./auth";
import { createClient } from "./supabase/server";
import { readAllPages } from "./room-occupancy";
import { localPeriod, periodChunks, validateCalendarBookings, type CalendarRoom, type RoomCalendarBooking, type RoomCalendarFilter } from "./room-calendar";

export async function loadRoomCalendar(filter: RoomCalendarFilter) {
  const profile = await requireActiveProfile();
  const db = await createClient();
  const [roomsResult, settingsResult, ownResult] = await Promise.all([
    db.rpc("list_bookable_rooms"),
    db.from("app_settings").select("key,value").in("key", ["opening_time", "closing_time", "default_advance_booking_days", "training_room_advance_days"]),
    db.from("profiles").select("advance_booking_days_override").eq("id", profile.id).maybeSingle(),
  ]);
  if (roomsResult.error || settingsResult.error || ownResult.error || !roomsResult.data || !settingsResult.data || !ownResult.data)
    throw new Error("A szobák és foglalási beállítások betöltése nem sikerült. Frissítsd az oldalt.");
  const rooms = roomsResult.data as CalendarRoom[];
  const room = filter.roomId ? rooms.find(r => r.room_id === filter.roomId) : rooms[0];
  if (filter.roomId && !room) throw new Error("A kiválasztott szobához nincs hozzáférésed.");
  const value = (key: string) => settingsResult.data.find(s => s.key === key)?.value;
  const open = value("opening_time"), close = value("closing_time");
  const time = /^(?:[01]\d|2[0-3]):(?:00|30)(?::00)?$/;
  if (typeof open !== "string" || typeof close !== "string" || !time.test(open) || !time.test(close)) throw new Error("Hiányos nyitvatartási beállítás.");
  const minutes = (s: string) => Number(s.slice(0,2))*60 + Number(s.slice(3,5));
  const opening = { start: minutes(open), end: minutes(close) };
  const defaultDays = value("default_advance_booking_days"), trainingDays = value("training_room_advance_days");
  const override = ownResult.data.advance_booking_days_override as number | null;
  if (opening.end <= opening.start || !Number.isSafeInteger(defaultDays) || Number(defaultDays) < 0 || !Number.isSafeInteger(trainingDays) || Number(trainingDays) < 0 || (override !== null && (!Number.isSafeInteger(override) || override < 0)))
    throw new Error("Hiányos foglalási beállítás. Frissítsd az oldalt.");
  const bookings: RoomCalendarBooking[] = [];
  if (room) for (const chunk of periodChunks(filter.from, filter.to)) {
    const rows = await readAllPages<RoomCalendarBooking>((from,to) => db.rpc("list_calendar_bookings", localPeriod(chunk.from, chunk.to), { count: "exact" })
      .eq("room_id", room.room_id).order("start_at").order("booking_id").range(from,to).abortSignal(AbortSignal.timeout(20000)));
    bookings.push(...rows);
    if (bookings.length > 20000) throw new Error("Túl sok találat; szűkítsd a dátumtartományt.");
  }
  if (room) validateCalendarBookings(bookings, room.room_id);
  return { rooms, room, bookings, opening, defaultDays: Number(defaultDays), trainingDays: Number(trainingDays), override, profile };
}
