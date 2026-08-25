"use server";

import { redirect } from "next/navigation";

import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

function uuid(value: FormDataEntryValue | null) {
  const text = String(value ?? "");
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text) ? text : null;
}

function resultUrl(kind: "hiba" | "uzenet", message: string, userId?: string | null) {
  const params = new URLSearchParams({ [kind]: message });
  if (userId) params.set("user", userId);
  return `/admin/dijazas?${params.toString()}`;
}

function safeRpcMessage(error: { code?: string; message?: string } | null, fallback: string) {
  if (!error) return fallback;
  return ["P0001", "22023", "22004", "42501"].includes(error.code ?? "") && (error.message?.length ?? 0) <= 240
    ? error.message!
    : fallback;
}

export async function setUserPricingPolicy(formData: FormData) {
  await requireAdmin();
  const userId = uuid(formData.get("userId"));
  const pricingScheme = String(formData.get("pricingScheme") ?? "");
  const validMonth = String(formData.get("validMonth") ?? "");

  if (!userId) redirect(resultUrl("hiba", "Érvénytelen felhasználó."));
  if (!["tiered", "progressive", "free"].includes(pricingScheme)) {
    redirect(resultUrl("hiba", "Érvénytelen díjazási mód.", userId));
  }
  if (!/^\d{4}-\d{2}$/.test(validMonth)) {
    redirect(resultUrl("hiba", "Az érvényességi hónap megadása kötelező.", userId));
  }

  const validFrom = `${validMonth}-01`;
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_user_pricing_policy", {
    p_user_id: userId,
    p_pricing_scheme: pricingScheme,
    p_valid_from: validFrom,
    p_correlation_id: crypto.randomUUID(),
  });

  if (error) redirect(resultUrl("hiba", safeRpcMessage(error, "A díjazási mód mentése nem sikerült."), userId));
  redirect(resultUrl("uzenet", "A díjazási mód és az érvényességi hónap elmentve.", userId));
}
