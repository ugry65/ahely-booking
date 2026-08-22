import { isValidDate, parseBookingForm, type BookingUseType } from "./booking-form";

export type RecurrenceFrequency = "daily" | "weekly" | "biweekly" | "monthly";
export type ConflictPolicy = "abort_all" | "create_available";
export type RecurringBookingRequest = {
  roomId: string; firstStartAt: string; firstEndAt: string; frequency: RecurrenceFrequency;
  endsOn: string | null; occurrenceCount: number | null; exceptionDates: string[];
  conflictPolicy: ConflictPolicy; useType: BookingUseType; note: string | null; bookingTitle: string | null;
  idempotencyKey: string; date: string;
};
export type RecurringFormResult = { ok: true; value: RecurringBookingRequest } | { ok: false; error: string };

function dayDistance(from: string, to: string) { return (Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000; }
function shiftDate(date: string, days: number) {
  const [year, month, day] = date.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}
function occurrenceDate(firstDate: string, frequency: RecurrenceFrequency, zeroBasedIndex: number) {
  if (frequency === "daily") return shiftDate(firstDate, zeroBasedIndex);
  if (frequency === "weekly") return shiftDate(firstDate, zeroBasedIndex * 7);
  if (frequency === "biweekly") return shiftDate(firstDate, zeroBasedIndex * 14);

  const [year, month, day] = firstDate.split("-").map(Number);
  const targetMonth = new Date(Date.UTC(year, month - 1 + zeroBasedIndex, 1));
  const targetYear = targetMonth.getUTCFullYear();
  const targetMonthIndex = targetMonth.getUTCMonth();
  const lastDay = new Date(Date.UTC(targetYear, targetMonthIndex + 1, 0)).getUTCDate();
  return new Date(Date.UTC(targetYear, targetMonthIndex, Math.min(day, lastDay))).toISOString().slice(0, 10);
}

export function parseRecurringBookingForm(input: Record<string, string>): RecurringFormResult {
  const base = parseBookingForm(input);
  if (!base.ok) return { ok: false, error: base.error };
  const frequency = input.frequency?.trim() as RecurrenceFrequency;
  const conflictPolicy = input.conflictPolicy?.trim() as ConflictPolicy;
  const endMode = input.endMode?.trim();
  if (!["daily", "weekly", "biweekly", "monthly"].includes(frequency) || !["abort_all", "create_available"].includes(conflictPolicy) || !["date", "count"].includes(endMode))
    return { ok: false, error: "Az ismétlődési adatok hiányosak vagy érvénytelenek." };

  let endsOn: string | null = null; let occurrenceCount: number | null = null;
  if (endMode === "date") {
    endsOn = input.endsOn?.trim() ?? "";
    if (!isValidDate(endsOn) || dayDistance(base.value.date, endsOn) < 0 || dayDistance(base.value.date, endsOn) > 366)
      return { ok: false, error: "A végdátum az első alkalomtól számított 366 napon belül legyen." };
  } else {
    const rawCount = input.occurrenceCount?.trim() ?? "";
    occurrenceCount = Number(rawCount);
    if (!/^\d+$/.test(rawCount) || !Number.isInteger(occurrenceCount) || occurrenceCount < 1 || occurrenceCount > 400)
      return { ok: false, error: "Az ismétlésszám 1 és 400 közötti egész szám legyen." };
    const lastOccurrence = occurrenceDate(base.value.date, frequency, occurrenceCount - 1);
    if (dayDistance(base.value.date, lastOccurrence) > 366)
      return { ok: false, error: "Az ismétlésszám legfeljebb 366 napos sorozatot eredményezhet." };
  }

  const rawExceptions = input.exceptionDates?.trim() ?? "";
  const exceptionDates = [...new Set(rawExceptions.split(/[\s,;]+/).filter(Boolean))].sort();
  if (exceptionDates.length > 100 || exceptionDates.some((date) => !isValidDate(date) || dayDistance(base.value.date, date) < 0 || (endsOn !== null && date > endsOn)))
    return { ok: false, error: "A kivételdátumok érvénytelenek vagy a sorozat időtartamán kívül esnek." };

  return { ok: true, value: {
    roomId: base.value.roomId, firstStartAt: base.value.startAt, firstEndAt: base.value.endAt,
    frequency, endsOn, occurrenceCount, exceptionDates, conflictPolicy,
    useType: base.value.useType, note: base.value.note, bookingTitle: base.value.bookingTitle, idempotencyKey: base.value.idempotencyKey,
    date: base.value.date,
  } };
}
