"use server";

import { redirect } from "next/navigation";

import { requireEnv } from "@/lib/env";
import { validateNewPassword } from "@/lib/password-policy";
import { createClient } from "@/lib/supabase/server";

function destination(path: string, key: string, value: string) {
  const query = new URLSearchParams({ [key]: value });
  return `${path}?${query.toString()}`;
}

export async function login(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const password = String(formData.get("password") ?? "");

  if (!email || !password) {
    redirect(destination("/belepes", "hiba", "Az e-mail és a jelszó kötelező."));
  }

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });

  if (error || !data.user) {
    redirect(destination("/belepes", "hiba", "Sikertelen bejelentkezés."));
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("is_active,role,must_change_password,onboarding_completed_at")
    .eq("id", data.user.id)
    .maybeSingle<{ is_active: boolean; role: "admin" | "user"; must_change_password: boolean; onboarding_completed_at: string | null }>();

  if (!profile?.is_active) {
    await supabase.auth.signOut({ scope: "local" });
    redirect(destination("/belepes", "hiba", "A hozzáférés nem aktív. Kérjük, fordulj az adminisztrátorhoz."));
  }

  if (profile.must_change_password) {
    redirect("/jelszo-csere");
  }

  if (profile.role !== "admin" && !profile.onboarding_completed_at) {
    redirect("/adatok-megadasa");
  }

  redirect("/foglalasok");
}

export async function logout() {
  const supabase = await createClient();
  await supabase.auth.signOut({ scope: "local" });
  redirect("/belepes");
}

export async function requestPasswordReset(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const siteUrl = requireEnv("SITE_URL");

  if (email) {
    const supabase = await createClient();
    await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${siteUrl}/auth/callback?next=/jelszo-visszaallitas`,
    });
  }

  redirect(destination("/elfelejtett-jelszo", "uzenet", "Ha a cím létezik, elküldtük a visszaállító levelet."));
}

export async function updatePassword(formData: FormData) {
  const password = String(formData.get("password") ?? "");

  const passwordError = validateNewPassword(password, password);
  if (passwordError) redirect(destination("/jelszo-visszaallitas", "hiba", passwordError));

  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;
  const { error } = await supabase.auth.updateUser({ password });

  if (error) {
    redirect(destination("/jelszo-visszaallitas", "hiba", "A jelszó módosítása nem sikerült."));
  }

  const { error: flagError } = await supabase.rpc("complete_own_password_change", {
    p_correlation_id: crypto.randomUUID(),
  });
  if (flagError) {
    redirect(destination("/jelszo-visszaallitas", "hiba", "A jelszó frissült, de az első belépési állapot lezárása nem sikerült. Kérjük, próbáld újra."));
  }

  if (userId) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("role,onboarding_completed_at")
      .eq("id", userId)
      .maybeSingle<{ role: "admin" | "user"; onboarding_completed_at: string | null }>();

    if (profile?.role !== "admin" && !profile?.onboarding_completed_at) {
      redirect("/adatok-megadasa");
    }
  }

  redirect(destination("/belepes", "uzenet", "A jelszó frissült, most már bejelentkezhetsz."));
}

export async function changeInitialPassword(formData: FormData) {
  const password = String(formData.get("password") ?? "");
  const confirmation = String(formData.get("confirmation") ?? "");
  const passwordError = validateNewPassword(password, confirmation);
  if (passwordError) redirect(destination("/jelszo-csere", "hiba", passwordError));

  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims?.sub) redirect("/belepes");
  const { error } = await supabase.auth.updateUser({ password });
  if (error) redirect(destination("/jelszo-csere", "hiba", "A jelszó módosítása nem sikerült."));
  const { error: flagError } = await supabase.rpc("complete_own_password_change", { p_correlation_id: crypto.randomUUID() });
  if (flagError) redirect(destination("/jelszo-csere", "hiba", "A jelszó módosult, de az első belépési állapot lezárása nem sikerült. Kérjük, próbáld újra."));

  const { data: profile } = await supabase.from("profiles").select("role,onboarding_completed_at").eq("id", claims.claims.sub).maybeSingle<{ role: "admin" | "user"; onboarding_completed_at: string | null }>();
  if (profile?.role !== "admin" && !profile?.onboarding_completed_at) redirect("/adatok-megadasa");
  redirect("/foglalasok");
}
