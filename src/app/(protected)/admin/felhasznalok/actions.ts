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

type ProfileInput = ReturnType<typeof profileInput>;

async function updateProfileRpc(userId: string, input: ProfileInput) {
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

function validateProfile(input: ProfileInput) {
  if (!input.firstName || !input.lastName) return "A vezetéknév és a keresztnév kötelező.";
  if (!['private', 'business'].includes(input.customerType)) return "Érvénytelen ügyféltípus.";
  if (input.customerType === "business" && !input.taxNumber) return "Vállalkozó esetén az adószám megadása kötelező.";
  return null;
}

export async function inviteUser(formData: FormData) {
  await requireAdmin();

  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const input = profileInput(formData);
  const validation = validateProfile(input);
  if (!email || validation) redirect(resultUrl("hiba", validation ?? "Az e-mail megadása kötelező."));

  const admin = createAdminClient();
  const siteUrl = requireEnv("SITE_URL");
  const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
    data: { first_name: input.firstName, last_name: input.lastName },
    redirectTo: `${siteUrl}/auth/callback?next=/jelszo-visszaallitas`,
  });

  if (error || !data.user) redirect(resultUrl("hiba", "A meghívó elküldése nem sikerült."));

  const updated = await updateProfileRpc(data.user.id, { ...input, isActive: true });
  if (updated.error) redirect(resultUrl("hiba", "A felhasználó létrejött, de a törzsadatok mentése nem sikerült."));

  redirect(resultUrl("uzenet", "A felhasználó létrejött és a meghívó elküldve."));
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
    redirect(resultUrl("hiba", auditError?.code === "P0001" ? auditError.message : "A jelszó-visszaállítás nem indítható."));
  }

  const siteUrl = requireEnv("SITE_URL");
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${siteUrl}/auth/callback?next=/jelszo-visszaallitas`,
  });
  if (error) redirect(resultUrl("hiba", "A jelszó-visszaállító e-mail elküldése nem sikerült."));
  redirect(resultUrl("uzenet", `A jelszó-visszaállító link elküldve: ${email}`));
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

  const prepared = rows.slice(1).map((row, offset) => {
    const email = value(row, "email").toLowerCase();
    const customerTypeRaw = value(row, "customer_type").toLowerCase();
    const customerType = ['business', 'vallalkozo', 'vállalkozó'].includes(customerTypeRaw) ? 'business' : 'private';
    const activeRaw = value(row, "is_active").toLowerCase();
    const input: ProfileInput = {
      firstName: value(row, "first_name"),
      lastName: value(row, "last_name"),
      phone: value(row, "phone"),
      customerType,
      billingPostalCode: value(row, "billing_postal_code"),
      billingCity: value(row, "billing_city"),
      billingStreet: value(row, "billing_street"),
      billingHouseNumber: value(row, "billing_house_number"),
      taxNumber: value(row, "tax_number"),
      isActive: !['false', '0', 'nem', 'inactive'].includes(activeRaw),
    };
    const validation = validateProfile(input);
    if (!email || !/^\S+@\S+\.\S+$/.test(email)) return { line: offset + 2, email, input, error: "Érvénytelen e-mail." };
    if (validation) return { line: offset + 2, email, input, error: validation };
    return { line: offset + 2, email, input, error: null as string | null };
  });

  const duplicateInFile = new Set<string>();
  const seen = new Set<string>();
  for (const item of prepared) {
    if (seen.has(item.email)) duplicateInFile.add(item.email);
    seen.add(item.email);
  }
  const invalid = prepared.filter((item) => item.error || duplicateInFile.has(item.email));
  if (invalid.length) {
    const details = invalid.slice(0, 5).map((item) => `${item.line}. sor: ${item.error ?? "duplikált e-mail a fájlban"}`).join("; ");
    redirect(resultUrl("hiba", `Az import nem indult el. ${details}${invalid.length > 5 ? `; további ${invalid.length - 5} hibás sor` : ""}`));
  }

  const admin = createAdminClient();
  const existingResult = await admin.from("profiles").select("id,email").in("email", prepared.map((item) => item.email));
  if (existingResult.error) redirect(resultUrl("hiba", "A meglévő felhasználók ellenőrzése nem sikerült."));
  const existing = new Map((existingResult.data ?? []).map((profile) => [String(profile.email), String(profile.id)]));

  let created = 0;
  let updated = 0;
  const failures: string[] = [];
  for (const item of prepared) {
    let userId = existing.get(item.email);
    if (!userId) {
      const temporaryPassword = `${crypto.randomUUID()}${crypto.randomUUID()}Aa1!`;
      const createdUser = await admin.auth.admin.createUser({
        email: item.email,
        password: temporaryPassword,
        email_confirm: true,
        user_metadata: { first_name: item.input.firstName, last_name: item.input.lastName },
      });
      if (createdUser.error || !createdUser.data.user) {
        failures.push(`${item.line}. sor (${item.email})`);
        continue;
      }
      userId = createdUser.data.user.id;
      created += 1;
    } else updated += 1;

    const saved = await updateProfileRpc(userId, item.input);
    if (saved.error) failures.push(`${item.line}. sor (${item.email})`);
  }

  if (failures.length) {
    redirect(resultUrl("hiba", `Az import részben sikerült: ${created} új, ${updated} meglévő feldolgozva; hibás: ${failures.slice(0, 5).join(", ")}. Jelszó e-mail automatikusan nem ment ki.`));
  }
  redirect(resultUrl("uzenet", `Import kész: ${created} új felhasználó, ${updated} meglévő frissítve. Automatikus jelszó- vagy meghívó e-mail nem ment ki.`));
}
