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

function uuid(value: FormDataEntryValue | null) {
  const text = String(value ?? "");
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text) ? text : null;
}

function profileInput(formData: FormData) {
  return {
    firstName: String(formData.get("firstName") ?? "").trim(),
    lastName: String(formData.get("lastName") ?? "").trim(),
    phone: String(formData.get("phone") ?? "").trim(),
    customerType: String(formData.get("customerType") ?? "private").trim(),
    billingPostalCode: String(formData.get("billingPostalCode") ?? "").trim(),
    billingCity: String(formData.get("billingCity") ?? "").trim(),
    billingStreet: String(formData.get("billingStreet") ?? "").trim(),
    billingHouseNumber: String(formData.get("billingHouseNumber") ?? "").trim(),
    taxNumber: String(formData.get("taxNumber") ?? "").trim(),
    isActive: checkboxValue(formData, "isActive"),
  };
}

async function updateProfileRpc(userId: string, input: ReturnType<typeof profileInput>) {
  const supabase = await createClient();
  return supabase.rpc("admin_update_profile", {
    p_user_id: userId,
    p_first_name: input.firstName,
    p_last_name: input.lastName,
    p_phone: input.phone,
    p_customer_type: input.customerType,
    p_billing_postal_code: input.billingPostalCode,
    p_billing_city: input.billingCity,
    p_billing_street: input.billingStreet,
    p_billing_house_number: input.billingHouseNumber,
    p_tax_number: input.taxNumber,
    p_is_active: input.isActive,
    p_correlation_id: crypto.randomUUID(),
  });
}

export async function inviteUser(formData: FormData) {
  await requireAdmin();

  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const input = profileInput(formData);
  if (!email || !input.firstName || !input.lastName) {
    redirect(resultUrl("hiba", "A név és az e-mail kitöltése kötelező."));
  }
  if (input.customerType === "business" && !input.taxNumber) {
    redirect(resultUrl("hiba", "Vállalkozó esetén az adószám megadása kötelező."));
  }

  const admin = createAdminClient();
  const siteUrl = requireEnv("SITE_URL");
  const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
    data: { first_name: input.firstName, last_name: input.lastName },
    redirectTo: `${siteUrl}/auth/callback?next=/jelszo-visszaallitas`,
  });

  if (error || !data.user) {
    redirect(resultUrl("hiba", "A meghívó elküldése nem sikerült."));
  }

  const updated = await updateProfileRpc(data.user.id, { ...input, isActive: true });
  if (updated.error) {
    redirect(resultUrl("hiba", "A felhasználó létrejött, de a törzsadatok mentése nem sikerült."));
  }

  redirect(resultUrl("uzenet", "A felhasználó létrejött és a meghívó elküldve."));
}

export async function updateUserProfile(formData: FormData) {
  await requireAdmin();
  const userId = uuid(formData.get("userId"));
  const input = profileInput(formData);
  if (!userId) redirect(resultUrl("hiba", "Érvénytelen felhasználói azonosító."));
  if (!input.firstName || !input.lastName) redirect(resultUrl("hiba", "A név megadása kötelező."));
  if (input.customerType === "business" && !input.taxNumber) {
    redirect(resultUrl("hiba", "Vállalkozó esetén az adószám megadása kötelező."));
  }

  const { error } = await updateProfileRpc(userId, input);
  if (error) redirect(resultUrl("hiba", error.code === "P0001" ? error.message : "A felhasználói adatok mentése nem sikerült."));
  redirect(resultUrl("uzenet", "A felhasználói adatok elmentve."));
}

export async function sendPasswordReset(formData: FormData) {
  await requireAdmin();
  const userId = uuid(formData.get("userId"));
  if (!userId) redirect(resultUrl("hiba", "Érvénytelen felhasználói azonosító."));

  const supabase = await createClient();
  const correlationId = crypto.randomUUID();
  const { data: email, error: auditError } = await supabase.rpc("admin_audit_password_reset_request", {
    p_user_id: userId,
    p_correlation_id: correlationId,
  });
  if (auditError || typeof email !== "string") {
    redirect(resultUrl("hiba", auditError?.code === "P0001" ? auditError.message : "A jelszó-visszaállítás nem indítható."));
  }

  const siteUrl = requireEnv("SITE_URL");
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${siteUrl}/auth/callback?next=/jelszo-visszaallitas`,
  });
  if (error) redirect(resultUrl("hiba", "A jelszó-visszaállító e-mail elküldése nem sikerült."));
  redirect(resultUrl("uzenet", `A jelszó-visszaállító link elküldve: ${email}`));
}
