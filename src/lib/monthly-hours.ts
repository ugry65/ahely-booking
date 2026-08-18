const MONTH_PATTERN = /^\d{4}-(0[1-9]|1[0-2])$/;

export type MonthlyHoursRow = {
  user_id: string;
  user_name: string;
  email: string;
  booking_count: number;
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

export function monthlyHoursCsv(month: string, rows: MonthlyHoursRow[]): string {
  const header = ["Hónap", "Felhasználó", "E-mail", "Foglalások száma", "Összes perc", "Összes óra"];
  const lines = [header.map(csvCell).join(";")];
  for (const row of rows) {
    lines.push([
      month, row.user_name, row.email, String(row.booking_count),
      String(row.total_minutes), String(row.total_hours),
    ].map(csvCell).join(";"));
  }
  return `\uFEFF${lines.join("\r\n")}\r\n`;
}
