export type PreviewFrequency = "daily" | "weekly" | "biweekly" | "monthly";

function validDate(value: string) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(`${value}T00:00:00Z`));
}

function dateParts(value: string) {
  const [year, month, day] = value.split("-").map(Number);
  return { year, month, day };
}

function isoDate(date: Date) {
  return date.toISOString().slice(0, 10);
}

function addDays(value: string, days: number) {
  const { year, month, day } = dateParts(value);
  return isoDate(new Date(Date.UTC(year, month - 1, day + days)));
}

function addMonthsClamped(value: string, months: number) {
  const { year, month, day } = dateParts(value);
  const monthStart = new Date(Date.UTC(year, month - 1 + months, 1));
  const nextMonth = new Date(Date.UTC(monthStart.getUTCFullYear(), monthStart.getUTCMonth() + 1, 1));
  const lastDay = new Date(nextMonth.getTime() - 86_400_000).getUTCDate();
  return isoDate(new Date(Date.UTC(monthStart.getUTCFullYear(), monthStart.getUTCMonth(), Math.min(day, lastDay))));
}

export function recurringOccurrenceDate(firstDate: string, frequency: PreviewFrequency, zeroBasedIndex: number) {
  if (!validDate(firstDate) || zeroBasedIndex < 0 || !Number.isInteger(zeroBasedIndex)) return null;
  if (frequency === "daily") return addDays(firstDate, zeroBasedIndex);
  if (frequency === "weekly") return addDays(firstDate, zeroBasedIndex * 7);
  if (frequency === "biweekly") return addDays(firstDate, zeroBasedIndex * 14);
  if (frequency === "monthly") return addMonthsClamped(firstDate, zeroBasedIndex);
  return null;
}

export function buildRecurringOccurrenceDates(input: {
  firstDate: string;
  frequency: PreviewFrequency;
  endMode: "count" | "date";
  occurrenceCount?: number | null;
  endsOn?: string | null;
}) {
  if (!validDate(input.firstDate)) return [];
  if (input.endMode === "count") {
    const count = input.occurrenceCount ?? 0;
    if (!Number.isInteger(count) || count < 1 || count > 400) return [];
    return Array.from({ length: count }, (_, index) => recurringOccurrenceDate(input.firstDate, input.frequency, index)).filter((value): value is string => Boolean(value));
  }

  if (!input.endsOn || !validDate(input.endsOn) || input.endsOn < input.firstDate) return [];
  const dates: string[] = [];
  for (let index = 0; index < 400; index += 1) {
    const date = recurringOccurrenceDate(input.firstDate, input.frequency, index);
    if (!date || date > input.endsOn) break;
    dates.push(date);
  }
  return dates;
}
