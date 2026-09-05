"use server";

import { redirect } from "next/navigation";

import { requireAdmin } from "@/lib/auth";
import { checkboxValue } from "@/lib/form-values";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { requireEnv } from "@/lib/env";
import { validateNewPassword } from "@/lib/password-policy";

function uuid(value: FormDataEntryValue | null) {
  const text = String(value ?? "");
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text) ? text : null;
}

function resultUrl(kind: "hiba" | "uzenet", message: string, formData?: FormData) {
  const params = new URLSearchParams({ [kind]: message });
  const selectedUserId = formData ? uuid(formData.get("userId")) : null;
  if (selectedUserId) params.set("user", selectedUserId);
  return `/admin/felhasznalok?${params.toString()}`;
}

function safeRpcMessage(error: { code?: string; message?: string } | null, fallback: string) {
  if (!error) return fallback;
  return ["P0001", "22023", "22004", "42501"].includes(error.code ?? "") && (error.message?.length ?? 0) <= 240
    ? error.message!
    : fallback;
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
  if (!["private", "business"].includes(input.customerType)) return "Érvénytelen ügyféltípus.";
  if (input.customerType === "business" && !input.taxNumber) return "Vállalkozó esetén az adószám megadása kötelező.";
  return null;
}

function passwordInput(formData: FormData) {
  return {
    password: String(formData.get("defaultPassword") ?? ""),
    confirmation: String(formData.get("defaultPasswordConfirmation") ?? ""),
  };
}

function safeAuthCreateError(error: { code?: string; status?: number; name?: string; message?: string } | null, email: string) {
  if (!error) return "A felhasználó létrehozása nem sikerült.";
  const code = String(error.code ?? "").toLowerCase();
  if (code.includes("email_exists") || code.includes("user_already_exists") || error.status === 422) {
    return "Ez az e-mail-cím már létezik az Auth-rendszerben. Próbálj másik címet.";
  }
  const safeMessage = String(error.message ?? "").replaceAll(email, "[e-mail elrejtve]").slice(0, 180);
  console.error("admin user creation failed", { status: error.status ?? null, code: error.code ?? null, name: error.name ?? null, message: safeMessage });
  return "A felhasználó létrehozása a hitelesítési szolgáltatásban hibázott. A technikai hibát naplóztuk; próbáld újra, vagy jelezd az adminisztrátornak.";
}

function safeAuthUpdateError(error: { code?: string; status?: number; name?: string; message?: string } | null) {
  if (error) {
    console.error("admin temporary password update failed", {
      status: error.status ?? null,
      code: error.code ?? null,
      name: error.name ?? null,
    });
  }
  return "Az ideiglenes jelszó beállítása a hitelesítési szolgáltatásban nem sikerült. A felhasználónak küldj jelszó-visszaállító linket.";
}

