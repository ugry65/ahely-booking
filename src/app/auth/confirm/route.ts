import { NextResponse, type NextRequest } from "next/server";

import { requireEnv } from "@/lib/env";
import { getSafeAuthRedirectPath } from "@/lib/safe-redirect";
import { createClient } from "@/lib/supabase/server";

const SUPPORTED_OTP_TYPES = new Set([
  "signup",
  "invite",
  "magiclink",
  "recovery",
  "email_change",
  "email",
]);

export async function GET(request: NextRequest) {
  const tokenHash = request.nextUrl.searchParams.get("token_hash");
  const type = request.nextUrl.searchParams.get("type");
  const requestedNext = request.nextUrl.searchParams.get("next");
  const next = getSafeAuthRedirectPath(requestedNext);
  const siteUrl = requireEnv("SITE_URL");

  if (tokenHash && type && SUPPORTED_OTP_TYPES.has(type)) {
    const supabase = await createClient();
    const { error } = await supabase.auth.verifyOtp({
      token_hash: tokenHash,
      type: type as "signup" | "invite" | "magiclink" | "recovery" | "email_change" | "email",
    });

    if (!error) {
      const destination = type === "recovery" ? "/jelszo-visszaallitas" : next;
      return NextResponse.redirect(new URL(destination, siteUrl));
    }
  }

  return NextResponse.redirect(
    new URL("/belepes?hiba=Érvénytelen vagy lejárt hivatkozás.", siteUrl),
  );
}
