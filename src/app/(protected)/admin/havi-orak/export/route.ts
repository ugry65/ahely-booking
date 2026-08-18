import { requireAdmin } from "@/lib/auth";
import { monthStart, monthlyHoursCsv, type MonthlyHoursRow, validMonth } from "@/lib/monthly-hours";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: Request) {
  await requireAdmin();
  const month = new URL(request.url).searchParams.get("honap") ?? "";
  if (!validMonth(month)) return new Response("Érvénytelen elszámolási hónap.", { status: 400 });
  const supabase = await createClient();
  const response = await supabase.rpc("admin_monthly_booking_hours", { p_month: monthStart(month)! }).returns<MonthlyHoursRow[]>();
  if (response.error) return new Response("A havi óraszám exportálása nem sikerült.", { status: 500 });
  const csv = monthlyHoursCsv(month, (response.data ?? []) as unknown as MonthlyHoursRow[]);
  return new Response(csv, { headers: {
    "Content-Type": "text/csv; charset=utf-8",
    "Content-Disposition": `attachment; filename="a-hely-havi-orak-${month}.csv"`,
    "Cache-Control": "private, no-store",
  } });
}
