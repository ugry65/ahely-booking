import { NextResponse, type NextRequest } from "next/server";

import { requireEnv } from "@/lib/env";
import { getSafeAuthRedirectPath } from "@/lib/safe-redirect";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const requestedNext = request.nextUrl.searchParams.get("next");
  const next = getSafeAuthRedirectPath(requestedNext);
  const siteUrl = requireEnv("SITE_URL");

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return NextResponse.redirect(new URL(next, siteUrl));
  }

  return NextResponse.redirect(new URL("/belepes?hiba=Érvénytelen vagy lejárt hivatkozás.", siteUrl));
}
