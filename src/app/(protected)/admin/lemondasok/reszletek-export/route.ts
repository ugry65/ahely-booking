import { requireAdmin } from "@/lib/auth";
import { cancellationDetailsCsv, cancellationPeriod, type CancellationDetailRow } from "@/lib/cancellation-report";
import { monthStart, validMonth } from "@/lib/monthly-hours";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: Request) {
  await requireAdmin();
  const url = new URL(request.url);
  const month = url.searchParams.get("honap") ?? "";
  if (!validMonth(month)) return new Response("Érvénytelen záró hónap.", { status: 400 });
  const period = cancellationPeriod(url.searchParams.get("idoszak") ?? undefined);
  const userId = url.searchParams.get("user") || null;
  const supabase = await createClient();
  const response = await supabase.rpc("admin_cancellation_details", {
    p_end_month: monthStart(month)!, p_months: period, p_user_id: userId,
  }).returns<CancellationDetailRow[]>();
  if (response.error) return new Response("A tételes lemondási export nem sikerült.", { status: 500 });
  const csv = cancellationDetailsCsv((response.data ?? []) as unknown as CancellationDetailRow[]);
  return new Response(csv, { headers: {
    "Content-Type": "text/csv; charset=utf-8",
    "Content-Disposition": `attachment; filename="a-hely-lemondasok-reszletes-${month}-${period}honap.csv"`,
    "Cache-Control": "private, no-store",
  } });
}
