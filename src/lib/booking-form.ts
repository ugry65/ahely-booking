export type BookingUseType = "individual" | "group";
export type BookingRequest = { roomId: string; date: string; startAt: string; endAt: string; useType: BookingUseType; note: string | null };
export type BookingFormResult = { ok: true; value: BookingRequest } | { ok: false; error: string; date: string | null };

// PostgreSQL UUID: a seedelt, stabil üzleti azonosítók nem feltétlenül RFC-v4 UUID-k.
const UUID_PATTERN = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const TIME_PATTERN = /^(?:[01]\d|2[0-3]):(?:00|30)$/;

export function isValidDate(value: string): boolean {
  if (!DATE_PATTERN.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  return parsed.getUTCFullYear() === year && parsed.getUTCMonth() === month - 1 && parsed.getUTCDate() === day;
}
function minutes(time: string) { const [hour, minute] = time.split(":").map(Number); return hour * 60 + minute; }
function localParts(instant: Date) {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(instant);
  return Object.fromEntries(parts.map((part) => [part.type, part.value]));
}
export function budapestLocalToIso(date: string, time: string): string | null {
  if (!isValidDate(date) || !TIME_PATTERN.test(time)) return null;
  const [year, month, day] = date.split("-").map(Number);
  const [hour, minute] = time.split(":").map(Number);
  const wallClockAsUtc = Date.UTC(year, month - 1, day, hour, minute);
  const first = localParts(new Date(wallClockAsUtc));
  const representedAsUtc = Date.UTC(Number(first.year), Number(first.month) - 1, Number(first.day), Number(first.hour), Number(first.minute));
  const result = new Date(wallClockAsUtc - (representedAsUtc - wallClockAsUtc));
  const verified = localParts(result);
  if (`${verified.year}-${verified.month}-${verified.day}` !== date || `${verified.hour}:${verified.minute}` !== time) return null;
  return result.toISOString();
}
export function parseBookingForm(input: Record<string, string>): BookingFormResult {
  const roomId = input.roomId?.trim() ?? ""; const date = input.date?.trim() ?? "";
  const startTime = input.startTime?.trim() ?? ""; const endTime = input.endTime?.trim() ?? "";
  const useType = input.useType?.trim() ?? ""; const note = input.note?.trim() ?? "";
  if (!UUID_PATTERN.test(roomId) || !isValidDate(date) || !TIME_PATTERN.test(startTime) || !TIME_PATTERN.test(endTime) || (useType !== "individual" && useType !== "group"))
    return { ok: false, error: "A foglalási adatok hiányosak vagy érvénytelenek.", date: isValidDate(date) ? date : null };
  if (minutes(startTime) < 420 || minutes(endTime) > 1320)
    return { ok: false, error: "A foglalásnak 07:00 és 22:00 közé kell esnie.", date };
  if (minutes(endTime) - minutes(startTime) < 60)
    return { ok: false, error: "A foglalás legalább 60 perces legyen.", date };
  if (note.length > 1000) return { ok: false, error: "A megjegyzés legfeljebb 1000 karakteres lehet.", date };
  const startAt = budapestLocalToIso(date, startTime); const endAt = budapestLocalToIso(date, endTime);
  if (!startAt || !endAt) return { ok: false, error: "A kiválasztott helyi időpont nem értelmezhető.", date };
  return { ok: true, value: { roomId, date, startAt, endAt, useType, note: note || null } };
}
