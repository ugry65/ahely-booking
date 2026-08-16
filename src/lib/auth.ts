import "server-only";

import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";

export type ActiveProfile = {
  id: string;
  first_name: string;
  last_name: string;
  email: string;
  role: "admin" | "user";
  is_active: boolean;
};

export async function requireActiveProfile(): Promise<ActiveProfile> {
  const supabase = await createClient();
  const { data: claimsData, error: claimsError } = await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;

  if (claimsError || !userId) {
    redirect("/belepes");
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("id,first_name,last_name,email,role,is_active")
    .eq("id", userId)
    .maybeSingle<ActiveProfile>();

  if (!profile?.is_active) {
    redirect("/belepes?hiba=inaktiv");
  }

  return profile;
}

export async function requireAdmin(): Promise<ActiveProfile> {
  const profile = await requireActiveProfile();

  if (profile.role !== "admin") {
    redirect("/foglalasok");
  }

  return profile;
}
