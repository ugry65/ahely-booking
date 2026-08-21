"use server";

import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";

function resultUrl(kind: "hiba" | "uzenet", message: string) {
  return `/adatok-megadasa?${new URLSearchParams({ [kind]: message }).toString()}`;
}

export async function completeOnboarding(formData: FormData) {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims?.sub) redirect("/belepes");

  const customerType = String(formData.get("customerType") ?? "").trim();
  const useProfileName = String(formData.get("useProfileName") ?? "") === "true";
  const firstName = String(formData.get("firstName") ?? "").trim();
  const lastName = String(formData.get("lastName") ?? "").trim();
  const manualBillingName = String(formData.get("billingName") ?? "").trim();
  const billingName = useProfileName ? `${lastName} ${firstName}`.trim() : manualBillingName;

  const phone = String(formData.get("phone") ?? "").trim();
  const billingPostalCode = String(formData.get("billingPostalCode") ?? "").trim();
  const billingCity = String(formData.get("billingCity") ?? "").trim();
  const billingStreet = String(formData.get("billingStreet") ?? "").trim();
  const billingHouseNumber = String(formData.get("billingHouseNumber") ?? "").trim();
  const taxNumber = String(formData.get("taxNumber") ?? "").trim();

  if (!phone || !billingName || !billingPostalCode || !billingCity || !billingStreet || !billingHouseNumber) {
    redirect(resultUrl("hiba", "A telefonszám, a számlázási név és a teljes számlázási cím kitöltése kötelező."));
  }
  if (!['private', 'business'].includes(customerType)) {
    redirect(resultUrl("hiba", "Válaszd ki, hogy magánszemélyként vagy vállalkozóként kéred a számlát."));
  }
  if (customerType === "business" && !taxNumber) {
    redirect(resultUrl("hiba", "Vállalkozói számlázás esetén az adószám megadása kötelező."));
  }

  const { error } = await supabase.rpc("complete_own_onboarding", {
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
    const message = error.code === "P0001" && error.message.length <= 260
      ? error.message
      : "Az adatok mentése nem sikerült. Kérlek, ellenőrizd a mezőket és próbáld újra.";
    redirect(resultUrl("hiba", message));
  }

  redirect("/foglalasok");
}
