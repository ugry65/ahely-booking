"use server";

import { redirect } from "next/navigation";

import { requireAdmin } from "@/lib/auth";
import { requireEnv } from "@/lib/env";
import { checkboxValue } from "@/lib/form-values";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";

function resultUrl(kind: "hiba" | "uzenet", message: string) {
  return `/admin/felhasznalok?${new URLSearchParams({ [kind]: message }).toString()}`;
}

export async function inviteUser(formData: FormData) {
  await requireAdmin();

  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const firstName = String(formData.get("firstName") ?? "").trim();
  const lastName = String(formData.get("lastName") ?? "").trim();

  if (!email || !firstName || !lastName) {
    redirect(resultUrl("hiba", "Minden mező kitöltése kötelező."));
  }

  const admin = createAdminClient();
  const siteUrl = requireEnv("SITE_URL");
  const { error } = await admin.auth.admin.inviteUserByEmail(email, {
    data: { first_name: firstName, last_name: lastName },
    redirectTo: `${siteUrl}/auth/callback?next=/jelszo-visszaallitas`,
  });

  if (error) {
    redirect(resultUrl("hiba", "A meghívó elküldése nem sikerült."));
  }

  redirect(resultUrl("uzenet", "A meghívó elküldve."));
}

export async function updateBookingNameVisibility(formData: FormData) {
  await requireAdmin();

  const userId = String(formData.get("userId") ?? "");
  const visible = checkboxValue(formData, "visible");

  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId)) {
    redirect(resultUrl("hiba", "Érvénytelen felhasználói azonosító."));
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_other_booker_names_visible", {
    p_user_id: userId,
    p_visible: visible,
    p_correlation_id: crypto.randomUUID(),
  });

  if (error) {
    redirect(resultUrl("hiba", "A névláthatósági beállítás mentése nem sikerült."));
  }

  redirect(resultUrl("uzenet", "A névláthatósági beállítás elmentve."));
}
