"use server";

import { redirect } from "next/navigation";

import { adminSettingsRedirectUrl } from "@/lib/admin-settings-redirect";
import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

function parseDays(value: FormDataEntryValue | null) {
  const text = String(value ?? "").trim();
  if (!/^\d+$/.test(text)) return null;
  const parsed = Number(text);
  return Number.isSafeInteger(parsed) ? parsed : null;
}

export async function saveAdvanceBookingLimits(formData: FormData) {
  await requireAdmin();
  const defaultDays = parseDays(formData.get("defaultDays"));
  const trainingDays = parseDays(formData.get("trainingDays"));
  if (defaultDays === null || trainingDays === null) {
    redirect(adminSettingsRedirectUrl("hiba", "Az előrefoglalási limitek csak nemnegatív egész napértékek lehetnek."));
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_advance_booking_limits", {
    p_default_days: defaultDays,
    p_training_days: trainingDays,
    p_correlation_id: crypto.randomUUID(),
  });

  if (error) {
    const message = ["P0001", "22023", "22004", "42501"].includes(error.code ?? "") && (error.message?.length ?? 0) <= 240
      ? error.message
      : "Az előrefoglalási limitek mentése nem sikerült.";
    redirect(adminSettingsRedirectUrl("hiba", message ?? "Az előrefoglalási limitek mentése nem sikerült."));
  }

  redirect(adminSettingsRedirectUrl("uzenet", "Az előrefoglalási limitek elmentve."));
}
