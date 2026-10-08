import { isValidDate } from "./booking-form";

export type ReportRoom = { id: string; name: string; is_active: boolean };
export type OccupancyBooking = {
  booking_id: string; user_id: string; user_name: string; booking_date: string;
  room_name: string; booking_title: string | null; start_time: string; end_time: string;
  status: "active" | "cancelled";
};
export type ReportParams = Record<string, string | string[] | undefined>;
export type OccupancyFilter = {
  from: string; to: string; roomIds: string[]; userId: string | null;
  cancelled: boolean; view: "list" | "week"; week: string; page: number;
  start: number; end: number; duration: number; whole: boolean;
};
export const REPORT_PAGE_SIZE = 100;
const UUID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
export function one(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] : value; }
export function todayBudapest(now = new Date()) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
}
export function shiftDay(date: string, days: number) { return new Date(Date.parse(`${date}T12:00:00Z`) + days * 86400000).toISOString().slice(0, 10); }
export function dayDistance(from: string, to: string) { return Math.round((Date.parse(`${to}T12:00:00Z`) - Date.parse(`${from}T12:00:00Z`)) / 86400000); }
export function monday(date: string) { return shiftDay(date, -(new Date(`${date}T12:00:00Z`).getUTCDay() + 6) % 7); }
export function timeMinutes(time: string) { const [h, m] = time.split(":").map(Number); return h * 60 + m; }
export function timeLabel(minutes: number) { return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`; }
export function dateLabel(date: string, weekday = false) {
  return new Intl.DateTimeFormat("hu-HU", { timeZone: "UTC", year: "numeric", month: "2-digit", day: "2-digit", ...(weekday ? { weekday: "long" as const } : {}) }).format(new Date(`${date}T12:00:00Z`));
}
export function parseOccupancyFilter(params: ReportParams, today = todayBudapest()): OccupancyFilter {
  const from = one(params.from) ?? `${today.slice(0, 7)}-01`;
  const to = one(params.to) ?? shiftDay(`${today.slice(0, 7)}-01`, 32).slice(0, 7) + "-01";
  // Default through the last day of this month, inclusive.
  const endDate = params.to === undefined ? shiftDay(to, -1) : to;
  if (!isValidDate(from) || !isValidDate(endDate) || endDate < from || dayDistance(from, endDate) > 365)
    throw new Error("Érvényes kezdő és záró dátumot adj meg, legfeljebb 366 napra.");
  const roomIds = [...new Set((one(params.rooms) ?? "").split(",").filter(Boolean))];
  if (roomIds.length > 100 || roomIds.some(id => !UUID.test(id))) throw new Error("A szobakijelölés érvénytelen.");
  const userId = one(params.user) || null;
  if (userId && !UUID.test(userId)) throw new Error("A foglaló kiválasztása érvénytelen.");
  const startTime = one(params.start) ?? "14:00", endTime = one(params.end) ?? "19:00";
  const timePattern = /^(?:[01]\d|2[0-3]):(?:00|30)$/;
  const start = timeMinutes(startTime), end = timeMinutes(endTime), duration = Number(one(params.duration) ?? "120");
  if (!timePattern.test(startTime) || !timePattern.test(endTime) || start >= end || !Number.isInteger(duration) || duration < 60 || duration > 900 || duration % 30)
    throw new Error("A keresési idősáv és a legalább egyórás időtartam legyen érvényes, félórás lépésekben.");
  const weekValue = one(params.week);
  if (weekValue && !isValidDate(weekValue)) throw new Error("A hét dátuma érvénytelen.");
  const anchor = weekValue ?? (today >= from && today <= endDate ? today : from);
  const clamped = anchor < from ? from : anchor > endDate ? endDate : anchor;
  const page = Number(one(params.page) ?? "1");
  if (!Number.isSafeInteger(page) || page < 1 || page > 200) throw new Error("Érvénytelen oldalszám.");
  return { from, to: endDate, roomIds, userId, cancelled: one(params.cancelled) === "1", view: one(params.view) === "week" ? "week" : "list", week: monday(clamped), page, start, end, duration, whole: one(params.whole) === "1" };
}
export function filterQuery(filter: OccupancyFilter, patch: Partial<OccupancyFilter> = {}) {
  const f = { ...filter, ...patch };
  const q = new URLSearchParams({ from: f.from, to: f.to, rooms: f.roomIds.join(","), view: f.view, week: f.week, page: String(f.page), start: timeLabel(f.start), end: timeLabel(f.end), duration: String(f.duration) });
  if (f.userId) q.set("user", f.userId);
  if (f.cancelled) q.set("cancelled", "1");
  if (f.whole) q.set("whole", "1");
  return q.toString();
}
export function reportMonths(from: string, to: string) {
  const result: string[] = []; let month = `${from.slice(0, 7)}-01`;
  while (month <= to) { result.push(month); month = shiftDay(month, 32).slice(0, 7) + "-01"; }
  return result;
}
export function visibleWeek(filter: OccupancyFilter) {
  return Array.from({ length: 7 }, (_, i) => shiftDay(filter.week, i));
}
export function freeIntervals(bookings: OccupancyBooking[], date: string, roomName: string, start: number, end: number) {
  const occupied = bookings.filter(b => b.status === "active" && b.booking_date === date && b.room_name === roomName)
    .map(b => ({ start: Math.max(start, timeMinutes(b.start_time)), end: Math.min(end, timeMinutes(b.end_time)) }))
    .filter(b => b.end > b.start).sort((a, b) => a.start - b.start);
  const free: Array<{ start: number; end: number }> = []; let cursor = start;
  for (const b of occupied) { if (b.start > cursor) free.push({ start: cursor, end: b.start }); cursor = Math.max(cursor, b.end); }
  if (cursor < end) free.push({ start: cursor, end });
  return free;
}
export function freeMatches(bookings: OccupancyBooking[], date: string, room: ReportRoom, filter: OccupancyFilter, opening: { start: number; end: number }) {
  if (!room.is_active) return [];
  // A fully free requested window must also be entirely within opening hours.
  if (filter.whole && (filter.start < opening.start || filter.end > opening.end)) return [];
  const start = Math.max(filter.start, opening.start), end = Math.min(filter.end, opening.end);
  if (end <= start) return [];
  return freeIntervals(bookings, date, room.name, start, end).filter(gap => filter.whole ? gap.start === filter.start && gap.end === filter.end : gap.end - gap.start >= filter.duration);
}
// Exact-count paging avoids Supabase's default row cap silently producing false availability.
export async function readAllPages<T>(read: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: unknown; count: number | null }>, maximum = 20000): Promise<T[]> {
  const all: T[] = []; let expected: number | null = null;
  for (let offset = 0; offset <= maximum;) {
    const result = await read(offset, offset + 499);
    if (result.error || result.count === null || !result.data) throw new Error("A lekérdezés nem sikerült. Hiányos foglaltsági eredmény nem jeleníthető meg.");
    if (result.count > maximum) throw new Error("Túl sok találat. Szűkítsd az időszakot vagy a szobakijelölést.");
    if (expected !== null && result.count !== expected) throw new Error("A foglalások közben változtak. Futtasd újra a lekérdezést.");
    expected = result.count; all.push(...result.data);
    if (all.length === expected) return all;
    if (!result.data.length || all.length > expected) break;
    offset += result.data.length;
  }
  throw new Error("Hiányos foglaltsági eredmény. Futtasd újra a lekérdezést.");
}
