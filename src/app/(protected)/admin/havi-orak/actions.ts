"use server";

import { redirect } from "next/navigation";

import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

function uuid(value: FormDataEntryValue | null) {
  const text = String(value ?? "");
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text) ? text : null;
}

function safeRpcMessage(error: { code?: string; message?: string } | null, fallback: string) {
  if (!error) return fallback;
  return ["P0001", "22023", "22004", "42501"].includes(error.code ?? "") && (error.message?.length ?? 0) <= 240
    ? error.message!
    : fallback;
}

function resultUrl(kind: "hiba" | "uzenet", message: string, months: string) {
  const params = new URLSearchParams({ [kind]: message });
  if (months) params.set("honapok", months);
  return `/admin/havi-orak?${params.toString()}`;
}

export async function closeMonthlySettlement(formData: FormData) {
  await requireAdmin();

  const userId = uuid(formData.get("userId"));
  const month = String(formData.get("month") ?? "");
  const returnMonths = String(formData.get("returnMonths") ?? "");

  if (!userId) redirect(resultUrl("hiba", "Érvénytelen felhasználó.", returnMonths));
  if (!/^\d{4}-\d{2}$/.test(month)) {
    redirect(resultUrl("hiba", "Érvénytelen elszámolási hónap.", returnMonths));
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_close_monthly_settlement", {
    p_user_id: userId,
    p_settlement_month: `${month}-01`,
  });

  if (error) {
    redirect(resultUrl("hiba", safeRpcMessage(error, "A havi elszámolás lezárása nem sikerült."), returnMonths));
  }

  redirect(resultUrl("uzenet", `${month} havi elszámolása lezárva.`, returnMonths));
}
