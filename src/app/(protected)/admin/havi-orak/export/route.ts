import { requireAdmin } from "@/lib/auth";
import { mergeBookingTitles, monthStart, monthlyHoursCsv, selectedMonths, type MonthlyActiveBookingTitle, type MonthlyBookingDetail, type MonthlyBookingDetailWithMonth, type MonthlyHoursRow, type MonthlyHoursWithMonth } from "@/lib/monthly-hours";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: Request) {
  await requireAdmin();
  const url = new URL(request.url);
  const fallback = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit" }).format(new Date());
  const months = selectedMonths(url.searchParams.get("honapok") ?? url.searchParams.get("honap") ?? undefined, fallback);
  const supabase = await createClient();
  const rows: MonthlyHoursWithMonth[] = [];
  const details: MonthlyBookingDetailWithMonth[] = [];

  for (const month of months) {
    const response = await supabase.rpc("admin_monthly_pricing_summary", { p_month: monthStart(month)! }).returns<MonthlyHoursRow[]>();
    if (response.error) return new Response("A havi óraszám exportálása nem sikerült. Hiányos export nem készül.", { status: 500 });
    for (const row of (response.data ?? []) as unknown as MonthlyHoursRow[]) rows.push({ ...row, month });
    const [pricingResponse, titleResponse] = await Promise.all([
      supabase.rpc("admin_monthly_pricing_details", { p_month: monthStart(month)!, p_user_id: null }),
      supabase.rpc("admin_monthly_active_booking_details", { p_month: monthStart(month)!, p_user_id: null }),
    ]);
    if (pricingResponse.error || titleResponse.error) {
      return new Response("Az alkalmi foglalók részleteinek exportálása nem sikerült. Hiányos export nem készül.", { status: 500 });
    }
    const enriched = mergeBookingTitles(
      (pricingResponse.data ?? []) as unknown as Omit<MonthlyBookingDetail, "booking_title">[],
      (titleResponse.data ?? []) as unknown as MonthlyActiveBookingTitle[],
    );
    for (const detail of enriched) details.push({ ...detail, month });
  }

  const csv = monthlyHoursCsv(rows, details);
  const suffix = months.length === 1 ? months[0] : `${months[0]}_${months.at(-1)}_${months.length}honap`;
  return new Response(csv, { headers: {
    "Content-Type": "text/csv; charset=utf-8",
    "Content-Disposition": `attachment; filename="a-hely-havi-orak-${suffix}.csv"`,
    "Cache-Control": "private, no-store",
  } });
}
