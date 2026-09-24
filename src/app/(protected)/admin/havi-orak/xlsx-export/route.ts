import { requireAdmin } from "@/lib/auth";
import { monthStart, selectedMonths, type MonthlyHoursRow, type MonthlyHoursWithMonth } from "@/lib/monthly-hours";
import { monthlySettlementXlsx } from "@/lib/monthly-settlement-xlsx";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: Request) {
  await requireAdmin();
  const url = new URL(request.url);
  const fallback = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit" }).format(new Date());
  const months = selectedMonths(url.searchParams.get("honapok") ?? url.searchParams.get("honap") ?? undefined, fallback);
  const supabase = await createClient();
  const rows: MonthlyHoursWithMonth[] = [];

  for (const month of months) {
    const response = await supabase.rpc("admin_monthly_pricing_summary", { p_month: monthStart(month)! }).returns<MonthlyHoursRow[]>();
    if (response.error) return new Response("Az elszámolási összesítés Excel-exportja nem sikerült. Hiányos export nem készül.", { status: 500 });
    for (const row of (response.data ?? []) as unknown as MonthlyHoursRow[]) rows.push({ ...row, month });
  }

  const workbook = monthlySettlementXlsx(rows);
  const suffix = months.length === 1 ? months[0] : `${months[0]}_${months.at(-1)}_${months.length}honap`;
  const body = new Uint8Array(workbook).buffer;
  return new Response(body, { headers: {
    "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "Content-Disposition": `attachment; filename="a-hely-elszamolasi-osszesites-${suffix}.xlsx"`,
    "Cache-Control": "private, no-store",
  } });
}
