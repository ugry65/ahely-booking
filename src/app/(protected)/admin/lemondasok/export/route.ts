import { requireAdmin } from "@/lib/auth";
import { cancellationPeriod, cancellationSummaryCsv, type CancellationSummaryRow } from "@/lib/cancellation-report";
import { monthStart, validMonth } from "@/lib/monthly-hours";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: Request) {
  await requireAdmin();
  const url = new URL(request.url);
  const month = url.searchParams.get("honap") ?? "";
  if (!validMonth(month)) return new Response("Érvénytelen záró hónap.", { status: 400 });
  const period = cancellationPeriod(url.searchParams.get("idoszak") ?? undefined);
  const supabase = await createClient();
  const response = await supabase.rpc("admin_cancellation_summary", {
    p_end_month: monthStart(month)!, p_months: period,
  }).returns<CancellationSummaryRow[]>();
  if (response.error) return new Response("A lemondási összesítő exportálása nem sikerült.", { status: 500 });
  const csv = cancellationSummaryCsv((response.data ?? []) as unknown as CancellationSummaryRow[]);
  return new Response(csv, { headers: {
    "Content-Type": "text/csv; charset=utf-8",
    "Content-Disposition": `attachment; filename="a-hely-lemondasok-${month}-${period}honap.csv"`,
    "Cache-Control": "private, no-store",
  } });
}
