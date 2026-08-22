const MONTH_PATTERN = /^\d{4}-(0[1-9]|1[0-2])$/;

export type MonthlyHoursRow = {
  user_id: string;
  user_name: string;
  email: string;
  booking_count: number;
  total_minutes: number;
  total_hours: number | string;
};

export type MonthlyBookingDetail = {
  booking_id: string;
  user_id: string;
  user_name: string;
  booking_date: string;
  room_name: string;
  start_time: string;
  end_time: string;
  total_minutes: number;
  total_hours: number | string;
};

export function validMonth(value: string): boolean {
  return MONTH_PATTERN.test(value);
}

export function monthStart(value: string): string | null {
  return validMonth(value) ? `${value}-01` : null;
}

export function csvCell(value: string): string {
  const safe = /^[\s]*[=+\-@]/.test(value) ? `'${value}` : value;
  return `"${safe.replaceAll('"', '""')}"`;
}

export function decimalComma(value: number | string): string {
  const number = Number(value);
  return Number.isFinite(number) ? number.toFixed(2).replace(".", ",") : "0,00";
}

export function monthlyHoursCsv(rows: MonthlyHoursRow[]): string {
  const lines = [`${csvCell("Felhasználó")};${csvCell("Összes óra")}`];
  for (const row of rows) {
    lines.push(`${csvCell(row.user_name)};${decimalComma(row.total_hours)}`);
  }
  return `\uFEFF${lines.join("\r\n")}\r\n`;
}
