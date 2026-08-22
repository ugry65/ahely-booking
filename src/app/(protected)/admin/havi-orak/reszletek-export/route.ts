import { requireAdmin } from "@/lib/auth";
import { monthStart, monthlyDetailsCsv, selectedMonths, type MonthlyBookingDetail, type MonthlyBookingDetailWithMonth } from "@/lib/monthly-hours";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: Request) {
  await requireAdmin();
  const url = new URL(request.url);
  const fallback = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Budapest", year: "numeric", month: "2-digit" }).format(new Date());
  const months = selectedMonths(url.searchParams.get("honapok") ?? undefined, fallback);
  const userId = url.searchParams.get("user") || null;
  const supabase = await createClient();
  const rows: MonthlyBookingDetailWithMonth[] = [];

  for (const month of months) {
    const response = await supabase.rpc("admin_monthly_active_booking_details", {
      p_month: monthStart(month)!, p_user_id: userId,
    }).returns<MonthlyBookingDetail[]>();
    if (response.error) return new Response("A tételes elszámolási export nem sikerült. Hiányos export nem készül.", { status: 500 });
    for (const row of (response.data ?? []) as unknown as MonthlyBookingDetail[]) rows.push({ ...row, month });
  }

  const csv = monthlyDetailsCsv(rows);
  const suffix = months.length === 1 ? months[0] : `${months[0]}_${months.at(-1)}_${months.length}honap`;
  return new Response(csv, { headers: {
    "Content-Type": "text/csv; charset=utf-8",
    "Content-Disposition": `attachment; filename="a-hely-havi-orak-reszletes-${suffix}.csv"`,
    "Cache-Control": "private, no-store",
  } });
}
