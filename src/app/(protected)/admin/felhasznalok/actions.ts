"use server";

import { redirect } from "next/navigation";

import { requireAdmin } from "@/lib/auth";
import { checkboxValue } from "@/lib/form-values";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { requireEnv } from "@/lib/env";

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
    billingName: String(formData.get("billingName") ?? "").trim(),
    billingPostalCode: String(formData.get("billingPostalCode") ?? "").trim(),
    billingCity: String(formData.get("billingCity") ?? "").trim(),
    billingStreet: String(formData.get("billingStreet") ?? "").trim(),
    billingHouseNumber: String(formData.get("billingHouseNumber") ?? "").trim(),
    taxNumber: String(formData.get("taxNumber") ?? "").trim(),
    isActive: checkboxValue(formData, "isActive"),
  };
}

type ProfileInput = ReturnType<typeof profileInput>;

async function updateProfileRpc(userId: string, input: ProfileInput) {
  const supabase = await createClient();
  return supabase.rpc("admin_update_profile", {
    p_user_id: userId,
    p_first_name: input.firstName,
    p_last_name: input.lastName,
    p_phone: input.phone,
    p_customer_type: input.customerType,
    p_billing_name: input.billingName,
    p_billing_postal_code: input.billingPostalCode,
    p_billing_city: input.billingCity,
    p_billing_street: input.billingStreet,
    p_billing_house_number: input.billingHouseNumber,
    p_tax_number: input.taxNumber,
    p_is_active: input.isActive,
    p_correlation_id: crypto.randomUUID(),
  });
}

function validateProfile(input: ProfileInput) {
  if (!input.firstName || !input.lastName) return "A vezetéknév és a keresztnév kötelező.";
  if (!['private', 'business'].includes(input.customerType)) return "Érvénytelen ügyféltípus.";
  if (input.customerType === "business" && !input.taxNumber) return "Vállalkozó esetén az adószám megadása kötelező.";
  return null;
}

export async function inviteUser(formData: FormData) {
  await requireAdmin();

  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const firstName = String(formData.get("firstName") ?? "").trim();
  const lastName = String(formData.get("lastName") ?? "").trim();
  if (!email || !firstName || !lastName) {
    redirect(resultUrl("hiba", "A vezetéknév, keresztnév és e-mail megadása kötelező."));
  }

  const admin = createAdminClient();
  const temporaryPassword = `${crypto.randomUUID()}${crypto.randomUUID()}Aa1!`;
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password: temporaryPassword,
    email_confirm: true,
    user_metadata: { first_name: firstName, last_name: lastName },
  });

  if (error || !data.user) redirect(resultUrl("hiba", "A felhasználó létrehozása nem sikerült. Ellenőrizd, hogy az e-mail cím nem szerepel-e már a rendszerben."));

  redirect(resultUrl("uzenet", "A felhasználó létrejött. Aktiváló/jelszóbeállító linket külön tudsz küldeni neki."));
}