async function sendPasswordSetupEmail(userId: string) {
  const supabase = await createClient();
  const { data: email, error: auditError } = await supabase.rpc("admin_audit_password_reset_request", {
    p_user_id: userId,
    p_correlation_id: crypto.randomUUID(),
  });
  if (auditError || typeof email !== "string") {
    return { error: safeRpcMessage(auditError, "A jelszóbeállító link nem küldhető.") };
  }

  const siteUrl = requireEnv("SITE_URL");
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${siteUrl}/auth/callback?next=/jelszo-visszaallitas`,
  });
  return error ? { error: "A jelszóbeállító e-mail elküldése nem sikerült." } : { email };
}

export async function inviteUser(formData: FormData) {
  await requireAdmin();

  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const firstName = String(formData.get("firstName") ?? "").trim();
  const lastName = String(formData.get("lastName") ?? "").trim();
  if (!email || !firstName || !lastName) {
    redirect(resultUrl("hiba", "A vezetéknév, keresztnév és e-mail megadása kötelező."));
  }
  const password = passwordInput(formData);
  const passwordError = validateNewPassword(password.password, password.confirmation);
  if (passwordError) redirect(resultUrl("hiba", `Az alapértelmezett jelszó: ${passwordError.charAt(0).toLowerCase()}${passwordError.slice(1)}`));

  const admin = createAdminClient();
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password: password.password,
    email_confirm: true,
    user_metadata: { first_name: firstName, last_name: lastName, must_change_password: true },
  });

  if (error || !data.user) redirect(resultUrl("hiba", safeAuthCreateError(error, email)));
  const emailResult = await sendPasswordSetupEmail(data.user.id);
  if (emailResult.error) {
    redirect(resultUrl("hiba", `A felhasználó létrejött, de ${emailResult.error.toLocaleLowerCase("hu-HU")} A szerkesztőben újraküldheted a linket.`));
  }
  redirect(resultUrl("uzenet", "A felhasználó létrejött, és megkapta a biztonságos jelszóbeállító linket. A kezdőjelszót nem küldtük el e-mailben."));
}

export async function updateUserProfile(formData: FormData) {
  await requireAdmin();
  const userId = uuid(formData.get("userId"));
  const input = profileInput(formData);
  if (!userId) redirect(resultUrl("hiba", "Érvénytelen felhasználói azonosító.", formData));
  const validation = validateProfile(input);
  if (validation) redirect(resultUrl("hiba", validation, formData));

  const { error } = await updateProfileRpc(userId, input);
  if (error) redirect(resultUrl("hiba", safeRpcMessage(error, "A felhasználói adatok mentése nem sikerült."), formData));
  redirect(resultUrl("uzenet", "A felhasználói adatok elmentve.", formData));
}

export async function setUserRole(formData: FormData) {
  await requireAdmin();
  const userId = uuid(formData.get("userId"));
  const role = String(formData.get("role") ?? "");
  if (!userId || !["admin", "user"].includes(role)) redirect(resultUrl("hiba", "Érvénytelen felhasználó vagy szerepkör.", formData));
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_profile_role", {
    p_user_id: userId,
    p_role: role,
    p_correlation_id: crypto.randomUUID(),
  });
  if (error) redirect(resultUrl("hiba", safeRpcMessage(error, "A szerepkör mentése nem sikerült."), formData));
  redirect(resultUrl("uzenet", "A felhasználó szerepköre elmentve.", formData));
}

export async function setUserRepeatPermission(formData: FormData) {
  await requireAdmin();
  const userId = uuid(formData.get("userId"));
  if (!userId) redirect(resultUrl("hiba", "Érvénytelen felhasználó.", formData));
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_profile_repeat_permission", {
    p_user_id: userId,
    p_can_repeat: checkboxValue(formData, "canRepeatBookings"),
    p_correlation_id: crypto.randomUUID(),
  });
  if (error) redirect(resultUrl("hiba", safeRpcMessage(error, "Az ismétlődő foglalási jogosultság mentése nem sikerült."), formData));
  redirect(resultUrl("uzenet", "Az ismétlődő foglalási jogosultság elmentve.", formData));
}

export async function setUserGroupMembership(formData: FormData) {
  await requireAdmin();
  const userId = uuid(formData.get("userId"));
  const groupId = uuid(formData.get("groupId"));
  if (!userId || !groupId) redirect(resultUrl("hiba", "Érvénytelen felhasználó vagy helyiségcsoport.", formData));
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_group_member", {
    p_group_id: groupId,
    p_user_id: userId,
    p_is_member: checkboxValue(formData, "isMember"),
    p_correlation_id: crypto.randomUUID(),
  });
  if (error) redirect(resultUrl("hiba", safeRpcMessage(error, "A helyiségcsoport-hozzárendelés mentése nem sikerült."), formData));
  redirect(resultUrl("uzenet", "A helyiségcsoport-hozzárendelés elmentve.", formData));
}

export async function sendPasswordReset(formData: FormData) {
  await requireAdmin();
  const userId = uuid(formData.get("userId"));
  if (!userId) redirect(resultUrl("hiba", "Érvénytelen felhasználói azonosító.", formData));

  const result = await sendPasswordSetupEmail(userId);
  if (result.error) redirect(resultUrl("hiba", result.error, formData));
  redirect(resultUrl("uzenet", `A biztonságos jelszóbeállító/visszaállító link elküldve: ${result.email}`, formData));
}

export async function setTemporaryPassword(formData: FormData) {
  await requireAdmin();
  const userId = uuid(formData.get("userId"));
  if (!userId) redirect(resultUrl("hiba", "Érvénytelen felhasználói azonosító.", formData));

  const password = passwordInput(formData);
  const passwordError = validateNewPassword(password.password, password.confirmation);
  if (passwordError) redirect(resultUrl("hiba", `Az ideiglenes jelszó: ${passwordError.charAt(0).toLowerCase()}${passwordError.slice(1)}`, formData));

  const supabase = await createClient();
  const { error: prepareError } = await supabase.rpc("admin_require_password_change", {
    p_user_id: userId,
    p_correlation_id: crypto.randomUUID(),
  });
  if (prepareError) {
    redirect(resultUrl("hiba", safeRpcMessage(prepareError, "Az ideiglenes jelszó előkészítése nem sikerült."), formData));
  }

  const admin = createAdminClient();
  const { error } = await admin.auth.admin.updateUserById(userId, { password: password.password });
  if (error) redirect(resultUrl("hiba", safeAuthUpdateError(error), formData));
  redirect(resultUrl("uzenet", "Az ideiglenes jelszó beállítva. A felhasználónak a következő belépéskor kötelező megváltoztatnia.", formData));
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
  if (required.some((name) => !headers.includes(name))) redirect(resultUrl("hiba", "A CSV kötelező oszlopai: last_name, first_name, email."));
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
  for (const item of prepared) { if (seen.has(item.email)) duplicateInFile.add(item.email); seen.add(item.email); }
  const invalid = prepared.filter((item) => !item.lastName || !item.firstName || !/^\S+@\S+\.\S+$/.test(item.email) || duplicateInFile.has(item.email));
  if (invalid.length) {
    const details = invalid.slice(0, 5).map((item) => `${item.line}. sor: hibás vagy duplikált név/e-mail`).join("; ");
    redirect(resultUrl("hiba", `Az import nem indult el. ${details}${invalid.length > 5 ? `; további ${invalid.length - 5} hibás sor` : ""}`));
  }

  const admin = createAdminClient();
  const existingResult = await admin.from("profiles").select("id,email").in("email", prepared.map((item) => item.email));
  if (existingResult.error) redirect(resultUrl("hiba", "A meglévő felhasználók ellenőrzése nem sikerült."));
  const existing = new Map((existingResult.data ?? []).map((profile) => [String(profile.email), String(profile.id)]));

  let created = 0; let skipped = 0; const failures: string[] = [];
  for (const item of prepared) {
    if (existing.has(item.email)) { skipped += 1; continue; }
    const temporaryPassword = `${crypto.randomUUID()}${crypto.randomUUID()}Aa1!`;
    const createdUser = await admin.auth.admin.createUser({ email: item.email, password: temporaryPassword, email_confirm: true, user_metadata: { first_name: item.firstName, last_name: item.lastName, must_change_password: true } });
    if (createdUser.error || !createdUser.data.user) failures.push(`${item.line}. sor (${item.email})`); else created += 1;
  }

  if (failures.length) redirect(resultUrl("hiba", `Az import részben sikerült: ${created} új, ${skipped} már létező kihagyva; hibás: ${failures.slice(0, 5).join(", ")}. Automatikus e-mail nem ment ki.`));
  redirect(resultUrl("uzenet", `Import kész: ${created} új felhasználó, ${skipped} már létező kihagyva. Aktiváló e-mail automatikusan nem ment ki.`));
}
