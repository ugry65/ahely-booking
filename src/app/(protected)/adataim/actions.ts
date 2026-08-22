"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireActiveProfile } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

function resultUrl(kind: "hiba" | "uzenet", message: string) {
  return `/adataim?${new URLSearchParams({ [kind]: message }).toString()}`;
}

export async function updateOwnProfileData(formData: FormData) {
  await requireActiveProfile();
  const customerType = String(formData.get("customerType") ?? "").trim();
  const phone = String(formData.get("phone") ?? "").trim();
  const billingName = String(formData.get("billingName") ?? "").trim();
  const billingPostalCode = String(formData.get("billingPostalCode") ?? "").trim();
  const billingCity = String(formData.get("billingCity") ?? "").trim();
  const billingStreet = String(formData.get("billingStreet") ?? "").trim();
  const billingHouseNumber = String(formData.get("billingHouseNumber") ?? "").trim();
  const taxNumber = String(formData.get("taxNumber") ?? "").trim();

  if (!phone || !billingName || !billingPostalCode || !billingCity || !billingStreet || !billingHouseNumber) {
    redirect(resultUrl("hiba", "A telefonszám, a számlázási név és a teljes számlázási cím kitöltése kötelező."));
  }
  if (customerType !== "private" && customerType !== "business") {
    redirect(resultUrl("hiba", "Válaszd ki a számla típusát."));
  }
  if (customerType === "business" && !taxNumber) {
    redirect(resultUrl("hiba", "Vállalkozói számlázás esetén az adószám megadása kötelező."));
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("update_own_profile_data", {
    p_phone: phone,
    p_customer_type: customerType,
    p_billing_name: billingName,
    p_billing_postal_code: billingPostalCode,
    p_billing_city: billingCity,
    p_billing_street: billingStreet,
    p_billing_house_number: billingHouseNumber,
    p_tax_number: taxNumber,
    p_correlation_id: crypto.randomUUID(),
  });
  if (error) {
    const message = error.code === "P0001" && error.message.length <= 260 ? error.message : "Az adatok mentése nem sikerült. Kérlek, ellenőrizd a mezőket és próbáld újra.";
    redirect(resultUrl("hiba", message));
  }
  revalidatePath("/adataim");
  redirect(resultUrl("uzenet", "Az adataid mentése sikerült."));
}
