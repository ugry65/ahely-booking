const MONTH_PATTERN = /^\d{4}-(0[1-9]|1[0-2])$/;

export type MonthlyHoursRow = {
  user_id: string;
  user_name: string;
  email: string;
  booking_count: number;
  total_minutes: number;
  total_hours: number | string;
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
};

export type MonthlyBookingDetailWithMonth = MonthlyBookingDetail & { month: string };

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
  const lines = [`${csvCell("Hónap")};${csvCell("Felhasználó")};${csvCell("Összes óra")}`];
  for (const row of rows) {
    lines.push(`${csvCell(row.month)};${csvCell(row.user_name)};${decimalComma(row.total_hours)}`);
  }
  return `\uFEFF${lines.join("\r\n")}\r\n`;
}

export function monthlyDetailsCsv(rows: MonthlyBookingDetailWithMonth[]): string {
  const header = ["Hónap", "Felhasználó", "Dátum", "Helyiség", "Foglalás címe", "Mettől", "Meddig", "Óra"];
  const lines = [header.map(csvCell).join(";")];
  for (const row of rows) {
    lines.push([
      row.month, row.user_name, row.booking_date, row.room_name, row.booking_title ?? "",
      row.start_time.slice(0, 5), row.end_time.slice(0, 5), decimalComma(row.total_hours),
    ].map(csvCell).join(";"));
  }
  return `\uFEFF${lines.join("\r\n")}\r\n`;
}