export async function updateUserProfile(formData: FormData) {
  await requireAdmin();
  const userId = uuid(formData.get("userId"));
  const input = profileInput(formData);
  if (!userId) redirect(resultUrl("hiba", "Érvénytelen felhasználói azonosító."));
  const validation = validateProfile(input);
  if (validation) redirect(resultUrl("hiba", validation));

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
    redirect(resultUrl("hiba", auditError?.code === "P0001" ? auditError.message : "Az aktiváló/jelszóbeállító link nem küldhető."));
  }

  const siteUrl = requireEnv("SITE_URL");
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${siteUrl}/auth/callback?next=/jelszo-visszaallitas`,
  });
  if (error) redirect(resultUrl("hiba", "Az aktiváló/jelszóbeállító e-mail elküldése nem sikerült."));
  redirect(resultUrl("uzenet", `Az aktiváló/jelszóbeállító link elküldve: ${email}`));
}

function parseCsv(text: string) {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];
    if (quoted) {
      if (char === '"' && text[i + 1] === '"') { field += '"'; i += 1; }
      else if (char === '"') quoted = false;
      else field += char;
    } else if (char === '"') quoted = true;
    else if (char === ',') { row.push(field); field = ""; }
    else if (char === '\n') { row.push(field.replace(/\r$/, "")); rows.push(row); row = []; field = ""; }
    else field += char;
  }
  if (field.length || row.length) { row.push(field.replace(/\r$/, "")); rows.push(row); }
  return rows.filter((item) => item.some((value) => value.trim()));
}

export async function importUsersCsv(formData: FormData) {
  await requireAdmin();
  const file = formData.get("file");
  if (!(file instanceof File) || !file.size) redirect(resultUrl("hiba", "Válassz CSV fájlt."));
  if (file.size > 1_000_000) redirect(resultUrl("hiba", "A CSV fájl legfeljebb 1 MB lehet."));

  const rows = parseCsv(await file.text());
  if (rows.length < 2) redirect(resultUrl("hiba", "A CSV nem tartalmaz importálható adatsort."));
  if (rows.length > 1001) redirect(resultUrl("hiba", "Egyszerre legfeljebb 1000 felhasználó importálható."));

  const headers = rows[0].map((value) => value.trim().toLowerCase());
  const required = ["last_name", "first_name", "email"];
  if (required.some((name) => !headers.includes(name))) {
    redirect(resultUrl("hiba", "A CSV kötelező oszlopai: last_name, first_name, email."));
  }
  const index = (name: string) => headers.indexOf(name);
  const value = (row: string[], name: string) => index(name) >= 0 ? String(row[index(name)] ?? "").trim() : "";

  const prepared = rows.slice(1).map((row, offset) => ({
    line: offset + 2,
    lastName: value(row, "last_name"),
    firstName: value(row, "first_name"),
    email: value(row, "email").toLowerCase(),
  }));

  const duplicateInFile = new Set<string>();
  const seen = new Set<string>();
  for (const item of prepared) {
    if (seen.has(item.email)) duplicateInFile.add(item.email);
    seen.add(item.email);
  }
  const invalid = prepared.filter((item) => !item.lastName || !item.firstName || !/^\S+@\S+\.\S+$/.test(item.email) || duplicateInFile.has(item.email));
  if (invalid.length) {
    const details = invalid.slice(0, 5).map((item) => `${item.line}. sor: hibás vagy duplikált név/e-mail`).join("; ");
    redirect(resultUrl("hiba", `Az import nem indult el. ${details}${invalid.length > 5 ? `; további ${invalid.length - 5} hibás sor` : ""}`));
  }

  const admin = createAdminClient();
  const existingResult = await admin.from("profiles").select("id,email").in("email", prepared.map((item) => item.email));
  if (existingResult.error) redirect(resultUrl("hiba", "A meglévő felhasználók ellenőrzése nem sikerült."));
  const existing = new Map((existingResult.data ?? []).map((profile) => [String(profile.email), String(profile.id)]));

  let created = 0;
  let skipped = 0;
  const failures: string[] = [];
  for (const item of prepared) {
    if (existing.has(item.email)) { skipped += 1; continue; }
    const temporaryPassword = `${crypto.randomUUID()}${crypto.randomUUID()}Aa1!`;
    const createdUser = await admin.auth.admin.createUser({
      email: item.email,
      password: temporaryPassword,
      email_confirm: true,
      user_metadata: { first_name: item.firstName, last_name: item.lastName },
    });
    if (createdUser.error || !createdUser.data.user) failures.push(`${item.line}. sor (${item.email})`);
    else created += 1;
  }

  if (failures.length) {
    redirect(resultUrl("hiba", `Az import részben sikerült: ${created} új, ${skipped} már létező kihagyva; hibás: ${failures.slice(0, 5).join(", ")}. Automatikus e-mail nem ment ki.`));
  }
  redirect(resultUrl("uzenet", `Import kész: ${created} új felhasználó, ${skipped} már létező kihagyva. Aktiváló e-mail automatikusan nem ment ki.`));
}
