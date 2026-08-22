import { requireAdmin } from "@/lib/auth";
import { monthStart, monthlyHoursCsv, selectedMonths, type MonthlyHoursRow, type MonthlyHoursWithMonth } from "@/lib/monthly-hours";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: Request) {
  await requireAdmin();
  const url = new URL(request.url);
  const fallback = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit" }).format(new Date());
  const months = selectedMonths(url.searchParams.get("honapok") ?? url.searchParams.get("honap") ?? undefined, fallback);
  const supabase = await createClient();
  const rows: MonthlyHoursWithMonth[] = [];

  for (const month of months) {
    const response = await supabase.rpc("admin_monthly_booking_hours", { p_month: monthStart(month)! }).returns<MonthlyHoursRow[]>();
    if (response.error) return new Response("A havi óraszám exportálása nem sikerült. Hiányos export nem készül.", { status: 500 });
    for (const row of (response.data ?? []) as unknown as MonthlyHoursRow[]) rows.push({ ...row, month });
  }

  const csv = monthlyHoursCsv(rows);
  const suffix = months.length === 1 ? months[0] : `${months[0]}_${months.at(-1)}_${months.length}honap`;
  return new Response(csv, { headers: {
    "Content-Type": "text/csv; charset=utf-8",
    "Content-Disposition": `attachment; filename="a-hely-havi-orak-${suffix}.csv"`,
    "Cache-Control": "private, no-store",
  } });
}
