import { requireAdmin } from "@/lib/auth";
import { mergeBookingTitles, monthStart, selectedMonths, type MonthlyActiveBookingTitle, type MonthlyBookingDetail, type MonthlyBookingDetailWithMonth, type MonthlyHoursRow, type MonthlyHoursWithMonth } from "@/lib/monthly-hours";
import { monthlySettlementXlsx } from "@/lib/monthly-settlement-xlsx";
import { createClient } from "@/lib/supabase/server";
import { mergePaymentBalances, type MonthlyPaymentBalance } from "@/lib/booking-payments";

export async function GET(request: Request) {
  await requireAdmin();
  const url = new URL(request.url);
  const fallback = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit" }).format(new Date());
  const months = selectedMonths(url.searchParams.get("honapok") ?? url.searchParams.get("honap") ?? undefined, fallback);
  const supabase = await createClient();
  const rows: MonthlyHoursWithMonth[] = [];
  const details: MonthlyBookingDetailWithMonth[] = [];

  for (const month of months) {
    const response = await supabase.rpc("admin_payment_pricing_summary", { p_month: monthStart(month)! }).returns<MonthlyHoursRow[]>();
    if (response.error) return new Response("Az elszámolási összesítés Excel-exportja nem sikerült. Hiányos export nem készül.", { status: 500 });
    const balances = await supabase.rpc("admin_monthly_booking_payment_summary", { p_month: monthStart(month)! });
    if (balances.error) return new Response("A befizetési összesítés nem tölthető be. Hiányos export nem készül.", { status: 500 });
    try {
      const pricing = (response.data ?? []) as unknown as MonthlyHoursRow[];
      const financial = (balances.data ?? []) as unknown as MonthlyPaymentBalance[];
      for (const row of mergePaymentBalances(pricing, financial)) rows.push({ ...row, month });
      // A cancelled booking can leave credit without a current pricing row.
      for (const balance of financial.filter((item) => !pricing.some((row) => row.user_id === item.user_id))) {
        const row: MonthlyHoursRow = { user_id: balance.user_id, user_name: balance.user_name, email: "", booking_count: 0, total_minutes: 0, total_hours: 0, normal_minutes: 0, special_minutes: 0, calculated_due_huf: Number(balance.due_huf), pricing_breakdown: [], pricing_state: "live", revision_id: null, revision_number: null };
        rows.push({ ...mergePaymentBalances([row], [balance])[0], month });
      }
    } catch {
      return new Response("Hiányos befizetési összesítésből export nem készül.", { status: 500 });
    }
    const [pricingResponse, titleResponse] = await Promise.all([
      supabase.rpc("admin_payment_pricing_details", { p_month: monthStart(month)!, p_user_id: null }),
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

  const workbook = monthlySettlementXlsx(rows, details);
  const suffix = months.length === 1 ? months[0] : `${months[0]}_${months.at(-1)}_${months.length}honap`;
  const body = new Uint8Array(workbook).buffer;
  return new Response(body, { headers: {
    "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "Content-Disposition": `attachment; filename="a-hely-elszamolasi-osszesites-${suffix}.xlsx"`,
    "Cache-Control": "private, no-store",
  } });
}
