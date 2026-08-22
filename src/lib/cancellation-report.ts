import { csvCell, decimalComma } from "./monthly-hours";

export const CANCELLATION_PERIODS = [1, 3, 6, 12] as const;
export type CancellationPeriod = (typeof CANCELLATION_PERIODS)[number];

export type CancellationSummaryRow = {
  user_id: string;
  user_name: string;
  total_bookings: number;
  cancelled_count: number;
  cancelled_hours: number | string;
  user_cancelled_count: number;
  user_cancelled_hours: number | string;
  cancellation_rate: number | string;
};

export type CancellationDetailRow = {
  booking_id: string;
  user_id: string;
  user_name: string;
  booking_date: string;
  room_name: string;
  start_time: string;
  end_time: string;
  cancelled_hours: number | string;
  cancelled_at: string;
  minutes_before_start: number;
  cancellation_reason: string | null;
  cancelled_by_user: boolean;
  cancelled_by_name: string;
};

export function cancellationPeriod(value: string | undefined): CancellationPeriod {
  const parsed = Number(value);
  return CANCELLATION_PERIODS.includes(parsed as CancellationPeriod) ? parsed as CancellationPeriod : 3;
}

export function leadTimeLabel(minutes: number): string {
  const absolute = Math.abs(minutes);
  const days = Math.floor(absolute / 1440);
  const hours = Math.floor((absolute % 1440) / 60);
  const mins = absolute % 60;
  const prefix = minutes < 0 ? "kezdés után " : "";
  if (days > 0) return `${prefix}${days} nap ${hours} óra`;
  if (hours > 0) return `${prefix}${hours} óra ${mins} perc`;
  return `${prefix}${mins} perc`;
}

function budapestTimestamp(value: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Budapest", year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hourCycle: "h23",
  }).formatToParts(new Date(value));
  const part = (type: Intl.DateTimeFormatPartTypes) => parts.find((item) => item.type === type)?.value ?? "";
  return `${part("year")}-${part("month")}-${part("day")} ${part("hour")}:${part("minute")}`;
}

export function cancellationSummaryCsv(rows: CancellationSummaryRow[]): string {
  const header = ["Felhasználó", "Összes foglalás", "Törölt foglalás", "Törölt óra", "User saját törlése", "User saját törölt órája", "Lemondási arány %"];
  const lines = [header.map(csvCell).join(";")];
  for (const row of rows) {
    lines.push([
      row.user_name, String(row.total_bookings), String(row.cancelled_count), decimalComma(row.cancelled_hours),
      String(row.user_cancelled_count), decimalComma(row.user_cancelled_hours), decimalComma(row.cancellation_rate),
    ].map(csvCell).join(";"));
  }
  return `\uFEFF${lines.join("\r\n")}\r\n`;
}

export function cancellationDetailsCsv(rows: CancellationDetailRow[]): string {
  const header = ["Felhasználó", "Dátum", "Helyiség", "Mettől", "Meddig", "Törölt óra", "Lemondás ideje", "Mennyivel előtte", "Lemondta", "Indok"];
  const lines = [header.map(csvCell).join(";")];
  for (const row of rows) {
    lines.push([
      row.user_name, row.booking_date, row.room_name, row.start_time.slice(0, 5), row.end_time.slice(0, 5),
      decimalComma(row.cancelled_hours), budapestTimestamp(row.cancelled_at), leadTimeLabel(row.minutes_before_start),
      `${row.cancelled_by_name} (${row.cancelled_by_user ? "user" : "admin"})`, row.cancellation_reason ?? "",
    ].map(csvCell).join(";"));
  }
  return `\uFEFF${lines.join("\r\n")}\r\n`;
}
