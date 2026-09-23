"use server";

import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

function integer(value: FormDataEntryValue | null) {
  const text = String(value ?? "").trim();
  const parsed = /^\d+$/.test(text) ? Number(text) : NaN;
  return Number.isSafeInteger(parsed) ? parsed : null;
}
function result(kind: "hiba" | "uzenet", message: string) {
  return `/admin/dijszabas?${new URLSearchParams({ [kind]: message })}`;
}
function safeMessage(error: { code?: string; message?: string } | null, fallback: string) {
  return error && ["P0001", "22004", "22023", "42501"].includes(error.code ?? "") && (error.message?.length ?? 0) < 260 ? error.message! : fallback;
}

export async function setCentralPricing(formData: FormData) {
  await requireAdmin();
  const validFrom = String(formData.get("validFrom") ?? "");
  const first = integer(formData.get("rate1To15"));
  const middle = integer(formData.get("rateOver15To60"));
  const upper = integer(formData.get("rateOver60"));
  const reason = String(formData.get("reason") ?? "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(validFrom) || first === null || middle === null || upper === null || !reason) redirect(result("hiba", "Minden díj, az érvényességi nap és az indok kötelező."));
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_central_pricing", {
    p_valid_from: validFrom, p_rate_1_15_huf: first, p_rate_over_15_to_60_huf: middle,
    p_rate_over_60_huf: upper, p_reason: reason, p_correlation_id: crypto.randomUUID(),
  });
  if (error) redirect(result("hiba", safeMessage(error, "A központi díjszabás mentése nem sikerült.")));
  redirect(result("uzenet", "A központi díjszabás új, auditált időszaka létrejött."));
}

export async function setTrainingRoomRate(formData: FormData) {
  await requireAdmin();
  const validFrom = String(formData.get("validFrom") ?? "");
  const rate = integer(formData.get("hourlyRate"));
  const reason = String(formData.get("reason") ?? "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(validFrom) || rate === null || !reason) redirect(result("hiba", "Az óradíj, az érvényességi nap és az indok kötelező."));
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_training_room_rate", {
    p_hourly_rate_huf: rate, p_valid_from: validFrom, p_reason: reason, p_correlation_id: crypto.randomUUID(),
  });
  if (error) redirect(result("hiba", safeMessage(error, "A Tréningterem díjának mentése nem sikerült.")));
  redirect(result("uzenet", "A Tréningterem új, auditált csoportos óradíja létrejött."));
}
