export const BUDAPEST_TIME_ZONE = "Europe/Budapest";

export type BookingDateLike = {
  booking_id: string;
  start_at: string;
};

function pad(value: number) {
  return String(value).padStart(2, "0");
}

function civilParts(date: string) {
  const [year, month, day] = date.split("-").map(Number);
  return { year, month, day };
}

function civilDate(year: number, month: number, day: number) {
  return `${year}-${pad(month)}-${pad(day)}`;
}

function utcDateForCivil(date: string) {
  const { year, month, day } = civilParts(date);
  return new Date(Date.UTC(year, month - 1, day, 12, 0, 0));
}

export function isValidCivilDate(value: string | undefined): value is string {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const { year, month, day } = civilParts(value);
  const parsed = new Date(Date.UTC(year, month - 1, day, 12, 0, 0));
  return parsed.getUTCFullYear() === year && parsed.getUTCMonth() === month - 1 && parsed.getUTCDate() === day;
}

export function addDays(date: string, amount: number) {
  const parsed = utcDateForCivil(date);
  parsed.setUTCDate(parsed.getUTCDate() + amount);
  return civilDate(parsed.getUTCFullYear(), parsed.getUTCMonth() + 1, parsed.getUTCDate());
}

export function shiftMonth(date: string, amount: number) {
  const { year, month, day } = civilParts(date);
  const targetFirst = new Date(Date.UTC(year, month - 1 + amount, 1, 12, 0, 0));
  const targetYear = targetFirst.getUTCFullYear();
  const targetMonth = targetFirst.getUTCMonth() + 1;
  const lastDay = new Date(Date.UTC(targetYear, targetMonth, 0, 12, 0, 0)).getUTCDate();
  return civilDate(targetYear, targetMonth, Math.min(day, lastDay));
}

export function monthGrid(date: string) {
  const { year, month } = civilParts(date);
  const first = civilDate(year, month, 1);
  const weekday = utcDateForCivil(first).getUTCDay();
  const mondayOffset = (weekday + 6) % 7;
  const start = addDays(first, -mondayOffset);
  return Array.from({ length: 42 }, (_, index) => addDays(start, index));
}

function budapestParts(iso: string) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: BUDAPEST_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(iso));
  return Object.fromEntries(parts.map((part) => [part.type, part.value]));
}

export function budapestDateFromIso(iso: string) {
  const parts = budapestParts(iso);
  return `${parts.year}-${parts.month}-${parts.day}`;
}

export function budapestTimeFromIso(iso: string) {
  const parts = budapestParts(iso);
  return `${parts.hour}:${parts.minute}`;
}

export function budapestToday(now = new Date()) {
  return budapestDateFromIso(now.toISOString());
}

export function civilDateLabel(date: string, options: Intl.DateTimeFormatOptions) {
  return new Intl.DateTimeFormat("hu-HU", { ...options, timeZone: "UTC" }).format(utcDateForCivil(date));
}

export function groupBookingsByBudapestDate<T extends BookingDateLike>(bookings: T[]) {
  const grouped: Record<string, T[]> = {};
  for (const booking of [...bookings].sort((a, b) => a.start_at.localeCompare(b.start_at))) {
    const date = budapestDateFromIso(booking.start_at);
    (grouped[date] ??= []).push(booking);
  }
  return grouped;
}

export function minutesFromTime(value: string) {
  const [hours, minutes] = value.split(":").map(Number);
  return hours * 60 + minutes;
}
