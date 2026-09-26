const MONTH_PATTERN = /^\d{4}-(0[1-9]|1[0-2])$/;

export type MonthlyHoursRow = {
  user_id: string;
  user_name: string;
  email: string;
  booking_count: number;
  total_minutes: number;
  total_hours: number | string;
  normal_minutes: number;
  special_minutes: number;
  calculated_due_huf: number;
  pricing_state: "live" | "snapshot";
  revision_id: string | null;
  revision_number: number | null;
};

export type MonthlyHoursWithMonth = MonthlyHoursRow & { month: string };

export type MonthlyBookingDetail = {
  booking_id: string;
  user_id: string;
  user_name: string;
  booking_date: string;
  room_name: string;
  booking_title: string | null;
  start_time: string;
  end_time: string;
  total_minutes: number;
  total_hours: number | string;
  rate_source: "booking_override" | "user_override" | "central_tier" | "training_room";
  hourly_rate_huf: number;
  amount_huf: number;
  pricing_state: "live" | "snapshot";
  revision_number: number | null;
};

export type MonthlyBookingDetailWithMonth = MonthlyBookingDetail & { month: string };

export type MonthlyActiveBookingTitle = {
  booking_id: string;
  booking_title: string | null;
};

export function mergeBookingTitles<T extends { booking_id: string }>(
  rows: T[],
  titles: MonthlyActiveBookingTitle[],
): Array<T & { booking_title: string | null }> {
  const titleByBookingId = new Map(titles.map((row) => [row.booking_id, row.booking_title]));
  return rows.map((row) => ({ ...row, booking_title: titleByBookingId.get(row.booking_id) ?? null }));
}

export function validMonth(value: string): boolean {
  return MONTH_PATTERN.test(value);
}

export function monthStart(value: string): string | null {
  return validMonth(value) ? `${value}-01` : null;
}

export function selectedMonths(value: string | undefined, fallback: string): string[] {
  const months = Array.from(new Set((value ?? "").split(",").map((item) => item.trim()).filter(validMonth))).sort();
  return months.length ? months : [fallback];
}

export function csvCell(value: string): string {
  const safe = /^[\s]*[=+\-@]/.test(value) ? `'${value}` : value;
  return `"${safe.replaceAll('"', '""')}"`;
}

export function decimalComma(value: number | string): string {
  const number = Number(value);
  return Number.isFinite(number) ? number.toFixed(2).replace(".", ",") : "0,00";
}

export function monthlyHoursCsv(rows: MonthlyHoursWithMonth[]): string {
  const header = ["Hónap", "Felhasználó", "Összes óra", "Normál óra", "Tréningterem csoportos óra", "Fizetendő Ft", "Állapot", "Revision"];
  const lines = [header.map(csvCell).join(";")];
  for (const row of rows) {
    lines.push([
      row.month, row.user_name, decimalComma(row.total_hours), decimalComma(row.normal_minutes / 60),
      decimalComma(row.special_minutes / 60), String(row.calculated_due_huf),
      row.pricing_state === "snapshot" ? "Snapshot" : "Élő előnézet", row.revision_number ? String(row.revision_number) : "",
    ].map(csvCell).join(";"));
  }
  return `\uFEFF${lines.join("\r\n")}\r\n`;
}

export function monthlyDetailsCsv(rows: MonthlyBookingDetailWithMonth[]): string {
  const header = ["Hónap", "Felhasználó", "Dátum", "Helyiség", "Foglalás címe", "Mettől", "Meddig", "Óra", "Árforrás", "Óradíj Ft", "Összeg Ft", "Állapot", "Revision"];
  const lines = [header.map(csvCell).join(";")];
  for (const row of rows) {
    lines.push([
      row.month, row.user_name, row.booking_date, row.room_name, row.booking_title ?? "",
      row.start_time.slice(0, 5), row.end_time.slice(0, 5), decimalComma(row.total_hours), row.rate_source,
      String(row.hourly_rate_huf), String(row.amount_huf), row.pricing_state === "snapshot" ? "Snapshot" : "Élő előnézet",
      row.revision_number ? String(row.revision_number) : "",
    ].map(csvCell).join(";"));
  }
  return `\uFEFF${lines.join("\r\n")}\r\n`;
}
