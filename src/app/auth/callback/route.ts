import { NextResponse, type NextRequest } from "next/server";

import { requireEnv } from "@/lib/env";
import { getSafeAuthRedirectPath } from "@/lib/safe-redirect";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const tokenHash = request.nextUrl.searchParams.get("token_hash");
  const type = request.nextUrl.searchParams.get("type");
  const requestedNext = request.nextUrl.searchParams.get("next");
  const next = getSafeAuthRedirectPath(requestedNext);
  const siteUrl = requireEnv("SITE_URL");

  const supabase = await createClient();

  // Recovery e-mailben token hash-t használunk, hogy a link másik böngészőben
  // vagy eszközön is működjön, és ne függjön a kérést indító PKCE cookie-jától.
  if (tokenHash && type === "recovery") {
    const { error } = await supabase.auth.verifyOtp({
      token_hash: tokenHash,
      type: "recovery",
    });
    if (!error) return NextResponse.redirect(new URL(next, siteUrl));
  }

  // Megtartjuk a korábbi PKCE callback támogatását más auth folyamatokhoz.
  if (code) {
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return NextResponse.redirect(new URL(next, siteUrl));
  }

  return NextResponse.redirect(new URL("/belepes?hiba=Érvénytelen vagy lejárt hivatkozás.", siteUrl));
}
