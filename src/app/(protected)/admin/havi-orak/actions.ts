"use server";

import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/auth";
import { validMonth } from "@/lib/monthly-hours";
import { createClient } from "@/lib/supabase/server";

const UUID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
function url(month: string, kind: "hiba" | "uzenet", message: string) {
  return `/admin/havi-orak?${new URLSearchParams({ honapok: month, [kind]: message })}`;
}
function safeMessage(error: { code?: string; message?: string } | null, fallback: string) {
  return error && ["P0001", "22004", "22023", "42501"].includes(error.code ?? "") && (error.message?.length ?? 0) < 260 ? error.message! : fallback;
}

export async function createSettlementRevision(formData: FormData) {
  await requireAdmin();
  const month = String(formData.get("month") ?? "");
  const userId = String(formData.get("userId") ?? "");
  const reason = String(formData.get("reason") ?? "").trim();
  if (!validMonth(month) || !UUID.test(userId) || !reason) redirect(url(month, "hiba", "A hónap, a felhasználó és az indok kötelező."));
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_create_monthly_settlement_revision", {
    p_user_id: userId, p_settlement_month: `${month}-01`, p_reason: reason, p_correlation_id: crypto.randomUUID(),
  });
  if (error) redirect(url(month, "hiba", safeMessage(error, "Az elszámolási revision létrehozása nem sikerült.")));
  redirect(url(month, "uzenet", "Az auditált, változtathatatlan elszámolási revision elkészült."));
}

export async function correctHistoricalBookingRate(formData: FormData) {
  await requireAdmin();
  const month = String(formData.get("month") ?? "");
  const bookingId = String(formData.get("bookingId") ?? "");
  const rateText = String(formData.get("hourlyRate") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const rate = /^\d+$/.test(rateText) ? Number(rateText) : NaN;
  if (!validMonth(month) || !UUID.test(bookingId) || !Number.isSafeInteger(rate) || rate < 0 || !reason) redirect(url(month, "hiba", "Érvényes óradíj és új korrekciós indok szükséges."));
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_correct_historical_booking_rate", {
    p_booking_id: bookingId, p_hourly_rate_huf: rate, p_reason: reason, p_correlation_id: crypto.randomUUID(),
  });
  if (error) redirect(url(month, "hiba", safeMessage(error, "A történeti díjkorrekció nem sikerült.")));
  redirect(url(month, "uzenet", "A korrekció és az új immutable revision egy tranzakcióban elkészült."));
}
