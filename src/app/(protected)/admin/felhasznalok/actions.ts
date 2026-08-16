"use server";

import { redirect } from "next/navigation";

import { requireAdmin } from "@/lib/auth";
import { createAdminClient } from "@/lib/supabase/admin";

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
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL;
  const { error } = await admin.auth.admin.inviteUserByEmail(email, {
    data: { first_name: firstName, last_name: lastName },
    redirectTo: siteUrl ? `${siteUrl}/auth/callback?next=/jelszo-visszaallitas` : undefined,
  });

  if (error) {
    redirect(resultUrl("hiba", "A meghívó elküldése nem sikerült."));
  }

  redirect(resultUrl("uzenet", "A meghívó elküldve."));
}
