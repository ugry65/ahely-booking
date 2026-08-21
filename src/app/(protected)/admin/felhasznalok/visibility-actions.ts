"use server";

import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/auth";
import { checkboxValue } from "@/lib/form-values";
import { createClient } from "@/lib/supabase/server";

export async function updateGlobalBookingNameVisibility(formData: FormData) {
  await requireAdmin();
  const visible = checkboxValue(formData, "visible");
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_booking_name_visibility", {
    p_visible: visible,
    p_correlation_id: crypto.randomUUID(),
  });
  const params = new URLSearchParams(error
    ? { hiba: "A globális névláthatósági beállítás mentése nem sikerült." }
    : { uzenet: "A globális névláthatósági beállítás elmentve." });
  redirect(`/admin/felhasznalok?${params.toString()}`);
}
