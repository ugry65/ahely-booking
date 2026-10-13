import { budapestLocalToIso, isValidDate } from "./booking-form";
import { addDays, budapestDateFromIso, budapestTimeFromIso, minutesFromTime, shiftMonth, groupBookingsByBudapestDate } from "./my-bookings-calendar";
import { dayDistance, timeLabel } from "./room-occupancy";

export type CalendarRoom = { room_id: string; room_name: string; is_training_room: boolean; display_order: number };
export type RoomCalendarBooking = {
  booking_id: string; room_id: string; room_name: string; start_at: string; end_at: string;
  use_type: "individual" | "group"; is_own: boolean; booker_display_name: string | null;
  booking_title: string | null; booker_color: string | null;
};
export type RoomCalendarFilter = {
  view: "month" | "list"; roomId: string; date: string; from: string; to: string;
  kind: "bookings" | "free"; start: number; end: number; duration: number; weekday: string;
};
export type FreeSlot = { date: string; start: number; end: number };
export type BookingPreset = { roomId: string; startTime: string; endTime: string };
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const time = /^(?:[01]\d|2[0-3]):(?:00|30)$/;
export function parseRoomCalendarFilter(params: Record<string, string | undefined>, today: string): RoomCalendarFilter {
  const suppliedDate = params.datum ?? today;
  if (params.month && !/^\d{4}-\d{2}$/.test(params.month)) throw new Error("Adj meg érvényes hónapot.");
  const date = params.month && params.month !== suppliedDate.slice(0,7) ? `${params.month}-01` : suppliedDate;
  if (!isValidDate(date)) throw new Error("Adj meg érvényes dátumot.");
  const first = `${date.slice(0, 7)}-01`;
  const view = params.view === "list" ? "list" : "month";
  const from = view === "month" ? first : params.from ?? first;
  const to = view === "month" ? addDays(shiftMonth(first, 1), -1) : params.to ?? addDays(shiftMonth(first, 1), -1);
  if (!isValidDate(from) || !isValidDate(to) || to < from || dayDistance(from, to) > 365)
    throw new Error("Érvényes dátumtartományt adj meg, legfeljebb 366 napra.");
  const roomId = params.room ?? "";
  if (roomId && !uuid.test(roomId)) throw new Error("Érvénytelen szobakijelölés.");
  const startTime = params.start ?? "07:00", endTime = params.end ?? "22:00";
  const start = minutesFromTime(startTime), end = minutesFromTime(endTime);
  const duration = Number(params.duration ?? "60"), weekday = params.weekday ?? "";
  if (!time.test(startTime) || !time.test(endTime) || end <= start || start < 420 || end > 1320 ||
      !Number.isInteger(duration) || duration < 60 || duration > 900 || duration % 30 || !/^[0-6]?$/.test(weekday))
    throw new Error("Az idősáv 07:00–22:00 közé essen; az időtartam legalább 1 óra, félórás lépésekben.");
  return { view, roomId, date, from, to, kind: params.kind === "free" ? "free" : "bookings", start, end, duration, weekday };
}
export function roomCalendarUrl(filter: RoomCalendarFilter, patch: Partial<RoomCalendarFilter> = {}) {
  const f = { ...filter, ...patch };
  return `/foglalasok?${new URLSearchParams({ view: f.view, room: f.roomId, datum: f.date, from: f.from, to: f.to, kind: f.kind, start: timeLabel(f.start), end: timeLabel(f.end), duration: String(f.duration), weekday: f.weekday })}`;
}
export function periodChunks(from: string, to: string) {
  const chunks: Array<{ from: string; to: string }> = [];
  for (let cursor = from; cursor <= to;) {
    const end = addDays(cursor, 30) < to ? addDays(cursor, 30) : to;
    chunks.push({ from: cursor, to: end }); cursor = addDays(end, 1);
  }
  return chunks;
}
export function dayBookings(bookings: RoomCalendarBooking[], date: string) {
  return bookings.filter(b => budapestDateFromIso(b.start_at) === date).sort((a,b) => a.start_at.localeCompare(b.start_at));
}
export function bookingMinutes(b: RoomCalendarBooking) {
  return { start: minutesFromTime(budapestTimeFromIso(b.start_at)), end: minutesFromTime(budapestTimeFromIso(b.end_at)) };
}
export function freeRoomSlots(bookings: RoomCalendarBooking[], filter: RoomCalendarFilter, opening: { start: number; end: number }) {
  const slots: FreeSlot[] = [];
  const grouped = groupBookingsByBudapestDate(bookings.filter(b => b.room_id === filter.roomId));
  const start = Math.max(filter.start, opening.start), end = Math.min(filter.end, opening.end);
  if (end <= start) return slots;
  for (let date = filter.from; date <= filter.to; date = addDays(date, 1)) {
    if (filter.weekday && String(new Date(`${date}T12:00:00Z`).getUTCDay()) !== filter.weekday) continue;
    let cursor = start;
    const occupied = (grouped[date] ?? []).map(bookingMinutes);
    for (const b of occupied) {
      const a = Math.max(start, b.start), z = Math.min(end, b.end);
      if (z <= a) continue;
      if (a - cursor >= filter.duration) slots.push({ date, start: cursor, end: a });
      cursor = Math.max(cursor, z);
    }
    if (end - cursor >= filter.duration) slots.push({ date, start: cursor, end });
  }
  return slots;
}
export function advanceLimit(role: "admin" | "user", room: CalendarRoom, defaults: number, training: number, override: number | null) {
  if (role === "admin") return null;
  const normal = override ?? defaults;
  return room.is_training_room ? Math.min(normal, training) : normal;
}
export function slotBookingLink(roomId: string, slot: FreeSlot, duration: number, today: string, limit: number | null, now = new Date()): { href: string | null; reason: string | null } {
  if (limit !== null && slot.date > addDays(today, limit)) return { href: null, reason: "Az előrefoglalási határon túl" };
  const localNow = minutesFromTime(budapestTimeFromIso(now.toISOString()));
  // Only future half-hour boundaries are proposed for today's remaining free time.
  const start = slot.date === today ? Math.max(slot.start, (Math.floor(localNow / 30) + 1) * 30) : slot.start;
  if (slot.date < today || slot.end - start < duration) return { href: null, reason: "Már nem foglalható időszak" };
  return { href: `/foglalasok?${new URLSearchParams({ datum: slot.date, room: roomId, start: timeLabel(start), end: timeLabel(start + duration), new: "1" })}`, reason: null };
}
export function parseBookingPreset(params: Record<string, string | undefined>, rooms: CalendarRoom[]): BookingPreset | undefined {
  if (params.new !== "1" || !rooms.some(r => r.room_id === params.room)) return undefined;
  if (!time.test(params.start ?? "") || !time.test(params.end ?? "")) return undefined;
  const start = minutesFromTime(params.start!), end = minutesFromTime(params.end!);
  if (start < 420 || end > 1320 || end - start < 60) return undefined;
  return { roomId: params.room!, startTime: params.start!, endTime: params.end! };
}
export function validateCalendarBookings(bookings: RoomCalendarBooking[], roomId: string) {
  const ids = new Set<string>();
  for (const b of bookings) {
    if (b.room_id !== roomId || !b.booking_id || ids.has(b.booking_id) || !Number.isFinite(Date.parse(b.start_at)) || !Number.isFinite(Date.parse(b.end_at)) || Date.parse(b.end_at) <= Date.parse(b.start_at))
      throw new Error("Hiányos vagy közben megváltozott foglaltsági adatok. Frissítsd az oldalt.");
    if (budapestDateFromIso(b.start_at) !== budapestDateFromIso(b.end_at)) throw new Error("Érvénytelen foglalási időszak.");
    const m = bookingMinutes(b);
    if (m.end <= m.start || m.start % 30 || m.end % 30) throw new Error("Érvénytelen foglalási időpont.");
    ids.add(b.booking_id);
  }
}
export function localPeriod(from: string, to: string) {
  return { p_start_at: budapestLocalToIso(from, "00:00"), p_end_at: budapestLocalToIso(addDays(to, 1), "00:00") };
}
