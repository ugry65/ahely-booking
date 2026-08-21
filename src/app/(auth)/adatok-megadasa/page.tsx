import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";
import { BillingOnboardingForm } from "./billing-onboarding-form";

type Profile = {
  first_name: string;
  last_name: string;
  email: string;
  role: "admin" | "user";
  is_active: boolean;
  onboarding_completed_at: string | null;
};

export default async function OnboardingPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;
  if (!userId) redirect("/belepes");

  const { data: profile } = await supabase
    .from("profiles")
    .select("first_name,last_name,email,role,is_active,onboarding_completed_at")
    .eq("id", userId)
    .maybeSingle<Profile>();

  if (!profile?.is_active) redirect("/belepes?hiba=inaktiv");
  if (profile.role === "admin" || profile.onboarding_completed_at) redirect("/foglalasok");

  return (
    <div className="auth-shell"><section className="card stack">
      <p className="eyebrow">Első belépés</p>
      <h1>Adataid megadása</h1>
      <p>A jelszó beállítása után még egyszer szükségünk van a kapcsolattartási és számlázási adataidra. Ezek megadása után használhatod a foglalási rendszert.</p>
      {params.hiba ? <p className="message error" role="alert">{params.hiba}</p> : null}
      <BillingOnboardingForm firstName={profile.first_name} lastName={profile.last_name} email={profile.email} />
    </section></div>
  );
}
